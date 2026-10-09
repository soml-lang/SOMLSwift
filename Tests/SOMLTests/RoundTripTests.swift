import Foundation
import Testing
@testable import SOML

/**
Random values of every type, with strings that hold quotes, escapes, controls, and invisible characters, round-trip through `jsonText()` and `parsingJSON:` in both formats, and a key path's description parses back to the same path.
*/
@Suite
struct JSONRoundTripTests {
	static func randomInstant(using generator: inout SeededGenerator) -> SOML.Instant? {
		let year = Int(generator.next() % 9980) + 1
		let month = Int(generator.next() % 12) + 1
		let day = Int(generator.next() % 28) + 1
		let hour = Int(generator.next() % 24)
		let minute = Int(generator.next() % 60)
		let second = Int(generator.next() % 60)
		return SOML.Instant(year: year, month: month, day: day, hour: hour, minute: minute, second: second, nanosecond: Int(generator.next() % 1_000_000_000))
	}

	static func randomValue(depth: Int, generator: inout SeededGenerator) -> SOML.Value {
		let choice = Int(generator.next() % 100)

		if depth <= 0 || choice < 45 {
			let scalar: SOML.Value = switch Int(generator.next() % 8) {
			case 0:
				.string(randomString(generator: &generator))
			case 1:
				.int(Int64(from: &generator))
			case 2:
				.float(Double(Int64(from: &generator)) / 8)
			case 3:
				.bool(generator.next() % 2 == 0)
			case 4:
				.null
			case 5:
				.duration(.nanoseconds(Int64(from: &generator)))
			case 6:
				Self.randomInstant(using: &generator).map(SOML.Value.instant) ?? .null
			default:
				.int(Int64(from: &generator))
			}

			return scalar
		} else if choice < 75 {
			let count = Int(generator.next() % 4)
			return .array((0..<count).map { _ in Self.randomValue(depth: depth - 1, generator: &generator) })
		} else {
			let count = Int(generator.next() % 4)
			var object = SOML.Object()

			for index in 0..<count {
				object[randomString(generator: &generator) + "\(index)"] = Self.randomValue(depth: depth - 1, generator: &generator)
			}

			return .object(object)
		}
	}

	static func containsTemporal(_ value: SOML.Value) -> Bool {
		switch value {
		case .duration, .instant:
			true
		case .array(let items):
			items.contains { Self.containsTemporal($0) }
		case .object(let object):
			object.values.contains { Self.containsTemporal($0) }
		default:
			false
		}
	}

	static func randomString(generator: inout SeededGenerator) -> String {
		let pieces = ["a", "b", "quote'", "double\"quote", "back\\slash", "tab\tchar", "nl\nchar", "ctrl\u{1}", "del\u{7F}", "c1\u{85}", "emoji 🌍", "unicode ünïcödé", "space ", " lead", "日本語", "\u{2028}", "\u{FEFF}inside"]
		return (0..<(Int(generator.next() % 3) + 1)).map { _ in pieces[Int(generator.next() % UInt64(pieces.count))] }.joined()
	}

	@Test
	func `json round trips`() throws {
		var roundTrips = 0

		for seed in 0..<2000 {
			var generator = SeededGenerator(seed: UInt64(seed + 100_000))
			let value = Self.randomValue(depth: 3, generator: &generator)

			// In plain JSON an instant or a duration is written as its canonical text, which reads back as a string, so only tagged JSON round-trips one.
			let writesTemporalAsText = if case .duration = value { true } else if case .instant = value { true } else { Self.containsTemporal(value) }

			for format in [SOML.JSONFormat.plain, .tagged] where !(writesTemporalAsText && format == .plain) {
				let text: String

				do {
					text = try value.jsonText(format: format)
				} catch {
					// The value cannot be JSON-written, like a duration outside its range, and the refusal must not depend on the format.
					do {
						_ = try value.jsonText(format: format == .plain ? .tagged : .plain)
						Issue.record("Seed \(seed): jsonText(.\(format)) threw \(error), but the other format did not")
					} catch {}

					continue
				}

				do {
					let parsed = try SOML.Value(parsingJSON: text, format: format)

					if parsed != value {
						Issue.record("Seed \(seed): JSON round trip of format .\(format) changed the value: \(text)")
					}

					roundTrips += 1
				} catch {
					Issue.record("Seed \(seed): the JSON of format .\(format) does not read back: \(error). Text: \(text)")
				}
			}
		}

		// A generator degenerating, or every value becoming unrepresentable, would otherwise make the test pass without a round trip.
		#expect(roundTrips > 1000, "Only \(roundTrips) values round-tripped")
	}

	@Test
	func `key path descriptions are stable`() throws {
		for seed in 0..<5000 {
			var generator = SeededGenerator(seed: UInt64(seed + 500_000))
			let segmentCount = Int(generator.next() % 5) + 1
			var segments = [SOML.KeyPath.Segment]()

			for index in 0..<segmentCount {
				if generator.next() % 3 == 0 {
					segments.append(.index(Int(generator.next() % 1000)))
				} else {
					segments.append(.key(Self.randomString(generator: &generator) + "k\(index)"))
				}
			}

			guard segments.contains(where: { if case .key = $0 { true } else { false } }) else {
				continue
			}

			let path = SOML.KeyPath(segments)
			let description = path.description

			guard let reparsed = try? SOML.KeyPath(parsing: description) else {
				Issue.record("Seed \(seed): the description \(description.debugDescription) does not parse")
				continue
			}

			if reparsed != path {
				Issue.record("Seed \(seed): \(description.debugDescription) reparsed to \(reparsed.description.debugDescription)")
			}
		}
	}
}

extension Int64 {
	/**
	Every bit pattern, including the ones that do not fit a positive count.
	*/
	init(from generator: inout SeededGenerator) {
		let high = generator.next()
		let low = generator.next()
		self.init(bitPattern: high << 32 | low)
	}
}

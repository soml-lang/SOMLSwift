import Foundation
import Testing
@testable import SOML

/**
The readme promises that the differences of two values are in an order in which `setting(_:at:)` and `removing(at:)` can apply them to a document, one by one, so that the document ends up with the new value.
*/
@Suite
struct DifferencesApplicationTests {
	/**
	Values with nested objects and arrays that overlap in their keys, so that the differences exercise merging, additions, and removals.
	*/
	static func randomValue(depth: Int, generator: inout SeededGenerator) -> SOML.Value {
		let choice = Int(generator.next() % 100)

		if depth <= 0 || choice < 40 {
			let scalar: SOML.Value = switch Int(generator.next() % 6) {
			case 0: .int(Int64(generator.next() % 1000))
			case 1: .string("s\(generator.next() % 5)")
			case 2: .bool(generator.next() % 2 == 0)
			case 3: .null
			case 4: .float(Double(generator.next() % 100))
			default: .duration(.seconds(Double(generator.next() % 100)))
			}

			return scalar
		} else if choice < 70 {
			let count = Int(generator.next() % 4)
			return .array((0..<count).map { _ in Self.randomValue(depth: depth - 1, generator: &generator) })
		} else {
			let count = Int(generator.next() % 4)
			var object = SOML.Object()

			for index in 0..<count {
				object["k\(Int(generator.next() % 5))\(index)"] = Self.randomValue(depth: depth - 1, generator: &generator)
			}

			return .object(object)
		}
	}

	@Test
	func `differences apply one by one`() {
		var violations = 0
		var applied = 0

		for seed in 0..<3000 {
			var generator = SeededGenerator(seed: UInt64(seed))
			let old = Self.randomValue(depth: 3, generator: &generator)
			let new = Self.randomValue(depth: 3, generator: &generator)

			guard old != new else {
				continue
			}

			guard let differences = new.differences(from: old) else {
				continue
			}

			guard case .object = old, case .object = new else {
				continue
			}

			guard var document = try? SOML.Document(parsing: old.canonicalDocument()) else {
				Issue.record("Old value has no canonical document")
				return
			}

			var failed = false

			for difference in differences {
				do {
					switch difference {
					case .added(let value, let path), .changed(_, let value, let path):
						document = try document.setting(value, at: path)
					case .removed(_, let path):
						document = try document.removing(at: path)
					}

					applied += 1
				} catch {
					violations += 1

					if violations <= 5 {
						Issue.record("Seed \(seed): applying \(difference) threw \(error)")
					}

					failed = true
					break
				}
			}

			if !failed, document.value != new {
				violations += 1

				if violations <= 5 {
					Issue.record("Seed \(seed): applying differences gave \(document.value), expected \(new)")
				}
			}
		}

		// The generator degenerating would otherwise make the test pass without exercising the promise.
		#expect(applied > 500, "Only \(applied) differences were applied")
		#expect(violations == 0)
	}

	/**
	Keys that need quoting, that look like a path or an index, and that are canonically equivalent but different, so that the differences are applied at paths that are hard to write.
	*/
	private static let unusualKeys = ["", "a.b", "it's", "x\"y", "\u{E9}", "e\u{301}", "[0]", "404", "a", "true", "a b", "\n"]

	private static func unusualValue(depth: Int, generator: inout SeededGenerator) -> SOML.Value {
		let choice = generator.next() % 10

		if depth <= 0 || choice < 3 {
			return switch generator.next() % 8 {
			case 0: .int(Int64(generator.next() % 3))
			case 1: .string(["", "\u{E9}", "e\u{301}", "'"][Int(generator.next() % 4)])
			case 2: .float([0.0, -0.0, .infinity][Int(generator.next() % 3)])
			case 3: .duration(.nanoseconds(Int64(generator.next() % 3) - 1))
			case 4: .instant(SOML.Instant(secondsSince1970: Int64(generator.next() % 2), nanoseconds: Int(generator.next() % 2))!)
			case 5: .object([:])
			case 6: .array([])
			default: .null
			}
		} else if choice < 6 {
			return .array((0..<Int(generator.next() % 4)).map { _ in Self.unusualValue(depth: depth - 1, generator: &generator) })
		} else {
			var object = SOML.Object()

			for _ in 0..<Int(generator.next() % 5) {
				object[Self.unusualKeys[Int(generator.next() % UInt64(Self.unusualKeys.count))]] = Self.unusualValue(depth: depth - 1, generator: &generator)
			}

			return .object(object)
		}
	}

	/**
	A value close to `value`: some members and items changed, removed, or added, the members reordered, and arrays grown or shrunk, so that the two values share most of their paths.
	*/
	private static func mutated(_ value: SOML.Value, depth: Int, generator: inout SeededGenerator) -> SOML.Value {
		switch value {
		case .object(var object):
			for key in object.keys {
				switch generator.next() % 6 {
				case 0:
					object[key] = nil
				case 1:
					object[key] = Self.mutated(object[key]!, depth: depth - 1, generator: &generator)
				case 2:
					object[key] = Self.unusualValue(depth: depth - 1, generator: &generator)
				default:
					break
				}
			}

			for _ in 0..<Int(generator.next() % 3) {
				object[Self.unusualKeys[Int(generator.next() % UInt64(Self.unusualKeys.count))]] = Self.unusualValue(depth: depth - 1, generator: &generator)
			}

			return .object(generator.next() % 3 == 0 ? SOML.Object(object.reversed()) : object)
		case .array(var items):
			for index in items.indices where generator.next() % 3 == 0 {
				items[index] = Self.mutated(items[index], depth: depth - 1, generator: &generator)
			}

			if generator.next() % 3 == 0 {
				items.removeLast(Int(generator.next() % UInt64(items.count + 1)))
			}

			for _ in 0..<Int(generator.next() % 3) {
				items.append(Self.unusualValue(depth: depth - 1, generator: &generator))
			}

			return .array(items)
		default:
			return generator.next() % 2 == 0 ? value : Self.unusualValue(depth: depth, generator: &generator)
		}
	}

	@Test
	func `differences of close values with unusual keys apply one by one, also to a document that is an array`() throws {
		var applied = 0

		for seed in 0..<3000 {
			var generator = SeededGenerator(seed: UInt64(seed))
			let old: SOML.Value = generator.next() % 2 == 0 ? .array([Self.unusualValue(depth: 3, generator: &generator)]) : .object(["a": Self.unusualValue(depth: 3, generator: &generator)])
			let new = Self.mutated(old, depth: 4, generator: &generator)
			let differences = try #require(new.differences(from: old), "Seed \(seed)")
			#expect(differences.isEmpty == (old == new), "Seed \(seed)")

			var document = try SOML.Document(parsing: old.canonicalDocument())

			for difference in differences {
				switch difference {
				case .added(let value, let path), .changed(_, let value, let path):
					document = try document.setting(value, at: path)
				case .removed(_, let path):
					document = try document.removing(at: path)
				}

				applied += 1
			}

			#expect(document.value == new, "Seed \(seed): applying \(differences) to \(old) gave \(document.value)")
		}

		// The generator degenerating would otherwise make the test pass without exercising the promise.
		#expect(applied > 1000, "Only \(applied) differences were applied")
	}
}

import Foundation
import Synchronization
import Testing
@testable import SOML

@Suite
struct ImprovementTests {
	struct ExtendsEncodedObject: Encodable {
		enum CodingKeys: String, CodingKey {
			case value
			case second
		}

		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(["first": 1], forKey: .value)
			var nested = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .value)
			try nested.encode(2, forKey: .second)
		}
	}

	@Test(arguments: [SOML.Encoder.KeyEncodingStrategy.useDefaultKeys, .convertToKebabCase, .convertToSnakeCase])
	func `extending an encoded dictionary preserves its existing members`(_ strategy: SOML.Encoder.KeyEncodingStrategy) throws {
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = strategy
		#expect(try encoder.encodeToValue(ExtendsEncodedObject()) == ["value": ["first": 1, "second": 2]])
	}
}

@Suite
struct ObjectOperationTests {
	enum Failure: Error {
		case stopped
	}

	@Test
	func `default members evaluate lazily and mutate nested storage`() {
		var object: SOML.Object = ["null": .null]
		var evaluations = 0

		func defaultValue() -> SOML.Value {
			evaluations += 1
			return ["port": 80]
		}

		#expect(object["server", default: defaultValue()] == ["port": 80])
		#expect(!object.contains(key: "server"))
		#expect(evaluations == 1)
		object["server", default: defaultValue()]["port"] = 8080
		let snapshot = object
		object["server", default: defaultValue()]["port"] = 443
		#expect(evaluations == 2)
		#expect(snapshot["server"] == ["port": 8080])
		#expect(object["server"] == ["port": 443])
		#expect(object["null", default: defaultValue()] == .null)
		#expect(evaluations == 2)
		#expect(object.keys == ["null", "server"])
	}

	@Test(arguments: [0, 31, 32, 33, 100])
	func `bulk object operations preserve exact keys and snapshots`(_ count: Int) throws {
		let keys = (0..<count).map { "member\($0)" } + ["é", "e\u{301}"]
		var object = SOML.Object(keys.enumerated().map { ($0.element, SOML.Value.int(Int64($0.offset))) })
		object.reserveCapacity(200)
		let snapshot = object
		let mapped = object.mapValues { .array([$0]) }
		#expect(mapped.keys.map { Array($0.utf8) } == keys.map { Array($0.utf8) })
		for (index, key) in keys.enumerated() {
			#expect(mapped[key] == .array([.int(Int64(index))]))
			#expect(object.contains(key: key))
		}
		let filtered: SOML.Object = object.filter { $0.key.utf8.count == 2 }
		#expect(filtered.count == 1)
		#expect(filtered["é"] == object["é"])
		#expect(!filtered.contains(key: "e\u{301}"))
		#expect(object.updateValue(.null, forKey: "é") == snapshot["é"])
		#expect(object.updateValue(true, forKey: "new") == nil)
		#expect(object.keys.last == "new")
		#expect(snapshot["é"] != .null)
		for keepingCapacity in [true, false] {
			object.removeAll(keepingCapacity: keepingCapacity)
			#expect(object.isEmpty)
			#expect(object.keys.isEmpty)
			#expect(object.values.isEmpty)
			#expect(!object.contains(key: "é"))
			object["é"] = 1
			object["e\u{301}"] = 2
			#expect(object.count == 2)
		}
	}

	@Test
	func `object transformations preserve typed errors without mutating the source`() {
		let object: SOML.Object = ["first": 1, "second": 2]
		var visited = [SOML.Value]()
		do throws(Failure) {
			_ = try object.mapValues { (value) throws(Failure) in
				visited.append(value)
				guard value != 2 else {
					throw .stopped
				}
				return .bool(true)
			}
			Issue.record("The transformation must throw")
		} catch {
			#expect(error == .stopped)
		}
		#expect(visited == [1, 2])
		#expect(object == ["first": 1, "second": 2])
		#expect(throws: Failure.self) {
			try object.filter { _ throws(Failure) in
				throw .stopped
			}
		}
	}

	@Test
	func `in place merge preserves recursive replacements and exact key order`() {
		var object: SOML.Object = ["server": ["port": 80, "host": "a"], "é": 1]
		let original = object
		let other: SOML.Object = ["server": ["port": 443], "e\u{301}": 2]
		object.merge(other)
		#expect(object == original.merging(other))
		#expect(object["server"] == ["port": 443, "host": "a"])
		#expect(object.keys.map { Array($0.utf8) } == ["server", "é", "e\u{301}"].map { Array($0.utf8) })
		let snapshot = object
		object.merge(object)
		#expect(object == snapshot)
		#expect(original["server"]?["port"] == 80)
	}
}

@Suite
struct PathAndDifferenceOperationTests {
	@Test
	func `path composition and collections retain exact scalar semantics`() throws {
		let path: SOML.KeyPath = ["servers", 0, "é"]
		#expect(Array(path) == path.segments)
		#expect(Array(path.reversed()) == path.segments.reversed())
		#expect(path.parent == ["servers", 0])
		#expect(path.parent?.parent == ["servers"])
		#expect(path.parent?.parent?.parent == nil)
		#expect(path.parent?.appending("é") == path)
		#expect(SOML.KeyPath(["servers"]).appending([0, "é"]) == path)
		#expect(path.hasPrefix(["servers", 0]))
		#expect(path.hasPrefix(path))
		#expect(!path.hasPrefix(["servers", 0, "e\u{301}"]))
		#expect(!path.hasPrefix(["servers", 0, "é", "more"]))
		#expect(try SOML.KeyPath(parsing: path.description) == path)
	}

	@Test
	func `difference application and inversion restore values and retain unrelated source`() throws {
		let document = try SOML.Document(parsing: "# Configuration\nports: [80, 443, 8080]\nhost: 'example' # Keep this\nold: true\n")
		let replacement: SOML.Value = ["ports": [443], "host": "example", "new": .null]
		let differences = try #require(replacement.differences(from: document.value))
		for difference in differences {
			#expect(difference.inverted.inverted == difference)
			#expect(difference.oldValue == document.value[path: difference.path])
			#expect(difference.newValue == replacement[path: difference.path])
		}
		let changed = try document.applying(differences.lazy)
		#expect(changed.value == replacement)
		#expect(changed.text.contains("host: 'example' # Keep this\n"))
		#expect(changed.text.hasPrefix("# Configuration\n"))
		let restored = try changed.applying(differences.reversed().map(\.inverted))
		#expect(restored.value == document.value)
		#expect(try document.applying([SOML.Difference]()).text == document.text)
	}

	@Test
	func `difference application errors leave the original document intact`() throws {
		let document = try SOML.Document(parsing: "answer: 42\n")
		let changes: [SOML.Difference] = [.changed(from: 42, to: 7, at: ["answer"]), .added(1, at: ["answer", "nested"])]
		#expect(throws: SOML.EditError.self) {
			try document.applying(changes)
		}
		#expect(document.text == "answer: 42\n")
		#expect(try document.applying(.changed(from: 0, to: 1, at: ["answer"])).value == ["answer": 1])
	}
}

@Suite
struct DiagnosticBoundTests {
	static let largeInputs = [
		Sample("unknown word", "value: " + String(repeating: "unknown", count: 100_000)),
		Sample("spaced key", "the " + String(repeating: "name ", count: 100_000) + ": 1"),
		Sample("unit", "value: 512 " + String(repeating: "Z", count: 500_000)),
		Sample("number before unit", "value: " + String(repeating: "0_", count: 100_000) + "1 ms"),
		Sample("space separated instant", "value: 2026-09-19 14:00:00." + String(repeating: "1", count: 500_000) + "Z"),
		Sample("table header", "[server" + String(repeating: "a", count: 500_000) + "]"),
		Sample("thousands groups", "[" + String(repeating: "123,", count: 100_000) + "000]")
	]

	@Test(arguments: largeInputs)
	func `malformed large inputs produce bounded useful diagnostics`(_ sample: Sample) {
		let error = parseError(sample.source)
		#expect(error != nil)
		#expect(error?.message.utf8.count ?? .max < 1000)
		#expect(error?.codeFrame.utf8.count ?? .max < 1000)
		#expect(error?.location.offset ?? .max < sample.source.utf8.count)
	}

	@Test
	func `ordinary unit and keyword hints survive bounded diagnostics`() {
		#expect(parseError("value: True")?.message.contains("Booleans are written") == true)
		#expect(parseError("value: undefined")?.message.contains("Null is written") == true)
		#expect(parseError("value: 5 ms")?.message.contains("as in 5ms") == true)
		#expect(parseError("value: 5 seconds")?.message.contains("as in '5 seconds'") == true)
		#expect(parseError("value: 2026-09-19 14:00:00Z")?.message.contains("2026-09-19T14:00:00Z") == true)
	}

	@Test
	func `scientific float scratch bytes are all initialized before use`() throws {
		var generator = SeededGenerator(seed: 0xF10A7)
		let boundaries: [Double] = [.leastNonzeroMagnitude, .leastNormalMagnitude, .greatestFiniteMagnitude, 1e-7, 1e-6, 1e20, 1e21, .pi]
		for value in boundaries + (0..<1000).map({ _ in Double(bitPattern: generator.next()) }).filter(\.isFinite) {
			let original = SOML.Value.float(value)
			let text = original.description
			#expect(try SOML.Value(parsingValue: text) == original)
			#expect(try JSONDecoder().decode(Double.self, from: Data(text.utf8)) == value)
		}
	}
}

@Suite
struct SuggestionWorkTests {
	struct Key: CodingKey {
		static let convertedLengths = Mutex<[Int]>([])
		let stringValue: String
		var intValue: Int? {
			nil
		}

		init?(stringValue: String) {
			guard stringValue != "\0" else {
				return nil
			}

			Self.convertedLengths.withLock {
				$0.append(stringValue.unicodeScalars.count)
			}
			self.stringValue = stringValue
		}

		init?(intValue: Int) {
			return nil
		}
	}

	@Test
	func `impossible typo candidates are rejected before coding key conversion`() throws {
		let longKey = "a-" + String(repeating: "e\u{301}", count: 100_000)
		let object = SOML.Object([(longKey, SOML.Value.int(1)), ("another-too-long-candidate", 2), ("short", 3)])
		let decoder = DecoderImplementation(value: .object(object), options: .init(keySeparator: "-", readKeys: nil, userInfo: [:]))
		let container = try decoder.container(keyedBy: Key.self)
		let key = try #require(Key(stringValue: "missing"))
		Key.convertedLengths.withLock {
			$0 = []
		}
		#expect(throws: DecodingError.self) {
			try container.decode(Int.self, forKey: key)
		}
		let converted = Key.convertedLengths.withLock { $0 }
		#expect(converted == [5])
	}
}

import Foundation
import Synchronization
import Testing
@testable import SOML

@Suite
struct PerformanceContractTests {
	final class Counter: Sendable {
		private let count = Mutex(0)

		var value: Int {
			get {
				count.withLock { $0 }
			}
			set {
				count.withLock {
					$0 = newValue
				}
			}
		}
	}

	struct CountedKey: CodingKey {
		let counter: Counter
		let name: String

		var stringValue: String {
			counter.value += 1
			return name
		}

		var intValue: Int? {
			nil
		}

		init(counter: Counter, name: String) {
			self.counter = counter
			self.name = name
		}

		init?(stringValue: String) {
			self.init(counter: Counter(), name: stringValue)
		}

		init?(intValue: Int) {
			return nil
		}
	}

	struct SuggestionKey: CodingKey {
		static let conversions = Mutex(0)
		let stringValue: String
		var intValue: Int? {
			nil
		}

		init?(stringValue: String) {
			guard stringValue != "\0" else {
				return nil
			}

			Self.conversions.withLock {
				$0 += 1
			}
			self.stringValue = stringValue
		}

		init?(intValue: Int) {
			return nil
		}
	}

	@Test
	func `missing key suggestions bound work before filtering candidates`() throws {
		let object = SOML.Object((0..<10_000).map { ("present\($0)", SOML.Value.int(1)) })
		let decoder = DecoderImplementation(value: .object(object), options: .init(keySeparator: nil, readKeys: nil, userInfo: [:]))
		let container = try decoder.container(keyedBy: SuggestionKey.self)
		let key = try #require(SuggestionKey(stringValue: "missing"))
		SuggestionKey.conversions.withLock {
			$0 = 0
		}
		#expect(throws: DecodingError.self) {
			try container.decode(Int.self, forKey: key)
		}
		#expect(SuggestionKey.conversions.withLock { $0 } <= 1000)
	}

	@Test(arguments: [SOML.Value.int(7), .null])
	func `primitive optional lookup reads the coding key once`(_ value: SOML.Value) throws {
		let decoder = DecoderImplementation(value: ["number": value], options: .init(keySeparator: nil, readKeys: nil, userInfo: [:]))
		let container = try decoder.container(keyedBy: CountedKey.self)
		let counter = Counter()
		let result = try container.decodeIfPresent(Int.self, forKey: CountedKey(counter: counter, name: "number"))
		#expect(result == value.intValue.map(Int.init))
		#expect(counter.value == 1)
	}

	@Test
	func `every primitive optional handles absence null and values with strict keys`() throws {
		struct Record: Codable, Equatable {
			var boolValue: Bool?
			var stringValue: String?
			var doubleValue: Double?
			var floatValue: Float?
			var intValue: Int?
			var int8Value: Int8?
			var int16Value: Int16?
			var int32Value: Int32?
			var int64Value: Int64?
			var uintValue: UInt?
			var uint8Value: UInt8?
			var uint16Value: UInt16?
			var uint32Value: UInt32?
			var uint64Value: UInt64?
			var int128Value: Int128?
			var uint128Value: UInt128?
		}

		let populated = Record(boolValue: true, stringValue: "é😀", doubleValue: 0.5, floatValue: 0.25, intValue: -1, int8Value: .min, int16Value: .max, int32Value: .min, int64Value: .max, uintValue: 1, uint8Value: .max, uint16Value: .max, uint32Value: .max, uint64Value: UInt64(Int64.max), int128Value: Int128(Int64.min), uint128Value: UInt128(Int64.max))
		for strategy in [SOML.Decoder.KeyDecodingStrategy.useDefaultKeys, .convertFromKebabCase, .convertFromSnakeCase] {
			var decoder = SOML.Decoder()
			decoder.keyDecodingStrategy = strategy
			decoder.rejectsUnknownKeys = true
			var encoder = SOML.Encoder()
			encoder.keyEncodingStrategy = strategy.matchingEncodingStrategy
			let value = try encoder.encodeToValue(populated)
			#expect(try decoder.decode(Record.self, from: value) == populated)
			#expect(try decoder.decode(Record.self, from: .object([:])) == Record())
			let nulls = SOML.Object(value.objectValue!.keys.map { ($0, SOML.Value.null) })
			#expect(try decoder.decode(Record.self, from: .object(nulls)) == Record())
			for key in nulls.keys {
				var invalid = nulls
				invalid[key] = []
				#expect(throws: DecodingError.self) {
					try decoder.decode(Record.self, from: .object(invalid))
				}
			}
		}
	}

	@Test
	func `failed unkeyed optional conversions do not consume an item`() throws {
		let decoder = DecoderImplementation(value: [.null, "wrong", 42], options: .init(keySeparator: nil, readKeys: nil, userInfo: [:]))
		var container = try decoder.unkeyedContainer()
		#expect(try container.decodeIfPresent(Int.self) == nil)
		#expect(container.currentIndex == 1)
		#expect(throws: DecodingError.self) {
			try container.decodeIfPresent(Int.self)
		}
		#expect(container.currentIndex == 1)
		#expect(try container.decodeIfPresent(String.self) == "wrong")
		#expect(try container.decodeIfPresent(Int.self) == 42)
		#expect(container.isAtEnd)
		#expect(try container.decodeIfPresent(Int.self) == nil)
		#expect(container.currentIndex == 3)
	}

	#if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
	@Test
	func `every finite Float16 bit pattern round trips directly`() throws {
		let values = (UInt16.min...UInt16.max).map(Float16.init(bitPattern:)).filter(\.isFinite)
		let encoded = try SOML.Encoder().encodeToValue(values)
		#expect(try SOML.Decoder().decode([Float16].self, from: encoded) == values)
		#expect(try SOML.Encoder().encodeToValue(Float16(0.1)) == .float(0.1))
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encodeToValue([Float16.nan])
		}
	}
	#endif

	@Test
	func `bulk escaped strings preserve exact text through every writer`() throws {
		let content = String(repeating: "é😀ordinary\\text", count: 10_000) + "'\t\n\u{7F}\0"
		let value = SOML.Value.array([.string(content)])
		#expect(try SOML.Value(parsing: value.canonicalDocument()) == value)
		for format in [SOML.JSONFormat.plain, .tagged] {
			#expect(try SOML.Value(parsingJSON: value.jsonText(format: format), format: format) == value)
		}
	}
}

@Suite
struct StorageContractTests {
	@Test
	func `reserving indexed objects preserves snapshots through growth removal and reindexing`() {
		let keys = (0..<100).map { "key\($0)" } + ["é", "e\u{301}"]
		var object = SOML.Object(keys.enumerated().map { ($0.element, SOML.Value.int(Int64($0.offset))) })
		let snapshot = object
		object.reserveCapacity(2000)
		for index in 100..<1000 {
			object["key\(index)"] = .int(Int64(index))
		}
		for index in 0..<1000 {
			#expect(object["key\(index)"] == .int(Int64(index)))
		}
		for index in 0..<980 {
			#expect(object.removeValue(forKey: "key\(index)") == .int(Int64(index)))
		}
		#expect(object.count == 22)
		#expect(object["é"] == 100)
		#expect(object["e\u{301}"] == 101)
		#expect(snapshot.keys.map { Array($0.utf8) } == keys.map { Array($0.utf8) })
		#expect(snapshot.values == (0..<keys.count).map { SOML.Value.int(Int64($0)) })
		#expect(snapshot["key100"] == nil)
	}

	@Test
	func `object mutations match an independent exact byte model across index thresholds`() throws {
		let keys = (0..<70).map { "shared-prefix-key-\($0)" } + ["é", "e\u{301}", "", "😀"]
		var object = SOML.Object()
		var model = [(key: String, value: SOML.Value)]()
		var generator = SeededGenerator(seed: 812)
		for step in 0..<1000 {
			let key = keys[Int.random(in: keys.indices, using: &generator)]
			let position = model.firstIndex { Array($0.key.utf8) == Array(key.utf8) }
			let snapshot = object
			if Int.random(in: 0..<3, using: &generator) == 0 {
				object[key] = nil
				if let position {
					model.remove(at: position)
				}
			} else {
				let value = SOML.Value.array([.int(Int64(step))])
				object[key] = value
				object[key]?[0] = .int(Int64(step + 1))
				let changed = SOML.Value.array([.int(Int64(step + 1))])
				if let position {
					model[position].value = changed
				} else {
					model.append((key, changed))
				}
			}
			#expect(object.keys.map { Array($0.utf8) } == model.map { Array($0.key.utf8) })
			#expect(object.values == model.map(\.value))
			for key in keys {
				#expect(object[key] == model.first { Array($0.key.utf8) == Array(key.utf8) }?.value)
			}
			#expect(snapshot.values.allSatisfy { $0.arrayValue?.first?.intValue != Int64(step + 1) })
		}
	}

	@Test
	func `wide merges preserve source snapshots and scalar distinct key order`() {
		let keys = (0..<80).map { "member\($0)" } + ["é", "e\u{301}"]
		let defaults = SOML.Object(keys.map { ($0, SOML.Value.object(["keep": 1, "change": 2])) })
		let overrides = SOML.Object(keys.reversed().map { ($0, SOML.Value.object(["change": 3])) } + [("new", .null)])
		let merged = defaults.merging(overrides)
		#expect(merged.keys.map { Array($0.utf8) } == (keys + ["new"]).map { Array($0.utf8) })
		for key in keys {
			#expect(merged[key] == ["keep": 1, "change": 3])
			#expect(defaults[key] == ["keep": 1, "change": 2])
			#expect(overrides[key] == ["change": 3])
		}
		#expect(merged["new"] == .null)
		#expect(defaults.merging([:]) == defaults)
		#expect(SOML.Object().merging(overrides) == overrides)
	}

	@Test
	func `JSON encoding validation agrees with an independent UTF8 scalar parser`() throws {
		let invalidSequences: [[UInt8]] = [[0x80], [0xC0, 0x80], [0xC2], [0xE0, 0x80, 0x80], [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xF0, 0x9F, 0x98], [0xFF]]
		for padding in 0..<17 {
			for invalid in invalidSequences {
				let bytes = Array((String(repeating: " ", count: padding) + "[\"é😀").utf8) + invalid + Array("\"]".utf8)
				let error = try #require(throws: SOML.JSONError.self) {
					try SOML.Value(parsingJSON: bytes)
				}
				#expect(error.location?.offset == bytes[...].firstInvalidUTF8Offset)
			}
		}
		#expect(try SOML.Value(parsingJSON: "\r\n\t [1] \r\n") == [1])
	}

	@Test(arguments: [#"\uD800\uDC00"#, #"\uD800\uDFFF"#, #"\uDBFF\uDC00"#, #"\uDBFF\uDFFF"#, #"\uD83D\uDE00"#])
	func `surrogate boundary pairs agree with Foundation`(_ escape: String) throws {
		let json = "\"\(escape)\""
		let expected = try JSONDecoder().decode(String.self, from: Data(json.utf8))
		#expect(try SOML.Value(parsingJSON: json) == .string(expected))
	}

	@Test
	func `direct JSON scalar writers use exact canonical spelling at boundaries`() throws {
		let value: SOML.Value = [.instant(.minimum), .instant(.maximum), .duration(.nanoseconds(Int64.min)), .duration(.nanoseconds(Int64.max)), .duration(.nanoseconds(1))]
		let json = try value.jsonText()
		#expect(json == "[\n\t\"0001-01-01T00:00:00Z\",\n\t\"9999-12-31T23:59:59.999999999Z\",\n\t\"-2562047h47m16.854775808s\",\n\t\"2562047h47m16.854775807s\",\n\t\"0.000000001s\"\n]\n")
	}
}

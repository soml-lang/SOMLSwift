import Foundation
import Testing
@testable import SOML

@Suite
struct OptimizationTests {
	@Test
	func `JSON escapes every control while preserving adjacent multibyte text`() throws {
		let controls = (0...0x9F).compactMap(Unicode.Scalar.init).filter { $0.properties.generalCategory == .control && $0 != "\r" }
		let content = controls.map { "é😀\($0)£\u{301}" }.joined()
		let value = SOML.Value.string(content)

		for format in [SOML.JSONFormat.plain, .tagged] {
			let json = try value.jsonText(format: format)
			#expect(try SOML.Value(parsingJSON: json, format: format) == value)
			#expect(!json.unicodeScalars.contains { $0.properties.generalCategory == .control && $0 != "\n" && $0 != "\t" })
		}
	}

	@Test
	func `tagged strings in type and value remain an object`() throws {
		let json = #"{"type":{"type":"string","value":"string"},"value":{"type":"string","value":"hello"}}"#
		#expect(try SOML.Value(parsingJSON: json, format: .tagged) == ["type": "string", "value": "hello"])
		let mixed = #"{"type":{"type":"string","value":"string"},"value":"hello"}"#
		let error = try #require(throws: SOML.JSONError.self) {
			try SOML.Value(parsingJSON: mixed, format: .tagged)
		}
		#expect(error.location?.offset == 51)
	}

	@Test(arguments: [799, 800, 801, 10_000])
	func `discarded decimal digits retain the rounding direction`(_ zeroCount: Int) throws {
		let zeros = String(repeating: "0", count: zeroCount)
		let fixtures: [(String, Double)] = [
			("9007199254740993.\(zeros)", 9_007_199_254_740_992),
			("9007199254740993.\(zeros)1", 9_007_199_254_740_994),
			("-9007199254740993.\(zeros)1", -9_007_199_254_740_994),
			("0.\(zeros)123e\(zeroCount + 3)", 123),
			("123\(zeros).0e-\(zeroCount)", 123),
		]

		for (text, expected) in fixtures {
			#expect(try SOML.Value(parsingValue: text) == .float(expected))
			#expect(try SOML.Value(parsingJSON: text) == .float(expected))
		}
	}

	@Test
	func `indexed locations agree with value ranges for large objects and exact keys`() throws {
		let keys = (0..<300).map { "member\($0)" } + ["é", "e\u{301}", "a.b", "", "😀"]
		let object = SOML.Object(keys.enumerated().map { ($0.element, SOML.Value.array([.int(Int64($0.offset))])) })
		let document = try SOML.Document(parsing: SOML.Value.object(object).canonicalDocument())

		for key in keys {
			let path = SOML.KeyPath([.key(key), .index(0)])
			let range = try #require(document.valueRange(of: path))
			#expect(document.location(of: path) == range.lowerBound)
			#expect(document.location(of: SOML.KeyPath([.key(key), .index(1)])) == document.range(of: [.key(key)])?.lowerBound)
			#expect(document.valueText(at: path) == object[key]?.arrayValue?.first?.description)
			#expect(document.path(atOffset: range.lowerBound.offset) == path)
		}
	}

	@Test
	func `difference paths do not share mutable traversal storage`() throws {
		let old: SOML.Value = ["a": ["same": [1, 2], "remove": 3], "b": [1, 2, 3]]
		let new: SOML.Value = ["a": ["same": [1, 2], "add": 4], "b": [9]]
		let differences = try #require(new.differences(from: old))
		#expect(differences.map(\.path) == [["a", "remove"], ["a", "add"], ["b", 0], ["b", 2], ["b", 1]])
		#expect(old.differences(from: old) == [])
		#expect(SOML.Value.object(["é": 1]).differences(from: ["e\u{301}": 1])?.count == 2)
	}

	@Test
	func `depth checks still find a container after many scalar siblings`() {
		let scalars = Array(repeating: SOML.Value.int(1), count: 100_000)
		#expect(!SOML.Value.array(scalars).isDeeperThan(1))
		#expect(SOML.Value.array(scalars + [.array([])]).isDeeperThan(1))
		#expect(!SOML.Value.array(scalars + [.array([])]).isDeeperThan(2))
		let object = SOML.Object(scalars.enumerated().map { ("key\($0.offset)", $0.element) })
		#expect(!SOML.Value.object(object).isDeeperThan(1))
	}

	@Test
	func `path diagnostics stop at a bounded prefix`() throws {
		let path = SOML.KeyPath(Array(repeating: .key("a"), count: 100_000))
		let document = try SOML.Document(parsing: "{}")
		let error = try #require(throws: SOML.EditError.self) {
			try document.setting(1, at: path)
		}
		#expect(error.message.utf8.count < 400)
		#expect(error.message.contains("nested more than 100"))
		#expect(path.segments[...].described == String(repeating: "a.", count: 100) + "…")
	}

	@Test
	func `integer fast paths preserve boundaries in every encoding container`() throws {
		struct Record<Integer: FixedWidthInteger & Codable>: Codable, Equatable {
			let number: Integer
		}

		/**
		Checks scalar, keyed, and unkeyed encodings at both bounds of an integer type.
		*/
		func check<Integer: FixedWidthInteger & Codable>(_ type: Integer.Type) throws {
			for number in [type.min, type.max] {
				let expected = SOML.Value.int(Int64(number))
				#expect(try SOML.Encoder().encodeToValue(number) == expected)
				#expect(try SOML.Encoder().encodeToValue([number]) == .array([expected]))
				#expect(try SOML.Encoder().encodeToValue(Record(number: number)) == ["number": expected])
				#expect(try SOML.Decoder().decode(Record<Integer>.self, from: ["number": expected]) == Record(number: number))
			}
		}

		try check(Int8.self)
		try check(Int16.self)
		try check(Int32.self)
		try check(Int64.self)
		try check(UInt8.self)
		try check(UInt16.self)
		try check(UInt32.self)
	}

	@Test
	func `lexical context is independent of a large trailing document`() {
		let prefix = "key: \"é\\n😀\""
		let suffix = "\n" + String(repeating: "other: [1, 2, 'x']\n", count: 10_000)
		for offset in 0..<prefix.utf8.count {
			#expect(SOML.lexicalContext(in: prefix, atUTF8Offset: offset) == SOML.lexicalContext(in: prefix + suffix, atUTF8Offset: offset))
		}
	}

	@Test
	func `instant length validation includes the longest offset spelling`() throws {
		let text = "2026-09-19T14:00:00.123456789+02:00"
		#expect(text.utf8.count == 35)
		#expect(SOML.Instant(text)?.description == "2026-09-19T12:00:00.123456789Z")
		#expect(SOML.Instant(text + String(repeating: "0", count: 100_000)) == nil)
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: .nan)) == nil)
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: .infinity)) == nil)
	}

	@Test
	func `quoted keys share decoded text while keeping their original ranges`() throws {
		let keys = ["", "a.b", "é", "e\u{301}", "'", "\"", "\\", "\n", "\t", "\0", "😀"]
		let members = keys.enumerated().map { "\(CanonicalWriter.string($0.element)): [\($0.offset)]" }.joined(separator: "\n")
		let document = try SOML.Document(parsing: "parent: {\n\(members)\n}")

		for (index, key) in keys.enumerated() {
			let path = SOML.KeyPath(["parent", .key(key)])
			#expect(document.value[path: path] == .array([.int(Int64(index))]))
			#expect(document.valueText(at: path) == "[\(index)]")
			let range = try #require(document.range(of: path))
			let original = String(decoding: document.tree.text[range.lowerBound.offset..<range.upperBound.offset], as: UTF8.self)
			#expect(original == "\(CanonicalWriter.string(key)): [\(index)]")
			#expect(try document.setting(9, at: path).value[path: path] == 9)
		}
	}

	@Test
	func `duration fractions can discard a million trailing zeros without changing precision`() throws {
		let zeros = String(repeating: "0", count: 1_000_000)
		#expect(try SOML.Value(parsingValue: "0.5\(zeros)s") == .duration(.milliseconds(500)))
		#expect(try SOML.Value(parsingValue: "0.0_0_0_5\(zeros)h") == .duration(.milliseconds(1800)))
		#expect(throws: SOML.ParseError.self) {
			try SOML.Value(parsingValue: "0.\(zeros)1s")
		}
	}

	@Test
	func `block comment error precedence includes overlapping delimiters`() throws {
		#expect(try SOML.Value(parsing: "/* /*/ a: 1") == ["a": 1])
		#expect(parseError("/* nested /* but never closed")?.message == "Unterminated block comment")
		let nested = try #require(parseError("/* first /* nested */ a: 1"))
		#expect(nested.location.offset == 9)
		#expect(nested.message.contains("cannot be nested"))
	}

	struct SuggestionProbe: Decodable {
		static let knownKeys = CodingUserInfoKey(rawValue: "knownKeys")!

		init(from decoder: any Decoder) throws {
			let keys = try #require(decoder.userInfo[Self.knownKeys] as? [String])
			let container = try decoder.container(keyedBy: SOMLCodingKey.self)
			for key in keys {
				_ = container.contains(SOMLCodingKey(stringValue: key))
			}
		}
	}

	/**
	A full-matrix reference for optimal string alignment, independent of the production rolling-row implementation.
	*/
	private func referenceDistance(_ first: String, _ second: String) -> Int {
		let first = Array(first.unicodeScalars)
		let second = Array(second.unicodeScalars)
		var matrix = Array(repeating: Array(repeating: 0, count: second.count + 1), count: first.count + 1)
		for index in 0...first.count {
			matrix[index][0] = index
		}
		for index in 0...second.count {
			matrix[0][index] = index
		}
		for firstIndex in first.indices {
			for secondIndex in second.indices {
				var distance = min(matrix[firstIndex][secondIndex + 1] + 1, matrix[firstIndex + 1][secondIndex] + 1, matrix[firstIndex][secondIndex] + (first[firstIndex] == second[secondIndex] ? 0 : 1))
				if
					firstIndex > 0,
					secondIndex > 0,
					first[firstIndex] == second[secondIndex - 1],
					first[firstIndex - 1] == second[secondIndex]
				{
					distance = min(distance, matrix[firstIndex - 1][secondIndex - 1] + 1)
				}
				matrix[firstIndex + 1][secondIndex + 1] = distance
			}
		}
		return matrix[first.count][second.count]
	}

	@Test
	func `typo suggestions match an independent distance algorithm and deterministic ties`() throws {
		var generator = SeededGenerator(seed: 782)
		let alphabet = Array("abcde")
		for _ in 0..<100 {
			let unknown = String((0..<6).map { _ in alphabet[Int.random(in: alphabet.indices, using: &generator)] })
			let known: [String] = (0..<25).map { _ in String((0..<Int.random(in: 4...8, using: &generator)).map { _ in alphabet[Int.random(in: alphabet.indices, using: &generator)] }) }.filter { $0 != unknown }
			let ranked: [(key: String, distance: Int)] = known.map { (key: $0, distance: referenceDistance(unknown, $0)) }.filter { $0.distance <= 2 }.sorted { first, second in
				first.distance == second.distance ? first.key < second.key : first.distance < second.distance
			}
			for candidates in [known, known.reversed()] {
				var decoder = SOML.Decoder()
				decoder.rejectsUnknownKeys = true
				decoder.userInfo[SuggestionProbe.knownKeys] = candidates
				let error = try #require(throws: DecodingError.self) {
					try decoder.decode(SuggestionProbe.self, from: .object(SOML.Object([(unknown, .int(1))])))
				}
				guard case .dataCorrupted(let context) = error else {
					Issue.record("Expected an unknown key error")
					continue
				}
				if let expected = ranked.first {
					#expect(context.debugDescription.hasSuffix(". Did you mean \(expected.key)?"))
				} else {
					#expect(!context.debugDescription.contains("Did you mean"))
				}
			}
		}
	}
}

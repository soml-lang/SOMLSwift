import Foundation
import Testing
@testable import SOML

@Suite
struct RefactorRegressionTests {
	@Test
	func `output spans append different byte collections without filling unused capacity`() {
		let scalar: Unicode.Scalar = "😀"
		let bytes = [UInt8](capacity: 20) { output in
			output.append(contentsOf: [UInt8]())
			output.append(contentsOf: Array("paddingab".utf8).dropFirst(7))
			output.append(contentsOf: scalar.utf8)
			output.append(contentsOf: repeatElement(UInt8.tab, count: 2))
		}

		#expect(bytes == Array("ab😀\t\t".utf8))
	}

	@Test(arguments: [0, 1, 6, 7, 8, 9, 14, 15, 16, 20, 254, 255, 256])
	func `small object lookup distinguishes byte prefixes at word and length boundaries`(_ length: Int) {
		let prefix = String(repeating: "a", count: length)
		let keys = [prefix, prefix + "H", prefix + "I", prefix + "é", prefix + "e\u{301}", prefix + "😀x", prefix + "😀y"]
		var object = SOML.Object()

		for (index, key) in keys.enumerated() {
			object[key] = .int(Int64(index))
		}

		for (index, key) in keys.enumerated() {
			#expect(object[key] == .int(Int64(index)))
			#expect(!object.contains(key: key + "missing"))
		}

		#expect(object.count == keys.count)
	}

	@Test(arguments: [0, 1, 8, 128])
	func `block reindentation preserves blank bytes when indentation shrinks or grows`(_ width: Int) throws {
		let blankLines = String(repeating: "\t \n\n", count: 100)
		let source = "'''\n\tvalue😀\n" + blankLines + "\t'''"
		let bytes = Array(("padding" + source).utf8).dropFirst(7)
		let indentation = String(repeating: "\t", count: width)
		let expected = "'''\n" + indentation + "value😀\n" + blankLines + indentation + "'''"
		let result = bytes.reindentingBlockString(with: repeatElement(.tab, count: width))

		#expect(result == Array(expected.utf8))
		#expect(try SOML.Value(parsingValue: String(decoding: result, as: UTF8.self)) == SOML.Value(parsingValue: source))
	}

	@Test
	func `static UTF8 matching preserves exact bytes and slice offsets`() {
		let cases: [(String, StaticString, Bool)] = [
			("", "", true),
			("null", "null", true),
			("nullx", "null", false),
			("null", "true", false),
			("é", "é", true),
			("e\u{301}", "é", false),
			("\0", "\0", true),
			("😀", "😀", true),
			("true", "true\0", false)
		]

		for (text, literal, matches) in cases {
			let bytes = Array(text.utf8)
			#expect(bytes.elementsEqual(literal) == matches)
			#expect(text.utf8.elementsEqual(literal) == matches)
			#expect((Array("padding".utf8) + bytes).dropFirst(7).elementsEqual(literal) == matches)
		}
	}

	@Test
	func `coding key word initials keep digits and internal punctuation unchanged`() {
		#expect("é-1BAR-a.b".convertedToCamelCase(separator: "-") == "é1barA.b")
		#expect("first-1BAR-a.b".convertedToCamelCase(separator: "-") == "first1barA.b")
	}

	@Test
	func `fixed keywords require complete spelling and a value boundary`() throws {
		let keywords: [(String, SOML.Value)] = [("true", true), ("false", false), ("null", .null), ("infinity", .float(.infinity)), ("-infinity", .float(-.infinity))]
		for (word, value) in keywords {
			#expect(try SOML.Value(parsingValue: word) == value)
			#expect(try SOML.Value(parsing: "[\(word), \(word)]") == .array([value, value]))
			for count in 0..<word.utf8.count {
				let truncated = String(word.prefix(count))
				#expect(throws: SOML.ParseError.self) {
					try SOML.Value(parsingValue: truncated)
				}
			}
			for suffix in ["a", "0", "_", "-"] {
				#expect(throws: SOML.ParseError.self) {
					try SOML.Value(parsingValue: word + suffix)
				}
			}
		}
	}

	@Test(arguments: ["true", "false", "null"])
	func `JSON keyword matching rejects every truncated prefix and bare suffix`(_ word: String) throws {
		let expected = try SOML.Value(parsingValue: word)
		#expect(try SOML.Value(parsingJSON: word) == expected)
		#expect(try SOML.Value(parsingJSON: "[\(word),\(word)]") == .array([expected, expected]))
		for count in 0..<word.utf8.count {
			#expect(throws: SOML.JSONError.self) {
				try SOML.Value(parsingJSON: String(word.prefix(count)))
			}
		}
		for suffix in ["a", "0", "_", "-"] {
			#expect(throws: SOML.JSONError.self) {
				try SOML.Value(parsingJSON: word + suffix)
			}
		}
	}

	@Test
	func `generic optional array decoding preserves null end and failed conversion indices`() throws {
		struct Item: Decodable, Equatable {
			let count: Int
		}
		struct Read: Decodable {
			init(from decoder: any Decoder) throws {
				var container = try decoder.unkeyedContainer()
				#expect(try container.decodeIfPresent(Item.self) == nil)
				#expect(container.currentIndex == 1)
				#expect(try container.decodeIfPresent(Item.self) == Item(count: 2))
				#expect(container.currentIndex == 2)
				#expect(throws: DecodingError.self) {
					try container.decodeIfPresent(Item.self)
				}
				#expect(container.currentIndex == 2)
				#expect(try container.decodeIfPresent(String.self) == "retry")
				#expect(container.currentIndex == 3)
				#expect(try container.decodeIfPresent(Item.self) == nil)
				#expect(container.currentIndex == 3)
			}
		}
		_ = try SOML.Decoder().decode(Read.self, from: "[null, {count: 2}, 'retry']")
	}

	@Test
	func `generic optional decoding propagates custom errors without consuming the item`() throws {
		enum Failure: Error, Equatable {
			case expected
		}
		struct Failing: Decodable {
			init(from decoder: any Decoder) throws {
				throw Failure.expected
			}
		}
		struct Read: Decodable {
			init(from decoder: any Decoder) throws {
				var container = try decoder.unkeyedContainer()
				#expect(throws: Failure.expected) {
					try container.decodeIfPresent(Failing.self)
				}
				#expect(container.currentIndex == 0)
				#expect(try container.decode(Int.self) == 7)
				#expect(container.currentIndex == 1)
			}
		}
		_ = try SOML.Decoder().decode(Read.self, from: "[7]")
	}

	@Test
	func `object decoding does not probe unrelated foreign containers`() throws {
		enum Failure: Error, Equatable {
			case expected
		}
		final class Visits {
			var unrelatedContainers = 0
		}
		struct Probe: Decoder {
			let visits: Visits
			let codingPath = [any CodingKey]()
			let userInfo = [CodingUserInfoKey: Any]()

			func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
				throw Failure.expected
			}

			func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
				visits.unrelatedContainers += 1
				throw Failure.expected
			}

			func singleValueContainer() throws -> any SingleValueDecodingContainer {
				visits.unrelatedContainers += 1
				throw Failure.expected
			}
		}
		let visits = Visits()
		#expect(throws: Failure.expected) {
			try SOML.Object(from: Probe(visits: visits))
		}
		#expect(visits.unrelatedContainers == 0)
		let object = try JSONDecoder().decode(SOML.Object.self, from: Data(#"{"é":1,"other":2,"items":[null,true]}"#.utf8))
		#expect(object.count == 3)
		#expect(object["é"] == 1)
		#expect(object["other"] == 2)
		#expect(object["items"] == [nil, true])
	}

	@Test
	func `mapping ordered values preserves typed errors and the original lookup index`() throws {
		enum Failure: Error, Equatable {
			case expected
		}
		var original = OrderedMembers<Int>()
		for index in 0..<80 {
			original.append(index, forKey: "key\(index)")
		}
		let mapped = original.mapValues { $0 * 2 }
		#expect(mapped.keys == original.keys)
		for index in 0..<80 {
			#expect(mapped.value(forKey: "key\(index)") == index * 2)
			#expect(original.value(forKey: "key\(index)") == index)
		}
		func fail() throws(Failure) {
			_ = try original.mapValues { (value) throws(Failure) -> Int in
				guard value != 50 else {
					throw .expected
				}

				return value
			}
		}
		#expect(throws: Failure.expected, performing: fail)
		#expect(original.value(forKey: "key79") == 79)
	}

	@Test
	func `byte classification and case conversion cover every possible byte`() {
		for value in 0...255 {
			let byte = UInt8(value)
			#expect(byte.isASCIINonzeroDigit == (49...57).contains(value))
			#expect(byte.isASCIIExponentMarker == (value == 69 || value == 101))
			#expect(byte.isQuote == (value == 34 || value == 39))
			#expect(byte.isSOMLWhitespace == [9, 10, 32].contains(value))
			#expect(byte.isJSONWhitespace == [9, 10, 13, 32].contains(value))
			#expect(byte.asciiLowercased == UInt8((65...90).contains(value) ? value + 32 : value))
			#expect(byte.asciiUppercased == UInt8((97...122).contains(value) ? value - 32 : value))
		}
	}

	@Test(arguments: [0, 0x7F, 0x80, 0x7FF, 0x800, 0xD7FF, 0xE000, 0xFFFF, 0x10000, 0x10FFFF])
	func `scalar appending preserves every UTF8 width boundary`(_ value: UInt32) throws {
		let scalar = try #require(Unicode.Scalar(value))
		var bytes = [UInt8]("prefix".utf8)
		bytes.appendScalar(scalar)
		bytes.appendUTF8("suffix")
		#expect(bytes == Array(("prefix" + String(scalar) + "suffix").utf8))
	}

	@Test
	func `signed decimal writing agrees with the standard library across integer boundaries`() {
		var values: [Int64] = [.min, .min + 1, -1, 0, 1, .max - 1, .max]
		var power: Int64 = 10
		for _ in 0..<17 {
			values += [power - 1, power, power + 1, -power - 1, -power, -power + 1]
			power *= 10
		}
		for value in values {
			var bytes = [UInt8]("prefix".utf8)
			bytes.appendSignedDecimal(value)
			#expect(String(decoding: bytes, as: UTF8.self) == "prefix\(value)")
		}
	}

	@Test
	func `validated integer conversion agrees with Int64 across every supported radix`() {
		let values: [Int64] = [.min, .min + 1, -1, 0, 1, 255, .max - 1, .max]
		for radix: Int64.SOMLRadix in [.binary, .octal, .decimal, .hexadecimal] {
			for value in values {
				let digits = String(value.magnitude, radix: Int(radix.rawValue), uppercase: true)
				let grouped = digits.map(String.init).joined(separator: "_")
				#expect(Int64(validatedDigits: Array(digits.utf8)[...], radix: radix, isNegative: value < 0) == value)
				#expect(Int64(validatedDigits: Array(grouped.utf8)[...], radix: radix, isNegative: value < 0) == value)
			}
			let tooLarge = String(UInt64.max, radix: Int(radix.rawValue), uppercase: true)
			#expect(Int64(validatedDigits: Array(tooLarge.utf8)[...], radix: radix) == nil)
			#expect(Int64(validatedDigits: Array(tooLarge.utf8)[...], radix: radix, isNegative: true) == nil)
		}
	}

	@Test
	func `JSON integer overflow diagnostics keep the end without allocating the full token`() throws {
		for value: Int64 in [.min, .min + 1, -1, 0, 1, .max - 1, .max] {
			#expect(try SOML.Value(parsingJSON: String(value)) == .int(value))
		}
		for token in ["9223372036854775808", "-9223372036854775809", String(repeating: "9", count: 100_000) + "1234567890123456789"] {
			let error = try #require(throws: SOML.JSONError.self) {
				try SOML.Value(parsingJSON: "[\(token)]")
			}
			#expect(error.message.contains("64-bit range"))
			#expect(error.location?.offset == 1)
			#expect(error.message.utf8.count < 150)
			if token.utf8.count > 40 {
				#expect(error.message.contains("…1234567890123456789"))
			}
		}
	}

	@Test(arguments: [Sample("underflow", "0." + String(repeating: "0", count: 100_000) + "1e-300"), Sample("overflow", "1" + String(repeating: "0", count: 100_000) + ".0")])
	func `rejected huge JSON floats report bounded messages at their starting offset`(_ sample: Sample) throws {
		let token = sample.source
		let error = try #require(throws: SOML.JSONError.self) {
			try SOML.Value(parsingJSON: "{\"number\": \(token)}")
		}
		#expect(error.location?.offset == 11)
		#expect(error.message.utf8.count < 180)
		#expect(error.message.contains("…"))
	}

	@Test
	func `byte scans preserve nonzero slice indices and incomplete delimiters`() {
		let bytes = Array("paddingaaa\n/**/tail/*/".utf8)
		let slice = bytes.dropFirst(7)
		#expect(slice.endOfRun(of: UInt8(ascii: "a"), from: 7) == 10)
		#expect(slice.lineEnd(from: 7) == 10)
		#expect(slice.lineEnd(from: 11) == bytes.count)
		#expect(slice.blockCommentEnd(from: 13) == 15)
		#expect(slice.blockCommentEnd(from: bytes.count - 1) == bytes.count)
		#expect(slice.endOfRun(of: .slash, from: bytes.count) == bytes.count)
	}

	@Test
	func `ASCII patterns require exact lengths and ASCII digits`() {
		for text in ["0000-00-00", "2026-10-13", "9999-99-99", "2026-10-1", "2026-10-130", "２０２６-10-13", "2026_10-13", "202a-10-13"] {
			let bytes = Array(text.utf8)
			let expected = bytes.count == 10 && bytes.enumerated().allSatisfy { index, byte in
				[4, 7].contains(index) ? byte == 45 : (48...57).contains(byte)
			}
			#expect(bytes.hasASCIIPattern("0000-00-00") == expected)
			#expect((Array("padding".utf8) + bytes).dropFirst(7).hasASCIIPattern("0000-00-00") == expected)
		}
	}

	@Test
	func `ASCII word conversion agrees with Foundation for generated coding keys`() throws {
		struct Names: Decodable {
			let firstName: Int
			let _firstName_: Int
		}
		let foundation = JSONDecoder()
		foundation.keyDecodingStrategy = .convertFromSnakeCase
		for first in ["FIRST", "First", "first"] {
			for second in ["NAME", "Name", "name"] {
				for separator in ["_", "__", "___"] {
					let key = first + separator + second
					let padded = "_" + key + "_"
					let decoded = try foundation.decode(Names.self, from: Data("{\"\(key)\":1,\"\(padded)\":2}".utf8))
					#expect(decoded.firstName == 1)
					#expect(decoded._firstName_ == 2)
					#expect(key.convertedToCamelCase(separator: "_") == "firstName")
					#expect(padded.convertedToCamelCase(separator: "_") == "_firstName_")
				}
			}
		}
		#expect("__FIRST__".convertedToCamelCase(separator: "_") == "__FIRST__")
		#expect("naïve_NAME".convertedToCamelCase(separator: "_") == "naïveName")
		#expect("ÉTAT__URL".convertedToCamelCase(separator: "_") == "étatUrl")
	}

	@Test(arguments: [false, true])
	func `descriptions bound unsupported nesting without losing surrounding values`(_ usesObjects: Bool) {
		var value = SOML.Value.int(1)
		for _ in 0..<150 {
			value = usesObjects ? .object(["child": value]) : .array([value])
		}
		let text = SOML.Value.array([value, 42]).description
		#expect(text.contains("…"))
		#expect(text.hasSuffix("\n\t42\n]"))
		#expect(text.utf8.count < 15_000)
	}

	@Test(arguments: ["value: @/* note */", "[@/* note */]", "@/* unfinished"])
	func `invalid token recovery preserves following block comments`(_ source: String) throws {
		let bytes = Array(source.utf8)
		let tokens = SOML.Token.tokens(in: source)
		let comment = try #require(tokens.first { $0.kind == .comment })
		#expect(String(decoding: bytes[comment.range], as: UTF8.self).hasPrefix("/*"))
		#expect(SOML.lexicalContext(in: source, atUTF8Offset: comment.range.lowerBound + 2) == .comment)
		#expect(tokens.contains { $0.kind == .invalid && bytes[$0.range].elementsEqual("@".utf8) })
	}

	@Test
	func `coding keys distinguish canonically equivalent scalar sequences`() {
		let composed = SOMLCodingKey(stringValue: "é")
		let decomposed = SOMLCodingKey(stringValue: "e\u{301}")
		#expect(composed != decomposed)
		#expect(Set([composed, decomposed]).count == 2)
		#expect(SOMLCodingKey(stringValue: "0") != SOMLCodingKey(intValue: 0))
		#expect(SOMLCodingKey(intValue: -1).stringValue == "-1")
	}

	@Test
	func `huge block delimiters cannot expand an error message`() throws {
		let delimiter = String(repeating: "'", count: 100_000)
		let source = "text: " + delimiter + "\nx" + delimiter
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.Value(parsing: source)
		}
		#expect(error.message.utf8.count < 300)
		#expect(error.message.contains("closing delimiter must start a line"))
	}

	@Test
	func `JSON key validation identifies the offending nested key`() throws {
		let value: SOML.Value = ["settings": ["bad\rkey": 1]]
		let error = try #require(throws: SOML.JSONError.self) {
			try value.jsonText()
		}
		#expect(error.message.contains("settings."))
		#expect(error.message.contains("bad"))
		#expect(error.message.contains("key"))
		#expect(!error.message.unicodeScalars.contains("\r"))
	}

	@Test
	func `wide object reversal preserves exact Unicode keys comments and source snapshots`() throws {
		let keys = (0..<2000).map { "key\($0)" } + ["é", "e\u{301}", "😀"]
		let lines = keys.enumerated().map { "\(CanonicalWriter.key($0.element)): \($0.offset) # comment \($0.offset)\n" }
		let document = try SOML.Document(parsing: lines.joined())
		let paths = keys.reversed().map { SOML.KeyPath([$0]) }
		let reordered = try document.reordering(paths)
		#expect(reordered.text == lines.reversed().joined())
		#expect(reordered.value == document.value)
		#expect(reordered.value.objectValue?.keys.map { Array($0.utf8) } == keys.reversed().map { Array($0.utf8) })
		#expect(document.text == lines.joined())
		for index in [0, 1000, 1999, 2000, 2001, 2002] {
			#expect(document.comments(at: SOML.KeyPath([keys[index]]))?.trailing == "comment \(index)")
		}
	}

	@Test
	func `array permutations follow positions even when values are equal`() throws {
		let document = try SOML.Document(parsing: "[\n\t1 # first\n\t1 # second\n\t2 # third\n\t1 # fourth\n]\n")
		let permutations = [[3, 1, 0, 2], [2, 0, 3, 1], [1, 0, 2, 3]]
		let sourceLines = document.text.split(separator: "\n").map(String.init)
		for permutation in permutations {
			let result = try document.reordering(permutation.map { SOML.KeyPath([.index($0)]) })
			let expected = "[\n" + permutation.map { sourceLines[$0 + 1] + "\n" }.joined() + "]\n"
			#expect(result.text == expected)
			#expect(result.value.arrayValue == permutation.map { document.value[$0]! })
		}
	}

	@Test
	func `removing an absent comment reuses the validated source storage`() throws {
		let document = try SOML.Document(parsing: "value: 1\n")
		for path: SOML.KeyPath in [["value"], ["missing"]] {
			let result = try document.settingComment(nil, at: path)
			#expect(result.text == document.text)
			let sharesBytes = document.tree.text.withUnsafeBufferPointer { original in
				result.tree.text.withUnsafeBufferPointer { $0.baseAddress == original.baseAddress }
			}
			#expect(sharesBytes)
		}
	}

	@Test
	func `generated deep edits match an independent value model with a large leaf`() throws {
		let keys = (0..<80).map { "key\($0)" }
		let leaf = SOML.Value.string(String(repeating: "texté😀", count: 5000))
		var expected = leaf
		for key in keys.reversed() {
			expected = .object(SOML.Object([(key, expected)]))
		}
		let document = try SOML.Document(parsing: "{}")
		let result = try document.setting(leaf, at: SOML.KeyPath(keys))
		#expect(result.value == expected)
		#expect(try SOML.Value(parsing: result.text) == expected)
		#expect(document.text == "{}")
		#expect(result.formatted() == result.text + "\n")
	}

	@Test
	func `context queries ignore arbitrarily deep incomplete container state`() {
		let prefix = String(repeating: "[{: , ", count: 20_000)
		let quoted = prefix + "\"😀\\\"text\""
		let start = prefix.utf8.count
		let end = quoted.utf8.count
		#expect(SOML.lexicalContext(in: quoted, atUTF8Offset: start) == .code)
		#expect(SOML.lexicalContext(in: quoted, atUTF8Offset: start + 1) == .string(delimiter: "\"", closingDelimiterRange: (end - 1)..<end))
		#expect(SOML.lexicalContext(in: quoted, atUTF8Offset: end) == .code)
		let comment = prefix + "/* unfinished"
		#expect(SOML.lexicalContext(in: comment, atUTF8Offset: comment.utf8.count) == .comment)
	}

	@Test
	func `UTF8 scan agrees with an independent scalar decoder for every single byte mutation`() {
		let original = Array("é€😀".utf8)
		for index in original.indices {
			for replacement in UInt8.min...UInt8.max {
				var bytes = original
				bytes[index] = replacement
				let expected = String(validating: bytes, as: UTF8.self) == nil ? bytes[...].firstInvalidUTF8Offset : nil
				#expect(Parser.scanEncoding(bytes).invalidUTF8Index == expected)
			}
		}
	}

	@Test
	func `bounded shortening respects UTF16 widths at every scalar boundary`() {
		let original = "é😀e\u{301}日"
		let scalars = Array(original.unicodeScalars)
		for limit in 0...12 {
			var width = 0
			var expected = String.UnicodeScalarView()
			for scalar in scalars {
				let next = scalar.value > 0xFFFF ? 2 : 1
				guard width + next <= limit else {
					break
				}
				width += next
				expected.append(scalar)
			}
			let suffix = expected.count == scalars.count ? "" : "…"
			#expect(original.shortened(to: limit) == String(expected) + suffix)
		}
	}

	@Test
	func `decimal appending preserves shared buffers and pads every width boundary`() {
		let original = Array("prefix😀".utf8)
		var values: [UInt64] = [0, 1, .max - 1, .max]
		var power: UInt64 = 10

		for exponent in 1...19 {
			values += [power - 1, power, power + 1]

			if exponent < 19 {
				power *= 10
			}
		}

		for value in values {
			let decimal = String(value)

			for width in [0, 1, 9, 20, 40] {
				var output = original
				output.appendDecimal(value, minimumDigitCount: width)
				output.appendUTF8("suffix")
				let expected = "prefix😀" + String(repeating: "0", count: max(0, width - decimal.count)) + decimal + "suffix"
				#expect(output == Array(expected.utf8))
				#expect(original == Array("prefix😀".utf8))
			}
		}
	}

	@Test
	func `negative diagnostic words match whole ASCII words in every letter case`() throws {
		for word in ["nan", "inf", "infinity"] {
			let letters = Array(word)

			for mask in 0..<(1 << letters.count) {
				let spelling = letters.enumerated().map { index, letter in
					mask & (1 << index) == 0 ? String(letter) : String(letter).uppercased()
				}.joined()
				if spelling == "infinity" {
					#expect(try SOML.Value(parsing: "value: -infinity")["value"] == .float(-.infinity))
					continue
				}

				let error = try #require(parseError("value: -" + spelling))
				let expected = word == "nan" ? "NaN is not representable. Use null for a missing value" : "“-\(spelling)” is not a value. Negative infinity is written -infinity"

				#expect(error.message == expected)
			}
		}

		for word in ["-nano", "-info", "-infinityx", "-n", "-", "-" + String(repeating: "x", count: 10_000)] {
			#expect(try #require(parseError("value: " + word)).message == "Expected a digit or “infinity” after “-”")
		}
	}


	@Test
	func `instant parsing borrows buffers and preserves exact offset nanoseconds`() throws {
		let cases: [(String, SOML.Instant)] = [
			("2026-01-01T00:15:00.000000001+00:30", try #require(SOML.Instant(year: 2025, month: 12, day: 31, hour: 23, minute: 45, nanosecond: 1))),
			("2026-12-31T23:45:00.999999999-00:30", try #require(SOML.Instant(year: 2027, month: 1, day: 1, minute: 15, nanosecond: 999_999_999))),
			("0001-01-01T00:00:00Z", .minimum),
			("9999-12-31T23:59:59.999999999Z", .maximum),
		]

		for (text, expected) in cases {
			#expect(SOML.Instant(text) == expected)
			#expect(SOML.Instant(NSMutableString(string: text) as String) == expected)
			let borrowed = try text.withUTF8Buffer { try SOML.Instant.parse($0) }
			#expect(borrowed == expected)
			let padded = Array("padding".utf8) + Array(text.utf8) + Array("suffix".utf8)
			#expect(try SOML.Instant.parse(padded[7..<(7 + text.utf8.count)]) == expected)
		}
	}

	@Test
	func `indentation appending keeps shared prefixes and handles zero depth`() {
		let original = Array("prefix😀".utf8)

		for depth in 0...100 {
			var output = original
			output.appendIndentation(depth)
			output.appendUTF8("suffix")
			#expect(output == Array(("prefix😀" + String(repeating: "\t", count: depth) + "suffix").utf8))
			#expect(original == Array("prefix😀".utf8))
		}
	}

	@Test
	func `array finalization leaves its storage intact after a late error`() throws {
		let storage = ArrayStorage()
		let text = String(repeating: "é😀", count: 1000)
		storage.items = Array(repeating: .value(.string(text)), count: 40)
		storage.items.append(.invalid(.invalidValue("bad", .init(codingPath: [SOMLCodingKey(intValue: 40)], debugDescription: "expected failure"))))
		storage.items.append(.value(.bool(true)))

		let error = try #require(throws: EncodingError.self) {
			try EncodedValue.array(storage).finalized()
		}
		guard case .invalidValue(_, let context) = error else {
			Issue.record("Expected the array member's encoding error")
			return
		}

		#expect(context.codingPath.last?.intValue == 40)
		#expect(context.debugDescription == "expected failure")
		#expect(storage.items.count == 42)
		storage.items.remove(at: 40)
		let finalized = try EncodedValue.array(storage).finalized()
		#expect(finalized == .array(Array(repeating: .string(text), count: 40) + [.bool(true)]))
	}

	@Test
	func `numeric diagnostic scans preserve precedence and their bounded prefix`() throws {
		let cases: [(String, String)] = [
			("0B1", "A number prefix is lowercase"),
			("-0XFF", "A number prefix is lowercase"),
			("0B+1", "A “+” sign is not allowed"),
			("0_1", "Leading zeros are not allowed"),
			("099", "Leading zeros are not allowed in a decimal number. Write an identifier"),
			("-012", "Leading zeros are not allowed in a decimal number"),
			("5.", "A decimal point must be followed by a digit"),
			("-5.e", "A decimal point must be followed by a digit"),
			("1.2.3", "Invalid number"),
			("1e-0", "“e-0” is not allowed"),
			(String(repeating: "1", count: 999) + "._", "A decimal point must be followed by a digit"),
			("-" + String(repeating: "1", count: 998) + ".", "A decimal point must be followed by a digit"),
			("-" + String(repeating: "1", count: 999) + ".", "Invalid number"),
		]

		for (text, expected) in cases {
			#expect(try #require(parseError("value: " + text)).message.hasPrefix(expected))
		}
	}

	@Test
	func `exponent diagnoses keep their precedence at the diagnostic byte limit`() throws {
		let cases: [(String, String)] = [
			(String(repeating: "1", count: 997) + "e-0", "“e-0” is not allowed"),
			("-" + String(repeating: "1", count: 997) + "e-0", "Expected digits after the exponent marker"),
			(String(repeating: "1", count: 998) + "e-0", "Expected digits after the exponent marker"),
			(String(repeating: "1", count: 999) + "e-0", "Expected digits after the exponent marker"),
			("-" + String(repeating: "1", count: 999) + "e-0", "Invalid number"),
			(String(repeating: "1", count: 997) + "e01", "Leading zeros are not allowed in an exponent"),
			("-" + String(repeating: "1", count: 997) + "e01", "Invalid number"),
			(String(repeating: "1", count: 999) + "E2", "An exponent marker is a lowercase"),
			("-" + String(repeating: "1", count: 999) + "E2", "Invalid number"),
			(String(repeating: "1", count: 996) + "e0_1", "Leading zeros are not allowed in an exponent"),
			("-" + String(repeating: "1", count: 996) + "e0_1", "An underscore in a number must be between two digits"),
		]

		for (token, expected) in cases {
			let error = try #require(parseError("value: " + token))
			#expect(error.message.hasPrefix(expected))
			#expect(error.location.offset == 7)
			#expect(error.message.utf8.count < 300)
		}
	}

	@Test
	func `numeric hints distinguish incomplete exponents malformed separators and colon groups`() throws {
		let cases: [(String, String)] = [
			("-1_2.3_4E-_", "An exponent marker is a lowercase"),
			("1e-0x", "Invalid number “1e-0x”. A string value must be quoted"),
			("5e0_1x", "Leading zeros are not allowed in an exponent"),
			("1.5_e-0", "An underscore in a number must be between two digits"),
			("1.5E-0x", "Invalid number “1.5E-0x”. A string value must be quoted"),
			("1.e-0", "A decimal point must be followed by a digit"),
			("1e--0", "Invalid number"),
			("1_2x_", "Invalid number “1_2x_”. A string value must be quoted"),
			("1:02:03", "A time of day is a string"),
			("123:02", "Invalid number “123:02”. A value that contains “:” must be quoted"),
			("1:02:3", "Invalid number “1:02:3”. A value that contains “:” must be quoted"),
			("1:02:03:04", "Invalid number “1:02:03:04”. A value that contains “:” must be quoted"),
			("1::02", "Invalid number “1::02”"),
			("1:02:", "Invalid number “1:02:”"),
		]

		for (token, expected) in cases {
			let error = try #require(parseError("value: " + token + " # retained comment"))
			#expect(error.message.hasPrefix(expected))
			#expect(error.location.offset == 7)
		}
	}

}

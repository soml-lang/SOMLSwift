import Foundation
import Testing
@testable import SOML

@Suite
struct JSONTests {
	@Test
	func `surrogate decoding covers every lead and trail boundaries`() throws {
		for lead in UInt32(0xD800)...UInt32(0xDBFF) {
			for trail: UInt32 in [0xDC00, 0xDE00, 0xDFFF] {
				let expected = 0x10000 + (lead - 0xD800) * 0x400 + (trail - 0xDC00)
				let json = "\"\\u\(String(lead, radix: 16))\\u\(String(trail, radix: 16))\""
				let text = try #require(try SOML.Value(parsingJSON: json).stringValue)
				#expect(text.unicodeScalars.map(\.value) == [expected])
			}
		}
	}

	@Test(arguments: ["e", "E+"])
	func `rounds long halfway decimals to the even float`(_ exponent: String) throws {
		let number = "1.00000000000000011102230246251565404236316680908203125" + String(repeating: "0", count: 900) + exponent + "0"
		#expect(try SOML.Value(parsingJSON: "[\(number), -\(number)]") == [.float(1), .float(-1)])
	}

	@Test
	func `reads long finite decimals`() throws {
		let padding = String(repeating: "0", count: 20_000)
		let cases: [(String, Double)] = [
			("1." + padding, 1),
			("1E+" + padding, 1),
			("0." + padding, 0),
			("1." + padding + "E+2", 100),
			("100." + padding + "E-2", 1),
			("1" + padding + "e-20000", 1),
		]

		for (number, expected) in cases {
			#expect(try SOML.Value(parsingJSON: "[\(number)]") == [.float(expected)])
		}
	}

	func json(_ document: String, format: SOML.JSONFormat = .plain) throws -> String {
		try SOML.Value(parsing: document).jsonText(format: format)
	}

	func readError(_ json: String, format: SOML.JSONFormat = .plain) -> SOML.JSONError? {
		do {
			let value = try SOML.Value(parsingJSON: json, format: format)
			Issue.record("Expected an error, got \(value)")
			return nil
		} catch {
			return error
		}
	}

	func writeError(_ document: String) throws -> String? {
		do {
			_ = try SOML.Value(parsing: document).jsonText()
			Issue.record("Expected an error")
			return nil
		} catch let error as SOML.JSONError {
			#expect(error.location == nil)
			return error.message
		}
	}

	@Test
	func `writes every type`() throws {
		#expect(try json("s: 'a\"b'\ni: 9007199254740993\nf: 1.0\nb: true\nn: null\nt: 2026-09-19T16:00:00+02:00\nd: 90m\na: []\no: {}\n") == """
			{
				"s": "a\\"b",
				"i": 9007199254740993,
				"f": 1.0,
				"b": true,
				"n": null,
				"t": "2026-09-19T14:00:00Z",
				"d": "1h30m",
				"a": [],
				"o": {}
			}

			""")
	}

	@Test
	func `escapes every control character, including C1, and keeps member order`() throws {
		#expect(try json("a: \"\u{9B}2J \u{A0}\"") == "{\n\t\"a\": \"\\u009b2J \u{A0}\"\n}\n")
		#expect(try json("z: 1\na: [\"\\u{0}\\n\\u{7f}\\t\"]\n") == "{\n\t\"z\": 1,\n\t\"a\": [\n\t\t\"\\u0000\\n\\u007f\\t\"\n\t]\n}\n")
	}

	@Test
	func `keeps keys that are only canonically equivalent apart, in both directions`() throws {
		#expect(try json("'\u{E9}': 1\n'e\u{301}': 2\n") == "{\n\t\"\u{E9}\": 1,\n\t\"e\u{301}\": 2\n}\n")
		#expect(try SOML.Value(parsingJSON: "{\"\u{E9}\": 1, \"e\u{301}\": 2}").objectValue?.keys == ["\u{E9}", "e\u{301}"])
	}

	@Test
	func `refuses infinity, NaN, and a duration SOML cannot hold, with the key path`() throws {
		#expect(try writeError("a: {b: [infinity]}") == "JSON has no infinity (at a.b[0])")
		#expect(try writeError("'the key': {x: [1.0, {y: -infinity}]}") == "JSON has no -infinity (at \"the key\".x[1].y)")
		#expect(try writeError("'a.b': [infinity]") == "JSON has no infinity (at \"a.b\"[0])")
		#expect(try writeError("[[infinity]]") == "JSON has no infinity (at [0][0])")
		for format in [SOML.JSONFormat.plain, .tagged] {
			#expect(throws: SOML.JSONError.self) {
				try SOML.Value.array([.float(.nan)]).jsonText(format: format)
			}
		}

		// Tagged JSON writes infinity as text, and it reads back.
		let infinity = SOML.Value.array([.float(.infinity), .float(-.infinity)])
		#expect(try SOML.Value(parsingJSON: infinity.jsonText(format: .tagged), format: .tagged) == infinity)
		#expect(throws: SOML.JSONError.self) {
			try SOML.Value.array([.duration(.seconds(Int64.max))]).jsonText()
		}
	}

	@Test
	func `a number SOML cannot hold is refused at its line and column, and the smallest float is not`() throws {
		for json in ["9223372036854775808", "-9223372036854775809", "1e400", "-1e400", "1e-400", "-2e-324"] {
			let error = try #require(readError("{\"a\":\n [\(json)]}"))
			#expect(error.location?.line == 2, "\(json)")
			#expect(error.location?.column == 3, "\(json)")
		}

		#expect(try SOML.Value(parsingJSON: "[5e-324, -9223372036854775808, 9223372036854775807]") == [.float(5e-324), .int(.min), .int(.max)])
	}

	@Test
	func `an int keeps every digit and the members keep their order, in both directions`() throws {
		let value = try SOML.Value(parsingJSON: #"{"z": 9007199254740993, "a": 1.0, "m": 10}"#)
		#expect(value == ["z": .int(9_007_199_254_740_993), "a": .float(1), "m": .int(10)])
		#expect(value.objectValue?.keys == ["z", "a", "m"])
		#expect(try value.jsonText() == "{\n\t\"z\": 9007199254740993,\n\t\"a\": 1.0,\n\t\"m\": 10\n}\n")
	}

	@Test
	func `an instant is written as its canonical text, and a string that looks like an instant or a duration stays a string`() throws {
		let value: SOML.Value = ["at": .instant(try #require(SOML.Instant("2026-09-19T14:00:00.50+02:00")))]
		#expect(try value.jsonText() == "{\n\t\"at\": \"2026-09-19T12:00:00.5Z\"\n}\n")
		#expect(try SOML.Value(parsingJSON: #"{"at": "2026-09-19T12:00:00Z", "timeout": "1h30m"}"#) == ["at": "2026-09-19T12:00:00Z", "timeout": "1h30m"])
	}

	@Test
	func `refuses to write what SOML cannot hold, so the JSON always reads back`() throws {
		for format in [SOML.JSONFormat.plain, .tagged] {
			let string = try #require(#expect(throws: SOML.JSONError.self) {
				try SOML.Value.object(["a": ["line\r\n"]]).jsonText(format: format)
			})
			#expect(string.message == "A string cannot contain a carriage return, because SOML cannot represent one (at a[0])")
			#expect(string.location == nil)

			let key = try #require(#expect(throws: SOML.JSONError.self) {
				try SOML.Value.object(["a": ["b\r": 1]]).jsonText(format: format)
			})
			#expect(key.message == #"A key cannot contain a carriage return, because SOML cannot represent one (at a."b\r")"#)

			// 100 levels is the most a reader accepts, also for a tagged scalar at the deepest level.
			let hundred = (1..<100).reduce(SOML.Value.array([1])) { value, _ in .array([value]) }
			let text = try hundred.jsonText(format: format)
			#expect(try SOML.Value(parsingJSON: text, format: format) == hundred)

			let tooDeep = try #require(#expect(throws: SOML.JSONError.self) {
				try SOML.Value.array([hundred]).jsonText(format: format)
			})
			#expect(tooDeep.message.hasPrefix("The value is nested more than 100 levels deep, which is the most SOML allows (at [0][0]"))

			let tooDeepObject = SOML.Value.object(["a": (1..<100).reduce(SOML.Value.object([:])) { value, _ in .object(["b": value]) }])
			#expect(throws: SOML.JSONError.self) {
				try tooDeepObject.jsonText(format: format)
			}
		}
	}

	@Test
	func `tagged JSON refuses exactly the values that canonical SOML refuses, and what it writes reads back`() throws {
		let deep = (1..<100).reduce(SOML.Value.array([1])) { value, _ in .array([value]) }
		let values: [SOML.Value] = [
			["line\r\n"],
			["\r"],
			.object(["a\rb": 1]),
			.object(["a": .object(["b": ["c\r"]])]),
			["a\nb", "\u{0}", "\u{85}", "\u{2028}"],
			[.float(.nan)],
			[.float(.infinity), .float(-.infinity)],
			[.duration(.seconds(Int64.max))],
			[.duration(.nanoseconds(Int64.min))],
			[.duration(.nanoseconds(1) / 2)],
			deep,
			[deep],
			.object(["a": deep]),
		]

		for value in values {
			let tagged = try? value.jsonText(format: .tagged)
			#expect((tagged == nil) == ((try? value.canonicalDocument()) == nil), "\(value)")

			if let tagged {
				#expect(try SOML.Value(parsingJSON: tagged, format: .tagged) == value)
			}

			// Plain JSON refuses the same, and infinity too, which it has no number for.
			if let plain = try? value.jsonText() {
				#expect(tagged != nil)
				#expect(throws: Never.self) {
					try SOML.Value(parsingJSON: plain)
				}
			}
		}
	}

	@Test
	func `reads numbers by their syntax`() throws {
		#expect(try SOML.Value(parsingJSON: "[1, 1.0, 1e2, -0, 9223372036854775807, -9223372036854775808, \"2026-09-19T14:00:00Z\", 0.0e-400, -0.0]") == [1, .float(1.0), .float(100.0), 0, .int(.max), .int(.min), "2026-09-19T14:00:00Z", .float(0), .float(0)])
		#expect(readError("[9223372036854775808]")?.message == "The int 9223372036854775808 is outside the 64-bit range of a SOML int")
		#expect(readError("[1e400]")?.message == "The float 1e400 is too large for a 64-bit float")
		#expect(readError("[1e-400]")?.message == "The float 1e-400 is too small for a 64-bit float, so it would become 0.0")
	}

	@Test
	func `refuses what SOML cannot hold, with a position`() throws {
		let duplicate = try #require(readError("{\"a\": 1,\n \"a\": 2}"))
		#expect(duplicate.message == "Duplicate key a. SOML does not allow one")
		#expect(duplicate.location?.line == 2)
		#expect(duplicate.location?.column == 2)
		#expect(readError("[\"\\ud800\"]")?.message == "A lone surrogate is not text, so SOML cannot hold it")
		#expect(readError("[\"\\udc00\"]")?.message == "A lone surrogate is not text, so SOML cannot hold it")
		#expect(readError("[\"\\ud800\\u0041\"]")?.message == "A lone surrogate is not text, so SOML cannot hold it")
		#expect(readError("[\"a\\rb\"]")?.message == "A string cannot contain a carriage return, because SOML cannot represent one")
		#expect(readError("[\"a\\u000Db\"]")?.message == "A string cannot contain a carriage return, because SOML cannot represent one")
		#expect(readError("[\"a\u{1}b\"]")?.message == "A control character must be escaped in a JSON string")

		// A raw carriage return gets the same error as an escaped one, because escaping it, as JSON requires, does not make it a string that SOML can hold.
		let rawCarriageReturn = try #require(readError("{\"a\": \"x\ry\"}"))
		#expect(rawCarriageReturn.message == "A string cannot contain a carriage return, because SOML cannot represent one")
		#expect(rawCarriageReturn.location?.column == 9)
		#expect(readError(String(repeating: "[", count: 101) + String(repeating: "]", count: 101))?.message == "The JSON is nested more than 100 levels deep, which is the most SOML allows")
		#expect(try SOML.Value(parsingJSON: String(repeating: "[", count: 100) + String(repeating: "]", count: 100)).arrayValue != nil)

		// The extra level of tagged JSON is only for a tagged scalar at the deepest level, not for another array or object.
		#expect(readError(String(repeating: "[", count: 101) + String(repeating: "]", count: 101), format: .tagged)?.message == "The JSON is nested more than 100 levels deep, which is the most SOML allows")
		#expect(readError(String(repeating: "[", count: 100) + "{}" + String(repeating: "]", count: 100), format: .tagged) != nil)
		let deepestScalar = String(repeating: "[", count: 100) + "{\"type\": \"int\", \"value\": \"1\"}" + String(repeating: "]", count: 100)
		#expect(throws: Never.self) {
			try SOML.Value(parsingJSON: deepestScalar, format: .tagged)
		}
	}

	@Test
	func `a scalar is a value too, though not a document`() throws {
		#expect(try SOML.Value(parsingJSON: " 1 ") == 1)
		#expect(try SOML.Value(parsingJSON: "\"x\"") == "x")
	}

	@Test(arguments: ["", "[1,]", "{\"a\" 1}", "[01]", "[1.]", "[.5]", "['a']", "[\"\u{1}\"]", "[1] [2]", "{a: 1}", "[\"\\x\"]", "[\"\\u12\"]", "[NaN]", "[\"\\u+123\"]", "[+1]", "[1e]", "[tru]", "[\"a", "{\"a\": 1"])
	func `refuses JSON that is not valid`(_ json: String) {
		#expect(readError(json) != nil)
	}

	@Test
	func `reports where invalid JSON is wrong`() throws {
		let error = try #require(readError("{\n\t\"a\": [1,]\n}"))
		#expect(error.message == "Expected a value")
		#expect(error.location?.line == 2)
		#expect(error.location?.column == 10)
		#expect(error.description == "Expected a value (line 2, column 10)")

		let encoding = try #require(#expect(throws: SOML.JSONError.self) {
			try SOML.Value(parsingJSON: Array("[\"a".utf8) + [0xFF] + Array("\"]".utf8))
		})
		#expect(encoding.message == "The text is not valid UTF-8")
		#expect(encoding.location?.column == 4)
	}

	@Test
	func `reports nesting that is too deep at the first level past the limit`() throws {
		let tooDeep = String(repeating: "[", count: 101)
		let closing = String(repeating: "]", count: 101)
		let scalar = #"{"type": "int", "value": "1"}"#

		#expect(readError(tooDeep + "1" + closing)?.location?.column == 101)
		#expect(readError(tooDeep + closing)?.location?.column == 101)
		#expect(readError(tooDeep + closing, format: .tagged)?.location?.column == 101)

		// In tagged JSON, the level past the limit is read for a tagged scalar, so what is too deep is the container that holds something there, not the tagged scalar.
		let inArray = try #require(readError(tooDeep + scalar + closing, format: .tagged))
		#expect(inArray.message == "The JSON is nested more than 100 levels deep, which is the most SOML allows")
		#expect(inArray.location?.column == 101)

		let hundred = String(repeating: "[", count: 100)
		let hundredClosing = String(repeating: "]", count: 100)
		#expect(readError(hundred + #"{"a": "# + scalar + "}" + hundredClosing, format: .tagged)?.location?.column == 101)
		#expect(readError(hundred + "[[]]" + hundredClosing, format: .tagged)?.location?.column == 101)
		#expect(readError(hundred + "[" + scalar + ", [[]]]" + hundredClosing, format: .tagged)?.location?.column == 101)
		#expect(readError(hundred + "[1]" + hundredClosing)?.location?.column == 101)

		let onSecondLine = try #require(readError("[\n" + hundred + scalar + hundredClosing + "]", format: .tagged))
		#expect(onSecondLine.location?.line == 2)
		#expect(onSecondLine.location?.column == 100)
	}

	@Test
	func `reports a bad escape after a lead surrogate at that escape`() throws {
		let badHex = try #require(readError(#"["\ud800\uzzzz"]"#))
		#expect(badHex.message == "Invalid “\\u” escape. It needs four hex digits")
		#expect(badHex.location?.column == 9)

		let cutShort = try #require(readError(#"["\ud800\u12"]"#))
		#expect(cutShort.message == "Invalid “\\u” escape. It needs four hex digits")
		#expect(cutShort.location?.column == 9)

		// A lone surrogate is the lead, so the error stays on it.
		#expect(readError(#"["\ud800A"]"#)?.location?.column == 3)
		#expect(readError(#"["\ud800x"]"#)?.location?.column == 3)
		#expect(readError(#"["\ud800"]"#)?.location?.column == 3)
		#expect(readError(#"["\uzzzz"]"#)?.location?.column == 3)
		#expect(readError(#"["\udc00\udc00"]"#)?.location?.column == 3)
		#expect(readError(#"["\ud800\ud800"]"#)?.location?.column == 3)
	}

	@Test
	func `reads escapes and surrogate pairs`() throws {
		#expect(try SOML.Value(parsingJSON: #"["\/\b\f\u00e9\ud83d\ude00\u0000\""]"#) == ["/\u{8}\u{C}\u{E9}\u{1F600}\u{0}\""])
	}

	@Test
	func `a string with many escapes takes linear time`() throws {
		func source(size: Int) -> String {
			"\"" + String(repeating: #"\n"#, count: size) + "\""
		}

		let small = source(size: 25_000)
		let large = source(size: 400_000)
		#expect(try SOML.Value(parsingJSON: large) == .string(String(repeating: "\n", count: 400_000)))

		try expectLinearTime {
			_ = try SOML.Value(parsingJSON: small)
		} large: {
			_ = try SOML.Value(parsingJSON: large)
		}
	}

	@Test(arguments: ["type", "value"])
	func `a tagged scalar with a long run of combining marks takes linear time`(_ member: String) throws {
		// One character that holds every mark, out of canonical order, so that comparing it with `==` normalizes it. It is the type, or the value of a null.
		func source(size: Int) -> String {
			let text = "x" + String(repeating: "\u{315}", count: size) + String(repeating: "\u{300}", count: size)
			return member == "type" ? "{\"type\": \"\(text)\", \"value\": \"1\"}" : "{\"type\": \"null\", \"value\": \"\(text)\"}"
		}

		let small = source(size: 1000)
		let large = source(size: 16_000)
		#expect(readError(large, format: .tagged)?.message.unicodeScalars.starts(with: (member == "type" ? "Unknown type “x" : "Invalid null “x").unicodeScalars) == true)

		expectLinearTime {
			_ = try? SOML.Value(parsingJSON: small, format: .tagged)
		} large: {
			_ = try? SOML.Value(parsingJSON: large, format: .tagged)
		}
	}

	@Test
	func `reads a float at the edges of the 64-bit range, and refuses one just past them`() throws {
		#expect(try SOML.Value(parsingJSON: "[1.7976931348623158e308, 2.4703282292062328e-324]") == [.float(.greatestFiniteMagnitude), .float(.leastNonzeroMagnitude)])
		#expect(readError("[1.7976931348623159e308]")?.message == "The float 1.7976931348623159e308 is too large for a 64-bit float")
		#expect(readError("[2.4703282292062327e-324]")?.message == "The float 2.4703282292062327e-324 is too small for a 64-bit float, so it would become 0.0")
	}

	@Test(arguments: [
		[0xC0, 0xAF],
		[0xE0, 0x80, 0xAF],
		[0xED, 0xA0, 0x80],
		[0xF4, 0x90, 0x80, 0x80],
	] as [[UInt8]])
	func `refuses overlong UTF-8, an encoded surrogate, and a scalar past U+10FFFF, at its first byte`(_ invalid: [UInt8]) throws {
		let error = try #require(#expect(throws: SOML.JSONError.self) {
			try SOML.Value(parsingJSON: Array("[\"\u{E9}".utf8) + invalid + Array("\"]".utf8))
		})
		#expect(error.message == "The text is not valid UTF-8")
		#expect(error.location?.offset == 4)
		#expect(error.location?.column == 4)
	}

	@Test
	func `refuses UTF-8 that is cut short at the end of the text`() throws {
		let error = try #require(#expect(throws: SOML.JSONError.self) {
			try SOML.Value(parsingJSON: Array("\n[\"".utf8) + [0xF0, 0x9F, 0x98])
		})
		#expect(error.message == "The text is not valid UTF-8")
		#expect(error.location?.line == 2)
		#expect(error.location?.column == 3)
	}

	@Test
	func `every valid document writes valid JSON, and tagged JSON reads back to the same value`() throws {
		var failures = [String]()

		for name in ConformanceTests.validCases {
			let value = try SOML.Value(parsing: try Data(contentsOf: ConformanceTests.root.appending(path: "valid/\(name).soml")))

			for format in [SOML.JSONFormat.plain, .tagged] {
				// Only infinity has no plain JSON.
				guard let text = try? value.jsonText(format: format) else {
					continue
				}

				if (try? JSONSerialization.jsonObject(with: Data(text.utf8))) == nil {
					failures.append("\(name), \(format): not valid JSON")
				}

				if
					format == .tagged,
					try SOML.Value(parsingJSON: text, format: .tagged) != value
				{
					failures.append("\(name): tagged JSON does not read back")
				}
			}
		}

		#expect(failures == [])
	}

	@Test
	func `plain JSON reads back to the same value, except instants and durations, which become strings`() throws {
		let value: SOML.Value = ["b": [1, .float(1.5), "x", nil, true], "a": ["c": .int(.max)]]
		#expect(try SOML.Value(parsingJSON: value.jsonText()) == value)
		#expect(try SOML.Value(parsingJSON: SOML.Value.array([.duration(.seconds(90))]).jsonText()) == ["1m30s"])
	}

	@Test
	func `reads only canonical tagged values`() {
		func tagged(_ type: String, _ value: String) -> String {
			"[{\"type\": \"\(type)\", \"value\": \"\(value)\"}]"
		}

		for (type, value) in [("int", "+5"), ("int", "007"), ("int", "-0"), ("float", "1e-400"), ("float", "Infinity"), ("float", "1"), ("float", "0x1p3"), ("float", "nan"), ("bool", "True"), ("null", "nil"), ("instant", "2026-09-19T16:00:00+02:00")] {
			#expect(readError(tagged(type, value), format: .tagged)?.message == "Invalid \(type) “\(value)”. A tagged value must be in canonical form", "\(type) \(value)")
		}

		// The canonical text of a duration in SOML, like `1h30m`, is not its tagged value, which is a count of nanoseconds.
		for value in ["1h30m", "90m", "+5", "1.5"] {
			#expect(readError(tagged("duration", value), format: .tagged)?.message == "Invalid duration “\(value)”. A tagged duration is its length in nanoseconds, as an int in canonical form, like “5400000000000”", "\(value)")
		}

		#expect(readError(tagged("date", "x"), format: .tagged)?.message.hasPrefix("Unknown type “date”.") == true)

		for (type, value) in [("int", "-9223372036854775808"), ("float", "5e-324"), ("float", "-infinity"), ("instant", "0001-01-01T00:00:00Z"), ("duration", "-1"), ("string", "+5")] {
			#expect(throws: Never.self, "\(type) \(value)") {
				try SOML.Value(parsingJSON: tagged(type, value), format: .tagged)
			}
		}
	}

	@Test
	func `in tagged JSON, a plain scalar is an error, and an object whose type and value are tagged stays an object`() throws {
		#expect(readError("[1]", format: .tagged)?.message.hasPrefix("Tagged JSON writes every scalar") == true)
		#expect(readError("{\"a\": \"x\"}", format: .tagged)?.message.hasPrefix("Tagged JSON writes every scalar") == true)

		let object = "{\"type\": {\"type\": \"string\", \"value\": \"a\"}, \"value\": {\"type\": \"int\", \"value\": \"1\"}}"
		#expect(try SOML.Value(parsingJSON: object, format: .tagged) == ["type": "a", "value": 1])
	}
}

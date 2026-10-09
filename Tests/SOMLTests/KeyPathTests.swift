import Testing
@testable import SOML

@Suite
struct KeyPathTests {
	@Test(arguments: [
		("port", ["port"]),
		("server.port", ["server", "port"]),
		("server.'the name'", ["server", "the name"]),
		(#""a.b"."\u{e9}""#, ["a.b", "\u{E9}"]),
		("404.x", ["404", "x"]),
		("''", [""]),
		("servers.0", ["servers", "0"]),
		("servers[0].host", ["servers", 0, "host"]),
		("a.b[12][0]", ["a", "b", 12, 0]),
		("[0].name", [0, "name"]),
		("[3]", [3]),
		("'a[0]'[1]", ["a[0]", 1]),
		(#""x\"[0]"[2].'y'"#, [#"x"[0]"#, 2, "y"]),
	] as [(String, [SOML.KeyPath.Segment])])
	func `parses a key path`(_ text: String, _ segments: [SOML.KeyPath.Segment]) throws {
		#expect(try SOML.KeyPath(parsing: text).segments == segments)
	}

	@Test(arguments: [
		("", "Expected a key"),
		("a.", "Expected a key"),
		(".a", "Expected a key"),
		("a b", "after the end of the key path"),
		(" a", "Expected a key"),
		("a: 1", "after the end of the key path"),
		("a # comment", "after the end of the key path"),
		("'''a'''", "A block string cannot be a key"),
		("a\r", "carriage return"),
		("a[", "Expected an array index"),
		("a[]", "Expected an array index"),
		("a[x]", "Expected an array index"),
		("a[-1]", "Expected an array index"),
		("a[01]", "cannot start with 0"),
		("a[1", "Expected “]”"),
		("a[1]b", "Expected “.”, “[”, or the end"),
		("a[1].", "Expected a key"),
		("a[1].[2]", "Expected a key"),
		("a.[0]", "Expected a key"),
		("a[99999999999999999999]", "too large"),
		("a[0] ", "Expected “.”, “[”, or the end"),
		(".", "Expected a key"),
		("[]", "Expected an array index"),
		("[0].", "Expected a key"),
	])
	func `rejects text that is not exactly one key`(_ text: String, _ fragment: String) {
		#expect {
			try SOML.KeyPath(parsing: text)
		} throws: { error in
			(error as? SOML.ParseError)?.message.contains(fragment) == true
		}
	}

	@Test
	func `the description is the canonical spelling`() {
		#expect(SOML.KeyPath(["server", "port"]).description == "server.port")
		#expect(SOML.KeyPath(["the name"]).description == "'the name'")
		#expect(SOML.KeyPath(["it's", ""]).description == #""it's".''"#)
		#expect(SOML.KeyPath(["\u{1B}"]).description == #""\u{1b}""#)
	}

	@Test
	func `a key with a dot is quoted, and a bare dot separates keys`() throws {
		let path = SOML.KeyPath(["example.com", "port"])
		#expect(path.description == "'example.com'.port")
		#expect(try SOML.KeyPath(parsing: path.description) == path)
		#expect(try SOML.KeyPath(parsing: #""example.com".port"#) == path)
		#expect(try SOML.KeyPath(parsing: "example.com.port").segments == ["example", "com", "port"])
	}

	@Test
	func `the description writes an index in brackets`() {
		#expect(SOML.KeyPath(["servers", 0, "host"]).description == "servers[0].host")
		#expect(SOML.KeyPath([0, 1, "the name"]).description == "[0][1].'the name'")
		#expect(SOML.KeyPath(["0"]).description == "0")
		#expect(SOML.KeyPath(["a[0]"]).description == "'a[0]'")
	}

	@Test
	func `the description parses back to the same segments`() throws {
		let cases: [[SOML.KeyPath.Segment]] = [["a"], ["a.b", "c d"], ["it's", "\"", "\\", "\n", "\u{E9}", "e\u{301}"], [0], ["a", 0, 10, "b[1]", 2], ["", 0, "''"]]

		for segments in cases {
			#expect(try SOML.KeyPath(parsing: SOML.KeyPath(segments).description).segments == segments)
		}
	}

	@Test
	func `an error in a key after an index has its position in the whole path`() throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: "servers[0].a b")
		}

		#expect(error.location.column == 13)
		#expect(error.message == "Unexpected “ ” after the end of the key path")
	}

	@Test
	func `equality compares Unicode scalars, as SOML compares keys`() {
		#expect(SOML.KeyPath(["\u{E9}"]) != SOML.KeyPath(["e\u{301}"]))
		#expect(SOML.KeyPath(["a", "b"]) == SOML.KeyPath(["a", "b"]))
		#expect(SOML.KeyPath(["ab"]) != SOML.KeyPath(["a", "b"]))
		#expect(Set([SOML.KeyPath(["\u{E9}"]), SOML.KeyPath(["e\u{301}"]), SOML.KeyPath(["\u{E9}"])]).count == 2)
		#expect(SOML.KeyPath(["a", 0]) != SOML.KeyPath(["a", "0"]))
		#expect(Set([SOML.KeyPath(["a", 0]), SOML.KeyPath(["a", "0"]), SOML.KeyPath(["a", 0])]).count == 2)
	}
}

@Suite
struct KeyPathLiteralTests {
	@Test
	func `an array literal is a key path of keys and indices`() {
		let path: SOML.KeyPath = ["servers", 0, "the name"]
		#expect(path.segments == [.key("servers"), .index(0), .key("the name")])
		#expect(path.description == "servers[0].'the name'")
	}

	@Test
	func `an API that takes a key path takes a literal`() throws {
		let document = try SOML.Document(parsing: "servers: [{port: 80}] # Kept")
		#expect(try document.setting(8080, at: ["servers", 0, "port"]).text == "servers: [{port: 8080}] # Kept")
	}

	@Test
	func `a value is read and changed at a key path`() throws {
		var value = try SOML.Value(parsing: "servers: [{host: 'a', port: 80}]\nname: 'api'")
		#expect(value[path: ["servers", 0, "port"]] == 80)
		#expect(value[path: ["servers", 1, "port"]] == nil)
		#expect(value[path: ["name", "x"]] == nil)
		#expect(value[path: ["name"]] == "api")

		value[path: ["servers", 0, "port"]] = 8080
		value[path: ["servers", 0, "host"]] = nil
		value[path: ["servers", 0, "tls"]] = true
		#expect(value == ["servers": [["port": 8080, "tls": true]], "name": "api"])

		// A missing step before the last changes nothing.
		value[path: ["missing", "x"]] = 1
		value[path: ["servers", 5, "x"]] = 1
		#expect(value == ["servers": [["port": 8080, "tls": true]], "name": "api"])
	}
}

@Suite
struct SingleValueTests {
	@Test(arguments: [
		("0o644", SOML.Value.int(420)),
		("'text'", "text"),
		("1h30m", .duration(.seconds(5400))),
		("[1, 2]", .array([1, 2])),
		("{a: 1}", .object(["a": 1])),
		("null", nil),
		("-infinity", .float(-.infinity)),
		("'''\n\tline\n\t'''", "line"),
	])
	func `parses one value`(_ text: String, _ expected: SOML.Value) throws {
		#expect(try SOML.Value(parsingValue: text) == expected)
	}

	@Test(arguments: [
		("", "Expected a value"),
		("nope", "Unexpected “nope”. A string value must be quoted"),
		(" 1", "Expected a value"),
		("1 ", "Unexpected “ ” after the end of the value"),
		("1 # comment", "Unexpected “ ” after the end of the value"),
		("1, 2", "Unexpected “,” after the end of the value"),
		("a: 1", "Expected a value, but found the key a"),
	])
	func `rejects text that is not exactly one value`(_ text: String, _ fragment: String) {
		#expect {
			try SOML.Value(parsingValue: text)
		} throws: { error in
			(error as? SOML.ParseError)?.message.contains(fragment) == true
		}
	}

	@Test
	func `a value is nested at most 100 levels deep`() throws {
		let deepest = String(repeating: "[", count: 100) + String(repeating: "]", count: 100)
		#expect(try SOML.Value(parsingValue: deepest).arrayValue != nil)

		let tooDeep = String(repeating: "[", count: 101) + String(repeating: "]", count: 101)
		#expect(throws: SOML.ParseError.self) {
			try SOML.Value(parsingValue: tooDeep)
		}
	}
}

@Suite
struct CanonicalDocumentTests {
	@Test
	func `writes the same text as the encoder in canonical form`() throws {
		let value: SOML.Value = ["b": [1, 2], "a": ["x": "y"], "c": .duration(.milliseconds(1500))]
		var encoder = SOML.Encoder()
		encoder.writesCanonicalForm = true
		#expect(try value.canonicalDocument() == "a: {\n\tx: 'y'\n}\nb: [\n\t1\n\t2\n]\nc: 1.5s\n")
		#expect(try value.canonicalDocument() == String(decoding: try encoder.encode(value), as: UTF8.self))
		#expect(try SOML.Encoder().encodeToString(value) == "b: [\n\t1\n\t2\n]\na: {\n\tx: 'y'\n}\nc: 1.5s\n")
	}

	@Test
	func `a value SOML cannot represent is a typed error that says where it is`() {
		let cases: [(SOML.Value, String, String)] = [
			(.int(1), "A SOML document must be an object or an array, not the int 1", "A SOML document must be an object or an array, not the int 1"),
			(["a": [1, .float(.nan)]], "NaN is not a SOML value", "NaN is not a SOML value (at a[1])"),
			(["the key": ["x": "a\rb"]], "A string cannot contain a carriage return, because SOML cannot represent one", "A string cannot contain a carriage return, because SOML cannot represent one (at \"the key\".x)"),
		]

		for (value, message, description) in cases {
			do throws(SOML.InvalidValueError) {
				_ = try value.canonicalDocument()
				Issue.record("Expected an error for \(value)")
			} catch {
				#expect(error.message == message)
				#expect(error.description == description)
			}
		}
	}

	@Test
	func `exact nanoseconds are public for durations`() {
		#expect(Duration.seconds(90).exactNanoseconds == 90_000_000_000)
		#expect(Duration(secondsComponent: 0, attosecondsComponent: 1).exactNanoseconds == nil)
		#expect(Duration.seconds(Int64.max).exactNanoseconds == nil)
		#expect(Duration.nanoseconds(Int64.max).exactNanoseconds == Int64.max)
		#expect(Duration.nanoseconds(Int64.min).exactNanoseconds == Int64.min)
		#expect((Duration.nanoseconds(Int64.max) + .nanoseconds(1)).exactNanoseconds == nil)
		#expect((Duration.nanoseconds(Int64.min) - .nanoseconds(1)).exactNanoseconds == nil)
		#expect(Duration(secondsComponent: 0, attosecondsComponent: -1).exactNanoseconds == nil)
	}
}

@Suite
struct MessageSafetyTests {
	@Test
	func `terminal sanitization replaces unsafe scalars individually and preserves Unicode and tabs`() throws {
		let unsafeValues = Array(UInt32(0)...8) + Array(UInt32(10)...31) + Array(UInt32(127)...159) + [0x061C, 0x200E, 0x200F] + Array(UInt32(0x202A)...0x202E) + Array(UInt32(0x2066)...0x2069)
		let safe = "é e\u{301} 😀\t\u{200D}"
		var original = safe
		var expected = safe

		for value in unsafeValues {
			original.unicodeScalars.append(try #require(Unicode.Scalar(value)))
			original += safe
			expected += "\u{FFFD}" + safe
		}

		let sanitized = original.sanitizedForTerminal
		#expect(Array(sanitized.utf8) == Array(expected.utf8))
		#expect(sanitized.unicodeScalars.count == original.unicodeScalars.count)
		#expect(Array(sanitized.sanitizedForTerminal.utf8) == Array(expected.utf8))
		#expect(Array(safe.sanitizedForTerminal.utf8) == Array(safe.utf8))
	}

	@Test
	func `a parse error never holds a character that a terminal acts on`() throws {
		for source in [#""\u{1b}[2J": 1"# + "\n" + #""\u{1b}[2J": 2"#, "'\u{9B}31m': 1\n'\u{9B}31m': 2", "\"\\u{202e}x\": 1\n\"\\u{202e}x\": 2"] {
			let error = try #require(parseError(source))
			#expect(!error.message.unicodeScalars.contains { $0.properties.generalCategory == .control || $0.properties.isBidiControl }, "\(error.message.debugDescription)")
		}
	}

	@Test
	func `a decoding error never holds a character that a terminal acts on`() throws {
		struct Port: Decodable {
			var port: Int
		}

		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true

		for source in ["port: 1\n\"\\u{9b}2J\": 1", "port: \"\\u{202e}80\"", "\"po\\u{9b}rt\": 1"] {
			do {
				_ = try decoder.decode(Port.self, from: source)
				Issue.record("Expected an error for \(source)")
			} catch let error as DecodingError {
				let description: String = switch error {
				case .dataCorrupted(let context), .typeMismatch(_, let context), .keyNotFound(_, let context), .valueNotFound(_, let context):
					context.debugDescription
				@unknown default:
					""
				}

				#expect(!description.isEmpty)
				#expect(!description.unicodeScalars.contains { $0.properties.generalCategory == .control || $0.properties.isBidiControl }, "\(description.debugDescription)")
			}
		}
	}
}

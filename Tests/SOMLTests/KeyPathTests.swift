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
		("a[-1]", "An array index cannot be negative"),
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

	// The text after `].` follows a dot, so it is read as a key after a dot, and a U+FEFF there is not at the start of the text, so it is not a BOM.
	@Test(arguments: [
		("[0].\u{FEFF}b", "Expected a key after “.”, but found U+FEFF (ZERO WIDTH NO-BREAK SPACE", 5),
		("a.\u{FEFF}b", "Expected a key after “.”, but found U+FEFF (ZERO WIDTH NO-BREAK SPACE", 3),
		("[0].[1]", "Expected a key after “.”, but found “[”", 5),
		("a[0].😀", "Expected a key after “.”, but found “😀”", 6),
		("a.😀", "Expected a key after “.”, but found “😀”", 3),
		("[0].", "Expected a key after “.”", 5),
		("\u{FEFF}a", "A byte order mark (BOM) is not allowed", 1),
	])
	func `a key after an index is read as a key after a dot`(_ text: String, _ message: String, _ column: Int) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}

		#expect(error.message.hasPrefix(message), "\(error.message)")
		#expect(error.location.column == column)
	}

	@Test(arguments: [
		("a$", "Unexpected “$” after the end of the key path. A key that contains characters other than letters, digits, “_”, and “-” must be quoted", 2),
		("a.b$", "Unexpected “$” after the end of the key path. A key that contains characters other than letters, digits, “_”, and “-” must be quoted", 4),
		("servers[0].b$", "Unexpected “$” after the end of the key path. A key that contains characters other than letters, digits, “_”, and “-” must be quoted", 13),
	])
	func `a quotable character directly after a bare key is an error that says to quote the key`(_ text: String, _ message: String, _ column: Int) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}

		#expect(error.message == message, "\(error.message)")
		#expect(error.location.column == column)
	}

	@Test(arguments: [
		("a b", "Unexpected “ ” after the end of the key path. A bare key cannot contain spaces. Quote it, as in 'a b'", 2),
		("a b c", "Unexpected “ ” after the end of the key path. A bare key cannot contain spaces. Quote it, as in 'a b c'", 2),
		("a.b c", "Unexpected “ ” after the end of the key path. A bare key cannot contain spaces. Quote it, as in 'b c'", 4),
		("trailing space b ", "Unexpected “ ” after the end of the key path. A bare key cannot contain spaces. Quote it, as in 'trailing space b'", 9),
		("a b$ ", "Unexpected “ ” after the end of the key path. A bare key cannot contain spaces. Quote it, as in 'a b$'", 2),
	])
	func `a space directly after a bare key is an error that says to quote the key`(_ text: String, _ message: String, _ column: Int) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}

		#expect(error.message == message, "\(error.message)")
		#expect(error.location.column == column)
	}

	@Test
	func `a tab directly after a bare key gets a hint to quote the key`() throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: "a\tb")
		}

		#expect(error.message.contains("A bare key cannot contain spaces. Quote it, as in 'a\tb'"), "\(error.message)")
		#expect(error.message.hasPrefix("Unexpected "), "\(error.message)")
		#expect(error.location.column == 2)
	}

	@Test(arguments: ["'a' b", "'a b' c", "a[0] b", "a[0]$", "a: 1", "a # comment", "'the name'$", "a $", "a."])
	func `a character after an index or a quoted key, or one with no suggestion, gets no quote hint from a key path`(_ text: String) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}

		#expect(!error.message.contains("must be quoted"), "\(error.message)")
	}

	@Test
	func `a dollar directly after a quoted key in a key path gets no quote hint`() throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: "'the name'$")
		}

		#expect(error.message == "Unexpected “$” after the end of the key path", "\(error.message)")
		#expect(error.location.column == 11)
	}

	@Test
	func `a single-quoted key ends at its quote, also after a backslash, which is no escape there`() throws {
		#expect(try SOML.KeyPath(parsing: "'a\\'[0]").segments == [.key("a\\"), .index(0)])
	}

	@Test(arguments: [("servers.[0]", 9), ("a.b.[0]", 5), ("a.'x'.[0]", 7), ("a[0].[1]", 6), ("a.[0].b", 3), ("a.[0].\u{1}", 3), ("a.[0].b\rc", 3), ("a.b.[0]\u{1}", 5)])
	func `an index after a dot is an error that names the bracket`(_ text: String, _ column: Int) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}

		#expect(error.message.hasSuffix("but found “[”"), "\(error.message)")
		#expect(error.location.column == column)
	}

	@Test(arguments: [("'a", "'a'", 1), ("a.'b", "'a'", 3), ("\"a", "\"a\"", 1)])
	func `an unterminated quoted key in a key path gets advice for a key, not for a block string`(_ text: String, _ example: String, _ column: Int) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}

		#expect(error.message == "Unterminated key. A quoted key ends with the quote it starts with, as in \(example)")
		#expect(error.location.column == column)
	}

	@Test(arguments: ["'a\nb'", "\"a\nb\"", "x.'a\nb'", "'a\n", "a[0].\"b\nc\""])
	func `a line break in a quoted key in a key path is an error that says so`(_ text: String) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}

		#expect(error.message == "A quoted key cannot contain a line break. Write one as \\n in a \"...\" key")
		#expect(error.location.line == 1)
	}

	@Test(arguments: ["servers[-1]", "[-1]", "a[-0]", "a.b[-12].c"])
	func `a negative index says that an index cannot be negative`(_ text: String) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}

		#expect(error.message == "An array index cannot be negative. The first item is [0]")
		#expect(error.location.column == Array(text.utf8).firstIndex(of: UInt8(ascii: "-"))! + 1)
	}

	@Test(arguments: ["a[-]", "a[-x]", "a[]", "a[x]"])
	func `a bracket without digits still asks for an index`(_ text: String) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}

		#expect(error.message == "Expected an array index after “[”, as in [0]")
	}

	@Test(arguments: [("a[05]", "[5]"), ("a[00]", "[0]"), ("[007].b", "[7]"), ("a[0" + String(repeating: "0", count: 1000) + "12]", "[12]")])
	func `an index with a leading zero gets the index without it as advice`(_ text: String, _ advice: String) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}

		#expect(error.message == "An array index cannot start with 0. Write it as \(advice)")
	}

	@Test
	func `an error in a key after an index has its position in the whole path`() throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: "servers[0].a b")
		}

		#expect(error.location.column == 13)
		#expect(error.message == "Unexpected “ ” after the end of the key path. A bare key cannot contain spaces. Quote it, as in 'a b'")
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
		("1\n", "Unexpected line break after the end of the value"),
		// A tab is whitespace, so it has no hint that says what whitespace is.
		("8080\t", "Unexpected U+0009 after the end of the value"),
		// The text of a value ends, not the value, which is missing.
		("", "Expected a value, but reached the end of the text"),
		("{a:", "Expected a value, but reached the end of the text"),
		("\t1", "Expected a value, but found U+0009"),
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
	func `converts durations to rounded SOML nanoseconds`() {
		#expect(Duration.seconds(90).somlNanoseconds == 90_000_000_000)
		#expect(Duration(secondsComponent: 0, attosecondsComponent: 1).somlNanoseconds == 0)
		#expect(Duration.seconds(Int64.max).somlNanoseconds == nil)
		#expect(Duration.nanoseconds(Int64.max).somlNanoseconds == Int64.max)
		#expect(Duration.nanoseconds(Int64.min).somlNanoseconds == Int64.min)
		#expect((Duration.nanoseconds(Int64.max) + .nanoseconds(1)).somlNanoseconds == nil)
		#expect((Duration.nanoseconds(Int64.min) - .nanoseconds(1)).somlNanoseconds == nil)
		#expect(Duration(secondsComponent: 0, attosecondsComponent: -1).somlNanoseconds == 0)
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

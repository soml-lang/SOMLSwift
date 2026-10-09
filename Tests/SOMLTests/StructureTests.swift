import Foundation
import Testing
@testable import SOML

@Suite
struct DocumentTests {
	static let documents: [Expectation] = [
		Expectation("a one-entry bare object", "a: 1", ["a": 1]),
		Expectation("a bare object with a trailing line feed", "a: 1\n", ["a": 1]),
		Expectation("a bare object with many trailing line feeds", "a: 1\n\n\n", ["a": 1]),
		Expectation("leading line feeds", "\n\n\na: 1", ["a": 1]),
		Expectation("leading spaces", "   a: 1", ["a": 1]),
		Expectation("indented entries", "  a: 1\n    b: 2\n\tc: 3", ["a": 1, "b": 2, "c": 3]),
		Expectation("trailing spaces", "a: 1   \nb: 2\t\t", ["a": 1, "b": 2]),
		Expectation("whitespace-only lines between entries", "a: 1\n  \n\t\nb: 2", ["a": 1, "b": 2]),
		Expectation("a braced object", "{a: 1}", ["a": 1]),
		Expectation("a braced object across lines", "{\n\ta: 1,\n\tb: 2,\n}", ["a": 1, "b": 2]),
		Expectation("a braced object without a trailing comma", "{\n\ta: 1,\n\tb: 2\n}", ["a": 1, "b": 2]),
		Expectation("an empty object", "{}", [:]),
		Expectation("an empty object with whitespace", "{ \n\t }", [:]),
		Expectation("an array", "[1, 'two', 3.0]", [1, "two", 3.0]),
		Expectation("an empty array", "[]", []),
		Expectation("an array of objects", "[{a: 1}, {a: 2}]", [["a": 1], ["a": 2]]),
		Expectation("an array of arrays", "[[], [[]], [[[]]]]", [[], [[]], [[[]]]]),
		Expectation("a value on the next line", "a:\n\n\t1", ["a": 1]),
		Expectation("an object value across lines in a bare object", "a: {\n\tb: 1,\n}\nc: 2", ["a": ["b": 1], "c": 2]),
		Expectation("an array value across lines in a bare object", "a: [\n\t1,\n\t2,\n]\nb: 3", ["a": [1, 2], "b": 3]),
		Expectation("a document that is one line of braces", "{a: 1, b: [1, 2], c: {d: true}}", ["a": 1, "b": [1, 2], "c": ["d": true]]),
		Expectation("mixed types in an array", "[1, 'two', true, null, 1.5, 2026-01-01T00:00:00Z, [], {}]", [1, "two", true, nil, 1.5, .instant(SOML.Instant("2026-01-01T00:00:00Z")!), [], [:]]),
		Expectation("keywords as values", "a: true\nb: false\nc: null", ["a": true, "b": false, "c": nil]),
	]

	@Test(arguments: documents)
	func `parses a document`(_ expectation: Expectation) throws {
		#expect(try parse(expectation.source) == expectation.value)
	}

	static let invalid: [Rejection] = [
		Rejection("an empty document", "", "A document must contain an object or an array, but this one is empty"),
		Rejection("only whitespace", " \n\t\n", "A document must contain an object or an array, but this one is empty"),
		Rejection("only a line comment", "# comment", "A document must contain an object or an array, but this one is empty"),
		Rejection("only a block comment", "/* comment */", "A document must contain an object or an array, but this one is empty"),
		Rejection("a bare int", "5", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("a bare float", "1.5", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("a bare string", "'hello'", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("a bare bool", "true", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("a bare null", "null", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("a bare instant", "2026-09-19T14:00:00Z", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("a bare block string", "'''\nhello\n'''", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("a bare scalar with a comment", "# note\n5 # five\n", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("two objects", "{a: 1}\n{b: 2}", "Unexpected “{” after the end of the document"),
		Rejection("two arrays", "[1] [2]", "Unexpected “[” after the end of the document"),
		Rejection("an object then an entry", "{a: 1}\nb: 2", "Unexpected “b” after the end of the document"),
		Rejection("an array then an entry", "[1]\nb: 2", "Unexpected “b” after the end of the document"),
		Rejection("an entry then an object", "a: 1\n{b: 2}", "Expected a key"),
		Rejection("a stray closing brace", "a: 1\n}", "Expected a key"),
		Rejection("a stray closing bracket", "]", "Expected a key"),
		Rejection("two entries on a line", "a: 1 b: 2", "Expected a line break before the next entry, but found “b”"),
		Rejection("two entries separated by a comment", "a: 1 /* x */ b: 2", "Expected a line break before the next entry, but found “b”"),
		Rejection("two entries separated by a multi-line block comment", "a: 1 /*\n*/ b: 2", "Expected a line break before the next entry, but found “b”"),
		Rejection("a comma between top-level entries", "a: 1,\nb: 2", "not commas"),
		Rejection("a trailing comma at the top level", "a: 1,", "not commas"),
		Rejection("an unclosed object", "{a: 1", "Unterminated object: expected “}”"),
		Rejection("an unclosed array", "[1, 2", "Unterminated array: expected “]”"),
		Rejection("an unclosed nested object", "a: {b: {c: 1}", "Unterminated object: expected “}”"),
		Rejection("a mismatched bracket", "[1}", "Expected “,”, a line break, or “]” after an array item, but found “}”"),
		Rejection("a mismatched brace", "{a: 1]", "Expected “,”, a line break, or “}” after an object member, but found “]”"),
		Rejection("a leading comma in an array", "[, 1]", "Expected a value"),
		Rejection("a leading comma in an object", "{, a: 1}", "Expected a key"),
		Rejection("a double comma in an array", "[1,, 2]", "Expected a value"),
		Rejection("a double comma in an object", "{a: 1,, b: 2}", "Expected a key"),
		Rejection("a lone comma in an array", "[,]", "Expected a value"),
		Rejection("a missing value", "a:", "Expected a value, but reached the end of the document"),
		Rejection("a missing value before the next entry", "a:\nb: 1", "Expected a value, but found the key b"),
		Rejection("a missing value before a quoted key", "a:\n'the name': 1", #"Expected a value, but found the key "the name""#),
		Rejection("a missing value before a quoted key with a dot", "a: # Note\n'b.c': 1", #"Expected a value, but found the key "b.c""#),
		Rejection("a missing value before a keyword key", "{a:\n\ttrue: 1}", "Expected a value, but found the key true"),
		Rejection("a missing value inside braces", "{a: }", "Expected a value"),
		Rejection("a missing comma between arrays", "[[1] [2]]", "Expected “,”, a line break, or “]” after an array item, but found “[”"),
		Rejection("two items separated by a multi-line block comment", "a: [1 /*\n*/ 2]", "A line break inside a block comment does not separate items"),
		Rejection("two members separated by a multi-line block comment", "{a: 1 /*\n*/ b: 2}", "A line break inside a block comment does not separate items"),
		Rejection("an unquoted string", "a: hello", "Unexpected “hello”. A string value must be quoted, as in 'hello'"),
		Rejection("an unquoted string with spaces", "a: hello world", "Unexpected “hello”. A string value must be quoted, as in 'hello world'"),
		Rejection("yes", "a: yes", "Booleans are written true and false"),
		Rejection("True", "a: True", "lowercase"),
		Rejection("NULL", "a: NULL", "lowercase"),
		Rejection("nil", "a: nil", "“nil” is not a value. Null is written null, in lowercase"),
		Rejection("undefined", "a: undefined", "“undefined” is not a value. Null is written null, in lowercase"),
		Rejection("a tilde", "a: ~", "Expected a value"),
		Rejection("a JSON-style object key", "{\"a\" : 1}", "Whitespace is not allowed"),
		Rejection("a YAML list item", "- a", "Expected “:” after the key, but found “a”"),
		Rejection("a TOML table header", "[table]\na: 1", "There are no table headers. Write the table as an object, as in table: {…}"),
		Rejection("an equals sign", "a = 1", "Expected “:” after the key, but found “=”"),
		Rejection("a value that is a key-value pair", "a: b: 1", "Unexpected “b”. A string value must be quoted, as in 'b: 1'"),
	]

	@Test(arguments: invalid)
	func `rejects an invalid document`(_ rejection: Rejection) {
		expectRejected(rejection.source, rejection.message)
	}

	@Test
	func `a missing value before a key on the next line is reported at that key, as in the reference implementation`() {
		#expect(parseError("'a': \n'b': 2")?.location.description == "line 2, column 1")
		#expect(parseError("{\n\ta:\n\t'b.c': 2\n}")?.location.description == "line 3, column 2")
		// A quoted key cannot be part of a value, so anything may follow its “:”, as in the reference implementation.
		#expect(parseError("a:\n'b':1a:")?.location.description == "line 2, column 1")
		#expect(parseError("'a': \n\n'b':} 2\n")?.location.description == "line 3, column 1")
		// A digit after the “:” is an instant, whose own error is more precise.
		#expect(parseError("a: 2026-09-19T25:00:00Z")?.message.contains("which looks like the key") == false)
		// On the same line, the string is the value, and what follows it is the problem.
		#expect(parseError("a: 'b': 2")?.message.contains("which looks like the key") == false)
	}

	@Test
	func `what follows a value is checked before its key is, as in the reference implementation`() {
		#expect(parseError("a: 1\na: 2[")?.location.description == "line 2, column 5")
		#expect(parseError("a: 1\na: 2{")?.description == "Unexpected “{” after a value (line 2, column 5)")
		#expect(parseError("a: 1\na: 'x'y")?.location.description == "line 2, column 7")
		#expect(parseError("{a: 1, a: 2[}")?.location.description == "line 1, column 12")
		#expect(parseError("a: 1\na: '''\n\tx\n\t'''y")?.location.description == "line 4, column 5")
		// After an object or an array, the duplicate key comes first.
		#expect(parseError("a: 1\na: {}x")?.location.description == "line 2, column 1")
		#expect(parseError("{a: 1, a: [1]x}")?.location.description == "line 1, column 8")
	}

	@Test
	func `the micro sign is reported only after a token that is otherwise valid, as in the reference implementation`() {
		#expect(parseError("a: 1µs")?.message.contains("written us") == true)
		#expect(parseError("a: x1µs")?.location.description == "line 1, column 4")
		#expect(parseError("a: 1.2.3µs")?.location.description == "line 1, column 4")
		#expect(parseError("a: 1.5s1µs")?.location.description == "line 1, column 4")
	}

	@Test
	func `nesting up to the limit is accepted`() throws {
		let depth = Parser.maximumDepth
		let arrays = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
		#expect(throws: Never.self) {
			try parse(arrays)
		}

		let objects = "a: " + String(repeating: "{a: ", count: depth - 1) + "1" + String(repeating: "}", count: depth - 1)
		#expect(throws: Never.self) {
			try parse(objects)
		}
	}

	@Test
	func `the brace-less top-level object counts as a level`() throws {
		let depth = Parser.maximumDepth
		let arrays = "a: " + String(repeating: "[", count: depth - 1) + String(repeating: "]", count: depth - 1)
		let value = try parse(arrays)
		#expect(try parse("{" + arrays + "}") == value)
		#expect(try parse(canonical(value)) == value)
		expectRejected("a: " + String(repeating: "[", count: depth) + String(repeating: "]", count: depth), "The document is nested more than 100 levels deep")
		expectRejected("{a: " + String(repeating: "[", count: depth) + String(repeating: "]", count: depth) + "}", "The document is nested more than 100 levels deep")
	}

	@Test
	func `nesting past the limit is an error, not a crash`() {
		let depth = Parser.maximumDepth + 1
		expectRejected(String(repeating: "[", count: depth) + String(repeating: "]", count: depth), "The document is nested more than 100 levels deep")
		expectRejected(String(repeating: "[", count: 100_000), "The document is nested more than 100 levels deep")
		expectRejected("a: " + String(repeating: "{a: ", count: 100_000), "The document is nested more than 100 levels deep")
	}

	@Test
	func `a large flat document`() throws {
		let source = (0..<10_000).map { "key-\($0): \($0)" }.joined(separator: "\n")
		let value = try parse(source)
		#expect(value.objectValue?.count == 10_000)
		#expect(value["key-9999"] == 9999)
	}

	@Test
	func `a large array`() throws {
		let source = "[" + (0..<10_000).map(String.init).joined(separator: ",") + "]"
		#expect(try parse(source).arrayValue?.count == 10_000)
	}
}

@Suite
struct CommentTests {
	static let documents: [Expectation] = [
		Expectation("a line comment", "# comment\na: 1", ["a": 1]),
		Expectation("a line comment after a value", "a: 1 # comment", ["a": 1]),
		Expectation("a line comment with no space", "a: 1#comment", ["a": 1]),
		Expectation("a line comment at the end without a line feed", "a: 1\n# end", ["a": 1]),
		Expectation("an empty line comment", "#\na: 1", ["a": 1]),
		Expectation("a line comment with quotes", "a: 1 # it's \"fine\"", ["a": 1]),
		Expectation("a line comment with braces", "a: 1 # { [ ,", ["a": 1]),
		Expectation("a line comment with non-ASCII text", "a: 1 # 日本語 😀 \u{2028}", ["a": 1]),
		Expectation("a block comment", "/* comment */\na: 1", ["a": 1]),
		Expectation("a multi-line block comment", "/*\n\tline one\n\tline two\n*/\na: 1", ["a": 1]),
		Expectation("an empty block comment", "/**/a: 1", ["a": 1]),
		Expectation("a block comment with stars", "/*** stars ***/\na: 1", ["a": 1]),
		Expectation("a block comment with a slash inside", "/* a/b */\na: 1", ["a": 1]),
		Expectation("a block comment starting with a slash", "/*/ x */\na: 1", ["a": 1]),
		Expectation("a block comment with a hash", "/* # */\na: 1", ["a": 1]),
		Expectation("a block comment whose body ends with a slash", "/* a/*/\na: 1", ["a": 1]),
		Expectation("a block comment that is only a slash", "/*/*/\na: 1", ["a": 1]),
		Expectation("a block comment whose body ends with a slash, after a value", "a: 1 /* x/*/ # y", ["a": 1]),
		Expectation("a block comment between a colon and a value", "a: /* x */ 1", ["a": 1]),
		Expectation("a block comment across the colon's line break", "a: /* x\n */ 1", ["a": 1]),
		Expectation("a block comment after a value", "a: 1 /* x */\nb: 2", ["a": 1, "b": 2]),
		Expectation("a multi-line block comment after a value", "a: 1 /* x\ny */\nb: 2", ["a": 1, "b": 2]),
		Expectation("comments inside an array", "[\n\t1, # one\n\t/* two */ 2,\n\t# nothing\n]", [1, 2]),
		Expectation("comments inside an object", "{\n\ta: 1, # one\n\t/* b */ b: 2,\n}", ["a": 1, "b": 2]),
		Expectation("comments before a comma", "[1 /* x */, 2 /* y */ , 3]", [1, 2, 3]),
		Expectation("a comment inside an empty object", "{ # nothing\n}", [:]),
		Expectation("a comment inside an empty array", "[ /* nothing */ ]", []),
		Expectation("comments around the document", "# start\n{a: 1}\n# end\n", ["a": 1]),
		Expectation("comment-only lines between entries", "a: 1\n# x\n\n# y\nb: 2", ["a": 1, "b": 2]),
	]

	@Test(arguments: documents)
	func `comments are not content`(_ expectation: Expectation) throws {
		#expect(try parse(expectation.source) == expectation.value)
	}

	static let invalid: [Rejection] = [
		Rejection("a nested block comment", "/* /* */ */\na: 1", "Block comments cannot be nested, and their body may not contain “/*”"),
		Rejection("an opening inside a block comment", "/* a /* b */\na: 1", "Block comments cannot be nested, and their body may not contain “/*”"),
		Rejection("an unterminated block comment", "a: 1\n/* no end", "Unterminated block comment"),
		Rejection("a block comment closed by half a terminator", "/* x *\na: 1", "Unterminated block comment"),
		Rejection("an opening right before the end", "/* a /**/\na: 1", "Block comments cannot be nested, and their body may not contain “/*”"),
		Rejection("an opening at the start of the body", "/*/* */\na: 1", "Block comments cannot be nested, and their body may not contain “/*”"),
		Rejection("a comment inside a key", "a/* x */b: 1", "Expected “:” after the key, but found “/”"),
		Rejection("a comment inside a number", "a: 1/* x */000", "Expected a line break"),
		Rejection("a C++ line comment", "// comment\na: 1", "Expected a key"),
		Rejection("a semicolon comment", "; comment\na: 1", "Expected a key"),
	]

	@Test(arguments: invalid)
	func `rejects an invalid comment`(_ rejection: Rejection) {
		expectRejected(rejection.source, rejection.message)
	}

	@Test
	func `the nested comment error points at the inner opening`() throws {
		let error = try #require(parseError("a: 1\n/* x /* y */"))
		#expect(error.location.line == 2)
		#expect(error.location.column == 6)
	}

	@Test
	func `the unterminated comment error points at the opening`() throws {
		let error = try #require(parseError("a: 1\n  /* x\n\n"))
		#expect(error.location.line == 2)
		#expect(error.location.column == 3)
	}

	@Test
	func `slash-dash before an entry is rejected`() {
		parseError("/- a: 1\nb: 2")
	}
}

@Suite
struct EncodingTests {
	@Test
	func `a BOM is rejected`() throws {
		let error = try #require(parseError("\u{FEFF}a: 1"))
		#expect(error.message.contains("byte order mark"))
		#expect(error.location.offset == 0)
	}

	@Test
	func `a BOM later in the document is not whitespace`() {
		expectRejected("a: 1\n\u{FEFF}b: 2", "Expected a key")
		expectRejected("a:\u{FEFF}1", "U+FEFF")
	}

	@Test
	func `a BOM inside a string is content`() throws {
		#expect(try parseScalar("'\u{FEFF}'") == "\u{FEFF}")
	}

	@Test
	func `a carriage return is rejected anywhere, with its position`() throws {
		for (source, line, column) in [
			("a: 1\r\nb: 2", 1, 5),
			("a: 1\nb: 2\r", 2, 5),
			("\r", 1, 1),
			("a: '\r'", 1, 5),
			("# comment \r\na: 1", 1, 11),
			("/* \r */ a: 1", 1, 4),
			("a: '''\n\tx\r\n\t'''", 2, 3),
		] {
			let error = try #require(parseError(source))
			#expect(error.message.contains("carriage return"), "\(source.debugDescription)")
			#expect(error.location.line == line, "\(source.debugDescription)")
			#expect(error.location.column == column, "\(source.debugDescription)")
		}
	}

	static let invalidUTF8: [(String, [UInt8], message: String)] = [
		("a lone continuation byte", [0x80], "Invalid UTF-8 byte 0x80"),
		("a truncated two-byte sequence", [0xC3], "Invalid UTF-8 byte 0xC3"),
		("an overlong encoding of a slash", [0xC0, 0xAF], "Invalid UTF-8 byte 0xC0"),
		("an overlong encoding of NUL", [0xC0, 0x80], "Invalid UTF-8 byte 0xC0"),
		("an encoded high surrogate", [0xED, 0xA0, 0x80], "Invalid UTF-8 byte 0xED"),
		("an encoded low surrogate", [0xED, 0xB0, 0x80], "Invalid UTF-8 byte 0xED"),
		("a code point above U+10FFFF", [0xF4, 0x90, 0x80, 0x80], "Invalid UTF-8 byte 0xF4"),
		("an invalid byte", [0xFF], "Invalid UTF-8 byte 0xFF"),
		("a truncated four-byte sequence", [0xF0, 0x9F, 0x98], "Invalid UTF-8 byte 0xF0"),
	]

	@Test(arguments: invalidUTF8)
	func `invalid UTF-8 is rejected with its position`(_ name: String, _ invalid: [UInt8], message: String) throws {
		let bytes = Array("a: 1\nb: '".utf8) + invalid + Array("'".utf8)

		do {
			_ = try SOML.Value(parsing: bytes)
			Issue.record("Expected an error for \(name)")
		} catch {
			#expect(error.message == message)
			#expect(error.location.line == 2)
			#expect(error.location.column == 5)
		}
	}

	static let truncatedUTF8: [[UInt8]] = [
		[0xC3],
		[0xE2, 0x82],
		[0xF0, 0x9F, 0x98],
	]

	@Test(arguments: truncatedUTF8)
	func `a sequence that the end of the document cuts short is reported as incomplete, as in the reference`(_ truncated: [UInt8]) throws {
		let error = try #require(#expect(throws: SOML.ParseError.self) {
			try SOML.Value(parsing: Array("a: 1\n# ".utf8) + truncated)
		})
		#expect(error.message == "Incomplete UTF-8 sequence at the end of the input")
		#expect(error.location.line == 2)
		#expect(error.location.column == 3)
	}

	@Test
	func `invalid UTF-8 anywhere is the error reported, before a control character, as in the reference`() throws {
		let error = try #require(#expect(throws: SOML.ParseError.self) {
			try SOML.Value(parsing: Array("a: '".utf8) + [0xFF] + Array("'\nb: '\r'".utf8))
		})
		#expect(error.message == "Invalid UTF-8 byte 0xFF")
		#expect(error.location.offset == 4)

		// The reference implementation decodes the bytes before it reads the text.
		let laterError = try #require(#expect(throws: SOML.ParseError.self) {
			try SOML.Value(parsing: Array("a: '\r'\nb: '".utf8) + [0xFF] + Array("'".utf8))
		})
		#expect(laterError.message == "Invalid UTF-8 byte 0xFF")
		#expect(laterError.location.offset == 11)
	}

	static let controlThenInvalidUTF8: [(String, [UInt8], offset: Int, message: String)] = [
		("NUL, then an invalid byte", Array("a: '".utf8) + [0x00] + Array("'\nb: '".utf8) + [0xFF] + Array("'".utf8), 11, "Invalid UTF-8 byte 0xFF"),
		("a control character, then an invalid byte", Array("a: '".utf8) + [0x01] + Array("'\nb: '".utf8) + [0xFF] + Array("'".utf8), 11, "Invalid UTF-8 byte 0xFF"),
		("DEL, then an encoded surrogate", Array("a: '".utf8) + [0x7F] + Array("'\nb: '".utf8) + [0xED, 0xA0, 0x80] + Array("'".utf8), 11, "Invalid UTF-8 byte 0xED"),
		("a control character after valid text, then a truncated sequence", Array("a: 'é'\nb: '".utf8) + [0x1B] + Array("'\n# ".utf8) + [0xE2, 0x82], 17, "Incomplete UTF-8 sequence at the end of the input"),
		("a control character, then an overlong form", Array("# ".utf8) + [0x08] + Array("\na: '".utf8) + [0xC0, 0xAF] + Array("'".utf8), 8, "Invalid UTF-8 byte 0xC0"),
	]

	@Test(arguments: controlThenInvalidUTF8)
	func `invalid UTF-8 after a control character is the error reported`(_ name: String, _ bytes: [UInt8], offset: Int, message: String) throws {
		let error = try #require(#expect(throws: SOML.ParseError.self) {
			try SOML.Value(parsing: bytes)
		}, "\(name)")
		#expect(error.message == message, "\(name)")
		#expect(error.location.offset == offset, "\(name)")
	}

	@Test
	func `the encoding check agrees with Swift's own UTF-8 decoder on random bytes`() throws {
		let invalidUTF8Messages = ["Invalid UTF-8 byte", "Incomplete UTF-8 sequence"]

		// Pieces that make every kind of sequence likely: printable ASCII, the allowed and refused control characters, valid sequences of every length, and the bytes that start or continue invalid ones.
		let pieces: [[UInt8]] = [
			Array("a: 'x".utf8), [0x27], [0x0A], [0x09], [0x00], [0x01], [0x0D], [0x1F], [0x7F],
			Array("é".utf8), Array("€".utf8), Array("😀".utf8), Array("\u{10FFFF}".utf8),
			[0x80], [0xBF], [0xC0], [0xC1], [0xC2], [0xDF], [0xE0], [0xE0, 0x80], [0xE0, 0xA0], [0xED], [0xED, 0xA0], [0xEF, 0xBB, 0xBF],
			[0xF0], [0xF0, 0x8F], [0xF0, 0x90], [0xF4], [0xF4, 0x90], [0xF5], [0xFF],
		]

		var generator = SeededGenerator(seed: 2026)
		var checkedInvalid = 0

		for _ in 0..<20_000 {
			var bytes = [UInt8]()

			for _ in 0..<Int.random(in: 1...12, using: &generator) {
				bytes += pieces[Int.random(in: pieces.indices, using: &generator)]
			}

			// The expected first problem, in the order the spec gives: invalid UTF-8 anywhere, then a BOM, then the first control character other than tab and LF.
			let expectedOffset: Int?
			let isExpectedInvalidUTF8: Bool

			if String(validating: bytes, as: UTF8.self) == nil {
				expectedOffset = bytes[...].firstInvalidUTF8Offset
				isExpectedInvalidUTF8 = true
			} else if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
				expectedOffset = 0
				isExpectedInvalidUTF8 = false
			} else {
				expectedOffset = bytes.firstIndex { ($0 < 0x20 && $0 != 0x09 && $0 != 0x0A) || $0 == 0x7F }
				isExpectedInvalidUTF8 = false
			}

			do {
				_ = try SOML.Value(parsing: bytes)
				#expect(expectedOffset == nil, "\(bytes) parsed, but its encoding is not valid")
			} catch {
				let isInvalidUTF8 = invalidUTF8Messages.contains { error.message.hasPrefix($0) }
				#expect(isInvalidUTF8 == isExpectedInvalidUTF8, "\(bytes): \(error.message)")

				if let expectedOffset {
					#expect(error.location.offset == expectedOffset, "\(bytes): \(error.message)")
				}

				if isInvalidUTF8 {
					checkedInvalid += 1
				}
			}
		}

		// The generator degenerating would otherwise make the test pass without checking the UTF-8 validation.
		#expect(checkedInvalid > 5000, "Only \(checkedInvalid) documents had invalid UTF-8")
	}

	@Test
	func `every byte is checked at every place in an eight-byte word of the encoding check`() throws {
		// The check skips eight bytes of plain text at a time, so each byte is put at each of the eight places in a word, in a comment long enough to be read as words.
		var failures = [String]()

		for byte in UInt8.min...UInt8.max {
			for offset in 0..<16 {
				// The text after the byte starts with `#`, so that it is a comment also after LF.
				let comment = Array(repeating: UInt8(ascii: "x"), count: offset) + [byte] + Array("#xxxxxxxxxxxxxxxx".utf8)
				let bytes = Array("a: 1 #".utf8) + comment
				let isAllowed = byte == .tab || byte == .lineFeed || (0x20..<0x7F).contains(byte)

				do {
					_ = try SOML.Value(parsing: bytes)

					if !isAllowed {
						failures.append("0x\(String(byte, radix: 16)) at \(offset) parsed")
					}
				} catch {
					if isAllowed || error.location.offset != 6 + offset {
						failures.append("0x\(String(byte, radix: 16)) at \(offset): \(error.message) at \(error.location.offset)")
					}
				}
			}
		}

		for failure in failures.prefix(5) {
			Issue.record("\(failure)")
		}

		#expect(failures.isEmpty, "\(failures.count) failed")
	}

	@Test
	func `the encoding check agrees with Swift's own UTF-8 decoder on every lead and second byte`() throws {
		// Every byte that is not ASCII, followed by every byte, in a string, and in a comment cut off by the end of the document. A lead of a longer sequence is also followed by bytes that continue it or not.
		var failures = [String]()
		var checkedValid = 0

		for lead in UInt8(0x80)...0xFF {
			let tails: [[UInt8]] = (0xE0...0xF4).contains(lead) ? [[], [0x80], [0xBF, 0x80], [0x80, 0x41]] : [[]]

			for second in UInt8.min...UInt8.max {
				for tail in tails {
					let sequence = [lead, second] + tail

					for (prefix, suffix) in [(Array("a: '".utf8), Array("'".utf8)), (Array("a: 1 # ".utf8), [])] {
						let bytes = prefix + sequence + suffix
						let isValid = String(validating: bytes, as: UTF8.self) != nil

						do {
							_ = try SOML.Value(parsing: bytes)

							if isValid {
								checkedValid += 1
							} else {
								failures.append("\(bytes) parsed, but it is not valid UTF-8")
							}
						} catch {
							let isInvalidUTF8 = error.message.hasPrefix("Invalid UTF-8 byte") || error.message.hasPrefix("Incomplete UTF-8 sequence")

							if isValid {
								// Valid UTF-8 can still be invalid SOML, like a control character or an unmatched quote, but never for its encoding.
								if isInvalidUTF8 {
									failures.append("\(bytes) is valid UTF-8, but: \(error.message)")
								}
							} else if !isInvalidUTF8 || error.location.offset != bytes[...].firstInvalidUTF8Offset {
								failures.append("\(bytes): \(error.message) at \(error.location.offset)")
							}
						}
					}
				}
			}
		}

		for failure in failures.prefix(5) {
			Issue.record("\(failure)")
		}

		#expect(failures.isEmpty, "\(failures.count) failed")
		#expect(checkedValid > 3000, "Only \(checkedValid) documents were valid")
	}

	// The reference implementation decodes the bytes before it reads the text, so invalid UTF-8 is reported before a BOM, and a BOM before a control character.
	static let byteOrderMarkCases: [(String, [UInt8], line: Int, column: Int, message: String)] = [
		("invalid UTF-8 later", [0xEF, 0xBB, 0xBF] + Array("a: 1\nb: 2".utf8) + [0xFF], 2, 5, "Invalid UTF-8 byte 0xFF"),
		("invalid UTF-8 in a string", [0xEF, 0xBB, 0xBF] + Array("a: 1\nb: '".utf8) + [0xFF] + Array("'".utf8), 2, 5, "Invalid UTF-8 byte 0xFF"),
		("invalid UTF-8 directly after it", [0xEF, 0xBB, 0xBF, 0xFF] + Array("a: 1".utf8), 1, 2, "Invalid UTF-8 byte 0xFF"),
		("a truncated BOM", [0xEF, 0xBB] + Array("a: 1".utf8), 1, 1, "Invalid UTF-8 byte 0xEF"),
		("a carriage return later", [0xEF, 0xBB, 0xBF] + Array("a: 1\r\n".utf8), 1, 1, "byte order mark"),
		("a control character later", [0xEF, 0xBB, 0xBF] + Array("a: 1\n".utf8) + [0x01], 1, 1, "byte order mark"),
		("nothing else wrong", [0xEF, 0xBB, 0xBF] + Array("a: 1".utf8), 1, 1, "byte order mark"),
	]

	@Test(arguments: byteOrderMarkCases)
	func `a BOM is reported after invalid UTF-8 and before a control character, as in the reference`(_ name: String, _ bytes: [UInt8], line: Int, column: Int, message: String) throws {
		let error = try #require(#expect(throws: SOML.ParseError.self) {
			try SOML.Document(parsing: bytes)
		})
		#expect(error.message.contains(message), "Message was: \(error.message)")
		#expect(error.location.line == line)
		#expect(error.location.column == column)
	}

	@Test(arguments: [[0xFF, 0xFE] as [UInt8], [0xFE, 0xFF]])
	func `a UTF-16 document is reported at its first byte, which is not valid UTF-8, as in the reference`(_ byteOrderMark: [UInt8]) throws {
		let body = Array("a: 1".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
		let error = try #require(#expect(throws: SOML.ParseError.self) {
			try SOML.Value(parsing: byteOrderMark + body)
		})
		#expect(error.message == "Invalid UTF-8 byte 0x\(String(byteOrderMark[0], radix: 16, uppercase: true))")
		#expect(error.location.offset == 0)
	}

	@Test
	func `invalid UTF-8 in a comment is rejected too`() {
		let bytes = Array("# ".utf8) + [0xFF] + Array("\na: 1".utf8)
		#expect(throws: SOML.ParseError.self) {
			try SOML.Value(parsing: bytes)
		}
	}

	@Test
	func `parses bytes and Data`() throws {
		#expect(try SOML.Value(parsing: Array("a: 1".utf8)) == ["a": 1])
		#expect(try SOML.Value(parsing: Data("a: 1".utf8)) == ["a": 1])
	}

	static let invisible: [(String, String)] = [
		("no-break space", "\u{00A0}"),
		("en quad", "\u{2000}"),
		("em space", "\u{2003}"),
		("thin space", "\u{2009}"),
		("zero width space", "\u{200B}"),
		("line separator", "\u{2028}"),
		("paragraph separator", "\u{2029}"),
		("ideographic space", "\u{3000}"),
		("vertical tab", "\u{0B}"),
		("form feed", "\u{0C}"),
		("next line", "\u{85}"),
		("zero width no-break space", "\u{FEFF}"),
		("word joiner", "\u{2060}"),
		("null", "\u{0}"),
	]

	@Test(arguments: invisible)
	func `an invisible character outside a string is an error that names it`(_ name: String, _ character: String) throws {
		let scalar = character.unicodeScalars.first!
		let hexadecimal = String(scalar.value, radix: 16, uppercase: true)
		let code = "U+" + String(repeating: "0", count: max(0, 4 - hexadecimal.count)) + hexadecimal

		for source in ["a:\(character)1", "a: 1\(character)", "\(character)a: 1", "[1,\(character)2]"] {
			let error = try #require(parseError(source))
			// A U+FEFF that starts the document is a BOM.
			let expected = source.hasPrefix("\u{FEFF}") ? "byte order mark" : code
			#expect(error.message.contains(expected), "\(name) in \(source.debugDescription): \(error.message)")
		}
	}

	@Test
	func `a column counts scalars, not bytes`() throws {
		let error = try #require(parseError("'日本語': 01"))
		#expect(error.location.column == 8)
		#expect(error.location.offset == 13)
	}
}

@Suite
struct ItemSeparatorTests {
	static let separated: [(String, SOML.Value)] = [
		("[\n80\n443\n]", SOML.Value.array([80, 443])),
		("{\na: 1\nb: 2\n}", ["a": 1, "b": 2]),
		("[1, 2\n3]", [1, 2, 3]),
		("[1,]", [1]),
		("[1,\n]", [1]),
		("[1, # one\n2]", [1, 2]),
		("[1 /* a\n */, 2]", [1, 2]),
		("[1 # one\n2]", [1, 2]),
		("[\n\t1\n\n\t2\n]", [1, 2]),
		("{a:\n1}", ["a": 1]),
		("[{a: 1}\n{b: 2}]", [["a": 1], ["b": 2]]),
		("['''\n\tx\n\t'''\n2]", ["x", 2]),
	]

	@Test(arguments: separated)
	func `a line break separates items inside brackets and braces, as a comma does`(_ source: String, _ expected: SOML.Value) throws {
		#expect(try parse("a: \(source)") == ["a": expected])
	}

	@Test(arguments: [
		("[1 2]", "Expected “,”, a line break, or “]” after an array item"),
		("{a: 1 b: 2}", "Expected “,”, a line break, or “}” after an object member"),
		("[,1]", "Expected a value"),
		("[1,,2]", "Expected a value"),
		("[,]", "Expected a value"),
		("[1 /*\n*/ 2]", "Expected “,”, a line break, or “]” after an array item, but found “2”. A line break inside a block comment does not separate items"),
		("{a:\nb: 2}", "Expected a value, but found the key b"),
	])
	func `two items on one line still need a comma, and a comma needs an item before it`(_ source: String, _ fragment: String) {
		expectRejected("a: \(source)", fragment)
	}

	@Test(arguments: [
		"[1\n, 2]",
		"[1\n,\n2]",
		"[1\n,]",
		"[\n\t1\n\t,\n]",
		"{a: 1\n, b: 2}",
		"[1 # one\n, 2]",
	])
	func `a comma must be on the same line as the item before it`(_ source: String) {
		expectRejected("a: \(source)", "A comma must be on the same line as the item before it")
	}

	@Test
	func `the top level still separates entries by line breaks only`() {
		expectRejected("a: 1, b: 2", "Top-level entries are separated by line breaks, not commas")
	}

	@Test
	func `canonical form writes no commas`() throws {
		#expect(try canonical("a: [1, {c: 3, b: 2}]") == "a: [\n\t1\n\t{\n\t\tb: 2\n\t\tc: 3\n\t}\n]\n")
	}
}

extension ArraySlice<UInt8> {
	/**
	The offset of the first invalid UTF-8 sequence in bytes that are known to be invalid.
	*/
	var firstInvalidUTF8Offset: Int {
		var index = self.startIndex

		while index < self.endIndex {
			var iterator = self[index...].makeIterator()
			var scalarParser = UTF8.ForwardParser()

			guard case .valid(let scalar) = scalarParser.parseScalar(from: &iterator) else {
				return index
			}

			index += scalar.count
		}

		return self.startIndex
	}

}

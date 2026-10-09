import Testing
@testable import SOML

@Suite
struct StringTests {
	static let literal: [(String, String)] = [
		("''", ""),
		("'a'", "a"),
		("'hello world'", "hello world"),
		(#"'C:\Users\sindre\dev'"#, #"C:\Users\sindre\dev"#),
		(#"'^\d{4}-\d{2}-\d{2}$'"#, #"^\d{4}-\d{2}-\d{2}$"#),
		(#"'\n is not an escape here'"#, #"\n is not an escape here"#),
		(#"'say "hi"'"#, #"say "hi""#),
		(#"'\'"#, #"\"#),
		("'tab\there'", "tab\there"),
		("'# not a comment'", "# not a comment"),
		("'/* not a comment */'", "/* not a comment */"),
		("'/- not removed'", "/- not removed"),
		("'a: b, c: d'", "a: b, c: d"),
		("'{[]}'", "{[]}"),
		("'日本語'", "日本語"),
		("'😀👍🏽'", "😀👍🏽"),
		("'e\u{301}'", "e\u{301}"),
		("'\u{2028}'", "\u{2028}"),
		("'\u{00A0}'", "\u{00A0}"),
		("'\u{FEFF}'", "\u{FEFF}"),
		("'   '", "   "),
	]

	@Test(arguments: literal)
	func `a literal string has no escapes`(_ source: String, _ expected: String) throws {
		#expect(try parseScalar(source) == .string(expected))
	}

	@Test
	func `a raw control character is an error, even in a string or a comment`() throws {
		let contexts = [("a: 'x", "y'"), ("a: \"x", "y\""), ("a: '''\n\tx", "\n\t'''"), ("a: \"\"\"\n\tx", "\n\t\"\"\""), ("'x", "y': 1"), ("\"x", "y\": 1"), ("# x", "\na: 1"), ("/* x", " */\na: 1"), ("a:", "1"), ("a: 1", "\nb: 2"), ("[1,", "2]")]
		let controls = Array(0x00...0x08) + Array(0x0B...0x0C) + Array(0x0E...0x1F) + [0x7F] as [UInt8]

		for control in controls {
			let hexadecimal = String(control, radix: 16, uppercase: true)
			let code = "U+00" + (hexadecimal.count == 1 ? "0" : "") + hexadecimal

			for (prefix, suffix) in contexts {
				let bytes = Array(prefix.utf8) + [control] + Array(suffix.utf8)

				do {
					let value = try SOML.Value(parsing: bytes)
					Issue.record("Expected an error for \(code) in \(prefix.debugDescription), got \(value)")
				} catch {
					#expect(error.message.contains(code), "\(error.message)")
					#expect(error.location.offset == prefix.utf8.count)
				}
			}
		}
	}

	@Test
	func `every control character but CR is representable as an escape, in a value and in a key`() throws {
		let controls = Array(0x00...0x0C) + Array(0x0E...0x1F) + [0x7F] as [UInt32]

		for control in controls {
			let scalar = try #require(Unicode.Scalar(control))
			let escape = "\\u{\(String(control, radix: 16))}"
			#expect(try parse("a: \"\(escape)\"") == ["a": .string(String(scalar))], "\(escape)")
			#expect(try parse("\"\(escape)\": 1") == [String(scalar): 1], "\(escape)")
		}
	}

	@Test
	func `a control character is written as an escape`() throws {
		#expect(try parseScalar(#""\u{0}\u{7f}\u{1b}[0m""#) == "\u{0}\u{7F}\u{1B}[0m")
		#expect(try canonical(.object(["a": "\u{0}\u{7F}"])) == "a: \"\\u{0}\\u{7f}\"\n")
	}

	static let escaped: [(String, String)] = [
		(#""""#, ""),
		(#""a""#, "a"),
		(#""\\""#, #"\"#),
		(#""\"""#, #"""#),
		(#""\n""#, "\n"),
		(#""\t""#, "\t"),
		(#""a\nb\tc""#, "a\nb\tc"),
		(#""\u{0}""#, "\u{0}"),
		(#""\u{9}""#, "\t"),
		(#""\u{a}""#, "\n"),
		(#""\u{41}""#, "A"),
		(#""\u{e9}""#, "é"),
		(#""\u{7f}""#, "\u{7F}"),
		(#""\u{ff}""#, "ÿ"),
		(#""\u{2028}""#, "\u{2028}"),
		(#""\u{fffe}""#, "\u{FFFE}"),
		(#""\u{ffff}""#, "\u{FFFF}"),
		(#""\u{10000}""#, "\u{10000}"),
		(#""\u{1f600}""#, "😀"),
		(#""\u{10ffff}""#, "\u{10FFFF}"),
		(#""\u{d7ff}""#, "\u{D7FF}"),
		(#""\u{e000}""#, "\u{E000}"),
		(#""it's""#, "it's"),
		(#""default-src 'self'""#, "default-src 'self'"),
		(#""\\\\server\\share""#, #"\\server\share"#),
		(#""a\u{301}""#, "a\u{301}"),
		(#""\u{1f1f3}\u{1f1f4}""#, "🇳🇴"),
		("\"raw\ttab\"", "raw\ttab"),
		("\"日本語\"", "日本語"),
		(#""\\n""#, #"\n"#),
		(#""\\u{41}""#, #"\u{41}"#),
	]

	@Test(arguments: escaped)
	func `an escaped string decodes its escapes`(_ source: String, _ expected: String) throws {
		#expect(try parseScalar(source) == .string(expected))
	}

	static let invalidEscapes: [Rejection] = [
		Rejection("\\r", #""\r""#, "carriage return"),
		Rejection("\\'", #""\'""#, "needs no escape"),
		Rejection("\\/", #""\/""#, #"Unknown escape “\/”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\b", #""\b""#, #"Unknown escape “\b”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\f", #""\f""#, #"Unknown escape “\f”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\v", #""\v""#, #"Unknown escape “\v”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\0", #""\0""#, #"Unknown escape “\0”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\x41", #""\x41""#, #"Unknown escape “\x”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\a", #""\a""#, #"Unknown escape “\a”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\e", #""\e""#, #"Unknown escape “\e”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\ followed by a space", #""\ ""#, #"Unknown escape “\ ”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\ followed by a non-ASCII character", #""\é""#, #"Unknown escape “\é”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\ at the end", #""abc\"#, #"A backslash must be followed by an escape character. Use \\ for a literal backslash, or a '...' string"#),
		Rejection("\\U", #""\U0001F600""#, #"Unknown escape “\U”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("\\u with four digits", #""\u0041""#, #"The four-digit \u0041 form is not an escape. Write \u{41}"#),
		Rejection("\\u with no braces", #""\u41""#, "A Unicode escape is written"),
		Rejection("\\u with an unclosed brace", #""\u{41""#, "A Unicode escape is written"),
		Rejection("\\u with a space", #""\u{ 41}""#, "A Unicode escape is written"),
		Rejection("\\u{} empty", #""\u{}""#, "A Unicode escape needs one to six hexadecimal digits"),
		Rejection("\\u with uppercase", #""\u{E9}""#, "lowercase"),
		Rejection("\\u with mixed case", #""\u{1F600}""#, "lowercase"),
		Rejection("\\u with a leading zero", #""\u{041}""#, #"A Unicode escape may not have leading zeros; write \u{41}"#),
		Rejection("\\u with zeros only", #""\u{00}""#, #"A Unicode escape may not have leading zeros; write \u{0}"#),
		Rejection("\\u with seven digits", #""\u{1000000}""#, "at most six"),
		Rejection("\\u with a non-hex letter", #""\u{4g}""#, "A Unicode escape is written"),
		Rejection("\\u with an underscore", #""\u{4_1}""#, "A Unicode escape is written"),
		Rejection("\\u{d}", #""\u{d}""#, "carriage return"),
		Rejection("\\u{d800}", #""\u{d800}""#, "surrogate"),
		Rejection("\\u{dbff}", #""\u{dbff}""#, "surrogate"),
		Rejection("\\u{dc00}", #""\u{dc00}""#, "surrogate"),
		Rejection("\\u{dfff}", #""\u{dfff}""#, "surrogate"),
		Rejection("\\u{110000}", #""\u{110000}""#, #"\u{110000} is above U+10FFFF, the largest Unicode scalar value"#),
		Rejection("\\u{ffffff}", #""\u{ffffff}""#, #"\u{ffffff} is above U+10FFFF, the largest Unicode scalar value"#),
	]

	@Test(arguments: invalidEscapes)
	func `rejects an invalid escape`(_ rejection: Rejection) {
		expectRejected("value: \(rejection.source)", rejection.message)
	}

	@Test
	func `a single-line string cannot span lines`() {
		expectRejected("a: 'one\ntwo'", "Unterminated string")
		expectRejected("a: \"one\ntwo\"", "Unterminated string")
		expectRejected("a: 'never closed", "Unterminated string")
		expectRejected("a: \"never closed", "Unterminated string")
		expectRejected("a: \"escaped quote at the end\\\"", "Unterminated string")
	}

	@Test
	func `the unterminated string error points at the opening quote`() throws {
		let error = try #require(parseError("a: 1\nb: 'never closed\nc: 3"))
		#expect(error.location.line == 2)
		#expect(error.location.column == 4)
	}

	@Test
	func `the escape error points at the backslash`() throws {
		let error = try #require(parseError("a: \"abc\\qdef\""))
		#expect(error.location.line == 1)
		#expect(error.location.column == 8)
	}

	@Test
	func `a string with a combining mark after its closing quote`() {
		// In Swift, a combining mark joins the quote's grapheme. Byte parsing keeps the quote a quote, so this is a string followed by a stray character.
		expectRejected("a: 'x'\u{301}", "Unexpected “\u{301}” after a value")
	}

	@Test
	func `strings are compared by scalars, without normalisation`() throws {
		let composed = try parseScalar("'\u{E9}'")
		let decomposed = try parseScalar("'e\u{301}'")
		#expect(composed != decomposed)
		#expect(composed == .string("\u{E9}"))
		#expect(try parseScalar(#""\u{e9}""#) == composed)
		#expect(try parseScalar(#""e\u{301}""#) == decomposed)
	}

	// MARK: Block strings

	static let blocks: [(String, String, String)] = [
		("a literal block", "a: '''\n\tone\n\ttwo\n\t'''", "one\ntwo"),
		("an escaped block", "a: \"\"\"\n\tone\\ttwo\n\tthree\\u{21}\n\t\"\"\"", "one\ttwo\nthree!"),
		("an escaped block keeps backslashes from escapes", "a: \"\"\"\n\t\\\\\n\t\"\"\"", "\\"),
		("a literal block keeps backslashes", "a: '''\n\tC:\\dev\\n\n\t'''", "C:\\dev\\n"),
		("no indentation", "a: '''\none\ntwo\n'''", "one\ntwo"),
		("space indentation", "a: '''\n    one\n    two\n    '''", "one\ntwo"),
		("deeper lines keep their extra indentation", "a: '''\n\tone\n\t\ttwo\n\t'''", "one\n\ttwo"),
		("a closing delimiter less indented than the content", "a: '''\n\t\tone\n\t'''", "\tone"),
		("an empty block", "a: '''\n'''", ""),
		("an empty block with indentation", "a: '''\n\t'''", ""),
		("only blank lines", "a: '''\n\n\n'''", ""),
		("only whitespace-only lines", "a: '''\n\t\n  \n \t \n\t'''", ""),
		("leading blank lines are dropped", "a: '''\n\n\n\tone\n\t'''", "one"),
		("trailing blank lines are dropped", "a: '''\n\tone\n\n\n\t'''", "one"),
		("inner blank lines are kept", "a: '''\n\tone\n\n\ttwo\n\t'''", "one\n\ntwo"),
		("a line with only the indentation is blank", "a: '''\n\t\n\tone\n\t\n\t'''", "one"),
		("an inner line with only the indentation becomes empty", "a: '''\n\tone\n\t\n\ttwo\n\t'''", "one\n\ntwo"),
		("a whitespace-only line with more than the indentation becomes empty", "a: '''\n\tone\n\t  \n\ttwo\n\t'''", "one\n\ntwo"),
		("a whitespace-only line indented less is blank", "a: '''\n\t\tone\n\t\n\t\t'''", "one"),
		("a whitespace-only line with other indentation characters is blank", "a: '''\n\tone\n  \n\ttwo\n\t'''", "one\n\ntwo"),
		("a leading whitespace-only line indented more is discarded", "a: '''\n    \n  x\n  '''", "x"),
		("a trailing whitespace-only line indented more is discarded", "a: '''\n  x\n     \n  '''", "x"),
		("an inner whitespace-only line indented less becomes empty", "a: '''\n  x\n \n  y\n  '''", "x\n\ny"),
		("an inner whitespace-only line in an escaped block becomes empty", "a: \"\"\"\n\tx\n \t \n\ty\n\t\"\"\"", "x\n\ny"),
		("trailing whitespace is content", "a: '''\n\tone  \n\t'''", "one  "),
		("a single quote inside", "a: '''\n\tit's\n\t'''", "it's"),
		("two single quotes inside", "a: '''\n\t''\n\t'''", "''"),
		("three quotes mid-line are content", "a: '''\n\tsay ''' here\n\t'''", "say ''' here"),
		("four quotes at a line start are content for a three-quote block", "a: '''\n\t''''\n\t'''", "''''"),
		("double quotes inside a literal block", "a: '''\n\t\"\"\"\n\t'''", "\"\"\""),
		("single quotes inside an escaped block", "a: \"\"\"\n\t'''\n\t\"\"\"", "'''"),
		("a four-quote block holds three", "a: ''''\n\t'''\n\t''''", "'''"),
		("a five-quote block", "a: '''''\n\t''''\n\t'''''", "''''"),
		("comment characters are content", "a: '''\n\t# not a comment\n\t/* nor this */\n\t'''", "# not a comment\n/* nor this */"),
		("non-ASCII content", "a: '''\n\t日本語\n\t😀\n\t'''", "日本語\n😀"),
		("an escaped line feed in an escaped block", "a: \"\"\"\n\tone\\ntwo\n\t\"\"\"", "one\ntwo"),
		("an escaped quote run in an escaped block", "a: \"\"\"\n\t\\\"\"\"\n\t\"\"\"", "\"\"\""),
	]

	@Test(arguments: blocks)
	func `parses a block string`(_ name: String, _ source: String, _ expected: String) throws {
		#expect(try parse(source)["a"] == .string(expected), "\(name)")
	}

	@Test
	func `a block string can be followed by a comma, a comment, or a closing bracket`() throws {
		#expect(try parse("[\n\t'''\n\tx\n\t''',\n]") == ["x"])
		#expect(try parse("[\n\t'''\n\tx\n\t'''\n]") == ["x"])
		#expect(try parse("[\n\t'''\n\tx\n\t'''  ,\n]") == ["x"])
		#expect(try parse("[\n\t'''\n\tx\n\t'''] ") == ["x"])
		#expect(try parse("a: '''\n\tx\n\t''' # comment\nb: 1") == ["a": "x", "b": 1])
		#expect(try parse("a: '''\n\tx\n\t'''\nb: 1") == ["a": "x", "b": 1])
		#expect(try parse("{a: '''\n\tx\n\t''', b: 1}") == ["a": "x", "b": 1])
	}

	@Test
	func `a block string as an array item and a member value`() throws {
		let value = try parse("""
			items: [
				'''
				one
				''',
				\"\"\"
				two\\n
				\"\"\",
			]
			""")
		#expect(value["items"] == ["one", "two\n"])
	}

	static let invalidBlocks: [Rejection] = [
		Rejection("content on the opening line", "a: '''one\n'''", "A block string's opening delimiter must be followed directly by a line break, and its content starts on the next line"),
		Rejection("trailing space on the opening line", "a: ''' \n\tone\n\t'''", "A block string's opening delimiter must be followed directly by a line break, and its content starts on the next line"),
		Rejection("a comment on the opening line", "a: ''' # comment\n\tone\n\t'''", "A block string's opening delimiter must be followed directly by a line break, and its content starts on the next line"),
		Rejection("never closed", "a: '''\n\tone\n", "Unterminated block string"),
		Rejection("never closed, at the end of the file", "a: '''\n\tone", "Unterminated block string"),
		Rejection("the opening delimiter at the end of the file", "a: '''", "Unterminated block string"),
		Rejection("an escaped block never closed", "a: \"\"\"\n\tone\n", "Unterminated block string"),
		Rejection("a four-quote block closed by three", "a: ''''\n\tone\n\t'''\n", "Unterminated block string"),
		Rejection("a line indented less", "a: '''\n\tone\n two\n\t'''", "This line does not start with the indentation of its block string's closing delimiter. Every line except a blank one must start with exactly the same spaces and tabs"),
		Rejection("a line with spaces where the delimiter has a tab", "a: '''\n    one\n\t'''", "This line does not start with the indentation of its block string's closing delimiter. Every line except a blank one must start with exactly the same spaces and tabs"),
		Rejection("a line with content indented less after a blank line", "a: '''\n\t\tone\n\n\ttwo\n\t\t'''", "This line does not start with the indentation of its block string's closing delimiter. Every line except a blank one must start with exactly the same spaces and tabs"),
		Rejection("an invalid escape in an escaped block", "a: \"\"\"\n\t\\q\n\t\"\"\"", #"Unknown escape “\q”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("a backslash at the end of a line", "a: \"\"\"\n\tone\\\n\ttwo\n\t\"\"\"", #"A backslash must be followed by an escape character. Use \\ for a literal backslash, or a '...' string"#),
		Rejection("text after the closing delimiter", "a: '''\n\tone\n\t'''x", "Unexpected “x” after a value"),
		Rejection("a block string as a key", "'''\nkey\n''': 1", "cannot be a key"),
	]

	@Test(arguments: invalidBlocks)
	func `rejects an invalid block string`(_ rejection: Rejection) {
		expectRejected(rejection.source, rejection.message)
	}

	@Test
	func `the dedent error points at the line`() throws {
		let error = try #require(parseError("a: '''\n\tone\n two\n\t'''"))
		#expect(error.location.line == 3)
		#expect(error.location.column == 1)
	}

	@Test
	func `an escape error in a block string points at the escape`() throws {
		let error = try #require(parseError("a: \"\"\"\n\tone\n\ttwo \\q\n\t\"\"\""))
		#expect(error.location.line == 3)
		#expect(error.location.column == 6)
	}

	@Test
	func `a block string that is never closed reports where it opened`() throws {
		let error = try #require(parseError("a: 1\nb: '''\n\tone\n\ttwo\n"))
		#expect(error.location.line == 2)
		#expect(error.location.column == 4)
	}

	@Test
	func `a block string in a nested context`() throws {
		let value = try parse("""
			outer: {
				inner: [
					{
						text: '''
							deep
							'''
					},
				],
			}
			""")
		#expect(value["outer"]?["inner"]?[0]?["text"] == "deep")
	}
}

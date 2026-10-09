import Foundation
import Testing
@testable import SOML

@Suite
struct EditorAPITests {
	@Test(arguments: [("{", "]"), ("[", "}")])
	func `tokenizing mismatched closing brackets takes linear time`(_ opening: String, _ closing: String) {
		let small = String(repeating: opening, count: 500) + String(repeating: closing, count: 500)
		let large = String(repeating: opening, count: 8000) + String(repeating: closing, count: 8000)

		expectLinearTime {
			_ = SOML.Token.tokens(in: small)
		} large: {
			_ = SOML.Token.tokens(in: large)
		}
	}

	@Test(arguments: ["", "name: '😀", "a: \"\\u{1F600}\"", "/* unfinished", "# comment", "value: '''\ntext", "[1, false, null, 30s, 2026-09-19T14:00:00Z]", "'quoted key': 'value'"])
	func `tolerant tokens have ordered bounded UTF8 ranges`(_ source: String) {
		let tokens = SOML.Token.tokens(in: source)
		var end = 0
		for token in tokens {
			#expect(token.range.lowerBound >= end)
			#expect(token.range.upperBound <= source.utf8.count)
			#expect(!token.range.isEmpty)
			end = token.range.upperBound
		}
	}

	@Test(arguments: ["", "  \n", "name: '😀", "a: \"\\u{1F600}\"", "/* unfinished", "# comment", "value: '''\ntext", "[1, false, null, 30s, 2026-09-19T14:00:00Z]", "'quoted key': 'value'", "a: \"é\\😀\"\r\n"])
	func `parts cover the whole text in order`(_ source: String) {
		let parts = SOML.Token.parts(in: source)
		#expect(parts.map(\.text).joined() == source)
		#expect(!parts.contains { $0.text.isEmpty })
		#expect(parts.compactMap(\.kind) == SOML.Token.tokens(in: source).map(\.kind))
	}

	@Test
	func `parts are made at their size, as text of one token for each byte has as many parts as bytes`() {
		let parts = SOML.Token.parts(in: String(repeating: "[],", count: 10_000) + " ")
		#expect(parts.count == 30_001)
		// Growing by doubling left up to twice the room, here 32768, where the allocator rounds the exact room up by about 1%.
		#expect(parts.capacity < parts.count + parts.count / 20)
	}

	@Test
	func `parts have the text of each token and the whitespace between them`() {
		let parts = SOML.Token.parts(in: "# note\nname: \"é\\t\" ")
		#expect(parts.map { part in "\(part.kind.map { "\($0)" } ?? "nil") \(part.text)" } == [
			"comment # note",
			"nil \n",
			"key name",
			"punctuation :",
			"nil  ",
			"string \"é",
			"escape \\t",
			"string \"",
			"nil  ",
		])
	}

	/**
	The parts of the text that are tokens, each as its kind and its text.
	*/
	static func describedTokens(in text: String) -> [String] {
		SOML.Token.parts(in: text).compactMap { part in
			part.kind.map { "\($0) \(part.text)" }
		}
	}

	@Test(arguments: [
		("a: \"\\u00e9 is e\" # c", ["key a", "punctuation :", "string \"", "escape \\u", "string 00e9 is e\"", "comment # c"]),
		("a: \"\\u{41\"", ["key a", "punctuation :", "string \"", "escape \\u{41", "string \""]),
		("a: \"\\u\"", ["key a", "punctuation :", "string \"", "escape \\u", "string \""]),
		("a: \"\\user}\"", ["key a", "punctuation :", "string \"", "escape \\u", "string ser}\""]),
		("a: \"\\u{41}b\"", ["key a", "punctuation :", "string \"", "escape \\u{41}", "string b\""]),
		("a: \"\\u{1f600}\\u{e9}\"", ["key a", "punctuation :", "string \"", "escape \\u{1f600}", "escape \\u{e9}", "string \""]),
		("a: \"\\u{41", ["key a", "punctuation :", "string \"", "escape \\u{41"]),
		("a: \"\\u{", ["key a", "punctuation :", "string \"", "escape \\u{"]),
		("a: \"\"\"\n\\u{41 x\n\"\"\"", ["key a", "punctuation :", "string \"\"\"\n", "escape \\u{41", "string  x\n\"\"\""]),
		("a: \"\"\"\nx\\\n\"\"\"", ["key a", "punctuation :", "string \"\"\"\nx", "escape \\", "string \n\"\"\""]),
	])
	func `an unfinished unicode escape stops at the end of its hex digits, and never takes the closing quote`(_ source: String, _ expected: [String]) {
		#expect(Self.describedTokens(in: source) == expected)
	}

	// While a member is typed, its value or its colon is missing, and the member on the next line must still have a key.
	static let incompleteMembers: [(String, [String])] = [
		("server: {\n\thost:\n\tport: 80\n}", ["punctuation {", "key host", "punctuation :", "key port", "punctuation :", "number 80", "punctuation }"]),
		("a: # note\nb: 1", ["punctuation :", "comment # note", "key b", "punctuation :", "number 1"]),
		("a:\n'b': 1", ["punctuation :", "key 'b'", "punctuation :", "number 1"]),
		("a:\n\n# note\n\"b\": 1", ["punctuation :", "comment # note", "key \"b\"", "punctuation :", "number 1"]),
		("hos\nport: 80", ["key hos", "key port", "punctuation :", "number 80"]),
		("'host'\nport: 80", ["key 'host'", "key port", "punctuation :", "number 80"]),
		("path: /usr/local\nport: 80", ["punctuation :", "invalid /usr/local", "key port", "punctuation :", "number 80"]),
		("name: Émile\nport: 80", ["punctuation :", "invalid Émile", "key port", "punctuation :", "number 80"]),
		("a: @\nb: 1", ["punctuation :", "invalid @", "key b", "punctuation :", "number 1"]),
		// A value on the line after its key stays a value.
		("a:\n\t1\nb: 2", ["punctuation :", "number 1", "key b", "punctuation :", "number 2"]),
		("a:\n\t2026-09-19T14:00:00Z\nb: 2", ["punctuation :", "instant 2026-09-19T14:00:00Z", "key b", "punctuation :", "number 2"]),
		("a:\n\t'x'\nb: 2", ["punctuation :", "string 'x'", "key b", "punctuation :", "number 2"]),
		("a:\n\t'''\n\tx: 1\n\t'''\nb: 2", ["punctuation :", "string '''\n\tx: 1\n\t'''", "key b", "punctuation :", "number 2"]),
		// An item of an array is never a member.
		("a: [\n\tb:\n]", ["punctuation [", "invalid b:", "punctuation ]"]),
		// A block comment can come before the key on its line.
		("a:\n/* x */ b: 2\n", ["punctuation :", "comment /* x */", "key b", "punctuation :", "number 2"]),
		("{\n\thost:\n\t/* default */ port: 80\n}\n", ["key host", "punctuation :", "comment /* default */", "key port", "punctuation :", "number 80", "punctuation }"]),
		("a:\n/* note\n*/ b: 2\n", ["punctuation :", "comment /* note\n*/", "key b", "punctuation :", "number 2"]),
		// A `\` before a line feed does not escape it, so the string ends at the line feed and is not a key.
		("a:\n\"x\\\nb\": 1\n", ["punctuation :", "string \"x", "escape \\", "key b", "string \": 1"]),
	]

	// A closing bracket also closes the unfinished containers inside the one it matches, as while typing, and a stray one closes nothing.
	static let unbalancedBrackets: [(String, [String])] = [
		("servers: [\n\t{host: 'a'\n]\nport: 80\nname: 'x'\n", ["punctuation ]", "key port", "punctuation :", "number 80", "key name", "punctuation :", "string 'x'"]),
		("a: [\n\t{b: [1\n\t}\n\t2\n]\nc: 1\n", ["punctuation }", "number 2", "punctuation ]", "key c", "punctuation :", "number 1"]),
		("a: [1]]\nb: 2\n", ["punctuation ]", "punctuation ]", "key b", "punctuation :", "number 2"]),
		("[{a: 1}}, 2]", ["punctuation }", "punctuation }", "punctuation ,", "number 2", "punctuation ]"]),
		// A document without braces has no `{`, so a `}` in it is stray too.
		("a: [{b: 1}}, 2]", ["punctuation }", "punctuation }", "punctuation ,", "number 2", "punctuation ]"]),
		("a: [}\n\t1\n\t2\n]\nb: 3", ["punctuation }", "number 1", "number 2", "punctuation ]", "key b", "punctuation :", "number 3"]),
		("a: 1\n}\nb:\nc: 2", ["punctuation }", "key b", "punctuation :", "key c", "punctuation :", "number 2"]),
	]

	@Test(arguments: unbalancedBrackets)
	func `a closing bracket closes the containers that it matches`(_ source: String, _ expected: [String]) {
		let tokens = Self.describedTokens(in: source)
		#expect(Array(tokens.drop { $0 != expected[0] }) == expected, "\(tokens)")
	}

	@Test
	func `the colon after a key with a dot in it is punctuation`() {
		#expect(Self.describedTokens(in: "example.com: 1\n") == ["key example", "invalid .com", "punctuation :", "number 1"])
		#expect(Self.describedTokens(in: "'a'.b: 1\n") == ["key 'a'", "invalid .b", "punctuation :", "number 1"])
		#expect(Self.describedTokens(in: "a b: 1\n") == ["key a", "invalid b", "punctuation :", "number 1"])
	}

	// The kinds of strings, block strings, comments, and scalars, and that a token ends where it should.
	static let tokenKinds: [(String, [String])] = [
		("a:\n  1", ["key a", "punctuation :", "number 1"]),
		("# {\na: 1", ["comment # {", "key a", "punctuation :", "number 1"]),
		("/* [ */ a: 1", ["comment /* [ */", "key a", "punctuation :", "number 1"]),
		("a: \"\\n\\t\"", ["key a", "punctuation :", "string \"", "escape \\n", "escape \\t", "string \""]),
		("a: 'x\nb: 1", ["key a", "punctuation :", "string 'x", "key b", "punctuation :", "number 1"]),
		("a: 'C:\\'\nb: 1", ["key a", "punctuation :", "string 'C:\\'", "key b", "punctuation :", "number 1"]),
		("a: '''\n  x\n  '''\nb: 2", ["key a", "punctuation :", "string '''\n  x\n  '''", "key b", "punctuation :", "number 2"]),
		("a: '''\nx\n''''\n'''\nb: 1", ["key a", "punctuation :", "string '''\nx\n''''\n'''", "key b", "punctuation :", "number 1"]),
		("a: '''\nx\\ny\n'''", ["key a", "punctuation :", "string '''\nx\\ny\n'''"]),
		("a: \"\\n\"", ["key a", "punctuation :", "string \"", "escape \\n", "string \""]),
		("a: \"\\u{e9}x\"", ["key a", "punctuation :", "string \"", "escape \\u{e9}", "string x\""]),
		("a: \"\"\"\n\\u{e9\nx\n\"\"\"", ["key a", "punctuation :", "string \"\"\"\n", "escape \\u{e9", "string \nx\n\"\"\""]),
		("a: 2026-09-19T14:00:00.Z", ["key a", "punctuation :", "invalid 2026-09-19T14:00:00.Z"]),
		("a: 2026-09-19T14:00:00Zx", ["key a", "punctuation :", "invalid 2026-09-19T14:00:00Zx"]),
		("a: ms", ["key a", "punctuation :", "invalid ms"]),
		("a: 1x5", ["key a", "punctuation :", "invalid 1x5"]),
		("a: 0x", ["key a", "punctuation :", "invalid 0x"]),
		("a: 1e5e5", ["key a", "punctuation :", "invalid 1e5e5"]),
		("a: 1-5", ["key a", "punctuation :", "invalid 1-5"]),
	]

	@Test(arguments: tokenKinds)
	func `tokens have the kind and the extent of what they are`(_ source: String, _ expected: [String]) {
		#expect(Self.describedTokens(in: source) == expected)
	}

	@Test
	func `a carriage return is an invalid token, as only space, tab, and line feed are whitespace`() {
		#expect(Self.describedTokens(in: "a: 1\r\nb: 2\r\n") == ["key a", "punctuation :", "number 1", "invalid \r", "key b", "punctuation :", "number 2", "invalid \r"])
		#expect(Self.describedTokens(in: "\r\n[1,\r 2]") == ["invalid \r", "punctuation [", "number 1", "punctuation ,", "invalid \r", "number 2", "punctuation ]"])
		#expect(Self.describedTokens(in: "a\r: 1") == ["key a", "invalid \r", "punctuation :", "number 1"])
	}

	@Test
	func `an unfinished block comment and an empty string have their lexical context`() {
		// `/*/` is not closed, because a `*/` must begin after the `/*`.
		#expect(SOML.lexicalContext(in: "/*/", atUTF8Offset: 3) == .comment)
		#expect(SOML.lexicalContext(in: "/* x/", atUTF8Offset: 5) == .comment)
		#expect(SOML.lexicalContext(in: "x: ''", atUTF8Offset: 5) == .code)
	}

	@Test
	func `the location of a path stops at the first step that does not exist`() throws {
		#expect(try SOML.Document(parsing: "a: {b: 1}").location(of: ["a", "x", "b"]).description == "line 1, column 1")
		#expect(try SOML.Document(parsing: "a: [1, [2]]").location(of: ["a", 5, 0]).description == "line 1, column 1")
	}

	@Test(arguments: incompleteMembers)
	func `a member without its value or its colon does not make the key on the next line a value`(_ source: String, _ expected: [String]) {
		let tokens = Self.describedTokens(in: source)
		#expect(Array(tokens.drop { $0 != expected[0] }) == expected, "\(tokens)")
	}

	@Test
	func `a quoted key has its escapes as separate tokens, like a string`() {
		#expect(Self.describedTokens(in: "\"a\\tb\": \"c\\td\"") == ["key \"a", "escape \\t", "key b\"", "punctuation :", "string \"c", "escape \\t", "string d\""])
		#expect(Self.describedTokens(in: "{\"\\u{61}\": 1}") == ["punctuation {", "key \"", "escape \\u{61}", "key \"", "punctuation :", "number 1", "punctuation }"])
		#expect(Self.describedTokens(in: "'a\\tb': 1") == ["key 'a\\tb'", "punctuation :", "number 1"])
	}

	@Test(arguments: ["name: '😀|", "name: 'a|b'", "'ke|y': 1", "value: \"a\\n|b\"", "value: '''\ntext|\n'''", "value: '''\ntext|"])
	func `lexical context recognizes strings and quoted keys`(_ fixture: String) throws {
		let prefix = try #require(fixture.split(separator: "|", omittingEmptySubsequences: false).first)
		let source = fixture.filter { $0 != "|" }
		guard case .string = SOML.lexicalContext(in: source, atUTF8Offset: prefix.utf8.count) else {
			Issue.record("Expected string context")
			return
		}
	}

	@Test(arguments: ["# note|", "# note|\nkey: 1", "/* note|", "/* note| */"])
	func `comments include their unfinished insertion boundary`(_ fixture: String) throws {
		let prefix = try #require(fixture.split(separator: "|", omittingEmptySubsequences: false).first)
		#expect(SOML.lexicalContext(in: fixture.filter { $0 != "|" }, atUTF8Offset: prefix.utf8.count) == .comment)
	}

	@Test(arguments: ["|", "x: |'a'", "x: 'a'|", "x: \"a\"|", "/* done */|", "# done\n|", "x: '''\na\n'''|"])
	func `complete delimiters return to code context`(_ fixture: String) throws {
		let prefix = try #require(fixture.split(separator: "|", omittingEmptySubsequences: false).first)
		#expect(SOML.lexicalContext(in: fixture.filter { $0 != "|" }, atUTF8Offset: prefix.utf8.count) == .code)
	}

	// Text typed between the characters of an opening delimiter breaks the delimiter, so that offset is not in the token.
	@Test(arguments: ["/|*/", "/|* note */", "x: '|''\na\n'''", "x: ''|'\na\n'''", "x: \"|\"\"\na\n\"\"\"", "x: ''''|'\na\n'''''"])
	func `an offset inside an opening delimiter of more than one character is outside the token`(_ fixture: String) throws {
		let prefix = try #require(fixture.split(separator: "|", omittingEmptySubsequences: false).first)
		#expect(SOML.lexicalContext(in: fixture.filter { $0 != "|" }, atUTF8Offset: prefix.utf8.count) == .code)
	}

	@Test
	func `an offset directly after an opening delimiter is inside the token`() {
		#expect(SOML.lexicalContext(in: "/* note */", atUTF8Offset: 2) == .comment)
		#expect(SOML.lexicalContext(in: "/*", atUTF8Offset: 2) == .comment)
		#expect(SOML.lexicalContext(in: "#", atUTF8Offset: 1) == .comment)
		#expect(SOML.lexicalContext(in: "x: '''\na\n'''", atUTF8Offset: 6) == .string(delimiter: "'''", closingDelimiterRange: 9..<12))
		#expect(SOML.lexicalContext(in: "x: ''", atUTF8Offset: 4) == .string(delimiter: "'", closingDelimiterRange: 4..<5))
	}

	@Test
	func `closing delimiter ranges are UTF8 and unsplit by escapes`() {
		let source = "value: \"😀\\ntext\""
		let offset = source.utf8.count - 1
		#expect(SOML.lexicalContext(in: source, atUTF8Offset: offset) == .string(delimiter: "\"", closingDelimiterRange: offset..<(offset + 1)))
		#expect(SOML.lexicalContext(in: source, atUTF8Offset: -1) == nil)
		#expect(SOML.lexicalContext(in: source, atUTF8Offset: source.utf8.count + 1) == nil)
	}

	@Test(arguments: ["items: [1, 2, {x: '😀', y: []}]", "[/* first */ 1, /* second */ 2]", "a: {x: 1 /* end */, y: [2, 3]}", "a: {}\nb: []", "a: ['[not a container]', 0xFF, 30s]"])
	func `expanded formatting preserves values and is idempotent`(_ source: String) throws {
		let document = try SOML.Document(parsing: source)
		let formatted = document.formatted(expandingContainers: true)
		let result = try SOML.Document(parsing: formatted)
		#expect(result.value == document.value)
		#expect(result.formatted(expandingContainers: true) == formatted)
		#expect(result.tree.comments.map { $0.text(in: result.tree.text) } == document.tree.comments.map { $0.text(in: document.tree.text) })
	}

	@Test
	func `formatting only expands when requested`() throws {
		let document = try SOML.Document(parsing: "items: [1, {x: 2}, []]")
		#expect(document.formatted() == "items: [1, {x: 2}, []]\n")
		#expect(document.formatted(expandingContainers: true) == "items: [\n\t1\n\t{\n\t\tx: 2\n\t}\n\t[]\n]\n")
	}

	@Test(arguments: ["[1, 2, 3]", "[\n1\n2\n3\n]", "[\n# one\n1 # first\n# two\n2 # second\n3\n]", "[/* one */ 1, /* two */ 2, 3]"])
	func `sibling moves preserve source and are reversible`(_ source: String) throws {
		let document = try SOML.Document(parsing: source)
		let moved = try document.swapping([0], with: [1])
		#expect(moved.value == [2, 1, 3])
		#expect(try moved.swapping([0], with: [1]).text == source)
	}

	@Test
	func `member moves carry keys and directly attached comments`() throws {
		let document = try SOML.Document(parsing: "# first\n'one': '😀' # trailing\n# second\ntwo: 0xFF\n")
		let moved = try document.swapping(["one"], with: ["two"])
		#expect(moved.text == "# second\ntwo: 0xFF\n# first\n'one': '😀' # trailing\n")
		#expect(moved.value == document.value)
		#expect(throws: SOML.EditError.self) {
			try document.swapping(["one"], with: ["one"])
		}
		#expect(throws: SOML.EditError.self) {
			try document.swapping(["one"], with: ["missing"])
		}
	}

	@Test(arguments: ["[1, 2, 3]", "[\n1\n2\n3\n]", "[\n# one\n1 # first\n# two\n2 # second\n3\n]", "[/* one */ 1, /* two */ 2, 3]", "[1, 2, 3,]"])
	func `reordering moves an item to another position and back`(_ source: String) throws {
		let document = try SOML.Document(parsing: source)
		let moved = try document.reordering([[1], [2], [0]])
		#expect(moved.value == [2, 3, 1])
		#expect(try moved.reordering([[2], [0], [1]]).text == source)
	}

	@Test
	func `reordering sorts members with their comments`() throws {
		let document = try SOML.Document(parsing: "# The port.\nport: 0x50 # Default\nhost: 'a'\nname: 'api'\n")
		let sorted = try document.reordering([["host"], ["name"], ["port"]])
		#expect(sorted.text == "host: 'a'\nname: 'api'\n# The port.\nport: 0x50 # Default\n")
		#expect(sorted.value == document.value)
	}

	@Test
	func `reordering nested items keeps the rest of the document`() throws {
		let document = try SOML.Document(parsing: "a: 1\nservers: [\n\t{host: 'a'}\n\t{host: 'b'}\n] # Hosts\n")
		let moved = try document.reordering([["servers", 1], ["servers", 0]])
		#expect(moved.text == "a: 1\nservers: [\n\t{host: 'b'}\n\t{host: 'a'}\n] # Hosts\n")
	}

	@Test
	func `a moved member keeps the blank line and comment before it`() throws {
		let document = try SOML.Document(parsing: "retry: 1s\n\n# Arrays\nlabels: []\nmatrix: []\n\n# Objects\npool: {}\ntimeout: 1s\n")
		let moved = try document.reordering([["retry"], ["timeout"], ["labels"], ["matrix"], ["pool"]])
		#expect(moved.text == "retry: 1s\ntimeout: 1s\n\n# Arrays\nlabels: []\nmatrix: []\n\n# Objects\npool: {}\n")
		#expect(try moved.reordering([["retry"], ["labels"], ["matrix"], ["pool"], ["timeout"]]).text == document.text)
	}

	@Test
	func `swapping groups keeps each group together`() throws {
		let document = try SOML.Document(parsing: "host: 'a'\nport: 80\n\n# Logging\nlevel: 'info'\n")
		#expect(try document.swapping(["port"], with: ["level"]).text == "host: 'a'\n\n# Logging\nlevel: 'info'\nport: 80\n")
	}

	@Test
	func `the first item takes the separator of the one that takes its place`() throws {
		let document = try SOML.Document(parsing: "[\n\t1\n\n\t2\n\t3\n]")
		let moved = try document.reordering([[1], [2], [0]])
		#expect(moved.text == "[\n\t2\n\t3\n\n\t1\n]")
		#expect(try moved.reordering([[2], [0], [1]]).text == document.text)
	}

	// A `#` comment that moves before text on its new line would take in that text, and comments on lines of their own that move after text on their new line would belong to what is before them.
	@Test(arguments: [
		("ports: [\n\t80, # HTTP\n\t443 # HTTPS\n]\n", ["ports", 0], ["ports", 1]),
		("{\n\ta: 1, # one\n\tb: 2 # two\n}\n", ["a"], ["b"]),
		("[\n\t1, 2 # two\n]\n", [0], [1]),
		("{\n\ta: 1, b: 2 # two\n}\n", ["a"], ["b"]),
		("a: [1 # one\n\t2]\n", ["a", 0], ["a", 1]),
		("{\n\t# The host\n\thost: 'a', port: 80\n}\n", ["host"], ["port"]),
		("{\n\t/* The host */\n\thost: 'a', port: 80\n}\n", ["host"], ["port"]),
		("[1,\n\t# about two\n\t2\n]\n", [0], [1]),
		// A separator that moves to after a `#` comment would go into it.
		("ports: [\n\t80 # HTTP\n\t443,\n\t8080\n]\n", ["ports", 1], ["ports", 2]),
		("{\n\ta: 1 # one\n\tb: 2,\n\tc: 3\n}\n", ["b"], ["c"]),
		("[\n\t0 # zero\n\t1, # one\n\t2\n]\n", [1], [2]),
		("[\n\t1, 2\n\t3 # three\n]\n", [1], [2]),
		("{\n\ta: 0, b: 1\n\tc: 2 # note\n}\n", ["b"], ["c"]),
		("[0 # x\n1, 2]", [1], [2]),
		("{\n\ta: 0 # zero\n\tb: 1, c:\n\t\t2\n}\n", ["b"], ["c"]),
	] as [(String, SOML.KeyPath, SOML.KeyPath)])
	func `a move that would change which member or item a comment belongs to is an error`(_ source: String, _ first: SOML.KeyPath, _ second: SOML.KeyPath) throws {
		let document = try SOML.Document(parsing: source)
		let error = try #require(throws: SOML.EditError.self) {
			try document.swapping(first, with: second)
		}

		#expect(error.message == "These comments cannot be moved with their values")
	}

	@Test
	func `a move keeps a comment at the end of the moved text when nothing follows on the new line`() throws {
		let document = try SOML.Document(parsing: "ports: [\n\t80 # HTTP\n\t443 # HTTPS\n]\n")
		let swapped = try document.swapping(["ports", 0], with: ["ports", 1])
		#expect(swapped.text == "ports: [\n\t443 # HTTPS\n\t80 # HTTP\n]\n")
		#expect(swapped.comments(at: ["ports", 0])?.trailing == "HTTPS")

		let leading = try SOML.Document(parsing: "{\n\t# The host\n\thost: 'a'\n\tport: 80\n}\n")
		#expect(try leading.swapping(["host"], with: ["port"]).text == "{\n\tport: 80\n\t# The host\n\thost: 'a'\n}\n")

		// What is between the members or items on a line does not matter when the moved ones keep their comments, so a move can be undone.
		let mixed = try SOML.Document(parsing: "{\n\ta: 0 # zero\n\tb: 1, c: 2\n}\n")
		let reordered = try mixed.reordering([["b"], ["c"], ["a"]])
		#expect(reordered.text == "{\n\tb: 1, c: 2\n\ta: 0 # zero\n}\n")
		#expect(try reordered.reordering([["a"], ["b"], ["c"]]).text == mixed.text)

		// The spaces at the end of a line go with what is before them, so they do not go into a `#` comment, and the move back gives the text before.
		let spaces = try SOML.Document(parsing: "a: 1   \nb: 2 # two\n")
		let swappedSpaces = try spaces.swapping(["a"], with: ["b"])
		#expect(swappedSpaces.text == "b: 2 # two\na: 1   \n")
		#expect(swappedSpaces.comments(at: ["b"])?.trailing == "two")
		#expect(try swappedSpaces.swapping(["a"], with: ["b"]).text == spaces.text)

		// An item with spaces at the end of its line can move before a closing bracket on that line, where the spaces stay with what moves there.
		#expect(try SOML.Document(parsing: "x: [\n\t1 \n\t2]\n").swapping(["x", 0], with: ["x", 1]).value == ["x": [2, 1]])
		#expect(try SOML.Document(parsing: "{\n\ta: 1 \n\tb: 2}\n").reordering([["b"], ["a"]]).value == ["b": 2, "a": 1])
		#expect(try SOML.Document(parsing: "x: [\n\t1 /* c */ \n\t2]\n").swapping(["x", 0], with: ["x", 1]).value == ["x": [2, 1]])

		let tabs = try SOML.Document(parsing: "[\n\t1\t\n\t2 # two\n\t3\n]\n")
		let reorderedTabs = try tabs.reordering([[1], [2], [0]])
		#expect(reorderedTabs.text == "[\n\t2 # two\n\t3\n\t1\t\n]\n")
		#expect(try reorderedTabs.reordering([[2], [0], [1]]).text == tabs.text)
	}

	@Test
	func `moving an item and reading the comments of every item take linear time with many spaces after the opening bracket`() throws {
		func document(count: Int) throws -> SOML.Document {
			try SOML.Document(parsing: "a: [" + String(repeating: " ", count: 10 * count) + (0..<count).map(String.init).joined(separator: ", ") + "]\n")
		}

		let small = try document(count: 100)
		let large = try document(count: 1600)

		try expectLinearTime {
			_ = try small.swapping(["a", 0], with: ["a", 99])
		} large: {
			_ = try large.swapping(["a", 0], with: ["a", 1599])
		}

		expectLinearTime {
			for index in 0..<100 {
				_ = small.comments(at: ["a", .index(index)])
			}
		} large: {
			for index in 0..<1600 {
				_ = large.comments(at: ["a", .index(index)])
			}
		}
	}

	@Test(arguments: ["a: [/* c */", "a: [ # c\n", "# c\na: ["])
	func `moving an item takes linear time with many spaces after a comment`(_ start: String) throws {
		func document(count: Int) throws -> SOML.Document {
			try SOML.Document(parsing: start + String(repeating: start.hasSuffix("\n") ? "\n" : " ", count: 10 * count) + (0..<count).map(String.init).joined(separator: ", ") + "]\n")
		}

		let small = try document(count: 50)
		let large = try document(count: 800)

		try expectLinearTime {
			_ = try small.swapping(["a", 0], with: ["a", 1])
		} large: {
			_ = try large.swapping(["a", 0], with: ["a", 1])
		}
	}

	@Test(arguments: [
		("a: [ /* note */ ]", ["a", 0], true),
		("a: [  ]", ["a", 0], false),
		("a: [ 1 ]", ["a", 1], true),
		("{a: {  }}", ["a", "b"], true),
		("a: {  }", ["a", "b"], false),
		("a: { # note\n}", ["a", "b"], false),
	] as [(String, SOML.KeyPath, Bool)])
	func `a container stays on one line when its brackets are on one line with something between them`(_ source: String, _ path: SOML.KeyPath, _ staysOnOneLine: Bool) throws {
		let edited = try SOML.Document(parsing: source).setting([1, 2], at: path)
		#expect(edited.text.contains("[1, 2]") == staysOnOneLine, "\(edited.text)")
	}

	@Test
	func `reordering in the same order changes nothing`() throws {
		let document = try SOML.Document(parsing: "{b: 1, a: 2}")
		#expect(try document.reordering([["b"], ["a"]]).text == document.text)
	}

	@Test
	func `reordering validates exact nested keys and distinguishes string keys from indices`() throws {
		let document = try SOML.Document(parsing: "outer: {'é': 1, 'e\u{301}': 2, '0': 3}\nkeep: true\n")
		let paths: [SOML.KeyPath] = [["outer", "0"], ["outer", "e\u{301}"], ["outer", "é"]]
		let reordered = try document.reordering(paths)
		#expect(reordered.text == "outer: {'0': 3, 'e\u{301}': 2, 'é': 1}\nkeep: true\n")
		#expect(reordered.value == document.value)
		#expect(reordered.value["outer"]?.objectValue?.keys.map { Array($0.utf8) } == ["0", "e\u{301}", "é"].map { Array($0.utf8) })

		for invalid: [SOML.KeyPath] in [
			[["outer", "0"], ["outer", "é"], ["outer", "é"]],
			[["outer", 0], ["outer", "e\u{301}"], ["outer", "é"]],
			[["outer", "missing"], ["outer", "e\u{301}"], ["outer", "é"]],
			[["outer", "0"], ["outer", "é"]],
			paths + [["outer", "extra"]]
		] {
			#expect(throws: SOML.EditError.self) {
				try document.reordering(invalid)
			}
		}
		#expect(document.text == "outer: {'é': 1, 'e\u{301}': 2, '0': 3}\nkeep: true\n")
	}

	@Test(arguments: [[["a"]], [["a"], ["a"]], [["a"], ["missing"]], [["a"], ["b"], ["c", "d"]], []] as [[SOML.KeyPath]])
	func `reordering requires every sibling once`(_ paths: [SOML.KeyPath]) throws {
		let document = try SOML.Document(parsing: "a: 1\nb: 2\nc: {d: 3}\n")
		#expect(throws: SOML.EditError.self) {
			try document.reordering(paths)
		}
	}
}

extension EditorAPITests {
	@Test(arguments: ConformanceTests.validCases)
	func `conformance documents tokenize and expand without losing values`(_ name: String) throws {
		let source = try String(contentsOf: ConformanceTests.root.appending(path: "valid/\(name).soml"), encoding: .utf8)
		#expect(!SOML.Token.tokens(in: source).contains { $0.kind == .invalid })
		let document = try SOML.Document(parsing: source)
		let expanded = document.formatted(expandingContainers: true)
		let result = try SOML.Document(parsing: expanded)
		#expect(result.value == document.value)
		#expect(result.formatted(expandingContainers: true) == expanded)
		let normalized = try SOML.Document(parsing: document.formatted())
		#expect(result.tree.comments.map { $0.text(in: result.tree.text) } == normalized.tree.comments.map { $0.text(in: normalized.tree.text) })
	}

	@Test(arguments: ["value: \"é\\😀a\"", "'é': \"😀\\u{1F600}\"", "/*😀*/ key: [true, 30ms]", "value: \"\"\"\n😀\\😀\n\"\"\""])
	func `all incomplete prefixes preserve Unicode token boundaries`(_ source: String) {
		let scalars = Array(source.unicodeScalars)
		for count in 0...scalars.count {
			let prefix = String(String.UnicodeScalarView(scalars.prefix(count)))
			let bytes = Array(prefix.utf8)
			for token in SOML.Token.tokens(in: prefix) {
				#expect(String(validating: bytes[token.range], as: UTF8.self) != nil)
			}
			#expect(SOML.lexicalContext(in: prefix, atUTF8Offset: bytes.count) != nil)
		}
	}
}

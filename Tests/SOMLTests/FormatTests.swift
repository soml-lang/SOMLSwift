import Foundation
import Testing
@testable import SOML

/**
Formats a document, and checks that the value is kept and that formatting again changes nothing.
*/
private func expectFormat(_ input: String, _ expected: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
	let document = try SOML.Document(parsing: input)
	let formatted = document.formatted()
	#expect(formatted == expected, sourceLocation: sourceLocation)

	let reformatted = try SOML.Document(parsing: formatted)
	#expect(reformatted.value == document.value, "The value changed.", sourceLocation: sourceLocation)
	#expect(reformatted.formatted() == formatted, "Formatting again changed the text.", sourceLocation: sourceLocation)
}

/**
The comment texts of a document in order, without the trailing whitespace and the runs of blank lines that the formatter removes.
*/
private func comments(_ document: SOML.Document) -> [String] {
	document.tree.comments.map { comment in
		document.tree.text[comment.range]
			.split(separator: .lineFeed, omittingEmptySubsequences: false)
			.map { String(decoding: $0.withoutTrailingWhitespace, as: UTF8.self) }
			.filter { !$0.isEmpty }
			.joined(separator: "\n")
	}
}

/**
Checks that formatting keeps the value and the comments, and that formatting again changes nothing.
*/
private func expectFormatKeepsDocument(_ text: some Sequence<UInt8>, sourceLocation: SourceLocation = #_sourceLocation) throws {
	let document = try SOML.Document(parsing: text)
	let formatted = try SOML.Document(parsing: document.formatted())
	#expect(formatted.value == document.value, "The value changed.", sourceLocation: sourceLocation)
	#expect(comments(formatted) == comments(document), "A comment changed.", sourceLocation: sourceLocation)
	#expect(formatted.formatted() == document.formatted(), "Formatting again changed the text.", sourceLocation: sourceLocation)
}

@Suite
struct FormatTests {
	/**
	The cases of the JS reference implementation's formatter tests, generated from that file, so the output is the reference's byte for byte.
	*/
	static let referenceCases: [(input: String, expected: String)] = [
		("a: {b: 1, c: [1,\n2], d: {}, e: [\n]}", "a: {\n\tb: 1\n\tc: [\n\t\t1\n\t\t2\n\t]\n\td: {}\n\te: []\n}\n"),
		("a: {b: 1,  c: [1,2,], d: {}}", "a: {b: 1, c: [1, 2], d: {}}\n"),
		("m: [\n[1,0], [0, 1]\n]", "m: [\n\t[1, 0]\n\t[0, 1]\n]\n"),
		("a: [[ /* x */ ], 1]", "a: [[/* x */], 1]\n"),
		("{a: 1}", "{a: 1}\n"),
		("{\na: 1}", "{\n\ta: 1\n}\n"),
		("[1,\n[2]]", "[\n\t1\n\t[2]\n]\n"),
		("a:1\nb:    2", "a: 1\nb: 2\n"),
		("a:\n\t1", "a: 1\n"),
		("'b c': [0xFF, 1_000, 90m, \"x\", 'y', 2026-09-19T16:00:00+02:00]", "'b c': [0xFF, 1_000, 90m, \"x\", 'y', 2026-09-19T16:00:00+02:00]\n"),
		("\n\n# Header   \n\n\n\na: 1  \n\n\n\nb: 2\n\n\n", "# Header\n\na: 1\n\nb: 2\n"),
		("a: [\n\n1,\n\n2,\n\n]", "a: [\n\t1\n\n\t2\n]\n"),
		("a: {\n\nb: 1\n\n}", "a: {\n\tb: 1\n}\n"),
		("[\n\n# c\n1]", "[\n\t# c\n\t1\n]\n"),
		("a: [1, # One\n2 # Two\n]", "a: [\n\t1 # One\n\t2 # Two\n]\n"),
		("a: [1 /* One */\n]", "a: [\n\t1 /* One */\n]\n"),
		("a: [\n\t1,\n\t2,\n]\nb: {\n\tc: 1,\n\td: [3, 4,],\n}", "a: [\n\t1\n\t2\n]\nb: {\n\tc: 1\n\td: [3, 4]\n}\n"),
		("[1, 2\n3,\n4,]", "[\n\t1\n\t2\n\t3\n\t4\n]\n"),
		("a: [\n\t1\n\t2\n]\nb: {\n\tc: 1 # c\n\td: 2\n}", "a: [\n\t1\n\t2\n]\nb: {\n\tc: 1 # c\n\td: 2\n}\n"),
		("{\na: 1\nb: 2\n}", "{\n\ta: 1\n\tb: 2\n}\n"),
		("[1, /* x */ 2\n]", "[\n\t1\n\t/* x */ 2\n]\n"),
		("a: [1 /* a */, /* b */ 2\n]", "a: [\n\t1 /* a */\n\t/* b */ 2\n]\n"),
		("[1, /* a */ /* b */ 2\n]", "[\n\t1\n\t/* a */ /* b */ 2\n]\n"),
		("[1 /* a */, /* b */ 2, /* c */]", "[1 /* a */, /* b */ 2 /* c */]\n"),
		("/* a */ /* b */ a: 1", "/* a */ /* b */ a: 1\n"),
		("a: [\n1,\n# Note\n2,\n# End\n]", "a: [\n\t1\n\t# Note\n\t2\n\t# End\n]\n"),
		("a: [ # c\n1]", "a: [ # c\n\t1\n]\n"),
		("a: { # only\n}", "a: { # only\n}\n"),
		("{#\n\n1: []}", "{ #\n\t1: []\n}\n"),
		("a: [\n# only\n]", "a: [\n\t# only\n]\n"),
		("a: /* c */ 1", "a: /* c */ 1\n"),
		("a: # c\n1", "a: # c\n\t1\n"),
		("a: # c\n{b: 1}", "a: # c\n\t{b: 1}\n"),
		("a: # c\n{\nb: 1}", "a: # c\n\t{\n\t\tb: 1\n\t}\n"),
		("a:\n# c\n1", "a:\n\t# c\n\t1\n"),
		("a: /* x\ny */ {b: 1}", "a: /* x\ny */ {b: 1}\n"),
		("/* a\n   b */ key: 1", "/* a\n   b */ key: 1\n"),
		("/* a\n\n\n\n   b   \n*/\nkey: 1", "/* a\n\n   b\n*/\nkey: 1\n"),
		("# x  \t\na: 1", "# x  \na: 1\n"),
		("a: 1 #﻿", "a: 1 #﻿\n"),
		("pool: {\n    description: '''\n        one\n          two\n\n        ''',\n}", "pool: {\n\tdescription:\n\t\t'''\n\t\tone\n\t\t  two\n\n\t\t'''\n}\n"),
		("a: [\n'''\nx\n'''\n]", "a: [\n\t'''\n\tx\n\t'''\n]\n"),
		("a: '''\n\tx  \n\t'''", "a:\n\t'''\n\tx  \n\t'''\n"),
		("a: [\n1,\n# One\n\n# Two\n2,\n]", "a: [\n\t1\n\t# One\n\n\t# Two\n\t2\n]\n"),
		("# One\n\n# Two\na: 1", "# One\n\n# Two\na: 1\n"),
		("# Head\n[1, # One\n2] # Tail", "# Head\n[\n\t1 # One\n\t2\n] # Tail\n"),
		("a: [1,\n2] /* t */\nb: 3", "a: [\n\t1\n\t2\n] /* t */\nb: 3\n"),
		("a: [1,\n/* one\n  two */\n2]", "a: [\n\t1\n\t/* one\n  two */\n\t2\n]\n"),
		("a: # c\n\t'''\n\tx\n\t'''", "a: # c\n\t'''\n\tx\n\t'''\n"),
		("a: '''\n  x\n   \n  y\n  '''", "a:\n\t'''\n\tx\n   \n\ty\n\t'''\n"),
	]

	@Test(arguments: referenceCases)
	func `formats like the reference`(input: String, expected: String) throws {
		try expectFormat(input, expected)
	}

	@Test(arguments: ConformanceTests.validCases)
	func `a valid case keeps its value and comments, and formatting it again changes nothing`(_ name: String) throws {
		let base = ConformanceTests.root.appending(path: "valid/\(name)")
		try expectFormatKeepsDocument(try Data(contentsOf: base.appendingPathExtension("soml")))

		// Canonical form is already formatted.
		let canonicalForm = try String(contentsOf: URL(filePath: base.path(percentEncoded: false) + ".canonical.soml"), encoding: .utf8)
		#expect(try SOML.Document(parsing: canonicalForm).formatted() == canonicalForm)
	}

	@Test
	func `the value is the parsed value`() throws {
		let text = "# Pool\npool: {\n\tmin: 2\n\tmax: 0x10 # Hex\n}\n"
		#expect(try SOML.Document(parsing: text).value == SOML.Value(parsing: text))
		#expect(try SOML.Document(parsing: Array(text.utf8)).formatted() == text)
	}

	@Test
	func `an invalid document throws the parse error`() throws {
		#expect(throws: try #require(parseError("a: 1\na: 2"))) {
			try SOML.Document(parsing: "a: 1\na: 2")
		}

		#expect(throws: SOML.ParseError.self) {
			try SOML.Document(parsing: "a: b")
		}

		#expect(throws: SOML.ParseError.self) {
			try SOML.Document(parsing: [0x61, 0x3A, 0x20, 0xFF])
		}
	}

	@Test
	func `the readme example`() throws {
		let document = try SOML.Document(parsing: """
			# The edge service.
			name:   'api-gateway'   # Shown in the dashboard.
			labels: ['prod',
			    'eu-west']



			postgres: {host: 'db.internal'}
			pool: {min: 2, max: 0x10 , idle: 90m} # Connections
			""")
		let expected = """
			# The edge service.
			name: 'api-gateway' # Shown in the dashboard.
			labels: [
				'prod'
				'eu-west'
			]

			postgres: {host: 'db.internal'}
			pool: {min: 2, max: 0x10, idle: 90m} # Connections

			"""
		#expect(document.formatted() == expected)
	}

	@Test
	func `a container on one line stays on one line, with a comma and a space between its items`() throws {
		try expectFormat("a: {b: /* c */ 1 ,c: 2 , }", "a: {b: /* c */ 1, c: 2}\n")
		try expectFormat("a: {b: [1, {c: 2}], d: {}} # tail", "a: {b: [1, {c: 2}], d: {}} # tail\n")
		try expectFormat("a: [1 /* a */ , 2]", "a: [1 /* a */, 2]\n")
		try expectFormat("a: [1, /* end */]", "a: [1 /* end */]\n")
		try expectFormat("a: [ /* x */ ]", "a: [/* x */]\n")
		try expectFormat("[1, 2]", "[1, 2]\n")
	}

	@Test
	func `a line break anywhere inside a container puts each item on its own line`() throws {
		try expectFormat("a: [[1,\n2], [3, 4]]", "a: [\n\t[\n\t\t1\n\t\t2\n\t]\n\t[3, 4]\n]\n")
		try expectFormat("a: [1, /* a\nb */ 2]", "a: [\n\t1\n\t/* a\nb */ 2\n]\n")
		try expectFormat("a: [1, \"\"\"\nx\n\"\"\"]", "a: [\n\t1\n\t\"\"\"\n\tx\n\t\"\"\"\n]\n")
	}

	@Test
	func `spelling is kept`() throws {
		try expectFormat("mode: 0o644\nsize: 1_000\ntimeout: 90m\nserver: {host: 'a'}\n", "mode: 0o644\nsize: 1_000\ntimeout: 90m\nserver: {host: 'a'}\n")
		try expectFormat(#""a\"b": -infinity"#, #""a\"b": -infinity"# + "\n")
	}

	@Test
	func `a block string with a longer delimiter begins on the line after its key, with its content at the indentation of its delimiters`() throws {
		try expectFormat("a: {\n        b: \"\"\"\"\n            x \"\"\"\n              y\n            \"\"\"\"\n}", "a: {\n\tb:\n\t\t\"\"\"\"\n\t\tx \"\"\"\n\t\t  y\n\t\t\"\"\"\"\n}\n")
	}

	@Test
	func `non-ASCII text is kept`() throws {
		try expectFormat("'ключ': ['日本', # コメント\n\"é\"] /* ü */", "'ключ': [\n\t'日本' # コメント\n\t\"é\"\n] /* ü */\n")
	}

	@Test
	func `a comment that ends with a format character keeps it, and the trailing whitespace after it goes`() throws {
		// A format character, like U+0600, joins the space after it into one `Character`, which a check on characters would hide from the removal of trailing whitespace.
		try expectFormatKeepsDocument(Array("a: 1 # x\u{0600} \n".utf8))
		try expectFormatKeepsDocument(Array("a: 1 # x\u{0600} ".utf8))
		try expectFormatKeepsDocument(Array("# \u{202E}a\nb: 2 # \u{0600}\t\n".utf8))
	}

	/*
	Swift Testing runs a test on a thread with a 512 KB stack, so these also check that the formatter's recursion fits there at the nesting limit in a debug build.
	*/

	@Test
	func `100 levels of nested objects`() throws {
		let depth = Parser.maximumDepth
		let text = "a: " + String(repeating: "{\na: ", count: depth - 1) + "1" + String(repeating: "}", count: depth - 1)
		var expected = "a: {\n"

		for level in 1..<(depth - 1) {
			expected += String(repeating: "\t", count: level) + "a: {\n"
		}

		expected += String(repeating: "\t", count: depth - 1) + "a: 1\n"

		for level in (0..<(depth - 1)).reversed() {
			expected += String(repeating: "\t", count: level) + "}\n"
		}

		try expectFormat(text, expected)
		try expectFormat("{\n" + text + "}", "{\n" + expected.split(separator: "\n").map { "\t\($0)" }.joined(separator: "\n") + "\n}\n")

		let oneLine = "a: " + String(repeating: "{a: ", count: depth - 1) + "1" + String(repeating: "}", count: depth - 1)
		try expectFormat(oneLine, oneLine + "\n")
		try expectFormat("{" + oneLine + "}", "{" + oneLine + "}\n")
	}

	@Test
	func `100 levels of nested arrays`() throws {
		let depth = Parser.maximumDepth
		var expected = ""

		for level in 0..<(depth - 1) {
			expected += String(repeating: "\t", count: level) + "[\n"
		}

		expected += String(repeating: "\t", count: depth - 1) + "[]\n"

		for level in (0..<(depth - 1)).reversed() {
			expected += String(repeating: "\t", count: level) + "]\n"
		}

		try expectFormat(String(repeating: "[\n", count: depth) + String(repeating: "]", count: depth), expected)

		let oneLine = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
		try expectFormat(oneLine, oneLine + "\n")
		try expectFormat(String(repeating: "[ /* c */ ", count: depth) + String(repeating: "]", count: depth), String(repeating: "[/* c */ ", count: depth - 1) + "[/* c */" + String(repeating: "]", count: depth) + "\n")
	}

	@Test
	func `100 levels of nesting with comments at every level`() throws {
		let depth = Parser.maximumDepth
		try expectFormatKeepsDocument((String(repeating: "[ # c\n", count: depth) + String(repeating: "] /* d */", count: depth)).utf8)
		try expectFormatKeepsDocument((String(repeating: "a: # c\n{", count: depth - 1) + "a: 1" + String(repeating: "/* d */}", count: depth - 1)).utf8)

		// One-line objects with a comment after every `:`, so each level also goes through the writing of those comments.
		try expectFormatKeepsDocument(("a: " + String(repeating: "{b: /* c */ ", count: depth - 1) + "1" + String(repeating: "}", count: depth - 1)).utf8)
	}

	@Test
	func `100 levels of mixed nesting with comments`() throws {
		// The brace-less top level is one level, and each repetition adds three: the object of `x`, the array, and the object in it. The comment after the `:` keeps the array on its own line, one level deeper.
		let repetitions = (Parser.maximumDepth - 1) / 3
		let opening = "x: {'y': # c\n[ /* c */ 1, {"
		let closing = "}, # d\n] /* d */}"
		let text = String(repeating: opening, count: repetitions) + "z: '''\n  deep\n  '''" + String(repeating: closing, count: repetitions)
		try expectFormatKeepsDocument(text.utf8)
		expectRejected(String(repeating: opening, count: repetitions) + "z: []" + String(repeating: closing, count: repetitions), "The document is nested more than 100 levels deep")

		let formatted = try SOML.Document(parsing: text).formatted()
		#expect(formatted.contains("\n" + String(repeating: "\t", count: 4 * repetitions) + "z:\n" + String(repeating: "\t", count: 4 * repetitions + 1) + "'''\n"))
	}

	@Test(.timeLimit(.minutes(1)))
	func `many block comments on one line format in linear time`() throws {
		// Looking for a line break between each comment and the item made this quadratic: 40,000 comments took 4 seconds in a release build.
		let document = try SOML.Document(parsing: "a: [" + String(repeating: " /*a*/", count: 40_000) + "\n 1]")
		#expect(document.formatted().hasSuffix("/*a*/\n\t1\n]\n"))
	}
}

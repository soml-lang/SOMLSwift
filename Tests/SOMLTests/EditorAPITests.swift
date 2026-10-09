import Foundation
import Testing
@testable import SOML

@Suite
struct EditorAPITests {
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

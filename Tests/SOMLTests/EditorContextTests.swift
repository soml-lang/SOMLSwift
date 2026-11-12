import Testing
@testable import SOML

@Suite
struct EditorContextTests {
	@Test
	func `key ranges preserve exact quoted spelling through nested arrays`() throws {
		let source = "keys: {'🎉': 1, 'the: name': 2}\nitems: [{name: 3}]\n"
		let document = try SOML.Document(parsing: source)
		let bytes = Array(source.utf8)
		let quoted = try #require(document.keyRange(of: ["keys", "the: name"]))
		#expect(String(decoding: bytes[quoted.lowerBound.offset..<quoted.upperBound.offset], as: UTF8.self) == "'the: name'")
		#expect(quoted.lowerBound.line == 1)
		#expect(quoted.lowerBound.column == 16)
		let nested = try #require(document.keyRange(of: ["items", 0, "name"]))
		#expect(String(decoding: bytes[nested.lowerBound.offset..<nested.upperBound.offset], as: UTF8.self) == "name")
		#expect(nested.lowerBound.line == 2)
		#expect(document.keyRange(of: ["items", 0]) == nil)
		#expect(document.keyRange(of: ["missing"]) == nil)
		#expect(document.keyRange(of: ["items", 9, "name"]) == nil)
	}

	@Test(arguments: ["enabled: |", "enabled: | # Note\n", "config: {enabled: |}", "items: [|]", "items: [1, |]", "items: [1\n\t|]"])
	func `value context uses the document grammar at an empty caret`(marked: String) throws {
		let offset = try #require(marked.utf8.firstIndex(of: 124))
		let caret = marked.utf8.distance(from: marked.utf8.startIndex, to: offset)
		let bytes = Array(marked.utf8.filter { $0 != 124 })
		#expect(SOML.Document.expectsValue(atOffset: caret, in: bytes))
	}

	@Test(arguments: ["enabled: tr|ue", "enabled: 'a|b'", "enabled: # No|te", "enabled: /* No|te */", "enabled: |true", "ena|bled: true", "enabled: true| ", "bad: %\nenabled: |", "|"])
	func `value context rejects strings comments existing tokens and uncertain prefixes`(marked: String) throws {
		let offset = try #require(marked.utf8.firstIndex(of: 124))
		let caret = marked.utf8.distance(from: marked.utf8.startIndex, to: offset)
		let bytes = Array(marked.utf8.filter { $0 != 124 })
		#expect(!SOML.Document.expectsValue(atOffset: caret, in: bytes))
	}

	@Test(arguments: ["rows: [{host: 'a'}, {|}]", "rows: [{host: 'a'}, {port: 80, |}]", "rows: [{host: 'a'}, {\n\t| # Note\n}]", "|"])
	func `key context recognizes empty member gaps with the native grammar`(marked: String) throws {
		let offset = try #require(marked.utf8.firstIndex(of: 124))
		let caret = marked.utf8.distance(from: marked.utf8.startIndex, to: offset)
		let bytes = Array(marked.utf8.filter { $0 != 124 })
		#expect(SOML.Document.expectsKey(atOffset: caret, in: bytes))
	}

	@Test(arguments: ["items: [|]", "rows: [{host: |}]", "rows: [{|host: 1}]", "rows: [{ho|st: 1}]", "rows: [{host: '|'}]", "rows: [{# Co|mment\n}]", "bad: %\nrows: [{|}]"])
	func `key context rejects values tokens comments and uncertain prefixes`(marked: String) throws {
		let offset = try #require(marked.utf8.firstIndex(of: 124))
		let caret = marked.utf8.distance(from: marked.utf8.startIndex, to: offset)
		let bytes = Array(marked.utf8.filter { $0 != 124 })
		#expect(!SOML.Document.expectsKey(atOffset: caret, in: bytes))
	}

	@Test(arguments: ["enabled: |\nnext: 1\n", "enabled: | # Note\nnext: 1\n", "{enabled: |\nnext: 1\n}"])
	func `value context permits following members across line breaks`(marked: String) throws {
		let offset = try #require(marked.utf8.firstIndex(of: 124))
		let caret = marked.utf8.distance(from: marked.utf8.startIndex, to: offset)
		let bytes = Array(marked.utf8.filter { $0 != 124 })
		#expect(SOML.Document.expectsValue(atOffset: caret, in: bytes))
	}

	@Test(arguments: ["enabled: |\ntrue\n", "enabled: |false\n", "bad: %\nenabled: |\nnext: 1\n"])
	func `value context never displaces an existing following value`(marked: String) throws {
		let offset = try #require(marked.utf8.firstIndex(of: 124))
		let caret = marked.utf8.distance(from: marked.utf8.startIndex, to: offset)
		let bytes = Array(marked.utf8.filter { $0 != 124 })
		#expect(!SOML.Document.expectsValue(atOffset: caret, in: bytes))
	}

	@Test
	func `key context rejects invalid UTF8 and offsets outside the source`() {
		#expect(!SOML.Document.expectsKey(atOffset: 0, in: [255]))
		#expect(!SOML.Document.expectsKey(atOffset: -1, in: []))
		#expect(!SOML.Document.expectsKey(atOffset: 1, in: []))
	}
}

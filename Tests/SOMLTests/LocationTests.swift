import Foundation
import Testing
@testable import SOML

@Suite
struct LocationTests {
	private func location(_ source: String, _ path: [any CodingKey]) throws -> (line: Int, column: Int) {
		let location = try SOML.Document(parsing: source).location(of: path)
		return (location.line, location.column)
	}

	@Test
	func `the location from the line feeds of the tree is the location from counting every line`() throws {
		// More than 32 members, so that a member is found through the hash index of the object, and wide characters and tabs, which a column counts as one.
		let members = (0..<40).map { "key\($0): 'é😀\t\($0)' # Ünïcode\n" }.joined()
		let source = "\n" + members + "list: [\n\t1,\n\t'ø',\n]\n"
		let document = try SOML.Document(parsing: source)
		let bytes = Array(source.utf8)

		for offset in 0...(bytes.count + 1) {
			#expect(document.tree.location(at: offset) == SOML.Location(offset: offset, in: bytes), "Offset \(offset)")
		}

		for index in 0..<40 {
			let range = try #require(document.range(of: [.key("key\(index)")]))
			#expect(range.lowerBound == SOML.Location(offset: range.lowerBound.offset, in: bytes))
			#expect(range.lowerBound.line == index + 2)
			#expect(range.lowerBound.column == 1)
			#expect(document.valueText(at: [.key("key\(index)")]) == "'é😀\t\(index)'")
		}
	}

	@Test
	func `finds a top-level member`() throws {
		let location = try location("name: 'api'\nport: 80", [SOMLCodingKey(stringValue: "port")])
		#expect(location == (2, 1))
	}

	@Test
	func `finds a nested member and an array item`() throws {
		let source = "server: {\n\thosts: [\n\t\t'a',\n\t\t'b',\n\t],\n}"
		let location = try location(source, [SOMLCodingKey(stringValue: "server"), SOMLCodingKey(stringValue: "hosts"), SOMLCodingKey(intValue: 1)])
		#expect(location == (4, 3))
	}

	@Test
	func `finds a key that contains a dot as one key`() throws {
		let source = "server: {host: 'a'}\n'server.port': 80"
		#expect(try location(source, [SOMLCodingKey(stringValue: "server.port")]) == (2, 1))
		#expect(try location(source, [SOMLCodingKey(stringValue: "server"), SOMLCodingKey(stringValue: "port")]) == (1, 1))
	}

	@Test
	func `finds a quoted key`() throws {
		let location = try location("a: 1\n'the name': 2", [SOMLCodingKey(stringValue: "the name")])
		#expect(location == (2, 1))
	}

	@Test
	func `gives the closest member for a missing key`() throws {
		let source = "a: 1\nserver: {\n\thost: 'a',\n}"
		let location = try location(source, [SOMLCodingKey(stringValue: "server"), SOMLCodingKey(stringValue: "port")])
		#expect(location == (2, 1))
	}

	@Test
	func `gives the start of the collection for an empty or unmatched path`() throws {
		#expect(try location("\n\na: 1", []) == (3, 1))
		#expect(try location("\n\na: 1", [SOMLCodingKey(stringValue: "b")]) == (3, 1))
	}

	@Test
	func `gives the closest item for an index past the end`() throws {
		let location = try location("a: [\n\t1,\n]", [SOMLCodingKey(stringValue: "a"), SOMLCodingKey(intValue: 5)])
		#expect(location == (1, 1))
	}

	@Test
	func `counts the column in Unicode scalars`() throws {
		let location = try location("a: ['é', 'ø']", [SOMLCodingKey(stringValue: "a"), SOMLCodingKey(intValue: 1)])
		#expect(location == (1, 10))
	}

	@Test
	func `gives the location of a decoding error`() throws {
		struct Config: Decodable {
			let ports: [Int]
		}

		let document = try SOML.Document(parsing: "name: 'api'\nports: [80, 'eighty']")
		let error = try #require(throws: DecodingError.self) {
			try SOML.Decoder().decode(Config.self, from: document.value)
		}

		guard case .typeMismatch(_, let context) = error else {
			Issue.record("Expected a type mismatch, got \(error)")
			return
		}

		#expect(document.location(of: context.codingPath).line == 2)
		#expect(document.location(of: context.codingPath).column == 13)
	}

	@Test
	func `finds the member of a decoding error with the decoder's key strategy`() throws {
		struct Server: Decodable {
			var maxConnections: Int
		}

		let document = try SOML.Document(parsing: "name: 'api'\nmax-connections: 'many'")
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase

		do {
			_ = try decoder.decode(Server.self, from: document.value)
			Issue.record("Expected a type mismatch")
		} catch DecodingError.typeMismatch(_, let context) {
			#expect(document.location(of: context.codingPath, keyDecodingStrategy: decoder.keyDecodingStrategy).line == 2)
			#expect(document.location(of: context.codingPath, keyDecodingStrategy: decoder.keyDecodingStrategy).column == 1)
			// Without the strategy, the camelCase key is not in the document, so the location is the start of the document.
			#expect(document.location(of: context.codingPath).line == 1)
			#expect(document.location(of: context.codingPath).column == 1)
		}
	}

	@Test
	func `a key that the decoder took from the document as it is, is not converted by the key strategy`() throws {
		struct Service: Decodable {
			var environment: [String: String]
		}

		struct Options: Decodable {
			var maxConnections: Int?
			var timeout: Int?
		}

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase

		// A dictionary key.
		let dictionaryError = try #require(throws: DecodingError.self) {
			try decoder.decode(Service.self, from: "environment: {\n\tPATH: '/bin'\n\tHOME: 1\n}")
		}

		guard case .typeMismatch(_, let dictionaryContext) = dictionaryError else {
			Issue.record("Expected a type mismatch, got \(dictionaryError)")
			return
		}

		#expect(dictionaryContext.debugDescription.hasSuffix("(line 3, column 2)"))

		// An unknown key, which would find another member if it were converted.
		decoder.rejectsUnknownKeys = true

		let unknownKeyError = try #require(throws: DecodingError.self) {
			try decoder.decode(Options.self, from: "timeout: 1\nmax-connections: 2\nTimeout: 3")
		}

		guard case .dataCorrupted(let unknownKeyContext) = unknownKeyError else {
			Issue.record("Expected an unknown key, got \(unknownKeyError)")
			return
		}

		#expect(unknownKeyContext.debugDescription.hasSuffix("(line 3, column 1)"))
	}

	@Test
	func `finds a member and an item at a key path`() throws {
		let document = try SOML.Document(parsing: "name: 'api'\nservers: [\n\t{host: 'a'}\n\t{host: 'b'}\n]\nlimits: {port: 80}")
		#expect(document.location(of: ["servers", 1, "host"]).description == "line 4, column 3")
		#expect(document.location(of: ["servers", 1]).description == "line 4, column 2")
		#expect(document.location(of: ["limits", "port"]).description == "line 6, column 10")
		#expect(try document.location(of: SOML.KeyPath(parsing: "servers[0].host")).description == "line 3, column 3")
	}

	@Test
	func `a key path index does not find a member and a key does not find an item`() throws {
		let document = try SOML.Document(parsing: "a: 1\nlist: [1, 2]\nobject: {'0': 1}")
		#expect(document.location(of: ["list", "0"]).description == "line 2, column 1")
		#expect(document.location(of: ["object", 0]).description == "line 3, column 1")
	}

	@Test
	func `a key path that goes past what exists finds the deepest member on the way`() throws {
		let document = try SOML.Document(parsing: "q: 1\na: {b: 1}")
		#expect(document.location(of: ["a", "c"]).description == "line 2, column 1")
	}

	@Test
	func `a key path and a coding path give the same location`() throws {
		let document = try SOML.Document(parsing: "a: {b: [1, {c: 2}]}\nd: 'x'")
		let codingPath: [any CodingKey] = [SOMLCodingKey(stringValue: "a"), SOMLCodingKey(stringValue: "b"), SOMLCodingKey(intValue: 1), SOMLCodingKey(stringValue: "c")]
		#expect(document.location(of: ["a", "b", 1, "c"]) == document.location(of: codingPath))
	}

	@Test
	func `an error at a key path has the location and a code frame`() throws {
		let document = try SOML.Document(parsing: "server: {\n\thost: 'a'\n\tport: 0\n}")
		let error = document.error("Port 0 is reserved", at: ["server", "port"])
		#expect(error.description == "Port 0 is reserved (line 3, column 2)")
		#expect(error.message == "Port 0 is reserved")
		#expect(error.codeFrame == "  1 | server: {\n  2 | \thost: 'a'\n> 3 | \tport: 0\n    | \t^")
	}

	@Test
	func `an error at a missing key path is at the closest member`() throws {
		let document = try SOML.Document(parsing: "name: 'api'\nserver: {\n\thost: 'a'\n}")
		#expect(document.error("The port is missing.", at: ["server", "port"]).location.description == "line 2, column 1")
	}

	/**
	Comparable requires that two locations that are not equal are ordered, also when they come from different documents and have the same offset.
	*/
	@Test
	func `locations with the same offset and different lines are ordered`() throws {
		let first = try SOML.Document(parsing: "x: 1\ny: 2").location(of: ["y"])
		let second = try SOML.Document(parsing: "x: { y: 1}").location(of: ["x", "y"])
		#expect(first.offset == second.offset)
		#expect(first != second)
		#expect((first < second) != (second < first))
		#expect([first, second].sorted() == [second, first])
	}
}

@Suite
struct SourceRangeTests {
	private let source = """
		# The service
		name: 'api' # The name
		port: 0x1F90
		server: {host: 'a', port: 80}
		description:
			'''
			Text
			'''
		tags: [
			'é',
			[1, 2],
		]
		"""

	private func text(_ range: Range<SOML.Location>?) -> String? {
		range.map { String(decoding: Array(source.utf8)[$0.lowerBound.offset..<$0.upperBound.offset], as: UTF8.self) }
	}

	private func offset(of substring: String) -> Int {
		source.utf8.distance(from: source.startIndex, to: source.range(of: substring)!.lowerBound)
	}

	@Test
	func `gives the range of a member and of its value`() throws {
		let document = try SOML.Document(parsing: source)

		#expect(text(document.range(of: ["name"])) == "name: 'api'")
		#expect(text(document.valueRange(of: ["name"])) == "'api'")
		#expect(text(document.valueRange(of: ["port"])) == "0x1F90")
		#expect(text(document.range(of: ["server", "port"])) == "port: 80")
		#expect(text(document.valueRange(of: ["server"])) == "{host: 'a', port: 80}")
		#expect(text(document.valueRange(of: ["description"])) == "'''\n\tText\n\t'''")
		#expect(text(document.range(of: ["tags", 1, 0])) == "1")
	}

	@Test
	func `gives the line and column of a range`() throws {
		let range = try #require(try SOML.Document(parsing: source).range(of: ["tags", 0]))
		#expect(range.lowerBound.line == 10)
		#expect(range.lowerBound.column == 2)
		#expect(range.upperBound.column == 5)
	}

	@Test
	func `gives nil for a path that is not in the document`() throws {
		let document = try SOML.Document(parsing: source)

		#expect(document.range(of: ["missing"]) == nil)
		#expect(document.range(of: ["tags", 2]) == nil)
		#expect(document.range(of: ["name", "inner"]) == nil)
		#expect(document.valueRange(of: ["tags", "key"]) == nil)
	}

	@Test
	func `gives the deepest member or item at an offset`() throws {
		let document = try SOML.Document(parsing: source)

		#expect(document.path(atOffset: offset(of: "api")) == ["name"])
		#expect(document.path(atOffset: offset(of: "name:")) == ["name"])
		#expect(document.path(atOffset: offset(of: " # The name")) == ["name"])
		#expect(document.path(atOffset: offset(of: "80}")) == ["server", "port"])
		#expect(document.path(atOffset: offset(of: "Text")) == ["description"])
		#expect(document.path(atOffset: offset(of: "2]")) == ["tags", 1, 1])
		#expect(document.path(atOffset: offset(of: " 2]")) == ["tags", 1])
	}

	@Test
	func `gives nil outside every member`() throws {
		let document = try SOML.Document(parsing: source)

		#expect(document.path(atOffset: 0) == nil)
		#expect(document.path(atOffset: offset(of: "The name")) == nil)
		#expect(document.path(atOffset: source.utf8.count + 10) == nil)
		#expect(document.path(atOffset: -1) == nil)
	}

	@Test
	func `gives the holder of white space and comments inside an object or an array`() throws {
		let source = "server: {a: 1, # Note\n\tb: 2}\nlist: [1, 2]\nempty: {}\n"
		let document = try SOML.Document(parsing: source)

		func offset(of substring: String) -> Int {
			source.utf8.distance(from: source.startIndex, to: source.range(of: substring)!.lowerBound)
		}

		#expect(document.path(atOffset: offset(of: "# Note")) == ["server"])
		#expect(document.path(atOffset: offset(of: ", 2]")) == ["list", 0])
		#expect(document.path(atOffset: offset(of: " 2]")) == ["list"])
		#expect(document.path(atOffset: offset(of: "]")) == ["list", 1])
		#expect(document.path(atOffset: offset(of: "{}") + 1) == ["empty"])
		#expect(document.path(atOffset: source.utf8.count) == nil)
	}

	@Test
	func `gives nil for the braces of a document with braces`() throws {
		let document = try SOML.Document(parsing: "{a: 1}")

		#expect(document.path(atOffset: 0) == nil)
		#expect(document.path(atOffset: 1) == ["a"])
		#expect(document.path(atOffset: 5) == ["a"])
		#expect(document.path(atOffset: 6) == nil)
	}

	@Test
	func `finds a quoted key with an escape`() throws {
		let source = #"'a b': 1"# + "\n" + #""c\u{41}": 2"#
		let document = try SOML.Document(parsing: source)

		#expect(text(in: source, document.range(of: ["cA"])) == #""c\u{41}": 2"#)
		#expect(text(in: source, document.valueRange(of: ["a b"])) == "1")
	}

	private func text(in source: String, _ range: Range<SOML.Location>?) -> String? {
		range.map { String(decoding: Array(source.utf8)[$0.lowerBound.offset..<$0.upperBound.offset], as: UTF8.self) }
	}

	@Test(arguments: ConformanceTests.validCases)
	func `every member and item of a valid case has a range that agrees with its value and with the path at its offsets`(_ name: String) throws {
		// The lookups walk the value and the syntax tree together, so this finds any document that the two read differently.
		let bytes = try Array(Data(contentsOf: ConformanceTests.root.appending(path: "valid/\(name).soml")))
		let document = try SOML.Document(parsing: bytes)

		// A list rather than recursion, because the suite has documents nested 100 levels deep.
		var pending: [(path: [SOML.KeyPath.Segment], value: SOML.Value, node: SyntaxTree.Node)] = [([], document.value, document.tree.body)]

		while let (segments, value, node) = pending.popLast() {
			if !segments.isEmpty {
				let path = SOML.KeyPath(segments)
				let range = try #require(document.range(of: path), "\(path)")
				let valueRange = try #require(document.valueRange(of: path), "\(path)")
				#expect(valueRange.lowerBound.offset == node.range.lowerBound, "\(path)")
				#expect(valueRange.upperBound == range.upperBound, "\(path)")
				#expect(range.lowerBound == SOML.Location(offset: range.lowerBound.offset, in: bytes), "\(path)")
				#expect(range.upperBound == SOML.Location(offset: range.upperBound.offset, in: bytes), "\(path)")
				#expect(document.location(of: path) == range.lowerBound, "\(path)")
				#expect(document.path(atOffset: range.lowerBound.offset) == path, "\(path)")
				#expect(document.path(atOffset: range.upperBound.offset) == path, "\(path)")

				switch node.kind {
				case .scalar, .blockString:
					let text = try #require(document.valueText(at: path))
					#expect(try SOML.Value(parsing: "value: " + text)["value"] == value, "\(path)")
				case .object, .array:
					break
				}
			}

			switch (value, node.kind) {
			case (.object(let object), .object(let members, _)):
				try #require(object.count == members.count, "\(segments)")

				for (member, syntax) in zip(object, members) {
					#expect(member.key.hasSameScalars(as: syntax.key), "\(segments)")
					pending.append((segments + [.key(member.key)], member.value, syntax.value))
				}
			case (.array(let array), .array(let items)):
				try #require(array.count == items.count, "\(segments)")

				for (index, item) in items.enumerated() {
					pending.append((segments + [.index(index)], array[index], item))
				}
			case (.object, _), (.array, _):
				Issue.record("The value and the syntax tree differ at \(segments)")
			default:
				break
			}
		}

		for offset in -1...(bytes.count + 1) {
			if let path = document.path(atOffset: offset) {
				let range = try #require(document.range(of: path), "\(path) at \(offset)")
				#expect(range.lowerBound.offset <= offset && offset <= range.upperBound.offset, "\(path) at \(offset)")
			}
		}
	}

	@Test
	func `gives the item of a document that is an array`() throws {
		let document = try SOML.Document(parsing: "[{a: 1}, 2]")

		#expect(document.path(atOffset: 2) == [0, "a"])
		#expect(document.path(atOffset: 9) == [1])
		#expect(document.path(atOffset: 0) == nil)
	}
}

@Suite
struct SourceTextTests {
	@Test
	func `value text preserves source spelling and excludes surrounding syntax`() throws {
		let source = "port: 0x1F90 # Default\nname: \"a\\tb\"\ntext: '''\nfirst\n\nlast\n'''\nobject: {enabled: true}\n"
		let document = try SOML.Document(parsing: source)
		#expect(document.valueText(at: ["port"]) == "0x1F90")
		#expect(document.valueText(at: ["name"]) == "\"a\\tb\"")
		#expect(document.valueText(at: ["text"]) == "'''\nfirst\n\nlast\n'''")
		#expect(document.valueText(at: ["object"]) == "{enabled: true}")
		#expect(document.valueText(at: ["object", "enabled"]) == "true")
	}

	@Test
	func `value text finds array items and rejects missing paths`() throws {
		let document = try SOML.Document(parsing: "[{values: [1_000, '😀']}, false]")
		#expect(document.valueText(at: [0, "values", 0]) == "1_000")
		#expect(document.valueText(at: [0, "values", 1]) == "'😀'")
		#expect(document.valueText(at: [1]) == "false")
		#expect(document.valueText(at: [2]) == nil)
		#expect(document.valueText(at: [0, "missing"]) == nil)
		#expect(document.valueText(at: [0, "values", 2]) == nil)
		#expect(document.valueText(at: [0, "values", "0"]) == nil)
		#expect(document.valueText(at: [1, "child"]) == nil)
		#expect(document.valueText(at: ["0"]) == nil)
	}

	@Test
	func `indexed source lookup keeps canonically equivalent keys distinct`() throws {
		// More than 32 members, so that the keys are found through the hash index of the object.
		let padding = (0..<40).map { "key\($0): \($0)" }.joined(separator: "\n")
		let source = padding + "\n'é': {name: 0xA}\n'e\u{301}': {name: 0xB}"
		let document = try SOML.Document(parsing: source)
		#expect(document.valueText(at: ["é", "name"]) == "0xA")
		#expect(document.valueText(at: ["e\u{301}", "name"]) == "0xB")
		#expect(document.valueRange(of: ["é", "name"])?.lowerBound.line == 41)
		#expect(document.range(of: ["e\u{301}"])?.lowerBound.line == 42)
	}

	@Test
	func `source text lookup scales across a large object`() throws {
		let source = (0..<5000).map { "entry\($0): {name: 'Service \($0)', port: \($0)}" }.joined(separator: "\n")
		let document = try SOML.Document(parsing: source)
		let start = ContinuousClock.now

		for index in 0..<5000 {
			#expect(document.valueText(at: [.key("entry\(index)"), "port"]) == String(index))
		}

		print("5,000 nested source text lookups: \(start.duration(to: .now))")
	}
}

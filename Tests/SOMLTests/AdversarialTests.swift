import Foundation
import Testing
@testable import SOML

/**
Large and hostile input. Each case must finish quickly, with a value or a `SOML.ParseError`, and never crash.
*/
@Suite(.timeLimit(.minutes(1)))
struct AdversarialTests {
	@Test
	func `a very long string`() throws {
		let content = String(repeating: "abcdefghij", count: 500_000)
		#expect(try parseScalar("'\(content)'") == .string(content))
		#expect(try parseScalar("\"\(content)\"") == .string(content))
	}

	@Test
	func `a string with many escapes`() throws {
		let source = "\"" + String(repeating: "\\n\\t\\u{1f600}\\\\", count: 50_000) + "\""
		let value = try #require(try parseScalar(source).stringValue)
		#expect(value.unicodeScalars.count == 200_000)
	}

	@Test
	func `a block string with many lines`() throws {
		let lines = (0..<50_000).map { "\tline \($0)" }.joined(separator: "\n")
		let value = try #require(try parse("a: '''\n\(lines)\n\t'''")["a"]?.stringValue)
		#expect(value.hasPrefix("line 0\nline 1\n"))
		#expect(value.hasSuffix("line 49999"))
	}

	@Test
	func `a block string with many blank lines at its edges`() throws {
		let blank = String(repeating: "\n", count: 100_000)
		#expect(try parse("a: '''\(blank)\tx\(blank)\t'''")["a"] == "x")
	}

	@Test
	func `an unterminated block string with many lines`() {
		expectRejected("a: '''\n" + String(repeating: "\tline\n", count: 100_000), "Unterminated block string")
	}

	@Test
	func `an error message stays short when the input it quotes is huge`() throws {
		let long = String(repeating: "k", count: 10_000)
		let digits = String(repeating: "1", count: 10_000)
		// One character, because every combining mark joins the “a”.
		let combining = "'a" + String(repeating: "\u{301}", count: 10_000) + "'"

		for (source, fragment) in [
			("a: \(long)", "A string value must be quoted"),
			("a: 1-\(digits)", "Invalid number"),
			("a: 1.\(digits).1", "Invalid number"),
			("a: 0\(digits)", "Leading zeros"),
			("\(long): 1\n\(long): 2", "Duplicate key"),
			("\(long).b: 1", "A key cannot contain “.” unless it is quoted"),
			("a.\(long): 1", "A key cannot contain “.” unless it is quoted"),
			("a.\(long.prefix(900)): 1", "A bare key cannot contain “.”. Quote it"),
			("\(long) b: 1", "cannot contain spaces"),
			("a:\n\(long): 1", "Expected a value, but found the key"),
			("'\(long)'", "A bare value is not a document"),
			("\(combining): 1\n\(combining): 2", "Duplicate key"),
			("\(combining).b: 2", "A key cannot contain “.” unless it is quoted"),
		] {
			let error = try #require(parseError(source))
			#expect(error.message.contains(fragment), "\(error.message.prefix(200))")
			#expect(error.message.utf8.count < 500, "\(error.message.prefix(200))")
		}
	}

	@Test
	func `a hint for a huge token is quick, and its message stays short`() throws {
		let long = String(repeating: "k", count: 1_000_000)
		let digits = String(repeating: "1", count: 1_000_000)

		for (source, fragment) in [
			// A long comment after a “:” whose value is missing.
			("a: #\(long)", "“#” starts a comment"),
			("a: #\(long)\nb: 1", "“#” starts a comment"),
			// A long number followed by a space and a unit.
			("a: 1.\(digits) s", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s"),
			("a: \(long) and more", "A string value must be quoted"),
			("a: 0\(digits) and more", "Leading zeros"),
			("a: 1\(String(repeating: ":11", count: 300_000))", "must be quoted"),
			("[\(long)]\nport: 1", "A string value must be quoted"),
			("[\(String(repeating: "a.", count: 500_000))a]\nport: 1", "A string value must be quoted"),
			("\(String(repeating: "k:", count: 500_000)): 1", "Expected a value, but found the key k"),
			("a: 2026-09-19 14:00:00.\(digits)Z", "not a space"),
			("a: [1\(String(repeating: ",000", count: 200_000))]", "A comma separates items"),
			// The whole of a long hexadecimal number decides its reason, as in the reference.
			("a: 0x\(digits)ff", "Hexadecimal digits are uppercase"),
			("a: 0x\(digits)f__f", "An underscore in a number must be between two digits"),
			("a: '''\n\(long)'''", "Its closing delimiter must start a line"),
			("a:\n  \(long): 1", "Indentation does not nest objects"),
		] {
			let error = try #require(parseError(source))
			#expect(error.message.contains(fragment), "\(error.message.prefix(200))")
			// A suggestion that holds keys shows up to 200 characters of each, as in the reference implementation.
			#expect(error.message.utf8.count < 700, "\(error.message.prefix(200))")
		}
	}

	@Test
	func `a very long number`() {
		let digits = String(repeating: "9", count: 1_000_000)
		expectRejected("a: \(digits)", "outside the 64-bit range")
		expectRejected("a: 1e\(digits)", "too large")
	}

	@Test
	func `a float with very many digits`() throws {
		let value = try parseScalar("0." + String(repeating: "3", count: 100_000))
		#expect(value == .float(1.0 / 3))
		#expect(try parseScalar("1" + String(repeating: "0", count: 300) + ".0") == .float(1e300))
	}

	@Test
	func `a long float still rounds correctly`() throws {
		let zeros = String(repeating: "0", count: 20_000)
		// 2^53 + 1 is halfway between two doubles, so it rounds to the even one, unless anything after it is nonzero.
		#expect(try parseScalar("9007199254740993.\(zeros)") == .float(9_007_199_254_740_992))
		#expect(try parseScalar("9007199254740993.\(zeros)1") == .float(9_007_199_254_740_994))
		#expect(try parseScalar("-9007199254740993.\(zeros)1") == .float(-9_007_199_254_740_994))
		#expect(try parseScalar("0.\(zeros)1e20005") == .float(1e4))
		#expect(try parseScalar("1\(zeros).0e-20000") == .float(1))
		expectRejected("a: 1\(zeros).0", "too large")
		expectRejected("a: 0.\(zeros)1", "too small")
		expectRejected("a: 1.0e-" + String(repeating: "9", count: 20_000), "too small")
		#expect(try parseScalar("0.\(zeros)e-" + String(repeating: "9", count: 20_000)) == .float(0))
	}

	@Test(arguments: [700, 753, 768, 769, 800, 1500])
	func `a halfway value with many trailing zeros rounds to even`(_ zeroCount: Int) throws {
		// `Double(String)` gets these wrong from 769 significant digits on.
		let zeros = String(repeating: "0", count: zeroCount)
		#expect(try parseScalar("9007199254740993.\(zeros)") == .float(9_007_199_254_740_992))
		#expect(try parseScalar("9007199254740995.\(zeros)") == .float(9_007_199_254_740_996))
		#expect(try parseScalar("9007199254740993.\(zeros)1") == .float(9_007_199_254_740_994))
		#expect(try parseScalar("9007199254740993\(zeros)e-\(zeroCount)") == .float(9_007_199_254_740_992))
	}

	@Test
	func `a large array`() throws {
		let source = "[" + String(repeating: "1,", count: 500_000) + "]"
		#expect(try parse(source).arrayValue?.count == 500_000)
	}

	@Test
	func `many empty containers`() throws {
		let source = "[" + String(repeating: "[], {}, ", count: 100_000) + "]"
		#expect(try parse(source).arrayValue?.count == 200_000)
	}

	@Test
	func `an object with many keys`() throws {
		let source = (0..<100_000).map { "k\($0): \($0)" }.joined(separator: "\n")
		let object = try #require(try parse(source).objectValue)
		#expect(object.count == 100_000)
		#expect(object["k77777"] == 77777)
	}

	@Test
	func `long combining sequences remain distinct keys and strings`() throws {
		// These sequences are canonically equivalent, but comparing their scalars does not need normalization.
		let first = "x" + String(repeating: "\u{315}", count: 128_000) + String(repeating: "\u{300}", count: 128_000)
		let second = "x" + String(repeating: "\u{300}", count: 128_000) + String(repeating: "\u{315}", count: 128_000)
		let object = try #require(try parse("'\(first)': 1\n'\(second)': 2").objectValue)
		#expect(object.count == 2)
		#expect(object[first] == 1)
		#expect(object[second] == 2)
		#expect(SOML.Value.string(first) != .string(second))
	}

	@Test
	func `a duplicate at the end of a large object`() {
		let source = (0..<100_000).map { "k\($0): \($0)" }.joined(separator: "\n") + "\nk0: 1"
		expectRejected(source, "Duplicate key k0")
	}

	@Test
	func `a very long comment`() throws {
		let comment = String(repeating: "x", count: 1_000_000)
		#expect(try parse("# \(comment)\na: 1") == ["a": 1])
		#expect(try parse("/* \(comment) */\na: 1") == ["a": 1])
	}

	@Test
	func `many comments`() throws {
		let source = String(repeating: "# comment\n/* block */\n", count: 50_000) + "a: 1"
		#expect(try parse(source) == ["a": 1])
	}

	@Test
	func `a long line with an error at the end reports the right column`() throws {
		let filler = String(repeating: "x", count: 100_000)
		let error = try #require(parseError("a: '\(filler)' 1"))
		#expect(error.location.line == 1)
		#expect(error.location.column == 100_007)
	}

	@Test
	func `many lines with an error at the end reports the right line`() throws {
		let source = String(repeating: "a: 1\n", count: 1) + (1..<100_000).map { "k\($0): 1\n" }.joined() + "bad"
		let error = try #require(parseError(source))
		#expect(error.location.line == 100_001)
	}

	@Test
	func `deep nesting repeated many times`() throws {
		let depth = Parser.maximumDepth
		let deep = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
		let source = "[" + Array(repeating: String(deep.dropFirst().dropLast()), count: 1000).joined(separator: ",") + "]"
		#expect(throws: Never.self) {
			try parse(source)
		}
	}

	struct Empty: Decodable {
		var value: Int?
	}

	@Test
	func `rejecting unknown keys takes linear time when a long key holds many objects`() throws {
		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true

		// The key and the number of objects grow together, so time that is the product of the two grows with the square of the size.
		func source(size: Int) -> String {
			String(repeating: "k", count: size) + ": [" + String(repeating: "{},", count: size) + "]"
		}

		let small = source(size: 1000)
		let large = source(size: 16_000)
		#expect(try decoder.decode([String: [Empty]].self, from: large).values.first?.count == 16_000)

		try expectLinearTime {
			_ = try decoder.decode([String: [Empty]].self, from: small)
		} large: {
			_ = try decoder.decode([String: [Empty]].self, from: large)
		}
	}

	struct Level: Decodable {
		var next: [Level]?
		var items: [Empty]?
	}

	@Test
	func `rejecting unknown keys takes about as long for objects nested deep as for shallow ones`() throws {
		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true

		// Every object is checked after the decode, so a copy of its coding path for each one would be close to a hundred keys per object at the depth limit.
		func source(depth: Int) -> String {
			String(repeating: "next: [{", count: depth) + "items: [" + String(repeating: "{},", count: 20_000) + "]" + String(repeating: "}]", count: depth)
		}

		let shallow = source(depth: 0)
		let deep = source(depth: (Parser.maximumDepth - 3) / 2)
		_ = try decoder.decode(Level.self, from: deep)

		try expectTimeRatio({ _ = try decoder.decode(Level.self, from: shallow) }, large: { _ = try decoder.decode(Level.self, from: deep) }, below: 1.5)
	}

	@Test
	func `random bytes never crash the parser`() {
		var generator = SeededGenerator(seed: 1)

		for _ in 0..<20_000 {
			let count = Int.random(in: 0..<64, using: &generator)
			let bytes = (0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) }
			_ = try? SOML.Value(parsing: bytes)
		}
	}

	@Test
	func `random punctuation never crashes the parser`() {
		var generator = SeededGenerator(seed: 2)
		let alphabet = Array("[]{}:,.'\"#/*-\\\n\t 0123abcexT_+".utf8)

		for _ in 0..<50_000 {
			let count = Int.random(in: 0..<48, using: &generator)
			let bytes = (0..<count).map { _ in alphabet.randomElement(using: &generator)! }
			_ = try? SOML.Value(parsing: bytes)
		}
	}
}

@Suite
struct DeepEncodingTests {
	struct NestedContainers: Encodable {
		let depth: Int

		func encode(to encoder: any Encoder) throws {
			var container = encoder.unkeyedContainer()

			for _ in 1..<depth {
				container = container.nestedUnkeyedContainer()
			}

			try container.encode(1)
		}
	}

	@Test(arguments: [Parser.maximumDepth + 2, 10_000])
	func `manually nested containers respect the depth limit`(depth: Int) throws {
		let value = NestedContainers(depth: depth)
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encodeToValue(value)
		}
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode(value)
		}
	}

	@Test
	func `manually nested containers up to the limit encode`() throws {
		let value = NestedContainers(depth: Parser.maximumDepth)
		let text = try SOML.Encoder().encodeToString(value)
		#expect(try SOML.Value(parsing: text) == SOML.Encoder().encodeToValue(value))
	}

	final class Node: Encodable {
		var next: Node?

		init(next: Node? = nil) {
			self.next = next
		}
	}

	@Test
	func `a deeply nested or cyclic value is an error, not a crash`() throws {
		var chain = Node()

		for _ in 0..<10_000 {
			chain = Node(next: chain)
		}

		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode(chain)
		}

		let cycle = Node()
		cycle.next = cycle
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode(cycle)
		}

		cycle.next = nil
	}

	@Test
	func `nesting up to the limit encodes`() throws {
		var chain = Node()

		for _ in 0..<(Parser.maximumDepth - 1) {
			chain = Node(next: chain)
		}

		let text = try SOML.Encoder().encodeToString(chain)
		#expect(throws: Never.self) {
			try SOML.Value(parsing: text)
		}
	}

	final class DecodableNode: Decodable {
		let next: DecodableNode?
	}

	@Test
	func `a recursive type decodes a document nested to the limit`() throws {
		// The deepest document a reader accepts must also decode, even though Codable uses more stack per level than the parser.
		// The brace-less top-level object is the first level.
		let depth = Parser.maximumDepth
		let source = String(repeating: "next: {", count: depth - 1) + "next: null" + String(repeating: "}", count: depth - 1)
		var node: DecodableNode? = try SOML.Decoder().decode(DecodableNode.self, from: source)
		var count = 0

		while let current = node {
			count += 1
			node = current.next
		}

		#expect(count == depth)
		expectRejected(String(repeating: "next: {", count: depth) + "next: null" + String(repeating: "}", count: depth), "The document is nested more than 100 levels deep")
	}

	@Test
	func `a deep array decodes as nested arrays`() throws {
		let depth = Parser.maximumDepth
		let source = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
		#expect(throws: Never.self) {
			try SOML.Decoder().decode(SOML.Value.self, from: source)
		}
	}

	@Test
	func `a huge number gives a short message`() throws {
		let error = try #require(scalarError(String(repeating: "9", count: 100_000)))
		#expect(error.message.count < 200)
	}
}

@Suite
struct ConcurrencyTests {
	struct Record: Codable, Equatable, Sendable {
		var id: Int
		var name: String
		var tags: [String]
		var at: Date
	}

	@Test
	func `one encoder and one decoder can be shared across tasks`() async throws {
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase

		try await withThrowingTaskGroup(of: Void.self) { group in
			for index in 0..<200 {
				group.addTask { [encoder, decoder] in
					let records = (0..<50).map { Record(id: index * 100 + $0, name: "record \($0)", tags: ["a", "b"], at: Date(timeIntervalSince1970: Double(index))) }
					let data = try encoder.encode(records)
					let decoded = try decoder.decode([Record].self, from: data)
					#expect(decoded == records)
				}
			}

			try await group.waitForAll()
		}
	}

	@Test(.enabled(if: isSpecAvailable))
	func `values are Sendable and can be parsed concurrently`() async throws {
		let source = try exampleBlock(startingWith: "/*\nEverything SOML can express")
		let expected = try parse(source)

		let values = try await withThrowingTaskGroup(of: SOML.Value.self) { group in
			for _ in 0..<100 {
				group.addTask {
					try SOML.Value(parsing: source)
				}
			}

			var values = [SOML.Value]()

			for try await value in group {
				values.append(value)
			}

			return values
		}

		#expect(values.count == 100)
		#expect(values.allSatisfy { $0 == expected })
	}
}

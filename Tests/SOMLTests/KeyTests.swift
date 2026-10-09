import Testing
@testable import SOML

@Suite
struct KeyTests {
	static let bareKeys = [
		"a",
		"name",
		"content-type",
		"x-forwarded-for",
		"_private",
		"__dunder__",
		"404",
		"-foo",
		"--flag",
		"2024-01-01",
		"7zip-bin",
		"a_b-c",
		"UPPER",
		"camelCase",
		"0x1F",
		"1e10",
		"-1",
		"-",
		"_",
		"true",
		"false",
		"null",
		"infinity",
		"-infinity",
		"nan",
		"inf",
	]

	@Test(arguments: bareKeys)
	func `a bare key is a string and is never coerced`(_ key: String) throws {
		let value = try parse("\(key): 1")
		#expect(value.objectValue?.keys == [key])
		#expect(value[key] == 1)
	}

	static let quotedKeys: [(String, String)] = [
		("'the name'", "the name"),
		("\"the name\"", "the name"),
		("'a.b'", "a.b"),
		("''", ""),
		("\"\"", ""),
		("'key: with colon'", "key: with colon"),
		("'#hash'", "#hash"),
		("'日本'", "日本"),
		("\"\\u{61}\"", "a"),
		("\"tab\\there\"", "tab\there"),
		("\"line\\nbreak\"", "line\nbreak"),
		("\"\\u{a}\"", "\n"),
		("'  padded  '", "  padded  "),
		(#"'C:\dir'"#, #"C:\dir"#),
		("\"it's\"", "it's"),
		("'{}'", "{}"),
	]

	@Test(arguments: quotedKeys)
	func `a quoted key`(_ source: String, _ key: String) throws {
		let value = try parse("\(source): 1")
		#expect(value.objectValue?.keys == [key])
	}

	@Test
	func `quoted keys work inside braces too`() throws {
		#expect(try parse("{'a b': 1, \"c.d\": 2}") == ["a b": 1, "c.d": 2])
	}

	static let collisions: [Rejection] = [
		Rejection("the same key twice", "a: 1\na: 2", "Duplicate key a"),
		Rejection("the same key twice with the same value", "a: 1\na: 1", "Duplicate key"),
		Rejection("the same key inside braces", "{a: 1, a: 2}", "Duplicate key"),
		Rejection("a bare key and a quoted key", "a: 1\n'a': 2", "Duplicate key"),
		Rejection("a bare key and a double-quoted key", "a: 1\n\"a\": 2", "Duplicate key"),
		Rejection("a bare key and an escaped key", "a: 1\n\"\\u{61}\": 2", "Duplicate key"),
		Rejection("the same quoted key with a dot twice", "'a.b': 1\n'a.b': 2", "Duplicate key \"a.b\""),
	]

	@Test(arguments: collisions)
	func `rejects a collision`(_ rejection: Rejection) {
		expectRejected(rejection.source, rejection.message)
	}

	@Test
	func `a quoted key with a dot is one key, which does not collide with a nested object`() throws {
		#expect(try parse("'a.b': 1\na: {b: 2}") == ["a.b": 1, "a": ["b": 2]])
	}

	@Test
	func `the collision error points at the second key`() throws {
		let error = try #require(parseError("a: 1\nb: 2\n  a: 3"))
		#expect(error.location.line == 3)
		#expect(error.location.column == 3)
	}

	@Test
	func `keys are compared by scalars, without normalisation`() throws {
		// U+00E9 and e + U+0301 are canonically equivalent, so Swift's `==` calls them equal. The spec says they are different keys.
		let value = try parse("'\u{E9}': 1\n'e\u{301}': 2")
		let object = try #require(value.objectValue)
		#expect(object.count == 2)
		#expect(object["\u{E9}"] == 1)
		#expect(object["e\u{301}"] == 2)
	}

	@Test
	func `keys that differ only in case are different keys`() throws {
		#expect(try parse("a: 1\nA: 2").objectValue?.count == 2)
	}

	@Test
	func `a dash and an underscore are different keys`() throws {
		#expect(try parse("transfer-encoding: 1\ntransfer_encoding: 2").objectValue?.count == 2)
	}

	static let invalidKeys: [Rejection] = [
		Rejection("a space in a bare key", "the name: 1", "A bare key cannot contain spaces. Quote it, as in 'the name'"),
		Rejection("a space before the colon", "a : 1", "Whitespace is not allowed between a key and its “:”"),
		Rejection("a tab before the colon", "a\t: 1", "Whitespace is not allowed"),
		Rejection("a space before the colon inside braces", "{a : 1}", "Whitespace is not allowed"),
		Rejection("a comment before the colon", "a# c\n: 1", "Expected “:” after the key, but found “#”"),
		Rejection("a block comment before the colon", "a/* c */: 1", "comment is not allowed"),
		Rejection("a missing colon", "a 1", "Expected “:” after the key, but found “1”"),
		Rejection("a missing colon at the end", "a", "Expected “:” after the key"),
		Rejection("an equals sign", "a = 1", "Expected “:” after the key, but found “=”"),
		Rejection("a non-ASCII bare key", "é: 1", "Expected a key"),
		Rejection("a dollar sign", "$key: 1", "Expected a key"),
		Rejection("an at sign", "@key: 1", "Expected a key"),
		Rejection("a key with a slash", "a/b: 1", "Expected “:” after the key, but found “/”"),
		Rejection("a key with a plus", "a+b: 1", "Expected “:” after the key, but found “+”. A key that contains characters other than letters, digits, “_”, and “-” must be quoted"),
		Rejection("a leading dot", ".a: 1", "Expected a key"),
		Rejection("a space before a dot", "a .b: 1", "Expected “:” after the key, but found “.”"),
		Rejection("a key with a line break", "'a\nb': 1", "Unterminated string"),
		Rejection("a block string key", "'''\na\n''': 1", "cannot be a key"),
		Rejection("no key before the colon", ": 1", "Expected a key"),
		Rejection("an object as a key", "{}: 1", "Unexpected “:” after the end of the document"),
	]

	@Test(arguments: invalidKeys)
	func `rejects an invalid key`(_ rejection: Rejection) {
		expectRejected(rejection.source, rejection.message)
	}

	@Test
	func `whitespace and line breaks are allowed after the colon`() throws {
		#expect(try parse("a:1") == ["a": 1])
		#expect(try parse("a:     1") == ["a": 1])
		#expect(try parse("a:\t1") == ["a": 1])
		#expect(try parse("a:\n\t1") == ["a": 1])
		#expect(try parse("a: # comment\n\t1") == ["a": 1])
		#expect(try parse("a: /* comment */ 1") == ["a": 1])
		#expect(try parse("{a:\n1}") == ["a": 1])
	}
}

@Suite
struct DotInKeyTests {
	// A key is never a path, so a “.” after a key is an error at the “.”, with the messages and the positions of the reference implementation.
	static let dotsInKeys: [PositionedRejection] = [
		PositionedRejection("a.b: 1", 1, 2, "A bare key cannot contain “.”. Quote it, as in 'a.b', or use braces to nest, as in a: {b: …}"),
		PositionedRejection("a.b.c: 1", 1, 2, "A bare key cannot contain “.”. Quote it, as in 'a.b.c', or use braces to nest, as in a: {b: {c: …}}"),
		PositionedRejection("example.com: 1", 1, 8, "A bare key cannot contain “.”. Quote it, as in 'example.com', or use braces to nest, as in example: {com: …}"),
		PositionedRejection("3.14: 'x'", 1, 2, "A bare key cannot contain “.”. Quote it, as in '3.14', or use braces to nest, as in 3: {14: …}"),
		PositionedRejection("1.5s: 1", 1, 2, "A bare key cannot contain “.”. Quote it, as in '1.5s', or use braces to nest, as in 1: {5s: …}"),
		PositionedRejection("a: 1\nb.c: 2", 2, 2, "A bare key cannot contain “.”. Quote it, as in 'b.c', or use braces to nest, as in b: {c: …}"),
		PositionedRejection("{a.b: 1}", 1, 3, "A bare key cannot contain “.”. Quote it, as in 'a.b', or use braces to nest, as in a: {b: …}"),
		PositionedRejection("x: {a.b: 1}", 1, 6, "A bare key cannot contain “.”. Quote it, as in 'a.b', or use braces to nest, as in a: {b: …}"),
		PositionedRejection("[{a.b: 1}]", 1, 4, "A bare key cannot contain “.”. Quote it, as in 'a.b', or use braces to nest, as in a: {b: …}"),
		PositionedRejection("'a'.b: 1", 1, 4, "A key cannot contain “.” unless it is quoted. Quote the whole key, or use braces to nest, as in a: {b: …}"),
		PositionedRejection("a.'b': 1", 1, 2, "A key cannot contain “.” unless it is quoted. Quote the whole key, or use braces to nest, as in a: {b: …}"),
		PositionedRejection("a.: 1", 1, 2, "A key cannot contain “.” unless it is quoted. Quote the whole key, or use braces to nest, as in a: {b: …}"),
		PositionedRejection("a..b: 1", 1, 2, "A key cannot contain “.” unless it is quoted. Quote the whole key, or use braces to nest, as in a: {b: …}"),
		PositionedRejection("a. b: 1", 1, 2, "A key cannot contain “.” unless it is quoted. Quote the whole key, or use braces to nest, as in a: {b: …}"),
		PositionedRejection("a.b 1", 1, 2, "A key cannot contain “.” unless it is quoted. Quote the whole key, or use braces to nest, as in a: {b: …}"),
		PositionedRejection(".a: 1", 1, 1, "Expected a key, but found “.”. A key that contains characters other than letters, digits, “_”, and “-” must be quoted, as in '.a'"),
		PositionedRejection(".env: 1", 1, 1, "Expected a key, but found “.”. A key that contains characters other than letters, digits, “_”, and “-” must be quoted, as in '.env'"),
		PositionedRejection("files: {.eslintrc.json: 1}", 1, 9, "Expected a key, but found “.”. A key that contains characters other than letters, digits, “_”, and “-” must be quoted, as in '.eslintrc.json'"),
	]

	@Test(arguments: dotsInKeys)
	func `a dot after a key is an error at the dot`(_ rejection: PositionedRejection) throws {
		let error = try #require(parseError(rejection.source))
		#expect(error.message == rejection.message)
		#expect(error.location.line == rejection.line)
		#expect(error.location.column == rejection.column)
	}

	@Test
	func `a very long key with dots is an error, not a crash`() {
		// The diagnosis does not scan the whole key, so it does not find the “:” and gives no suggestion.
		expectRejected(Array(repeating: "a", count: 100_000).joined(separator: ".") + ": 1", "A key cannot contain “.” unless it is quoted")
	}

	@Test
	func `a long key with dots is cut short in the suggestions`() throws {
		let key = Array(repeating: "a", count: 30).joined(separator: ".")
		let error = try #require(parseError(key + ": 1"))
		#expect(error.message.hasPrefix("A bare key cannot contain “.”. Quote it, as in '\(key.shortened())'"))
	}
}

@Suite
struct MissingColonTests {
	@Test
	func `a key at the end of a line is reported after its trailing spaces, as in the reference`() throws {
		let error = try #require(parseError("a: 1\nc: 2\nd \t\nx: 1"))
		#expect(error.message == "Expected “:” after the key, but found a line break")
		#expect(error.location.line == 3)
		#expect(error.location.column == 4)
	}

	// The positions are the ones the reference implementation reports.
	static let missingColons: [PositionedRejection] = [
		PositionedRejection("server localhost:8080", 1, 8, "Expected “:” after the key, but found “l”"),
		PositionedRejection("the name:1", 1, 5, "Expected “:” after the key, but found “n”"),
		PositionedRejection("a b:c d: 1", 1, 3, "Expected “:” after the key, but found “b”"),
		PositionedRejection("a b", 1, 3, "Expected “:” after the key, but found “b”"),
		PositionedRejection("the name: 1", 1, 1, "A bare key cannot contain spaces. Quote it, as in 'the name'"),
		PositionedRejection("the name:\n1", 1, 1, "A bare key cannot contain spaces. Quote it, as in 'the name'"),
		PositionedRejection("the name:\t1", 1, 1, "A bare key cannot contain spaces. Quote it, as in 'the name'"),
		PositionedRejection("a b:", 1, 1, "A bare key cannot contain spaces. Quote it, as in 'a b'"),
		PositionedRejection("server localhost: 8080", 1, 1, "A bare key cannot contain spaces. Quote it, as in 'server localhost'"),
		PositionedRejection("{the name: 1}", 1, 2, "A bare key cannot contain spaces. Quote it, as in 'the name'"),
	]

	@Test(arguments: missingColons)
	func `a key with a space is only reported as one when a colon that ends a key follows`(_ rejection: PositionedRejection) throws {
		let error = try #require(parseError(rejection.source))
		#expect(error.message.contains(rejection.message), "Message was: \(error.message)")
		#expect(error.location.line == rejection.line)
		#expect(error.location.column == rejection.column)
	}
}

/**
A document that must fail at a position, with a message that contains a fragment.
*/
struct PositionedRejection: CustomTestStringConvertible, Sendable {
	let source: String
	let line: Int
	let column: Int
	let message: String

	init(_ source: String, _ line: Int, _ column: Int, _ message: String) {
		self.source = source
		self.line = line
		self.column = column
		self.message = message
	}

	var testDescription: String {
		source.debugDescription
	}
}

@Suite
struct KeyWithColonTests {
	// A “:” that whitespace or the end follows ends the key, so the key is reported as one that must be quoted, at its start, as in the reference implementation.
	static let keysWithColons: [PositionedRejection] = [
		PositionedRejection("12:30: 'lunch'", 1, 1, "A key that contains “:” must be quoted, as in '12:30'"),
		PositionedRejection("{a:null: 1}", 1, 2, "A key that contains “:” must be quoted, as in 'a:null'"),
		PositionedRejection("a:b: 1", 1, 1, "A key that contains “:” must be quoted, as in 'a:b'"),
		PositionedRejection("a:b:\n1", 1, 1, "A key that contains “:” must be quoted, as in 'a:b'"),
		PositionedRejection("{2026-09-19T14:00:00Z: 1}", 1, 2, "A key that contains “:” must be quoted, as in '2026-09-19T14:00:00Z'"),
	]

	@Test(arguments: keysWithColons)
	func `a bare key with a colon in it that a colon ends is reported as a key that must be quoted`(_ rejection: PositionedRejection) throws {
		let error = try #require(parseError(rejection.source))
		#expect(error.message == rejection.message)
		#expect(error.location.line == rejection.line)
		#expect(error.location.column == rejection.column)
	}

	// Otherwise the rest after the “:” is read as the value, which is what is reported, as in the reference implementation.
	static let valuesAfterKeys: [PositionedRejection] = [
		PositionedRejection("a:b", 1, 3, "Unexpected “b”. A string value must be quoted, as in 'b'"),
		PositionedRejection("a:b:c", 1, 3, "Expected a value, but found the key b"),
		PositionedRejection("a:b:c:d", 1, 3, "Expected a value, but found the key b"),
		PositionedRejection("a: b:c: 1", 1, 4, "Unexpected “b”. A string value must be quoted, as in 'b:c: 1'"),
		PositionedRejection("'a':b: 1", 1, 5, "Expected a value, but found the key b"),
		PositionedRejection("a:'b': 1", 1, 6, "Unexpected “:” after a value"),
		PositionedRejection("a:1{: 2", 1, 4, "Unexpected “{” after a value"),
	]

	@Test(arguments: valuesAfterKeys)
	func `a bare key with a colon in it is reported at what follows its first colon`(_ rejection: PositionedRejection) throws {
		let error = try #require(parseError(rejection.source))
		#expect(error.message.contains(rejection.message), "Message was: \(error.message)")
		#expect(error.location.line == rejection.line)
		#expect(error.location.column == rejection.column)
	}

	@Test
	func `a valid value directly after the colon is still valid`() throws {
		#expect(try parse("a:1\nb:true\nc:2026-09-19T14:00:00Z\nd:1h") == ["a": 1, "b": true, "c": .instant(SOML.Instant("2026-09-19T14:00:00Z")!), "d": .duration(.seconds(3600))])
		#expect(try parse("{a:1, b:null}") == ["a": 1, "b": nil])
	}
}

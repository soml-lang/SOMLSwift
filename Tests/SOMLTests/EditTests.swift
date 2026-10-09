import Foundation
import Testing
@testable import SOML

/**
Sets the value written as `value` at the key path written as `path`, and returns the text.
*/
private func set(_ text: String, _ path: String, _ value: String) throws -> String {
	try SOML.Document(parsing: text).setting(SOML.Value(parsingValue: value), at: SOML.KeyPath(parsing: path)).text
}

/**
Removes the member at the key path written as `path`, and returns the text.
*/
private func remove(_ text: String, _ path: String) throws -> String {
	try SOML.Document(parsing: text).removing(at: SOML.KeyPath(parsing: path)).text
}

/**
Sets the value written as `valueText`, as typed, at the key path written as `path`, and returns the text.
*/
private func setText(_ text: String, _ path: String, _ valueText: String) throws -> String {
	try SOML.Document(parsing: text).setting(valueText: valueText, at: SOML.KeyPath(parsing: path)).text
}

/**
Renames the member at the key path written as `path`, and returns the text.
*/
private func rename(_ text: String, _ path: String, _ newKey: String) throws -> String {
	try SOML.Document(parsing: text).renamingKey(at: SOML.KeyPath(parsing: path), to: newKey).text
}

/**
Sets or removes the comment at the end of the line of the member or item at the key path written as `path`, and returns the text.
*/
private func comment(_ text: String, _ path: String, _ comment: String?) throws -> String {
	try SOML.Document(parsing: text).settingComment(comment, at: SOML.KeyPath(parsing: path)).text
}

/**
The message of the `SOML.EditError` that a change throws, or `nil` when it does not throw one.
*/
private func editError(_ change: () throws -> Void) -> String? {
	do {
		try change()
		return nil
	} catch let error as SOML.EditError {
		return error.message
	} catch {
		return nil
	}
}

/**
The message of the `SOML.EditError` that setting `value` at the key path written as `path` throws.
*/
private func setError(_ text: String, _ path: String, _ value: SOML.Value) -> String? {
	editError {
		_ = try SOML.Document(parsing: text).setting(value, at: SOML.KeyPath(parsing: path))
	}
}

/**
The message of the `SOML.EditError` that removing the member at the key path written as `path` throws.
*/
private func removeError(_ text: String, _ path: String) -> String? {
	editError {
		_ = try SOML.Document(parsing: text).removing(at: SOML.KeyPath(parsing: path))
	}
}

/**
The texts of a document's comments, in order.
*/
private func commentTexts(_ document: SOML.Document) -> [String] {
	document.tree.comments.map { String(decoding: document.tree.text[$0.range], as: UTF8.self) }
}

/**
The key path of every member of every object and every item of every array.
*/
private func keyPaths(_ value: SOML.Value, prefix: [SOML.KeyPath.Segment] = []) -> [[SOML.KeyPath.Segment]] {
	var paths = [[SOML.KeyPath.Segment]]()

	switch value {
	case .object(let object):
		for (key, child) in object {
			paths.append(prefix + [.key(key)])
			paths += keyPaths(child, prefix: prefix + [.key(key)])
		}
	case .array(let items):
		for (index, child) in items.enumerated() {
			paths.append(prefix + [.index(index)])
			paths += keyPaths(child, prefix: prefix + [.index(index)])
		}
	default:
		break
	}

	return paths
}

/**
A pseudo-random number generator with a seed, so that a failing case can be run again. It is SplitMix64.
*/
private struct SeededRandom: RandomNumberGenerator {
	var state: UInt64

	mutating func next() -> UInt64 {
		state &+= 0x9E37_79B9_7F4A_7C15
		var result = state
		result = (result ^ (result >> 30)) &* 0xBF58_476D_1CE4_E5B9
		result = (result ^ (result >> 27)) &* 0x94D0_49BB_1331_11EB
		return result ^ (result >> 31)
	}

	/**
	`true` with the given probability.
	*/
	mutating func chance(_ probability: Double) -> Bool {
		Double.random(in: 0..<1, using: &self) < probability
	}

	/**
	A key from a few that need different spellings: bare, quoted, empty, non-ASCII, with a dot, a quote, a line feed, or a control character, one that looks like a number or an index, and one that is canonically equivalent to another but has other scalars.
	*/
	mutating func key() -> String {
		["a", "b", "port", "the name", "x.y", "", "é", "e\u{301}", "key-2", "'", "1", "[0]", "a\nb", "\u{1B}"].randomElement(using: &self)!
	}

	/**
	A value nested at most `depth` levels deep.
	*/
	mutating func value(depth: Int) -> SOML.Value {
		switch Int.random(in: 0..<(depth > 0 ? 9 : 7), using: &self) {
		case 0:
			.int(Int64.random(in: -1000...1000, using: &self))
		case 1:
			.float(Double(Int.random(in: -100...100, using: &self)) / 8)
		case 2:
			.string(["text", "it's", "line\nbreak", "", "\"quoted\""].randomElement(using: &self)!)
		case 3:
			.bool(chance(0.5))
		case 4:
			.null
		case 5:
			.array([])
		case 6:
			.object([:])
		case 7:
			.array((0..<Int.random(in: 1...3, using: &self)).map { _ in value(depth: depth - 1) })
		default:
			.object(SOML.Object((0..<Int.random(in: 1...3, using: &self)).map { _ in (key(), value(depth: depth - 1)) }))
		}
	}

	/**
	A key path into `value`, through objects and arrays: to an existing member or item, or to a missing member or the end of an array, sometimes with more missing keys after it.
	*/
	mutating func keyPath(in value: SOML.Value) -> (segments: [SOML.KeyPath.Segment], exists: Bool) {
		var segments = [SOML.KeyPath.Segment]()
		var current = value

		while true {
			switch current {
			case .object(let object):
				if object.isEmpty || chance(0.2) {
					var key = self.key()

					while object[key] != nil {
						key += "z"
					}

					segments.append(.key(key))
					appendMissingKeys(to: &segments)
					return (segments, false)
				}

				let key = object.keys.randomElement(using: &self)!
				segments.append(.key(key))
				current = object[key]!
			case .array(let items):
				if items.isEmpty || chance(0.2) {
					segments.append(.index(items.count))
					appendMissingKeys(to: &segments)
					return (segments, false)
				}

				let index = Int.random(in: 0..<items.count, using: &self)
				segments.append(.index(index))
				current = items[index]
			default:
				return (segments, true)
			}

			guard
				current.objectValue != nil || current.arrayValue != nil,
				!chance(0.4)
			else {
				return (segments, true)
			}
		}
	}

	/**
	Adds up to two keys, sometimes none, for objects that do not exist yet.
	*/
	mutating func appendMissingKeys(to segments: inout [SOML.KeyPath.Segment]) {
		for _ in 0..<max(0, Int.random(in: -2...2, using: &self)) {
			segments.append(.key(key()))
		}
	}

	/**
	A comment text, or `nil` to remove the comment.
	*/
	mutating func comment() -> String? {
		[nil, "Note", "", "it's # odd", "Ünïcode", "/* not a block */"].randomElement(using: &self)!
	}

	/**
	A value as a person types it, which is often not canonical form.
	*/
	mutating func valueText() -> String {
		guard chance(0.5) else {
			return value(depth: 2).description
		}

		return ["0o644", "1h30m", "['a', 'b']", "{x: 1, 'y z': [true, null]}", "'''\n\tline\n\t'''", "''''\n'''\n''''", "\"\"\"\n  \\t x\n\n  \"\"\"", "-0.5", "\"it's\""].randomElement(using: &self)!
	}
}

/**
A change that the random edits make.
*/
private enum Change: CustomStringConvertible {
	case set(SOML.Value)
	case setText(String)
	case remove
	case rename(String)
	case comment(String?)

	/**
	The parts of the errors that a random change can meet without a bug: a result that is nested more than 100 levels deep, a key that exists, a comment where the next member follows on the line, and an array item, which has no key.
	*/
	static let expectedErrors = [
		"nested more than",
		"already exists",
		"something other than a comment follows it",
		"which has no key",
	]

	/**
	The document with the change made at `path`.
	*/
	func apply(to document: SOML.Document, at path: SOML.KeyPath) throws(SOML.EditError) -> SOML.Document {
		switch self {
		case .set(let value):
			try document.setting(value, at: path)
		case .setText(let valueText):
			try document.setting(valueText: valueText, at: path)
		case .remove:
			try document.removing(at: path)
		case .rename(let newKey):
			try document.renamingKey(at: path, to: newKey)
		case .comment(let comment):
			try document.settingComment(comment, at: path)
		}
	}

	/**
	The value after the change.
	*/
	func expectedValue(of value: SOML.Value, at path: ArraySlice<SOML.KeyPath.Segment>) throws -> SOML.Value {
		switch self {
		case .set(let newValue):
			value.setting(newValue, at: path)
		case .setText(let valueText):
			value.setting(try SOML.Value(parsingValue: valueText), at: path)
		case .remove:
			value.removing(at: path)
		case .rename(let newKey):
			value.renamingKey(at: path, to: newKey)
		case .comment:
			value
		}
	}

	var description: String {
		switch self {
		case .set(let value):
			"set to \(value)"
		case .setText(let valueText):
			"set to the text \(valueText.debugDescription)"
		case .remove:
			"removed"
		case .rename(let newKey):
			"renamed to \(newKey.debugDescription)"
		case .comment(let comment):
			"comment \(comment.debugDescription)"
		}
	}
}

@Suite
struct EditTests {
	@Test
	func `the example in the readme`() throws {
		let document = try SOML.Document(parsing: """
			# The edge service.
			name: 'api'
			port: 0x1F90 # The default.
			""")

		let edited = try document
			.setting(8080, at: SOML.KeyPath(["port"]))
			.setting(["a", "b"], at: SOML.KeyPath(parsing: "tls.hosts"))
			.removing(at: SOML.KeyPath(["name"]))

		#expect(edited.text == "# The edge service.\nport: 8080 # The default.\ntls: {\n\thosts: [\n\t\t'a'\n\t\t'b'\n\t]\n}")
		#expect(edited.value == ["port": 8080, "tls": ["hosts": ["a", "b"]]])
	}

	@Test
	func `the array example in the readme`() throws {
		let document = try SOML.Document(parsing: """
			servers: [
				{host: 'a'}, # Primary
				{host: 'b'},
			]
			mode: 420
			""")

		let edited = try document
			.setting("c", at: SOML.KeyPath(parsing: "servers[1].host"))
			.setting(["host": "d"], at: SOML.KeyPath(parsing: "servers[2]"))
			.removing(at: SOML.KeyPath(parsing: "servers[0]"))
			.setting(valueText: "0o644", at: SOML.KeyPath(["mode"]))
			.renamingKey(at: SOML.KeyPath(["mode"]), to: "permissions")
			.settingComment("Owner can write", at: SOML.KeyPath(["permissions"]))

		#expect(edited.text == "servers: [\n\t{host: 'c'},\n\t{\n\t\thost: 'd'\n\t}\n]\npermissions: 0o644 # Owner can write")
	}

	@Test
	func `the text is the source`() throws {
		let text = "# Head\na: 1 # One\n"
		#expect(try SOML.Document(parsing: text).text == text)
	}

	// MARK: Setting, from `soml set` in soml-cli

	@Test
	func `replaces a value and keeps the comments`() throws {
		#expect(try set("/* The edge service. */\nport: 0x1F90 # The default.\nname: 'a'\n", "port", "8080") == "/* The edge service. */\nport: 8080 # The default.\nname: 'a'\n")
		#expect(try set("server: {\n\thost: 'a', # Primary\n\tport: 1,\n}\n", "server.host", "'b'") == "server: {\n\thost: 'b', # Primary\n\tport: 1,\n}\n")
		#expect(try set("'server.host': 'a'\n", "'server.host'", "'b'") == "'server.host': 'b'\n")
		#expect(try set("a: {b: 1}\n", "a", "[1, 2]") == "a: [\n\t1\n\t2\n]\n")
	}

	@Test
	func `writes the value in canonical form`() throws {
		#expect(try set("a: 1\n", "mode", "0o644") == "a: 1\nmode: 420\n")
		#expect(try set("a: 1\n", "timeout", "90m") == "a: 1\ntimeout: 1h30m\n")
		#expect(try set("a: 0xFF\nb: 0b11 # Bits\n", "a", "255") == "a: 255\nb: 0b11 # Bits\n")
		#expect(try set("a: 1", "a", "1.0") == "a: 1.0")
		#expect(try set("a: 1", "a", "\"it's\"") == "a: \"it's\"")
		#expect(try set("a: 1", "a", "'''\n\tx\n\ty\n\t'''") == "a: \"x\\ny\"")
	}

	@Test
	func `keeps the order of the members of a new object`() throws {
		#expect(try set("a: 1\n", "server", "{port: 80, host: 'a'}") == "a: 1\nserver: {\n\tport: 80\n\thost: 'a'\n}\n")
	}

	@Test
	func `adds a member at the top level`() throws {
		#expect(try set("a: 1 # One\n# The end.\n", "b", "2") == "a: 1 # One\nb: 2\n# The end.\n")
		#expect(try set("a: 1", "b", "2") == "a: 1\nb: 2")
		#expect(try set("a: 1 /* x\ny */\n", "b", "2") == "a: 1 /* x\ny */\nb: 2\n")
		#expect(try set("a: 1\n", "'the name'", "2") == "a: 1\n'the name': 2\n")
		#expect(try set("x: 1\n", "'a.b'", "'y'") == "x: 1\n'a.b': 'y'\n")
	}

	@Test
	func `adds a member to a braced object`() throws {
		#expect(try set("server: {\n\thost: 'a',\n}\n", "server.port", "443") == "server: {\n\thost: 'a',\n\tport: 443\n}\n")
		#expect(try set("server: {\n\thost: 'a'\n}\n", "server.port", "443") == "server: {\n\thost: 'a'\n\tport: 443\n}\n")
		#expect(try set("server: {host: 'a'}\n", "server.port", "443") == "server: {host: 'a', port: 443}\n")
		#expect(try set("server: {host: 'a', }\n", "server.port", "443") == "server: {host: 'a', port: 443, }\n")
		#expect(try set("{\n\ta: 1,\n}\n", "b", "2") == "{\n\ta: 1,\n\tb: 2\n}\n")
		#expect(try set("{\n\ta: 1 # One\n}\n", "b", "2") == "{\n\ta: 1 # One\n\tb: 2\n}\n")
		#expect(try set("a: {\n\tb: 1, # One\n}\n", "a.c", "3") == "a: {\n\tb: 1, # One\n\tc: 3\n}\n")
		#expect(try set("a: 1 # One", "b", "2") == "a: 1 # One\nb: 2")
	}

	@Test
	func `adds a member to an empty object`() throws {
		#expect(try set("server: {}\n", "server.port", "443") == "server: {\n\tport: 443\n}\n")
		#expect(try set("server: { }\n", "server.port", "443") == "server: {\n\tport: 443\n}\n")
		#expect(try set("{}\n", "a", "1") == "{\n\ta: 1\n}\n")
		#expect(try set("{}", "a", "1") == "{\n\ta: 1\n}")
	}

	@Test
	func `keeps the comments of an empty object in place`() throws {
		#expect(try set("\tserver: { # Soon\n\t}\n", "server.port", "443") == "\tserver: { # Soon\n\t\tport: 443\n\t}\n")
		#expect(try set("server: {\n\t# Soon\n}\n", "server.port", "443") == "server: {\n\t# Soon\n\tport: 443\n}\n")
		#expect(try set("server: {/* Soon */\n}\n", "server.port", "443") == "server: {/* Soon */\n\tport: 443\n}\n")
		#expect(try set("server: {/* Soon */}\n", "server.port", "443") == "server: {/* Soon */ port: 443}\n")
		#expect(try set("a: { # None yet\n}", "a.b", "1") == "a: { # None yet\n\tb: 1\n}")
	}

	@Test
	func `indents a new member as the line where a block comment before it starts`() throws {
		#expect(try set("/* a\n \t b */x: 1\n", "y", "2") == "/* a\n \t b */x: 1\ny: 2\n")
		#expect(try set("s: {\n\t/* a\n  b */ x: 1,\n}\n", "s.y", "2") == "s: {\n\t/* a\n  b */ x: 1,\n\ty: 2\n}\n")
		#expect(try set("{\n\t/* a\n b */ x: 1,\n}\n", "x", "{a: 1}") == "{\n\t/* a\n b */ x: {\n\t\ta: 1\n\t},\n}\n")
	}

	@Test
	func `creates the missing objects with braces`() throws {
		#expect(try set("a: 1\n", "server.tls.port", "443") == "a: 1\nserver: {\n\ttls: {\n\t\tport: 443\n\t}\n}\n")
		#expect(try set("server: {\n\thost: 'a',\n}\n", "server.tls.port", "443") == "server: {\n\thost: 'a',\n\ttls: {\n\t\tport: 443\n\t}\n}\n")
		#expect(try set("a: {x: 1}", "a.y.z", "2") == "a: {x: 1, y: {z: 2}}")
		#expect(try setText("a: 1\n", "b.c", "'''\n\tx\n\t'''") == "a: 1\nb: {\n\tc:\n\t\t'''\n\t\tx\n\t\t'''\n}\n")
	}

	@Test
	func `indents a multi-line value to fit the line it goes on`() throws {
		#expect(try set("a: {\n\tb: 1,\n}\n", "a.b", "{c: [1]}") == "a: {\n\tb: {\n\t\tc: [\n\t\t\t1\n\t\t]\n\t},\n}\n")
		#expect(try set("a: {\n\tb: 1,\n}\n", "a.c", "[1]") == "a: {\n\tb: 1,\n\tc: [\n\t\t1\n\t]\n}\n")
		#expect(try set("a: {\n\tb: 1}", "a.c", "[1]") == "a: {\n\tb: 1, c: [\n\t\t1\n\t]}")
		#expect(try set("  a: {}\n", "a.b", "{c: 1}") == "  a: {\n  \tb: {\n  \t\tc: 1\n  \t}\n  }\n")
	}

	@Test
	func `moves a block string over as a whole`() throws {
		#expect(try set("s: '''\n\tx\n\t'''\n", "t", "1") == "s: '''\n\tx\n\t'''\nt: 1\n")
		#expect(try set("a: {b: '''\n\tx\n\t'''}", "a.c", "1") == "a: {b: '''\n\tx\n\t''', c: 1}")
	}

	@Test
	func `a new value for a block string on the line after its key goes on the key's line, as the formatter writes it`() throws {
		#expect(try set("a:\n\t'''\n\tx\n\t'''\nb: 1\n", "a", "2") == "a: 2\nb: 1\n")
		#expect(try set("a: {\n\tb:\n\t\t'''\n\t\tx\n\t\t'''\n}\n", "a.b", "{c: 1}") == "a: {\n\tb: {\n\t\tc: 1\n\t}\n}\n")
		#expect(try set("a: [\n\t'''\n\tx\n\t'''\n]\n", "a[0]", "2") == "a: [\n\t2\n]\n")

		// With a comment between, and for a new block string, the value stays on its own line.
		#expect(try set("a: # c\n\t'''\n\tx\n\t'''\n", "a", "2") == "a: # c\n\t2\n")
		#expect(try setText("a:\n\t'''\n\tx\n\t'''\n", "a", "'''\n\ty\n\t'''") == "a:\n\t'''\n\ty\n\t'''\n")
	}

	@Test
	func `refuses what has no single place`() {
		#expect(setError("a: 1\n", "a.b", 2) == "Cannot edit a.b, because a is not an object or an array")
		#expect(setError("a: [1]\n", "a.b", 2) == "Cannot edit a.b, because a is an array, so it needs an index, not a key")
		#expect(setError("a: {b: 1}\n", "a.b.c.d", 2) == "Cannot edit a.b.c.d, because a.b is not an object or an array")
		#expect(setError("[1]\n", "a", 2) == "Cannot edit a, because the document is an array, so it needs an index, not a key")
	}

	@Test
	func `refuses a value that SOML cannot represent`() {
		#expect(setError("a: 1\n", "b", .float(.nan)) == "Cannot set b, because the value cannot be written as SOML. NaN is not a SOML value")
		#expect(setError("a: 1\n", "b", ["c": "x\ry"]) == "Cannot set b, because the value cannot be written as SOML. A string cannot contain a carriage return, because SOML cannot represent one (at c)")
		#expect(editError { _ = try SOML.Document(parsing: "a: 1\n").setting(1, at: SOML.KeyPath(["x\ry"])) } == "Cannot set \"x\\ry\", because a key cannot contain a carriage return, which SOML cannot represent")

		var deep = SOML.Value.array([])

		for _ in 0..<Parser.maximumDepth {
			deep = .array([deep])
		}

		#expect(setError("a: 1\n", "b", deep)?.hasPrefix("Cannot set b, because the value cannot be written as SOML. The value is nested more than 100 levels deep") == true)
	}

	@Test
	func `refuses a result that is not valid`() throws {
		// The top-level object, `b`, and 99 arrays are 101 levels.
		let deep = String(repeating: "[", count: 99) + String(repeating: "]", count: 99)
		#expect(setError("a: 1\n", "b.c", try SOML.Value(parsingValue: deep))?.hasPrefix("The change would make the document invalid: ") == true)
	}

	@Test
	func `refuses a path longer than the nesting limit`() throws {
		let path = SOML.KeyPath(Array(repeating: "a", count: 10_000))
		#expect(editError { _ = try SOML.Document(parsing: "a: 1\n").setting(1, at: path) }?.hasSuffix("because the path is nested more than 100 levels deep, which is the most a SOML reader accepts") == true)
		#expect(try SOML.Document(parsing: "b: 1\n").removing(at: path).text == "b: 1\n")
	}

	@Test
	func `the nesting limit counts from where the value goes`() throws {
		let deep = String(repeating: "a: {", count: 98) + "a: 1" + String(repeating: "}", count: 98)
		let path = SOML.KeyPath(Array(repeating: "a", count: 99))
		#expect(try SOML.Document(parsing: deep).setting([:], at: path).text == String(repeating: "a: {", count: 98) + "a: {}" + String(repeating: "}", count: 98))
		#expect(editError { _ = try SOML.Document(parsing: deep).setting(["b": [:]], at: path) }?.hasPrefix("The change would make the document invalid: ") == true)
	}

	@Test
	func `error messages replace the characters that a terminal acts on`() {
		let message = editError {
			_ = try SOML.Document(parsing: "\"a\\u{1b}\\u{202e}\": 1\n").setting(1, at: SOML.KeyPath(["a\u{1B}\u{202E}", "b"]))
		}

		#expect(message == #"Cannot edit "a\u001b\u{202e}".b, because "a\u001b\u{202e}" is not an object or an array"#)
	}

	// MARK: Removing, from `edit()` in the JS reference implementation

	@Test
	func `a removed member takes its line, with the comment at its end`() throws {
		#expect(try remove("# Head\na: 1 # One\nb: 2\n", "a") == "# Head\nb: 2\n")
		#expect(try remove("a: 1\nb: 2\n", "a") == "b: 2\n")
		#expect(try remove("x: {\n\ta: 1,\n\tb: 2, # Two\n\tc: 3,\n}", "x.b") == "x: {\n\ta: 1,\n\tc: 3,\n}")
	}

	@Test
	func `a removed member that shares its line takes only itself and its comma, or the comma before it when it is last`() throws {
		#expect(try remove("x: {a: 1, b: 2, c: 3}", "x.b") == "x: {a: 1, c: 3}")
		#expect(try remove("x: {a: 1, b: 2}", "x.b") == "x: {a: 1}")
		#expect(try remove("x: {a: 1, b: 2, c: 3}", "x.c") == "x: {a: 1, b: 2}")
		#expect(try remove("{x: 1, a: {b: 1, c: 2}}", "a") == "{x: 1}")
		#expect(try remove("x: {a: 1, b: 2, c: 3,}", "x.c") == "x: {a: 1, b: 2,}")
		#expect(try remove("x: {\n\ta: 1, b: 2,\n}", "x.b") == "x: {\n\ta: 1,\n}")
		#expect(try remove("/* Note */ a: 1\nb: 2", "a") == "b: 2")
		#expect(try remove("# Note\na: 1\nb: 2", "a") == "# Note\nb: 2")
	}

	@Test
	func `the comments that a removed member owns go with it, as the formatter keeps them with it`() throws {
		#expect(try remove("{a: 1 /* a */ , b: 2}", "a") == "{b: 2}")
		#expect(try remove("{a: 1, b: 2 /* a */ /* b */, # c\n c: 3}", "b") == "{a: 1,\n c: 3}")
		#expect(try remove("{a: 1, /* a */ b: 2, c: 3}", "b") == "{a: 1, c: 3}")
		#expect(try remove("x: {a: 1, /* note */ b: 2}", "x.b") == "x: {a: 1}")
	}

	@Test
	func `a removed member at the end takes the comma before it also when it owns a comment`() throws {
		#expect(try remove("x: {b: 0, a: 1 /* c */}", "x.a") == "x: {b: 0}")
		#expect(try remove("{b: 0, a: 1 /* c */ /* d */}", "a") == "{b: 0}")
		#expect(try remove("{\n\tb: 0, a: 1 /* c */\n}", "a") == "{\n\tb: 0\n}")

		// With a comma after it, the comma before it stays.
		#expect(try remove("{b: 0, a: 1 /* c */,}", "a") == "{b: 0,}")
	}

	@Test
	func `a removed line does not leave two blank lines, or one directly inside a bracket`() throws {
		#expect(try remove("a: 1\n\nb: 2\n\nc: 3\n", "b") == "a: 1\n\nc: 3\n")
		#expect(try remove("a: 1\n\nb: 2\n", "b") == "a: 1\n")
		#expect(try remove("{\n\ta: 1,\n\n\tb: 2,\n}\n", "a") == "{\n\tb: 2,\n}\n")
		#expect(try remove("{\n\ta: 1,\n\n\tb: 2,\n}\n", "b") == "{\n\ta: 1,\n}\n")
		#expect(try remove("# Lead\n\na: 1\n\nb: 2\n", "a") == "# Lead\n\nb: 2\n")
	}

	@Test
	func `removing any member or item of a valid document leaves no line of only spaces and no new run of blank lines`() throws {
		/**
		Every key path in a value, to each member and item.
		*/
		func paths(in value: SOML.Value, at path: [SOML.KeyPath.Segment] = []) -> [SOML.KeyPath] {
			switch value {
			case .object(let object):
				object.flatMap { key, member in [SOML.KeyPath(path + [.key(key)])] + paths(in: member, at: path + [.key(key)]) }
			case .array(let items):
				items.indices.flatMap { [SOML.KeyPath(path + [.index($0)])] + paths(in: items[$0], at: path + [.index($0)]) }
			default:
				[]
			}
		}

		// Removing only takes text away, so these can only grow from what an edit leaves behind.
		func spaceOnlyLineCount(_ text: String) -> Int {
			text.split(separator: "\n", omittingEmptySubsequences: false).count { !$0.isEmpty && $0.allSatisfy { $0 == " " || $0 == "\t" } }
		}

		func blankLineRunCount(_ text: String) -> Int {
			text.ranges(of: "\n\n\n").count
		}

		var failures = [String]()

		for name in ConformanceTests.validCases {
			let text = try String(contentsOf: ConformanceTests.root.appending(path: "valid/\(name).soml"), encoding: .utf8)
			let document = try SOML.Document(parsing: text)

			for path in paths(in: document.value) {
				let result = try document.removing(at: path).text

				if spaceOnlyLineCount(result) > spaceOnlyLineCount(text) || blankLineRunCount(result) > blankLineRunCount(text) {
					failures.append("\(name) at \(path): \(String(reflecting: result))")
				}
			}
		}

		#expect(failures.isEmpty, "\(failures.prefix(10).joined(separator: "\n"))")
	}

	@Test
	func `a removed item on the line of a bracket does not leave a blank line directly inside the bracket`() throws {
		// Like the same item on a line of its own.
		#expect(try remove("[\n\t1,\n\n\t2\n]\n", "[1]") == "[\n\t1,\n]\n")
		#expect(try remove("[\n\t1,\n\n\t2]\n", "[1]") == "[\n\t1,\n]\n")
		#expect(try remove("a: {\n\tb: 1\n\n\tc: 2}\n", "a.c") == "a: {\n\tb: 1\n}\n")
		#expect(try remove("a: {\n\tb: 1\n\n\tc: 2 }\n", "a.c") == "a: {\n\tb: 1\n}\n")
		#expect(try remove("[\n\t1,\n\n\n\t2]\n", "[1]") == "[\n\t1,\n\n]\n")
		#expect(try remove("[\n\t1,\n\n\n\t2\n]\n", "[1]") == "[\n\t1,\n\n]\n")

		#expect(try remove("[\n\t1\n\n\t2\n]\n", "[0]") == "[\n\t2\n]\n")
		#expect(try remove("[1,\n\n\t2\n]\n", "[0]") == "[\n\t2\n]\n")
		#expect(try remove("[ 1\n\n\t2\n]\n", "[0]") == "[\n\t2\n]\n")
		#expect(try remove("a: {b: 1\n\n\tc: 2\n}\n", "a.b") == "a: {\n\tc: 2\n}\n")

		// A blank line that is not directly inside the bracket stays.
		#expect(try remove("[\n\t1,\n\n\t2,\n\t3]\n", "[2]") == "[\n\t1,\n\n\t2,\n]\n")
		#expect(try remove("[1,\n\t2,\n\n\t3\n]\n", "[0]") == "[\n\t2,\n\n\t3\n]\n")

				// A comment after the bracket is on the line that opens it, so the blank line after that line goes.
		#expect(try remove("[ # Ports\n\t1\n\n\t2]\n", "[1]") == "[ # Ports\n\t1\n]\n")
	}

	@Test
	func `removing every member of a braced object closes it up, unless a comment is left inside`() throws {
		#expect(try remove("{\n\ta: 1,\n}\n", "a") == "{}\n")
		#expect(try remove("x: {\n\ta: 1,\n}\n", "x.a") == "x: {}\n")
		#expect(try remove("x: {\n\t# Kept\n\ta: 1,\n}\n", "x.a") == "x: {\n\t# Kept\n}\n")
		// A comment after the opening brace on its line is left inside too.
		#expect(try remove("x: { # Kept\n\ta: 1\n}\n", "x.a") == "x: { # Kept\n}\n")
		#expect(try remove("x: { /* Kept */\n\ta: 1\n}\n", "x.a") == "x: { /* Kept */\n}\n")
		#expect(try remove("x: {\n\ta: 1\n\t/* Kept */ }\n", "x.a") == "x: {\n\t/* Kept */ }\n")
	}

	@Test
	func `removing the only member of a document without braces leaves an empty object`() throws {
		#expect(try remove("# Head\na: 1\n", "a") == "# Head\n{}\n")
		#expect(try remove("{a: 1}", "a") == "{}")
		// The new text keeps the comments that the member owned.
		#expect(try remove("a: 1 # note\n", "a") == "{} # note\n")
	}

	@Test
	func `a block string before a removed member`() throws {
		#expect(try remove("a: {\n\ts: '''\n\t\tx\n\t\t''',\n\tb: 2,\n}\n", "a.b") == "a: {\n\ts: '''\n\t\tx\n\t\t''',\n}\n")
		#expect(try remove("a: {\n\ts: '''\n\t\tx\n\t\t''',\n\tb: 2,\n}\n", "a.s") == "a: {\n\tb: 2,\n}\n")
	}

	@Test(arguments: [
		("a: 1 # One\n", "b"),
		("a: {x: 1}\n", "a.b.c"),
		("a: 1\n", "b.c[0]"),
		("a: 1\n", "b[0].c"),
		("a: {b: 1}\n", "a.c[0]"),
		("a: [1]\n", "a[1]"),
		("a: [1]\n", "a[5]"),
		("a: [1]\n", "a[5].x"),
		("a: [1]\n", "a[1][0]"),
		("a: []\n", "a[3]"),
		("[1, 2]\n", "[2]"),
	])
	func `removing what is not there changes nothing`(_ text: String, _ path: String) throws {
		#expect(try remove(text, path) == text)
		#expect(try comment(text, path, nil) == text)
	}

	@Test
	func `removing the same path twice is safe`() throws {
		let document = try SOML.Document(parsing: "a: 1\nb: [1, 2]\n")

		for path: SOML.KeyPath in [["a"], ["b", 1]] {
			let once = try document.removing(at: path)
			let twice = try once.removing(at: path)
			#expect(once.text != document.text)
			#expect(twice.text == once.text)
		}
	}

	@Test
	func `removing a value that does not exist changes nothing`() throws {
		let document = try SOML.Document(parsing: "a: [1, 2] # Items\nb: {c: 1}\n")
		let paths: [SOML.KeyPath] = [
			["x"],
			["x", "y"],
			["x", 0],
			["x", 0, "y"],
			["b", "x"],
			["b", "x", "y"],
			["b", "x", 0],
			["a", 2],
			["a", 5],
			["a", 2, "x"],
			["a", 5, 0],
		]

		for path in paths {
			#expect(try document.removing(at: path).text == document.text, "\(path)")
		}
	}

	@Test
	func `refuses to remove at a path that does not fit the document`() {
		#expect(removeError("a: 1\n", "a.b") == "Cannot edit a.b, because a is not an object or an array")
		#expect(removeError("a: 1\n", "a.b.c") == "Cannot edit a.b.c, because a is not an object or an array")
		#expect(removeError("[1]\n", "a") == "Cannot edit a, because the document is an array, so it needs an index, not a key")
		#expect(removeError("a: [1]\n", "a.x") == "Cannot edit a.x, because a is an array, so it needs an index, not a key")
		#expect(removeError("a: {b: 1}\n", "a[0]") == "Cannot edit a[0], because a is an object, so it needs a key, not an index")
		// The end of a long path stays, because it is usually the part that matters.
		let longPath = (0..<30).map { "k\($0)" }.joined(separator: ".")
		#expect(removeError("k0: 1\n", longPath)?.hasSuffix("k28.k29, because k0 is not an object or an array") == true)
	}

	@Test
	func `shortens a long key in an error`() {
		// A long key is shortened.
		let longKey = String(repeating: "k", count: 5000)
		#expect(editError { _ = try rename("a: 1\n", longKey, "b") } == "Cannot rename \(String(repeating: "k", count: 40))…, because it does not exist")
	}

	// MARK: Array items, from `edit()` in the JS reference implementation

	@Test
	func `replaces an array item and keeps the comments`() throws {
		#expect(try set("servers: [\n\t{host: 'a'}, # Primary\n\t{host: 'b'},\n]\n", "servers[0].host", "'c'") == "servers: [\n\t{host: 'c'}, # Primary\n\t{host: 'b'},\n]\n")
		#expect(try set("ports: [80, 443] # Open\n", "ports[1]", "8443") == "ports: [80, 8443] # Open\n")
		#expect(try set("[1, 2\n]", "[0]", "{a: 1}") == "[{\n\ta: 1\n}, 2\n]")
		#expect(try set("[1, 2]", "[0]", "{a: 1}") == "[{a: 1}, 2]")
		#expect(try set("a: [\n\t[1],\n]\n", "a[0][0]", "[2]") == "a: [\n\t[[2]],\n]\n")
		#expect(try set("a: [{b: 1}]\n", "a[0].c", "2") == "a: [{b: 1, c: 2}]\n")
	}

	@Test
	func `an index that is the number of items adds an item at the end`() throws {
		#expect(try set("[1, 2]", "[2]", "3") == "[1, 2, 3]")
		#expect(try set("a: [1, 2,]", "a[2]", "3") == "a: [1, 2, 3,]")
		#expect(try set("a: []", "a[0]", "'x'") == "a: [\n\t'x'\n]")
		#expect(try set("a: [\n\t1, # One\n]\n", "a[1]", "2") == "a: [\n\t1, # One\n\t2\n]\n")
		#expect(try set("a: [\n\t1 # One\n]\n", "a[1]", "2") == "a: [\n\t1 # One\n\t2\n]\n")
		#expect(try set("a: [ # None yet\n]\n", "a[0]", "1") == "a: [ # None yet\n\t1\n]\n")
		#expect(try set("[\n\t/* a\n b */ 's',\n]\n", "[1]", "1") == "[\n\t/* a\n b */ 's',\n\t1\n]\n")
		#expect(try set("a: [\n\t'''\n\t\tx\n\t\t''',\n]\n", "a[1]", "2") == "a: [\n\t'''\n\t\tx\n\t\t''',\n\t2\n]\n")
	}

	@Test
	func `a new item for a path that goes on with keys is an object`() throws {
		#expect(try set("a: [\n\t{b: 1},\n]\n", "a[1].b", "2") == "a: [\n\t{b: 1},\n\t{\n\t\tb: 2\n\t}\n]\n")
		#expect(try set("a: []\n", "a[0].b.c", "[1]") == "a: [\n\t{\n\t\tb: {\n\t\t\tc: [\n\t\t\t\t1\n\t\t\t]\n\t\t}\n\t}\n]\n")
		#expect(try set("a: [{b: 1}]\n", "a[1].b.c", "[1]") == "a: [{b: 1}, {b: {c: [1]}}]\n")
		#expect(try set("b: []", "b[0].c", "1") == "b: [\n\t{\n\t\tc: 1\n\t}\n]")
	}

	@Test
	func `a new item in an empty container gets its own line, unless the container is inside a container on one line`() throws {
		#expect(try set("a: [\n]", "a[0]", "'x'") == "a: [\n\t'x'\n]")
		#expect(try set("a: [ ]", "a[0]", "{b: [1]}") == "a: [\n\t{\n\t\tb: [\n\t\t\t1\n\t\t]\n\t}\n]")
		#expect(try set("deps: {}", "deps.a", "'1.0'") == "deps: {\n\ta: '1.0'\n}")
		#expect(try set("a: [1, []]", "a[1][0]", "2") == "a: [1, [2]]")
		#expect(try set("a: [1, [ ]]", "a[1][0]", "2") == "a: [1, [2]]")
		#expect(try set("a: [1, {}]", "a[1].b", "2") == "a: [1, {b: 2}]")
		#expect(try set("a: {b: 1, c: {}}", "a.c.d", "[1]") == "a: {b: 1, c: {d: [1]}}")
		#expect(try set("[/* None yet */]", "[0]", "1") == "[/* None yet */ 1]")
		#expect(try set("a: [/* x */ ]", "a[0]", "1") == "a: [/* x */ 1]")
	}

	@Test
	func `the comments that a removed item owns go with it, as the formatter keeps them with it`() throws {
		#expect(try remove("a: [1, /* note */ 2]", "a[1]") == "a: [1]")
		#expect(try remove("[1 /* a */ , 2]", "[0]") == "[2]")
		#expect(try remove("[1, 2 /* a */ /* b */, # c\n 3]", "[1]") == "[1,\n 3]")
		#expect(try remove("[1, /* a */ 2, 3]", "[1]") == "[1, 3]")
		#expect(try remove("x: [/* c */ 1, 2]", "x[0]") == "x: [2]")
		#expect(try remove("x: [/* c */ 1]", "x[0]") == "x: []")

		// A comment on a line of its own belongs to no item, so it stays.
		#expect(try remove("x: [\n\t1\n\t# About 2\n\t2\n]", "x[1]") == "x: [\n\t1\n\t# About 2\n]")
	}

	@Test
	func `a new item goes after the comments that the item before it owns`() throws {
		#expect(try set("x: [1, 2 /* About 2 */]", "x[2]", "3") == "x: [1, 2 /* About 2 */, 3]")
		#expect(try set("x: [\n\t1\n\t2 # About 2\n]", "x[2]", "3") == "x: [\n\t1\n\t2 # About 2\n\t3\n]")
		#expect(try set("x: [\n\t1\n\t# More later\n]", "x[1]", "2") == "x: [\n\t1\n\t2\n\t# More later\n]")

		// An item added to a container that holds only a comment owns that comment, so removing it again removes the comment too.
		#expect(try set("x: [/* None yet */]", "x[0]", "1") == "x: [/* None yet */ 1]")
		#expect(try remove("x: [/* None yet */ 1]", "x[0]") == "x: []")
	}

	@Test
	func `a new value in a container on one line is on one line`() throws {
		#expect(try set("x: {a: 1}", "x.b", "[2, 3]") == "x: {a: 1, b: [2, 3]}")
		#expect(try set("a: [1, 2]", "a[2]", "{b: 1, c: [true]}") == "a: [1, 2, {b: 1, c: [true]}]")
		#expect(try set("a: {x: 1}", "a.x", "[1, {y: 2}]") == "a: {x: [1, {y: 2}]}")
		#expect(try set("a: {x: [1, 2]}", "a.x[2]", "{b: [1, {c: 2}]}") == "a: {x: [1, 2, {b: [1, {c: 2}]}]}")
		#expect(try set("a: [1, {b: []}]", "a[1].b[0]", "{c: 1}") == "a: [1, {b: [{c: 1}]}]")
		#expect(try set("a: 1", "a", "{b: 1}") == "a: {\n\tb: 1\n}")
		#expect(try set("a: {x: 1}\n", "a", "{b: [1]}") == "a: {\n\tb: [\n\t\t1\n\t]\n}\n")
	}

	@Test
	func `the comma before a removed last item stays when a line break is between them`() throws {
		#expect(try remove("a: [\n\t1,\n\t2\n]", "a[1]") == "a: [\n\t1,\n]")
		#expect(try remove("a: [\n\t1\n\t2,\n]", "a[1]") == "a: [\n\t1\n]")
	}

	@Test
	func `a removed item takes its comma, and its line when nothing else is on it`() throws {
		#expect(try remove("x: [\n\t1,\n\t2, # Two\n\t3,\n]", "x[1]") == "x: [\n\t1,\n\t3,\n]")
		#expect(try remove("[\n\t1, /* a\n\t*/ /* b */\n\t2,\n]", "[0]") == "[\n\t2,\n]")
		#expect(try remove("x: [1, 2, 3]", "x[1]") == "x: [1, 3]")
		#expect(try remove("x: [1, 2]", "x[1]") == "x: [1]")
		#expect(try remove("x: [1 /* c */, 2]", "x[1]") == "x: [1 /* c */]")
		#expect(try remove("x: [1, 2 # c\n]", "x[1]") == "x: [1\n]")
		#expect(try remove("x: [1, 2 /* c */]", "x[1]") == "x: [1]")
		#expect(try remove("x: [1, 2, 3,]", "x[2]") == "x: [1, 2,]")
		#expect(try remove("x: [\n\t1, 2,\n]", "x[1]") == "x: [\n\t1,\n]")
		#expect(try remove("[\n\t1,\n\n\t2,\n]\n", "[0]") == "[\n\t2,\n]\n")
		#expect(try remove("a: [\n\t'''\n\t\tx\n\t\t''',\n\t2,\n]\n", "a[0]") == "a: [\n\t2,\n]\n")
		#expect(try remove("a: [{b: 1, c: 2}]\n", "a[0].b") == "a: [{c: 2}]\n")
	}

	@Test
	func `a removed item leaves a separator between its neighbors`() throws {
		#expect(try remove("x: [\n\t1\n\t2\n\t3\n]", "x[1]") == "x: [\n\t1\n\t3\n]")
		#expect(try remove("x: [1, 2\n\t3]", "x[1]") == "x: [1,\n\t3]")
		#expect(try remove("x: [1\n\t2, 3]", "x[1]") == "x: [1\n\t3]")
		#expect(try remove("x: [1, 2\n\t3]", "x[0]") == "x: [2\n\t3]")
		#expect(try remove("x: {a: 1 # One\n\tb: 2}", "x.a") == "x: {\n\tb: 2}")
	}

	@Test
	func `a new item on its own line gets no comma, and the commas of the others stay`() throws {
		#expect(try set("a: [\n\t1\n\t2\n]\n", "a[2]", "3") == "a: [\n\t1\n\t2\n\t3\n]\n")
		#expect(try set("a: [\n\t1,\n\t2,\n]\n", "a[2]", "3") == "a: [\n\t1,\n\t2,\n\t3\n]\n")
		#expect(try set("a: [1 /* x\n*/\n]\n", "a[1]", "2") == "a: [1 /* x\n*/\n2\n]\n")

		#expect(try set("a: [\n\t1, 2\n]", "a[2]", "9") == "a: [\n\t1, 2\n\t9\n]")
		#expect(try set("a: [1 # c\n]", "a[1]", "9") == "a: [1 # c\n9\n]")

		// The mixed style is valid, and the formatter removes the commas.
		#expect(try SOML.Document(parsing: set("a: [\n\t1,\n\t2,\n]\n", "a[2]", "3")).formatted() == "a: [\n\t1\n\t2\n\t3\n]\n")
	}

	@Test
	func `a new item goes on the line of the item before it when something follows that item there`() throws {
		#expect(try set("a: [\n\t1\n\t2]", "a[2]", "3") == "a: [\n\t1\n\t2, 3]")
		#expect(try set("a: [\n\t1\n\t2 /* c */]", "a[2]", "9") == "a: [\n\t1\n\t2 /* c */, 9]")
		#expect(try set("a: [1 /* x\n*/]", "a[1]", "9") == "a: [1 /* x\n*/, 9]")
		#expect(try set("a: [\n\t'''\n\tx\n\t''']", "a[1]", "9") == "a: [\n\t'''\n\tx\n\t''', 9]")
		#expect(try set("a: {\n\tb: 1\n\tc: 2}", "a.z", "9") == "a: {\n\tb: 1\n\tc: 2, z: 9}")
		#expect(try set("a: {b: 1 /* c */}", "a.z", "9") == "a: {b: 1 /* c */, z: 9}")
		#expect(try set("{\n\tb: 1}", "z", "9") == "{\n\tb: 1, z: 9}")
	}

	@Test
	func `removing every item of an array closes it up, unless a comment is left inside`() throws {
		#expect(try remove("a: [\n\t1,\n]\n", "a[0]") == "a: []\n")
		#expect(try remove("[\n\t1,\n]\n", "[0]") == "[]\n")
		#expect(try remove("a: [\n\t# Kept\n\t1,\n]\n", "a[0]") == "a: [\n\t# Kept\n]\n")
		#expect(try remove("a: [ # Kept\n\t1\n]\n", "a[0]") == "a: [ # Kept\n]\n")
		// A comment that the item owns goes with it.
		#expect(try remove("a: [\n\t1 # one\n]\n", "a[0]") == "a: []\n")
		#expect(try remove("a: [1 /* c */]\n", "a[0]") == "a: []\n")
	}

	@Test
	func `refuses a path that does not fit the arrays`() {
		#expect(setError("a: 1", "a[0]", 1) == "Cannot edit a[0], because a is not an object or an array")
		#expect(setError("a: {}", "a[0]", 1) == "Cannot edit a[0], because a is an object, so it needs a key, not an index")
		#expect(setError("a: 1", "[0]", 1) == "Cannot edit [0], because the document is an object, so it needs a key, not an index")
		#expect(removeError("a: {b: 1}", "a[0]") == "Cannot edit a[0], because a is an object, so it needs a key, not an index")
		#expect(setError("a: {b: {c: 1}}", "a.b[0].x", 1) == "Cannot edit a.b[0].x, because a.b is an object, so it needs a key, not an index")
		#expect(setError("a: [1]", "a[3]", 1) == "Cannot edit a[3], because the array at a has 1 item. Add an item at index 1")
		#expect(setError("[1, 2]", "[3]", 1) == "Cannot edit [3], because the document has 2 items. Add an item at index 2")
		#expect(setError("a: [1]", "a[1][0]", 1) == "Cannot edit a[1][0], because a[1] does not exist, so it has no index 0")
		#expect(setError("a: 1", "b[0]", 1) == "Cannot edit b[0], because b does not exist, so it has no index 0")
		#expect(setError("a: 1", "b.c[2].d", 1) == "Cannot edit b.c[2].d, because b.c does not exist, so it has no index 2")
		#expect(setError("a: [1]", "a[3].b", 1) == "Cannot edit a[3].b, because the array at a has 1 item. Add an item at index 1")
		#expect(removeError("a: [1]", "a[0].b") == "Cannot edit a[0].b, because a[0] is not an object or an array")
		#expect(editError { _ = try rename("a: [1]", "a[1].b", "c") } == "Cannot rename a[1].b, because the array at a has 1 item")
		#expect(editError { _ = try rename("a: [1]", "a[3]", "c") } == "Cannot rename a[3], because the array at a has 1 item")
		#expect(editError { _ = try rename("a: [1]", "a[1]", "c") } == "Cannot rename a[1], because the array at a has 1 item")
		#expect(editError { _ = try rename("a: []", "a[0]", "c") } == "Cannot rename a[0], because the array at a has 0 items")
		#expect(editError { _ = try comment("a: [1]", "a[1].b", "c") } == "Cannot set the comment of a[1].b, because the array at a has 1 item")
		#expect(editError { _ = try comment("a: [1]", "a[3]", "c") } == "Cannot set the comment of a[3], because the array at a has 1 item")
	}

	@Test(arguments: [
		("a: 1\n", "b[0][1]", "Cannot edit b[0][1], because b[0] does not exist, so it has no index 1"),
		("a: 1\n", "b[0].c[2]", "Cannot edit b[0].c[2], because b[0].c does not exist, so it has no index 2"),
		("a: 1\n", "b.c[0].d", "Cannot edit b.c[0].d, because b.c does not exist, so it has no index 0"),
		("a: 1\n", "b[0][1][2]", "Cannot edit b[0][1][2], because b[0][1] does not exist, so it has no index 2"),
		("a: [1]\n", "a[1][0][3]", "Cannot edit a[1][0][3], because a[1][0] does not exist, so it has no index 3"),
		("a: [1]\n", "a[1].x[0].y", "Cannot edit a[1].x[0].y, because a[1].x does not exist, so it has no index 0"),
		("a: {b: 1}\n", "a.c[0][1]", "Cannot edit a.c[0][1], because a.c[0] does not exist, so it has no index 1"),
		("[1]\n", "[1][0].k[5]", "Cannot edit [1][0].k[5], because [1][0].k does not exist, so it has no index 5"),
		("a: {}\n", "a.b[4].c[7]", "Cannot edit a.b[4].c[7], because a.b[4].c does not exist, so it has no index 7"),
	])
	func `names the last index of a new path, as the JS reference implementation does`(_ text: String, _ path: String, _ expected: String) {
		#expect(setError(text, path, 1) == expected)
	}

	// MARK: Setting a value as typed

	@Test
	func `writes the value text as typed`() throws {
		#expect(try setText("mode: 420 # Permissions\n", "mode", "0o644") == "mode: 0o644 # Permissions\n")
		#expect(try setText("a: 1\n", "timeout", "1h30m") == "a: 1\ntimeout: 1h30m\n")
		#expect(try setText("a: {\n\tb: 1,\n}\n", "a.labels", "['a', 'b']") == "a: {\n\tb: 1,\n\tlabels: ['a', 'b']\n}\n")
		#expect(try setText("a: [1, 2]\n", "a[1]", "0xFF") == "a: [1, 0xFF]\n")
		#expect(try setText("a: [1]\n", "a[1]", "{x: 1}") == "a: [1, {x: 1}]\n")
	}

	@Test
	func `does not indent a multi-line value text`() throws {
		#expect(try setText("a: {\n\tb: 1,\n}\n", "a.b", "{\nc: 1,\n}") == "a: {\n\tb: {\nc: 1,\n},\n}\n")
	}

	@Test(arguments: [
		// A member's block string begins on the line after its key, one level deeper, also for a new member and in a nested object.
		("a: 1\n", "a", "'''\nx\n'''", "a:\n\t'''\n\tx\n\t'''\n"),
		("a: 1 # c\n", "a", "'''\nx\n'''", "a:\n\t'''\n\tx\n\t''' # c\n"),
		("a: 1\n", "b", "'''\nx\n'''", "a: 1\nb:\n\t'''\n\tx\n\t'''\n"),
		("a: {\n\tb: 1\n}\n", "a.b", "'''\n\tline\n\t'''", "a: {\n\tb:\n\t\t'''\n\t\tline\n\t\t'''\n}\n"),
		("a: {\n\tb: 1\n}\n", "a.c", "\"\"\"\nx\n\"\"\"", "a: {\n\tb: 1\n\tc:\n\t\t\"\"\"\n\t\tx\n\t\t\"\"\"\n}\n"),
		("a:\n\t'''\n\tx\n\t'''\n", "a", "'''\ny\n'''", "a:\n\t'''\n\ty\n\t'''\n"),

		// Each content line keeps its indentation relative to the closing delimiter, and a blank line stays empty.
		("a: 1\n", "a", "'''\n  x\n\n    y\n  '''", "a:\n\t'''\n\tx\n\n\t  y\n\t'''\n"),

		// A comment between the key and the value stays, and the block string begins on the line after it.
		("a: # c\n\t1\n", "a", "'''\nx\n'''", "a: # c\n\t'''\n\tx\n\t'''\n"),
		("a: # c\n1\n", "a", "'''\nx\n'''", "a: # c\n\t'''\n\tx\n\t'''\n"),
		("a: /* c */ 1\n", "a", "'''\nx\n'''", "a: /* c */\n\t'''\n\tx\n\t'''\n"),

		// An array item keeps its own line and its indentation.
		("a: [\n\t1\n]\n", "a[0]", "'''\nx\n'''", "a: [\n\t'''\n\tx\n\t'''\n]\n"),
		("a: [\n\t1\n]\n", "a[1]", "'''\nx\n'''", "a: [\n\t1\n\t'''\n\tx\n\t'''\n]\n"),
		("a: [\n\t{\n\t\tb: 1\n\t}\n]\n", "a[1].c", "'''\nx\n'''", "a: [\n\t{\n\t\tb: 1\n\t}\n\t{\n\t\tc:\n\t\t\t'''\n\t\t\tx\n\t\t\t'''\n\t}\n]\n"),
	])
	func `writes a block string value text as the formatter does`(text: String, path: String, valueText: String, expected: String) throws {
		let result = try setText(text, path, valueText)
		#expect(result == expected)
		#expect(try SOML.Document(parsing: result).formatted() == result)
	}

	@Test
	func `writes value text next to a comment or a comma without spaces`() throws {
		#expect(try setText("a: 'x'# c\n", "a", "1") == "a: 1# c\n")
		#expect(try setText("a: 'x'/* c */\n", "a", "1") == "a: 1/* c */\n")
		#expect(try setText("a: ['x',/* c */'y']\n", "a[1]", "1") == "a: ['x',/* c */1]\n")
		#expect(try setText("a: ['x','y']\n", "a[2]", "1") == "a: ['x','y', 1]\n")
		#expect(try setText("{a: 1,}", "b", "2") == "{a: 1, b: 2,}")
	}

	@Test
	func `writes a block string value text in a container on one line`() throws {
		#expect(try setText("x: {a: 1, b: 2}\n", "x.a", "'''\nx\n'''") == "x: {a:\n\t'''\n\tx\n\t''', b: 2}\n")
		#expect(try setText("x: {a: 1}\n", "x.b", "'''\nx\n'''") == "x: {a: 1, b:\n\t'''\n\tx\n\t'''}\n")
		#expect(try setText("x: [1, 2]\n", "x[1]", "'''\nx\n'''") == "x: [1, '''\nx\n''']\n")
	}

	@Test
	func `refuses value text that is not one value`() {
		let message = editError {
			_ = try SOML.Document(parsing: "a: 1\n").setting(valueText: "1 2", at: SOML.KeyPath(["a"]))
		}

		#expect(message == "Cannot set a, because the value text is not one SOML value. Unexpected “ ” after the end of the value (at line 1, column 2 of the value text)")

		#expect(editError { _ = try SOML.Document(parsing: "a: 1\n").setting(valueText: "", at: SOML.KeyPath(["a"])) }?.hasPrefix("Cannot set a, because the value text is not one SOML value. Expected a value") == true)
		#expect(editError { _ = try SOML.Document(parsing: "a: 1\n").setting(valueText: "x: 1", at: SOML.KeyPath(["a"])) }?.contains("Expected a value, but found the key x") == true)
		#expect(editError { _ = try SOML.Document(parsing: "a: 1\n").setting(valueText: "1", at: SOML.KeyPath(["a", "b"])) } == "Cannot edit a.b, because a is not an object or an array")
	}

	// MARK: Renaming

	@Test
	func `renames a key and keeps the value and the comments`() throws {
		#expect(try rename("# Head\nhost: 'a' # Primary\nport: 1\n", "host", "hostname") == "# Head\nhostname: 'a' # Primary\nport: 1\n")
		#expect(try rename("server: {\n\thost: 'a', # Primary\n}\n", "server.host", "the name") == "server: {\n\t'the name': 'a', # Primary\n}\n")
		#expect(try rename("x: {a: 1, b: 2}", "x.a", "c") == "x: {c: 1, b: 2}")
		#expect(try rename("servers: [{host: 'a'}]\n", "servers[0].host", "name") == "servers: [{name: 'a'}]\n")
		#expect(try rename("a: {\n\tb: [\n\t\t1,\n\t],\n}\n", "a.b", "c") == "a: {\n\tc: [\n\t\t1,\n\t],\n}\n")
	}

	@Test
	func `renames a key that contains a dot`() throws {
		#expect(try rename("'a.b': 1\n", "'a.b'", "c") == "c: 1\n")
		#expect(try rename("a: {'x.y': 1}\n", "a.'x.y'", "x.z") == "a: {'x.z': 1}\n")
	}

	@Test
	func `writes the new key in canonical form`() throws {
		#expect(try rename("\"a\": 1\n", "a", "a") == "a: 1\n")
		#expect(try rename("a: 1\n", "a", "x.y") == "'x.y': 1\n")
		#expect(try rename("a: 1\n", "a", "") == "'': 1\n")
		#expect(try rename("a: 1\n", "a", "it's") == "\"it's\": 1\n")
	}

	@Test
	func `compares a new key with the others by Unicode scalars`() throws {
		// `é` and `e` with a combining accent are two keys, as the spec requires.
		#expect(editError { _ = try rename("'\u{E9}': 1\n'e\u{301}': 2\n", "'\u{E9}'", "e\u{301}") } == "Cannot rename \"\u{E9}\" to \"e\u{301}\", because \"e\u{301}\" already exists")
		#expect(try rename("a: 1\n'e\u{301}': 2\n", "a", "\u{E9}") == "'\u{E9}': 1\n'e\u{301}': 2\n")
		#expect(try rename("'\u{E9}': 1\n", "'\u{E9}'", "e\u{301}") == "'e\u{301}': 1\n")
	}

	@Test
	func `refuses a rename that has no single place`() {
		#expect(editError { _ = try rename("a: 1\nb: 2\n", "a", "b") } == "Cannot rename a to b, because b already exists")
		#expect(editError { _ = try rename("a: {b: 1, c: {d: 2}}\n", "a.b", "c") } == "Cannot rename a.b to c, because a.c already exists")
		#expect(editError { _ = try rename("a: [1]\n", "a[0]", "b") } == "Cannot rename a[0], because it is an array item, which has no key")
		#expect(editError { _ = try rename("a: 1\n", "b", "c") } == "Cannot rename b, because it does not exist")
		#expect(editError { _ = try rename("a: 1\n", "a.b", "c") } == "Cannot rename a.b, because a is not an object or an array")
		#expect(editError { _ = try rename("a: 1\n", "a", "x\ry") } == "Cannot rename a to \"x\\ry\", because a key cannot contain a carriage return, which SOML cannot represent")
	}

	// MARK: Comments

	@Test
	func `sets the comment at the end of a member's line`() throws {
		#expect(try comment("port: 80\nhost: 'a'\n", "port", "The default") == "port: 80 # The default\nhost: 'a'\n")
		#expect(try comment("port: 80 # Old\n", "port", "New") == "port: 80 # New\n")
		#expect(try comment("port: 80   \n", "port", "New") == "port: 80 # New\n")
		#expect(try comment("port: 80", "port", "") == "port: 80 #")
		#expect(try comment("server: {\n\thost: 'a',\n\tport: 1\n}\n", "server.host", "Primary") == "server: {\n\thost: 'a', # Primary\n\tport: 1\n}\n")
		#expect(try comment("a: {\n\tb: 1,\n}\n", "a", "Object") == "a: {\n\tb: 1,\n} # Object\n")
		#expect(try comment("a: 1 /* Kept */\n", "a", "New") == "a: 1 /* Kept */ # New\n")
		#expect(try comment("a: 1 /* Kept */ # Old\n", "a", "New") == "a: 1 /* Kept */ # New\n")
		#expect(try comment("'a.b': 1\n", "'a.b'", "Quoted") == "'a.b': 1 # Quoted\n")
	}

	@Test
	func `sets the comment at the end of an item's line`() throws {
		#expect(try comment("a: [\n\t1,\n\t2,\n]\n", "a[1]", "Two") == "a: [\n\t1,\n\t2, # Two\n]\n")
		#expect(try comment("a: [\n\t1, # One\n]\n", "a[0]", "Uno") == "a: [\n\t1, # Uno\n]\n")
		#expect(try comment("[\n\t{\n\t\ta: 1,\n\t},\n]\n", "[0].a", "A") == "[\n\t{\n\t\ta: 1, # A\n\t},\n]\n")
	}

	@Test
	func `removes the comment at the end of a member's line`() throws {
		#expect(try comment("port: 80 # The default\nhost: 'a'\n", "port", nil) == "port: 80\nhost: 'a'\n")
		#expect(try comment("a: [\n\t1, # One\n]\n", "a[0]", nil) == "a: [\n\t1,\n]\n")
		#expect(try comment("a: 1 /* Kept */ # Old\n", "a", nil) == "a: 1 /* Kept */\n")
		#expect(try comment("# Above\na: 1\n", "a", nil) == "# Above\na: 1\n")
	}

	@Test
	func `refuses a comment that has no single place`() {
		#expect(editError { _ = try comment("a: 1\n", "a", "two\nlines") } == "Cannot set the comment of a, because a comment cannot contain a line break")
		#expect(editError { _ = try comment("a: 1\n", "a", "x\ry") } == "Cannot set the comment of a, because a comment cannot contain a line break")
		#expect(editError { _ = try comment("x: {a: 1, b: 2}\n", "x.a", "One") } == "Cannot set the comment of x.a, because something other than a comment follows it on its line")
		#expect(editError { _ = try comment("x: {a: 1}\n", "x.a", nil) } == "Cannot remove the comment of x.a, because something other than a comment follows it on its line")
		#expect(editError { _ = try comment("a: 1\n", "b", "One") } == "Cannot set the comment of b, because it does not exist")
		#expect(editError { _ = try comment("a: [1]\n", "a[1]", "One") } == "Cannot set the comment of a[1], because the array at a has 1 item")
		#expect(editError { _ = try comment("a: 1\n", "a", "\u{1}") }?.hasPrefix("The change would make the document invalid: ") == true)
	}

	// MARK: Every valid document

	@Test(arguments: ConformanceTests.validCases)
	func `setting a member or item of a canonical document to its own value changes nothing`(_ name: String) throws {
		let url = URL(filePath: ConformanceTests.root.appending(path: "valid/\(name)").path(percentEncoded: false) + ".canonical.soml")
		let document = try SOML.Document(parsing: try String(contentsOf: url, encoding: .utf8))

		for path in keyPaths(document.value) {
			let value = try #require(document.value.value(at: path[...]))
			#expect(try document.setting(value, at: SOML.KeyPath(path)).text == document.text, "\(path)")
		}
	}

	@Test(arguments: ConformanceTests.validCases)
	func `a change to a valid document is the same change to its value, and keeps the other comments`(_ name: String) throws {
		let document = try SOML.Document(parsing: try Data(contentsOf: ConformanceTests.root.appending(path: "valid/\(name).soml")))
		let formatted = try SOML.Document(parsing: document.formatted())
		var random = SeededRandom(state: UInt64(truncatingIfNeeded: name.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }))

		for _ in 0..<12 {
			let (segments, exists) = random.keyPath(in: document.value)
			let path = SOML.KeyPath(segments)

			let change: Change = switch exists ? Int.random(in: 0..<5, using: &random) : Int.random(in: 0..<2, using: &random) {
			case 0:
				.set(random.value(depth: 2))
			case 1:
				.setText(random.valueText())
			case 2:
				.remove
			case 3:
				.rename(random.key())
			default:
				.comment(random.comment())
			}

			let label = "\(path): \(change)"
			let edited: SOML.Document

			do {
				edited = try change.apply(to: document, at: path)
			} catch where Change.expectedErrors.contains(where: error.message.contains) {
				// Any other error, such as an invalid result, is a bug.
				continue
			}

			#expect(try edited.value == change.expectedValue(of: document.value, at: segments[...]), "\(label)")

			let before = commentTexts(document)
			let after = commentTexts(edited)

			switch change {
			case .set, .setText, .remove:
				// Only the comments inside a replaced or removed value can go away.
				#expect(after.allSatisfy(before.contains), "\(label): a comment changed\n\(edited.text)")

				if !exists {
					#expect(after == before, "\(label): a comment was lost\n\(edited.text)")
				}
			case .rename:
				#expect(after == before, "\(label): a comment changed\n\(edited.text)")
			case .comment(let text):
				// Only the comment at the end of the line can change.
				#expect(before.filter { !after.contains($0) }.count <= 1, "\(label): a comment was lost\n\(edited.text)")

				if let text {
					#expect(after.contains(text.isEmpty ? "#" : "# \(text)"), "\(label): the comment is missing\n\(edited.text)")
				}
			}

			// Making the same change again changes nothing.
			switch change {
			case .set, .setText, .comment:
				#expect(try change.apply(to: edited, at: path).text == edited.text, "\(label)")
			case .remove, .rename:
				break
			}

			// An edit to a formatted document leaves it formatted, except for a value written as typed.
			if case .setText = change {
				continue
			}

			let editedFormatted = try change.apply(to: formatted, at: path)
			#expect(editedFormatted.formatted() == editedFormatted.text, "\(label): not formatted\n\(editedFormatted.text)")
		}
	}

	/**
	Documents in layouts that the formatter does not write, or with keys that need quoting, for the chained changes.
	*/
	static let unusualDocuments = [
		"'a b': 1\n\"\": 2\n'1': 3\n",
		"'é': 1\n'e\u{301}': 2\n",
		"[\n\t{a: 1},\n\t[2, 3],\n\t'''\n\tx\n\t''',\n]\n",
		"a: # Note\n\t1\n",
		"a: /* Note */ 1 # Line\nb: 2\n",
		"{a: 1, b: 2,}",
		"{a: 1,\n\tb: 2}",
		"a:\n\t'''\n\tx\n\t'''\nb: 2\n",
		"a: [\n\t'''\n\tx\n\t''', # Note\n\t2\n]\n",
		"a: \"\"\"\"\n\t\"\"\"\n\t\"\"\"\"\n",
		"# Top\n\na: 1 # One\n\n# Middle\nb: 2 # Two\n\n# End\n",
		"a: {/* Note */}\nb: [/* Note */]\n",
		"a: {\n\t# Only\n}\n",
		"a: 1 /* x\ny */\nb: 2\n",
		"{a: [1, 2] /* Note */, b: 3}\n",
		"\n\na: 1\n\n\nb: 2\n\n",
		"[1, [2, {a: 3}]]",
	]

	@Test(arguments: unusualDocuments)
	func `chained changes to a document in an unusual layout each give the expected value, and a set comment reads back`(_ text: String) throws {
		var random = SeededRandom(state: UInt64(truncatingIfNeeded: text.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }))

		for _ in 0..<4 {
			var document = try SOML.Document(parsing: text)
			var labels = [String]()

			for _ in 0..<30 {
				let (segments, exists) = random.keyPath(in: document.value)
				let path = SOML.KeyPath(segments)

				let change: Change = switch exists ? Int.random(in: 0..<5, using: &random) : Int.random(in: 0..<2, using: &random) {
				case 0:
					.set(random.value(depth: 2))
				case 1:
					.setText(random.valueText())
				case 2:
					.remove
				case 3:
					.rename(random.key())
				default:
					.comment(random.comment())
				}

				labels.append("\(path): \(change)")
				let edited: SOML.Document

				do {
					edited = try change.apply(to: document, at: path)
				} catch where Change.expectedErrors.contains(where: error.message.contains) {
					continue
				}

				#expect(try edited.value == change.expectedValue(of: document.value, at: segments[...]), "\(labels)")

				if
					case .comment(let comment) = change,
					exists
				{
					#expect(edited.comments(at: path)?.trailing == comment, "\(labels)\n\(edited.text)")
				}

				let formatted = try SOML.Document(parsing: edited.formatted())
				#expect(formatted.value == edited.value, "\(labels)\n\(edited.text)")
				#expect(formatted.formatted() == formatted.text, "\(labels)\n\(edited.text)")
				document = edited
			}
		}
	}

	// MARK: Nesting

	/*
	Swift Testing runs a test on a thread with a 512 KB stack, so these also check that editing fits there at the nesting limit in a debug build.
	*/

	@Test
	func `100 levels of nested objects`() throws {
		let depth = Parser.maximumDepth
		let text = "a: " + String(repeating: "{a: ", count: depth - 2) + "1" + String(repeating: "}", count: depth - 2)
		let path = SOML.KeyPath(Array(repeating: "a", count: depth - 1))
		let document = try SOML.Document(parsing: text)

		#expect(try document.setting([:], at: path).text == text.replacing("1", with: "{}"))
		#expect(try document.setting(["b": 1], at: path).value == document.value.setting(["b": 1], at: path.segments[...]))
		#expect(try document.removing(at: path).text == text.replacing("{a: 1}", with: "{}"))
		#expect(editError { _ = try document.setting(["b": [:]], at: path) }?.hasPrefix("The change would make the document invalid: ") == true)

		#expect(try document.setting(["b": 1], at: path).text == text.replacing("1", with: "{b: 1}"))

		let expanded = "a: " + String(repeating: "{\na: ", count: depth - 2) + "1" + String(repeating: "}", count: depth - 2)
		let formatted = try SOML.Document(parsing: SOML.Document(parsing: expanded).formatted())
		let edited = try formatted.setting(["b": 1], at: path)
		#expect(edited.formatted() == edited.text)
		#expect(try formatted.removing(at: path).value == document.value.removing(at: path.segments[...]))

		#expect(try document.renamingKey(at: path, to: "b").text == text.replacing("{a: 1}", with: "{b: 1}"))
		#expect(try formatted.settingComment("Deep", at: path).formatted() == formatted.settingComment("Deep", at: path).text)
	}

	@Test
	func `100 levels of nested arrays`() throws {
		let depth = Parser.maximumDepth
		let text = "a: " + String(repeating: "[", count: depth - 1) + "1" + String(repeating: "]", count: depth - 1)
		let indices = Array(repeating: SOML.KeyPath.Segment.index(0), count: depth - 1)
		let path = SOML.KeyPath(["a"] + indices)
		let document = try SOML.Document(parsing: text)

		#expect(try document.setting(2, at: path).text == text.replacing("[1]", with: "[2]"))
		#expect(try document.setting(valueText: "0x2", at: path).text == text.replacing("[1]", with: "[0x2]"))
		#expect(try document.setting(2, at: SOML.KeyPath(["a"] + indices.dropLast() + [1])).text == text.replacing("[1]", with: "[1, 2]"))
		#expect(try document.removing(at: path).text == text.replacing("[1]", with: "[]"))
		#expect(try document.settingComment("Deep", at: SOML.KeyPath(["a"])).text == text + " # Deep")
		#expect(editError { _ = try document.setting([1], at: path) }?.hasPrefix("The change would make the document invalid: ") == true)

		let expanded = "a: " + String(repeating: "[\n", count: depth - 1) + "1" + String(repeating: "]", count: depth - 1)
		let formatted = try SOML.Document(parsing: SOML.Document(parsing: expanded).formatted())
		let edited = try formatted.setting(2, at: SOML.KeyPath(["a"] + indices.dropLast() + [1]))
		#expect(edited.formatted() == edited.text)
		#expect(try formatted.removing(at: path).value == document.value.removing(at: path.segments[...]))
		#expect(try formatted.settingComment("Deep", at: path).formatted() == formatted.settingComment("Deep", at: path).text)
	}
}

@Suite
struct TypedEditTests {
	struct Config: Codable {
		var name: String
		var maxConnections: Int
		var labels: [String]
		var owner: String?
		var server: Server

		struct Server: Codable {
			var host: String
			var port: Int
		}
	}

	static let source = """
		# The edge service.
		name: 'api' # Shown in the dashboard
		max-connections: 0x10
		labels: [
			'prod', # Production
			'eu',
		]
		owner: 'ops'
		server: {
			host: 'a'
			port: 80
		}
		unknown: true # Not in the model
		"""

	static func update(_ change: (inout Config) throws -> Void) throws -> String {
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		return try SOML.Document(parsing: source).updating(as: Config.self, decoder: decoder, encoder: encoder, change).text
	}

	@Test
	func `no change keeps every byte`() throws {
		#expect(try Self.update { _ in } == Self.source)
	}

	@Test
	func `a changed value is replaced in place, and everything else stays`() throws {
		let text = try Self.update {
			$0.server.port = 8080
			$0.name = "edge"
		}

		#expect(text == Self.source.replacing("port: 80", with: "port: 8080").replacing("name: 'api'", with: "name: 'edge'"))
	}

	@Test
	func `an optional set to nil is removed, and a new member is added`() throws {
		struct Extended: Codable {
			var name: String
			var owner: String?
			var replicas: Int?
		}

		let document = try SOML.Document(parsing: "name: 'api'\nowner: 'ops' # Remove me\n")
		let edited = try document.updating(as: Extended.self) {
			$0.owner = nil
			$0.replicas = 3
		}

		#expect(edited.text == "name: 'api'\nreplicas: 3\n")
	}

	@Test
	func `array items change in place, are appended, and are removed from the end`() throws {
		#expect(try Self.update { $0.labels[1] = "us" } == Self.source.replacing("'eu',", with: "'us',"))
		#expect(try Self.update { $0.labels.append("staging") } == Self.source.replacing("'eu',\n", with: "'eu',\n\t'staging'\n"))
		#expect(try Self.update { $0.labels.removeLast() } == Self.source.replacing("\t'eu',\n", with: ""))
		#expect(try Self.update { $0.labels = [] }.contains("labels: []"))
	}

	@Test
	func `a document that is an array changes too`() throws {
		let document = try SOML.Document(parsing: "[1, 2, 3] # Numbers")
		#expect(try document.updating(as: [Int].self) { $0 = [1, 5] }.text == "[1, 5] # Numbers")
	}

	@Test
	func `a member that the model gives a default and the document leaves out is added whole when it changes`() throws {
		struct Defaulted: Codable {
			var name: String
			var hosts: [String]
			var debug: Bool

			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				self.name = try container.decode(String.self, forKey: .name)
				self.hosts = try container.decodeIfPresent([String].self, forKey: .hosts) ?? ["a", "b"]
				self.debug = try container.decodeIfPresent(Bool.self, forKey: .debug) ?? false
			}
		}

		let document = try SOML.Document(parsing: "name: 'api' # The service\n")
		#expect(try document.updating(as: Defaulted.self) { $0.name = "edge" }.text == "name: 'edge' # The service\n")
		#expect(try document.updating(as: Defaulted.self) { $0.hosts.append("c") }.value == ["name": "api", "hosts": ["a", "b", "c"]])
		#expect(try document.updating(as: Defaulted.self) { $0.hosts.removeLast() }.value == ["name": "api", "hosts": ["a"]])
	}

	@Test
	func `a member that the model gives a default and the document writes as null is set whole when it changes`() throws {
		struct Server: Codable, Equatable {
			var host = "localhost"
			var port = 80
		}

		struct Defaulted: Codable {
			var name: String
			var hosts: [String]
			var server: Server

			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				self.name = try container.decode(String.self, forKey: .name)
				self.hosts = try container.decodeIfPresent([String].self, forKey: .hosts) ?? []
				self.server = try container.decodeIfPresent(Server.self, forKey: .server) ?? Server()
			}
		}

		// `decodeIfPresent(_:forKey:)` reads null as absent, so the model has the default, which the document cannot be changed inside of.
		let document = try SOML.Document(parsing: "name: 'api'\nhosts: null # None yet\nserver: null\n")
		#expect(try document.updating(as: Defaulted.self) { $0.hosts.append("a") }.text == "name: 'api'\nhosts: [\n\t'a'\n] # None yet\nserver: null\n")
		#expect(try document.updating(as: Defaulted.self) { $0.server.port = 8080 }.value == ["name": "api", "hosts": nil, "server": ["host": "localhost", "port": 8080]])

		// Without a change, the null stays.
		#expect(try document.updating(as: Defaulted.self) { $0.name = "edge" }.text == "name: 'edge'\nhosts: null # None yet\nserver: null\n")
	}

	@Test
	func `a defaulted member written as null deeper in the document, with a key strategy, is set whole when it changes`() throws {
		struct TLS: Codable {
			var certificatePath = "a.pem"
			var minimumVersion = 2
		}

		struct Server: Codable {
			var hostName: String
			var tlsOptions: TLS

			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				self.hostName = try container.decode(String.self, forKey: .hostName)
				self.tlsOptions = try container.decodeIfPresent(TLS.self, forKey: .tlsOptions) ?? TLS()
			}
		}

		struct Config: Codable {
			var servers: [Server]
		}

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase

		let document = try SOML.Document(parsing: "servers: [\n\t{host-name: 'a', tls-options: null}, # First\n\t{host-name: 'b'},\n]\n")
		let edited = try document.updating(as: Config.self, decoder: decoder, encoder: encoder) {
			$0.servers[0].tlsOptions.minimumVersion = 3
			$0.servers[1].tlsOptions.minimumVersion = 3
		}

		let tls: SOML.Value = ["certificate-path": "a.pem", "minimum-version": 3]
		#expect(edited.value == ["servers": [["host-name": "a", "tls-options": tls], ["host-name": "b", "tls-options": tls]]])
		#expect(edited.comments(at: ["servers", 0])?.trailing == "First")
	}

	@Test
	func `what the change throws is passed on, and the document is unchanged`() throws {
		struct Stop: Error {}

		#expect(throws: Stop.self) {
			try Self.update { _ in
				throw Stop()
			}
		}
	}
}

@Suite
struct TypedEditTypesTests {
	enum Level: String, Codable {
		case info
		case debug
	}

	struct Model: Codable {
		var limits: [String: Int]
		var deployedAt: Date
		var timeout: Duration
		var level: Level
		var homepage: URL
		var ratio: Double
	}

	static let source = """
		limits: {cpu: 2, memory: 512} # Limits
		deployedAt: 2026-09-19T14:00:00Z
		timeout: 1h30m
		level: 'info'
		homepage: 'https://example.com'
		ratio: 0.5
		ignored: 'stays' # Not in the model
		"""

	@Test
	func `dictionaries, dates, durations, enums, and URLs change in place, and a member the model does not read stays`() throws {
		let edited = try SOML.Document(parsing: Self.source).updating(as: Model.self) {
			$0.limits["cpu"] = 4
			$0.limits["memory"] = nil
			$0.limits["disk"] = 10
			$0.deployedAt.addTimeInterval(60)
			$0.timeout = .seconds(90)
			$0.level = .debug
			$0.homepage = try #require(URL(string: "https://example.org"))
		}

		#expect(edited.text == """
			limits: {cpu: 4, disk: 10} # Limits
			deployedAt: 2026-09-19T14:01:00Z
			timeout: 1m30s
			level: 'debug'
			homepage: 'https://example.org'
			ratio: 0.5
			ignored: 'stays' # Not in the model
			""")
	}
}

@Suite
struct DecodingErrorLocationTests {
	struct Strict: Codable {
		var name: String
		var port: Int
		var tags: [String]
	}

	@Test(arguments: [
		("name: 'a'\ntags: []", "No member with the key port (line 1, column 1)"),
		("name: 'a'\nport: null\ntags: []", "Expected an int for Int, but found null (line 2, column 1)"),
		("name: 'a'\nport: 'x'\ntags: []", "Expected an int for Int, but found the string 'x' (line 2, column 1)"),
		("name: 'a'\nport: 1\ntags: [1]", "Expected a string for String, but found the int 1 (line 3, column 8)"),
		("name: 'a'\nport: 1\ntags: []\nextra: 1", "Unknown key extra, which Strict does not read (line 4, column 1)"),
	])
	func `every kind of decoding error says where its value is`(_ text: String, _ expected: String) throws {
		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true
		let error = try #require(throws: DecodingError.self) {
			try decoder.decode(Strict.self, from: text)
		}

		let description = switch error {
		case .keyNotFound(_, let context), .valueNotFound(_, let context), .typeMismatch(_, let context), .dataCorrupted(let context):
			context.debugDescription
		@unknown default:
			""
		}

		#expect(description == expected)
	}

	@Test
	func `decoding a value that was already parsed has no location, because there is no text`() throws {
		let error = try #require(throws: DecodingError.self) {
			try SOML.Decoder().decode(Strict.self, from: SOML.Value(parsing: "name: 'a'"))
		}

		guard case .keyNotFound(_, let context) = error else {
			Issue.record("Expected a missing key")
			return
		}

		#expect(context.debugDescription == "No member with the key port")
	}
}

@Suite
struct DifferenceTests {
	@Test
	func `lists the added, removed, and changed members and items`() throws {
		let old = try SOML.Value(parsing: "port: 80\nhosts: ['a', 'b']\ndebug: true")
		let new = try SOML.Value(parsing: "port: 8080\nhosts: ['a']\nname: 'api'")

		#expect(new.differences(from: old) == [
			.changed(from: 80, to: 8080, at: ["port"]),
			.removed("b", at: ["hosts", 1]),
			.removed(true, at: ["debug"]),
			.added("api", at: ["name"]),
		])
	}

	@Test
	func `compares objects by key and arrays by index`() throws {
		let old = try SOML.Value(parsing: "a: 1\nb: {c: [1, 2], d: 'x'}")
		let new = try SOML.Value(parsing: "b: {d: 'x', c: [1, 3, 4, 5]}\na: 1")

		#expect(new.differences(from: old) == [
			.changed(from: 2, to: 3, at: ["b", "c", 1]),
			.added(4, at: ["b", "c", 2]),
			.added(5, at: ["b", "c", 3]),
		])
	}

	@Test
	func `an object gives its changed and removed members in the old order, then its added members`() throws {
		let old = try SOML.Value(parsing: "a: {x: 1}\nb: 1")
		let new = try SOML.Value(parsing: "a: {x: 1, y: 2}\nc: 3")

		#expect(new.differences(from: old) == [
			.added(2, at: ["a", "y"]),
			.removed(1, at: ["b"]),
			.added(3, at: ["c"]),
		])
	}

	@Test
	func `removes items from the end`() throws {
		let old: SOML.Value = [1, 2, 3, 4]
		let new: SOML.Value = [0]

		#expect(new.differences(from: old) == [
			.changed(from: 1, to: 0, at: [0]),
			.removed(4, at: [3]),
			.removed(3, at: [2]),
			.removed(2, at: [1]),
		])
	}

	@Test
	func `a value that changes kind is changed as a whole`() throws {
		let old = try SOML.Value(parsing: "a: {b: 1}\nc: [1]")
		let new = try SOML.Value(parsing: "a: [1]\nc: {d: 1}")

		#expect(new.differences(from: old) == [
			.changed(from: ["b": 1], to: [1], at: ["a"]),
			.changed(from: [1], to: ["d": 1], at: ["c"]),
		])
	}

	@Test
	func `equal values have no differences`() throws {
		let value = try SOML.Value(parsing: "a: {b: [1, {c: 2}]}")
		#expect(value.differences(from: value) == [])
		#expect(SOML.Value.int(1).differences(from: .int(1)) == [])
	}

	@Test
	func `values that are not both objects or both arrays have no key path for their difference`() {
		#expect(SOML.Value.int(2).differences(from: .int(1)) == nil)
		#expect(SOML.Value.array([]).differences(from: .object([:])) == nil)
		#expect(SOML.Value.object([:]).differences(from: .string("a")) == nil)
	}

	@Test
	func `the path of a difference`() {
		#expect(SOML.Difference.added(1, at: ["a"]).path == ["a"])
		#expect(SOML.Difference.removed(1, at: ["a", 0]).path == ["a", 0])
		#expect(SOML.Difference.changed(from: 1, to: 2, at: ["b"]).path == ["b"])
	}

	@Test(arguments: ConformanceTests.validCases)
	func `applying the differences to a document gives the new value`(_ name: String) throws {
		let url = URL(filePath: ConformanceTests.root.appending(path: "valid/\(name)").path(percentEncoded: false) + ".canonical.soml")
		let document = try SOML.Document(parsing: try String(contentsOf: url, encoding: .utf8))
		let old = document.value
		var random = SeededRandom(state: UInt64(truncatingIfNeeded: name.utf8.reduce(7919) { ($0 &* 31) &+ Int($1) }))

		for _ in 0..<8 {
			var new = old

			for _ in 0..<Int.random(in: 1...4, using: &random) {
				let (segments, exists) = random.keyPath(in: new)

				new = exists && random.chance(0.4)
					? new.removing(at: segments[...])
					: new.setting(random.value(depth: 2), at: segments[...])
			}

			let differences = try #require(new.differences(from: old))
			#expect(differences.isEmpty == (new == old))
			var edited = document

			for difference in differences {
				switch difference {
				case .added(let value, let path):
					#expect(old.value(at: path.segments[...]) == nil, "\(difference)")
					#expect(new.value(at: path.segments[...]) == value, "\(difference)")
					edited = try edited.setting(value, at: path)
				case .removed(let value, let path):
					#expect(old.value(at: path.segments[...]) == value, "\(difference)")
					#expect(new.value(at: path.segments[...]) == nil, "\(difference)")
					edited = try edited.removing(at: path)
				case .changed(let oldValue, let newValue, let path):
					#expect(old.value(at: path.segments[...]) == oldValue, "\(difference)")
					#expect(new.value(at: path.segments[...]) == newValue, "\(difference)")
					edited = try edited.setting(newValue, at: path)
				}
			}

			#expect(edited.value == new, "\(differences)")
		}
	}
}

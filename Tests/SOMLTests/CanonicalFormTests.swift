import Foundation
import Testing
@testable import SOML

@Suite
struct CanonicalFormTests {
	@Test
	func `a flat document`() throws {
		#expect(try canonical("b: 2\na: 1\nc: 'x'") == "a: 1\nb: 2\nc: 'x'\n")
	}

	@Test
	func `the encoder keeps the source order of a parsed value unless it writes canonical form`() throws {
		let value = try SOML.Value(parsing: "name: 'api'\nserver: {port: 80, host: 'a'}\ndescription: 'x'")
		#expect(try SOML.Encoder().encodeToString(value) == "name: 'api'\nserver: {\n\tport: 80\n\thost: 'a'\n}\ndescription: 'x'\n")
		#expect(try canonical(value) == "description: 'x'\nname: 'api'\nserver: {\n\thost: 'a'\n\tport: 80\n}\n")
		#expect(try canonical(value) == value.canonicalDocument())
	}

	@Test
	func `nesting is written with braces, tabs, and trailing commas`() throws {
		let source = """
			server: {port: 8080, host: 'localhost'}
			labels: ['b', 'a']
			empty-object: {}
			empty-array: []
			matrix: [[1, 2], []]
			"""
		let expected = """
			empty-array: []
			empty-object: {}
			labels: [
				'b'
				'a'
			]
			matrix: [
				[
					1
					2
				]
				[]
			]
			server: {
				host: 'localhost'
				port: 8080
			}

			"""
		#expect(try canonical(source) == expected)
	}

	@Test
	func `a top-level array`() throws {
		#expect(try canonical("[1, {b: 2, a: 1}, []]") == "[\n\t1\n\t{\n\t\ta: 1\n\t\tb: 2\n\t}\n\t[]\n]\n")
	}

	@Test
	func `an empty top-level array and object`() throws {
		#expect(try canonical("[]") == "[]\n")
		#expect(try canonical("{}") == "{}\n")
		#expect(try canonical(SOML.Value.object([:])) == "{}\n")
	}

	@Test
	func `a braced top-level object loses its braces`() throws {
		#expect(try canonical("{a: 1}") == "a: 1\n")
	}

	@Test
	func `comments and block strings are gone`() throws {
		let source = """
			# comment
			a: {
				b: '''
					line one
					line two
					'''
			}
			"""
		#expect(try canonical(source) == "a: {\n\tb: \"line one\\nline two\"\n}\n")
	}

	@Test
	func `members are sorted by Unicode scalars`() throws {
		// Uppercase sorts before lowercase, digits before letters, and "-" (U+002D) before digits. "é" (U+00E9) sorts after "z", and "😀" after everything in the BMP.
		let source = "z: 1\na: 2\nB: 3\n'é': 4\n'😀': 5\n'\u{FFFD}': 6\n1: 7\n-: 8\n'': 9\n'a b': 10\na-b: 11\na_b: 12\naa: 13"
		let keys = try #require(parse(canonical(source)).objectValue?.keys)
		#expect(keys == ["", "-", "1", "B", "a", "a b", "a-b", "a_b", "aa", "z", "é", "\u{FFFD}", "😀"])
	}

	@Test
	func `sorting is by scalar values, not by canonical equivalence or locale`() throws {
		var object = SOML.Object()
		object["e\u{301}"] = 1
		object["\u{E9}"] = 2
		object["f"] = 3
		// "e" + U+0301 starts with "e", so it sorts before "f", and U+00E9 sorts after "f".
		#expect(try canonical(.object(object)) == "'e\u{301}': 1\nf: 3\n'\u{E9}': 2\n")
	}

	@Test
	func `canonical keys are bare when they can be`() throws {
		let cases: [(String, String)] = [
			("a", "a"),
			("content-type", "content-type"),
			("404", "404"),
			("_x", "_x"),
			("-", "-"),
			("true", "true"),
			("2024-01-01", "2024-01-01"),
			("", "''"),
			("a.b", "'a.b'"),
			("a b", "'a b'"),
			("é", "'é'"),
			("it's", "\"it's\""),
			("tab\there", "\"tab\\there\""),
			("a\nb", "\"a\\nb\""),
			("a:b", "'a:b'"),
			("#", "'#'"),
		]

		for (key, expected) in cases {
			#expect(try canonical(.object([key: 1])) == "\(expected): 1\n", "\(key)")
		}
	}

	static let strings: [(String, String)] = [
		("", "''"),
		("plain", "'plain'"),
		(#"C:\Users"#, #"'C:\Users'"#),
		(#"say "hi""#, #"'say "hi"'"#),
		("it's", #""it's""#),
		(#"it's "quoted""#, #""it's \"quoted\"""#),
		(#"it's C:\dir"#, #""it's C:\\dir""#),
		("line\nbreak", #""line\nbreak""#),
		("tab\there", #""tab\there""#),
		("\u{0}", #""\u{0}""#),
		("\u{1}", #""\u{1}""#),
		("\u{8}", #""\u{8}""#),
		("\u{B}", #""\u{b}""#),
		("\u{C}", #""\u{c}""#),
		("\u{1B}", #""\u{1b}""#),
		("\u{1F}", #""\u{1f}""#),
		("\u{7F}", #""\u{7f}""#),
		("\u{80}", "'\u{80}'"),
		("\u{A0}", "'\u{A0}'"),
		("\u{2028}", "'\u{2028}'"),
		("\u{2029}", "'\u{2029}'"),
		("\u{FEFF}", "'\u{FEFF}'"),
		("\u{FFFE}", "'\u{FFFE}'"),
		("日本語", "'日本語'"),
		("😀", "'😀'"),
		("e\u{301}", "'e\u{301}'"),
		("# not a comment", "'# not a comment'"),
		("'", #""'""#),
		("\\", #"'\'"#),
		("\"", #"'"'"#),
		("\\\n", #""\\\n""#),
	]

	@Test(arguments: strings)
	func `a string uses the literal form unless it must be escaped`(_ string: String, _ expected: String) throws {
		#expect(try canonical(.object(["a": .string(string)])) == "a: \(expected)\n")
		#expect(try parse(canonical(.object(["a": .string(string)])))["a"] == .string(string))
	}

	static let integers: [(Int64, String)] = [
		(0, "0"),
		(1, "1"),
		(-1, "-1"),
		(255, "255"),
		(1_000_000, "1000000"),
		(.max, "9223372036854775807"),
		(.min, "-9223372036854775808"),
	]

	@Test(arguments: integers)
	func `an int is plain decimal`(_ value: Int64, _ expected: String) throws {
		#expect(try canonical(.object(["a": .int(value)])) == "a: \(expected)\n")
	}

	@Test
	func `an int keeps no spelling from the source`() throws {
		#expect(try canonical("a: 0xFF\nb: 0o644\nc: 0b1010\nd: 1_000") == "a: 255\nb: 420\nc: 10\nd: 1000\n")
	}

	static let floats: [(Double, String)] = [
		(0, "0.0"),
		(-0.0, "0.0"),
		(1, "1.0"),
		(-1, "-1.0"),
		(0.5, "0.5"),
		(1.5, "1.5"),
		(30, "30.0"),
		(100, "100.0"),
		(0.1, "0.1"),
		(0.2, "0.2"),
		(0.30000000000000004, "0.30000000000000004"),
		(1.0 / 3, "0.3333333333333333"),
		(2.0 / 3, "0.6666666666666666"),
		(123.456, "123.456"),
		(1e20, "100000000000000000000.0"),
		(1e21, "1e21"),
		(1.5e21, "1.5e21"),
		(1e22, "1e22"),
		(123456789012345680000.0, "123456789012345680000.0"),
		(9007199254740992, "9007199254740992.0"),
		(1e16, "10000000000000000.0"),
		(1e-6, "0.000001"),
		(1.5e-6, "0.0000015"),
		(1e-7, "1e-7"),
		(1.5e-7, "1.5e-7"),
		(0.000123, "0.000123"),
		(1e-5, "0.00001"),
		(1e100, "1e100"),
		(1e-100, "1e-100"),
		(1.7976931348623157e308, "1.7976931348623157e308"),
		(-1.7976931348623157e308, "-1.7976931348623157e308"),
		(5e-324, "5e-324"),
		(2.2250738585072014e-308, "2.2250738585072014e-308"),
		(4.35, "4.35"),
		(0.1 + 0.2, "0.30000000000000004"),
		(.infinity, "infinity"),
		(-.infinity, "-infinity"),
	]

	@Test(arguments: floats)
	func `a float is the shortest decimal, laid out like ECMAScript`(_ value: Double, _ expected: String) throws {
		#expect(try canonical(.object(["a": .float(value)])) == "a: \(expected)\n")
		#expect(try parse("a: \(expected)")["a"] == .float(value))
	}

	@Test
	func `random floats read back exactly and are never longer than needed`() throws {
		var generator = SeededGenerator(seed: 3)

		for _ in 0..<20_000 {
			let value = Double(bitPattern: generator.next())

			guard value.isFinite else {
				continue
			}

			let text = SOML.Value.float(value).description
			let parsed = try #require(try parseScalar(text).floatValue, "\(text)")
			#expect(parsed == value, "\(value) was written as \(text)")
			#expect(text.contains(".") || text.contains("e"), "\(text) would read as an int")
			#expect(!text.contains("+"))
			#expect(!text.contains("e0"))
			#expect(!text.contains("e-0"))
			#expect(!text.hasSuffix("0e") && !text.contains("0e"), "\(text) has a trailing zero before its exponent")
		}
	}

	@Test
	func `random floats in a narrow range`() throws {
		var generator = SeededGenerator(seed: 5)

		for _ in 0..<10_000 {
			let value = Double.random(in: -1_000_000...1_000_000, using: &generator)
			let text = SOML.Value.float(value).description
			#expect(try parseScalar(text) == .float(value), "\(text)")
		}
	}

	@Test
	func `a float keeps no spelling from the source`() throws {
		#expect(try canonical("a: 1_000.5\nb: 15e-1\nc: 0.50\nd: 1e5") == "a: 1000.5\nb: 1.5\nc: 0.5\nd: 100000.0\n")
	}

	@Test
	func `an instant is UTC with no trailing zeros`() throws {
		#expect(try canonical("a: 2026-09-19T16:00:00.500+02:00") == "a: 2026-09-19T14:00:00.5Z\n")
		#expect(try canonical("a: 2026-09-19T14:00:00.000Z") == "a: 2026-09-19T14:00:00Z\n")
		#expect(try canonical("a: 2026-09-19T14:00:00.000000100Z") == "a: 2026-09-19T14:00:00.0000001Z\n")
	}

	@Test
	func `bools and null`() throws {
		#expect(try canonical("a: true\nb: false\nc: null") == "a: true\nb: false\nc: null\n")
	}

	@Test(.enabled(if: isSpecAvailable))
	func `the output ends with exactly one line feed and has no carriage return or BOM`() throws {
		let text = try canonical(exampleBlock(startingWith: "/*\nEverything SOML can express"))
		#expect(text.hasSuffix("\n"))
		#expect(!text.hasSuffix("\n\n"))
		#expect(!text.utf8.contains(0x0D))
		#expect(!text.hasPrefix("\u{FEFF}"))
		#expect(!text.contains("  "))
		#expect(!text.contains(" \n"))
	}

	@Test
	func `two spellings of one value give the same bytes`() throws {
		let first = """
			# A comment.
			server: {port: 0x1F90, host: "localhost"}
			at: 2026-09-19T16:00:00+02:00
			tags: ['a', 'b',]
			"""
		let second = "{tags: [\"a\", \"\\u{62}\"], at: 2026-09-19T14:00:00.000Z, server: {host: 'localhost', port: 8080}}"
		#expect(try canonical(first) == canonical(second))
	}

	@Test(.enabled(if: isSpecAvailable))
	func `canonical form is stable`() throws {
		let text = try canonical(exampleBlock(startingWith: "/*\nEverything SOML can express"))
		#expect(try canonical(text) == text)
	}

	@Test
	func `canonical form is the same for equal values with different member order`() throws {
		var first = SOML.Object()
		first["b"] = 1
		first["a"] = ["y": 1, "x": 2]
		var second = SOML.Object()
		second["a"] = ["x": 2, "y": 1]
		second["b"] = 1
		#expect(first == second)
		#expect(try canonical(.object(first)) == canonical(.object(second)))
	}

	@Test
	func `two values have the same canonical form exactly when they are equal`() throws {
		let pairs: [(SOML.Value, SOML.Value)] = [
			(["a": .float(0)], ["a": .float(-0.0)]),
			(["a": .duration(.seconds(60))], ["a": .duration(.milliseconds(60_000))]),
			(["a": .instant(try #require(SOML.Instant("2026-09-19T14:00:00+02:00")))], ["a": .instant(try #require(SOML.Instant("2026-09-19T12:00:00Z")))]),
			(["a": 1], ["a": .float(1)]),
			(["a": "\u{E9}"], ["a": "e\u{301}"]),
			(["\u{E9}": 1], ["e\u{301}": 1]),
			(["a": .float(.infinity)], ["a": .float(-.infinity)]),
			(["a": .float(5e-324)], ["a": .float(0)]),
			(["a": [:]], ["a": []]),
			(["a": nil], [:]),
			([], [:]),
		]

		for (first, second) in pairs {
			// The bytes, because `String` equality treats canonically equivalent text as equal.
			let isCanonicalFormEqual = try Array(canonical(first).utf8) == Array(canonical(second).utf8)
			#expect(isCanonicalFormEqual == (first == second), "\(first) and \(second)")
		}
	}

	@Test
	func `writing refuses what SOML cannot represent`() {
		let cases: [(SOML.Value, String)] = [
			(["a": "carriage\rreturn"], "carriage return"),
			(["a\rb": 1], "carriage return"),
			(["a": .float(.nan)], "NaN"),
			([["a": [.float(.nan)]]], "NaN"),
			("scalar", "must be an object or an array"),
			(1, "must be an object or an array"),
			(nil, "must be an object or an array"),
		]

		for (value, fragment) in cases {
			do {
				_ = try canonical(value)
				Issue.record("Expected an error for \(value)")
			} catch let error as EncodingError {
				guard case .invalidValue(_, let context) = error else {
					Issue.record("Unexpected \(error)")
					continue
				}

				#expect(context.debugDescription.contains(fragment), "\(context.debugDescription)")
			} catch {
				Issue.record("Unexpected \(error)")
			}
		}
	}

	@Test
	func `the error for an unrepresentable value has its coding path`() throws {
		do {
			_ = try canonical(["outer": ["list": [1, ["bad": "\r"]]]])
			Issue.record("Expected an error")
		} catch EncodingError.invalidValue(_, let context) {
			#expect(context.codingPath.map(\.stringValue) == ["outer", "list", "1", "bad"])
			#expect(context.codingPath[2].intValue == 1)
		}
	}

	@Test
	func `description is the text of a value, with members in their order`() throws {
		#expect(SOML.Value.string("it's").description == #""it's""#)
		#expect(SOML.Value.int(5).description == "5")
		#expect(SOML.Value.float(5).description == "5.0")
		#expect(SOML.Value.null.description == "null")
		#expect(SOML.Value.array([1, 2]).description == "[\n\t1\n\t2\n]")
		#expect(SOML.Value.object(["b": 1, "a": 2]).description == "{\n\tb: 1\n\ta: 2\n}")
		#expect((["b": 1, "a": 2] as SOML.Object).description == "{\n\tb: 1\n\ta: 2\n}")
		// A description never throws, even for a value SOML cannot represent.
		#expect(SOML.Value.float(.nan).description == "nan")
	}
}

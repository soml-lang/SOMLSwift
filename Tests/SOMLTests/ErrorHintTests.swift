import Foundation
import Testing
@testable import SOML

/**
The hints that errors give for common mistakes, as in the reference implementation, whose test/errors.ts has the same cases. Messages match the reference implementation's reasons except for native Unicode character names, and each error is at the line and column that the reference reports.
*/
@Suite
struct ErrorHintTests {
	@Test(arguments: [
		("\u{2061}", "U+2061 (FUNCTION APPLICATION)"),
		("\u{0085}", "U+0085 (only space, tab, and line feed are whitespace)"),
		("\u{00A0}", "U+00A0 (NO-BREAK SPACE; only space, tab, and line feed are whitespace)"),
		("\u{200B}", "U+200B (ZERO WIDTH SPACE; only space, tab, and line feed are whitespace)"),
		("\u{FEFF}", "U+FEFF (ZERO WIDTH NO-BREAK SPACE; only space, tab, and line feed are whitespace)"),
		("\u{E000}", "U+E000"),
		("\u{0378}", "U+0378"),
		("$", "“$”")
	])
	func `unexpected characters use native names without hiding whitespace guidance`(_ character: String, _ description: String) {
		#expect(parseError("{}" + character)?.message == "Unexpected \(description) after the end of the document")
	}

	static let hints: [(source: String, message: String)] = [
		("a: 512 MiB", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s, and anything else, such as a size, as a string, as in '512 MiB'"),
		("a: 10 seconds", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s, and anything else, such as a size, as a string, as in '10 seconds'"),
		("a: 100 ms", "A unit cannot follow a number after a space. Write a duration without the space, as in 100ms, and anything else, such as a size, as a string, as in '100 ms'"),
		("a: 10 m", "A unit cannot follow a number after a space. Write a duration without the space, as in 10m, and anything else, such as a size, as a string, as in '10 m'"),
		("a: 1.5 h # note", "A unit cannot follow a number after a space. Write a duration without the space, as in 1.5h, and anything else, such as a size, as a string, as in '1.5 h'"),
		("a: [100 ms]", "A unit cannot follow a number after a space. Write a duration without the space, as in 100ms, and anything else, such as a size, as a string, as in '100 ms'"),
		("a: {b: 100 ms}", "A unit cannot follow a number after a space. Write a duration without the space, as in 100ms, and anything else, such as a size, as a string, as in '100 ms'"),
		("a: [1 true]", "Expected “,”, a line break, or “]” after an array item, but found “t”"),
		("a: 5 and more", "Expected a line break before the next entry, but found “a”"),
		("a: 'x' MiB", "Expected a line break before the next entry, but found “M”"),
		("// note\na: 1", "Expected a key, but found “/”. A comment starts with “#”"),
		("a: 1 // note", "Expected a line break before the next entry, but found “/”. A comment starts with “#”"),
		("a: [1 // note\n]", "Expected “,”, a line break, or “]” after an array item, but found “/”. A comment starts with “#”"),
		("a: [1, // note\n2]", "Expected a value, but found “/”. A comment starts with “#”"),
		("a: 1 / 2", "Expected a line break before the next entry, but found “/”"),
		("key: |\n  text", "Expected a value, but found “|”. Write a multiline string as a block string, between ''' lines"),
		("key: >-\n  text", "Expected a value, but found “>”"),
		("key: | x", "Expected a value, but found “|”"),
		("[server]\nport: 1", "There are no table headers. Write the table as an object, as in server: {…}"),
		("[[servers.http]]\nport: 1", "Unexpected “servers”. A string value must be quoted, as in 'servers.http'"),
		("a: [server]", "Unexpected “server”. A string value must be quoted, as in 'server'"),
		("name: 'x'\n\n[server]\nport: 1", "There are no table headers. Write the table as an object, as in server: {…}"),
		("a: 1\n[", "Expected a key, but found “[”"),
		("{2026-09-19T14:00:00Z: 1}", "A key that contains “:” must be quoted, as in '2026-09-19T14:00:00Z'"),
		("12:30: 'lunch'", "A key that contains “:” must be quoted, as in '12:30'"),
		("a:b: 1", "A key that contains “:” must be quoted, as in 'a:b'"),
		("a:b", "Unexpected “b”. A string value must be quoted, as in 'b'"),
		("a:{b: nope}", "Unexpected “nope”. A string value must be quoted, as in 'nope'"),
		("a:\n\t12:30", "A time of day is a string, so it must be quoted"),
		("a: 07:32:00", "A time of day is a string, so it must be quoted"),
		("a: 12:00", "A time of day is a string, so it must be quoted"),
		("a: 10:30 PM", "A time of day is a string, so it must be quoted"),
		("a: 8080:80", "Invalid number “8080:80”. A value that contains “:” must be quoted, as in '8080:80'"),
		("color: #FFF\nsize: 1", "Expected a value, but found the key size. “#” starts a comment, so a value that starts with “#” must be quoted, as in '#FFF'"),
		("{color: #FFF\nsize: 1}", "Expected a value, but found the key size. “#” starts a comment, so a value that starts with “#” must be quoted, as in '#FFF'"),
		("color: #FFF", "Expected a value, but reached the end of the document. “#” starts a comment, so a value that starts with “#” must be quoted, as in '#FFF'"),
		("color: #FFF\n", "Expected a value, but reached the end of the document. “#” starts a comment, so a value that starts with “#” must be quoted, as in '#FFF'"),
		("{color: #FFF\n}", "Expected a value, but found “}”. “#” starts a comment, so a value that starts with “#” must be quoted, as in '#FFF'"),
		("color: #FFF, size: 1", "Expected a value, but reached the end of the document. “#” starts a comment, so a value that starts with “#” must be quoted, as in '#FFF'"),
		("color: # The color\nsize: 1", "Expected a value, but found the key size"),
		("server:\n  port: 80", "Expected a value, but found the key port. Indentation does not nest objects, so write server: {port: …}"),
		("ports:\n  - 80\n  - 443", "Expected a value, but found a “-” list. An array is written in brackets, as in [80, 443]"),
		("ports:\n- 80", "Expected a value, but found a “-” list. An array is written in brackets, as in [80, 443]"),
		("{\n\ta:\n\tb: 1\n}", "Expected a value, but found the key b"),
		("a: 1979-05-27 07:32:00Z", "The date and time separator in an instant is an uppercase “T”, not a space, as in 1979-05-27T07:32:00Z"),
		("a: 1979-05-27 07:32:00.5+02:00", "The date and time separator in an instant is an uppercase “T”, not a space, as in 1979-05-27T07:32:00.5+02:00"),
		("a: [1979-05-27 07:32:00Z]", "The date and time separator in an instant is an uppercase “T”, not a space, as in 1979-05-27T07:32:00Z"),
		("a: 1979-05-27 07:32:00", "The date and time separator in an instant is an uppercase “T”, not a space, and an instant needs the offset it was meant in, as in 1979-05-27T07:32:00Z for UTC. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '1979-05-27 07:32:00'"),
		("a: 1979-05-27 07:32:00,5Z", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 1979-05-27 07:32", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 1979-05-27 # note", "1979-05-27 is a date, not an instant. Write a date as a string, as in '1979-05-27'. An instant needs a time and an offset, as in 1979-05-27T00:00:00Z"),
		("a: 2026-09-19T14:00:00", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 2026-09-19T14:00:00.5", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00.5', or add the offset it was meant in"),
		("a: '''\nWelcome!'''", "Unterminated block string. Its closing delimiter must start a line, so move the ''' at the end of line 2 to a new line"),
		("a: \"\"\"\n\tHello\n\tWelcome!\"\"\"  \nb: 1", #"Unterminated block string. Its closing delimiter must start a line, so move the """ at the end of line 3 to a new line"#),
		("a: [1,000]", "Leading zeros are not allowed in a decimal number. A comma separates items, so 1,000 is not one number. Write it as 1_000 or 1000"),
		("a: [-1,000]", "Leading zeros are not allowed in a decimal number. A comma separates items, so -1,000 is not one number. Write it as -1_000 or -1000"),
		("a: [12,345,000]", "Leading zeros are not allowed in a decimal number. A comma separates items, so 12,345,000 is not one number. Write it as 12_345_000 or 12345000"),
		("a: [1,234,567,000]", "Leading zeros are not allowed in a decimal number. A comma separates items, so 1,234,567,000 is not one number. Write it as 1_234_567_000 or 1234567000"),
		("a: [12,050,000]", "Leading zeros are not allowed in a decimal number. A comma separates items, so 12,050,000 is not one number. Write it as 12_050_000 or 12050000"),
		("a: [0x1,000]", "Leading zeros are not allowed in a decimal number. Write an octal number, such as a file mode, as 0o0, and an identifier, such as a ZIP code, as a string: '000'"),
		("a: [1, 000]", "Leading zeros are not allowed in a decimal number. Write an octal number, such as a file mode, as 0o0, and an identifier, such as a ZIP code, as a string: '000'"),
		("a: 1.5µs", "The unit for microseconds is written us, as in 1.5us"),
		("a: 3μs", "The unit for microseconds is written us, as in 3us"),
		("a: 'it''s'", #"There is no '' escape in a '...' string. Write a string that contains ' as "...", as in "it's""#),
	]

	@Test(arguments: hints)
	func `a common mistake gets a hint`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let unquotedValues: [(source: String, text: String)] = [
		("name: John Smith", "John Smith"),
		("name: John Smith # The owner", "John Smith"),
		("name: John Smith \t\nisAdmin: true", "John Smith"),
		("a: foo.bar", "foo.bar"),
		("a: foo/bar", "foo/bar"),
		("a: v1.2.3", "v1.2.3"),
		("a: C# and F#", "C# and F#"),
		("a: say \"hi\"", "say \"hi\""),
		("a: [foo bar, true]", "foo bar"),
		("a: [foo bar]", "foo bar"),
		("a: {b: foo bar}", "foo bar"),
		("a: {b: foo bar, c: true}", "foo bar"),
		("a: [\n\tfoo bar\n]", "foo bar"),
		("a: hello world /* note */", "hello world"),
		("a: [hello world\t/* note */]", "hello world"),
		// A “/*” directly after the text is part of it.
		("a: src/*.js", "src/*.js"),
	]

	@Test(arguments: unquotedValues)
	func `a suggested quoted string holds the whole unquoted value`(_ source: String, _ text: String) throws {
		let message = try #require(parseError(source)?.message)
		#expect(message.hasSuffix("A string value must be quoted, as in '\(text)'"), "\(message)")
		// The suggestion is what was meant: with the text quoted, the document is valid and holds it.
		#expect(try parse(source.replacing(text, with: "'\(text)'", maxReplacements: 1)).containsString(text))
	}

	@Test
	func `an unquoted value names its first word, and a value with a single quote or a long value has a shorter suggestion`() {
		#expect(parseError("name: John Smith")?.message == "Unexpected “John”. A string value must be quoted, as in 'John Smith'")
		#expect(parseError("a: it's here")?.message == "Unexpected “it”. A string value must be quoted")
		let words = Array(repeating: "word", count: 1000).joined(separator: " ")
		#expect(parseError("a: \(words)")?.message == "Unexpected “word”. A string value must be quoted, as in '\(words.shortened())'")
		#expect(parseError("a: 01234 O'Brien")?.message == "Leading zeros are not allowed in a decimal number. Write an identifier, such as a ZIP code, as a string")
	}

	static let memberValues: [(source: String, message: String)] = [
		("url: https://example.com", "Unexpected “https”. A string value must be quoted, as in 'https://example.com'"),
		("url: https://example.com/a?b=c # The API", "Unexpected “https”. A string value must be quoted, as in 'https://example.com/a?b=c'"),
		("host: localhost:8080", "Unexpected “localhost”. A string value must be quoted, as in 'localhost:8080'"),
		("a: {url: https://x, b: true}", "Unexpected “https”. A string value must be quoted, as in 'https://x'"),
		("a: x:y", "Unexpected “x”. A string value must be quoted, as in 'x:y'"),
		("msg: Error: file not found", "Unexpected “Error”. A string value must be quoted, as in 'Error: file not found'"),
		("a: [Note: x, true]", "Expected a value, but found the key Note"),
		("a: {msg: Error: x}", "Unexpected “Error”. A string value must be quoted, as in 'Error: x'"),
		("a: b:", "Unexpected “b”. A string value must be quoted, as in 'b:'"),
		("a:\nb: 1", "Expected a value, but found the key b"),
		("a:\nb:\t1", "Expected a value, but found the key b"),
		("a:\nb:", "Expected a value, but found the key b"),
		("a:\nb:1\nc: 2", "Expected a value, but found the key b"),
		("{a:\nb:1}", "Expected a value, but found the key b"),
		("a: [\n\t3\n\tc: 5\n]", "Expected a value, but found the key c"),
		("[a:1]", "Expected a value, but found the key a"),
		("x: [a:b, c]", "Expected a value, but found the key a"),
		("a: [https://x, true]", "Expected a value, but found the key https"),
	]

	@Test(arguments: memberValues)
	func `a word after the colon of a member and a space is an unquoted string, but a key anywhere else`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let floatsTooLarge: [(source: String, message: String)] = [
		("a: 1e999", "1e999 is too large to be a finite float. Use infinity if you mean it"),
		("a: 1.7976931348623159e308", "1.7976931348623159e308 is too large to be a finite float. Use infinity if you mean it"),
		("a: -1e999", "-1e999 is too large to be a finite float. Use -infinity if you mean it"),
		("a: -1.7976931348623159e308", "-1.7976931348623159e308 is too large to be a finite float. Use -infinity if you mean it"),
		("a: -1_000e1_000", "-1_000e1_000 is too large to be a finite float. Use -infinity if you mean it"),
	]

	@Test(arguments: floatsTooLarge)
	func `a float that is too large suggests the infinity of its sign`(_ source: String, _ message: String) throws {
		#expect(parseError(source)?.message == message)
		// The suggestion reads as the value that the literal rounds to.
		let isNegative = source.hasPrefix("a: -")
		#expect(try parse(isNegative ? "a: -infinity" : "a: infinity") == ["a": .float(isNegative ? -.infinity : .infinity)])
		#expect(message.contains(isNegative ? "Use -infinity" : "Use infinity"))
	}

	static let otherHints: [(source: String, message: String)] = [
		// A value that starts with “.” is only a number when a digit follows.
		("a: .5", "A number cannot begin with “.”; write a digit before it, as in 0.5"),
		("a: .5e3", "A number cannot begin with “.”; write a digit before it, as in 0.5"),
		("a: .env", "Unexpected “.”. A string value must be quoted, as in '.env'"),
		("a: ./foo # The path", "Unexpected “.”. A string value must be quoted, as in './foo'"),
		("files: [.env, .git]", "Unexpected “.”. A string value must be quoted, as in '.env'"),
		("a: ...", "Unexpected “.”. A string value must be quoted, as in '...'"),
		("a: .", "Unexpected “.”. A string value must be quoted, as in '.'"),
		// A keyword hint is only for a word on its own, because following it would change the value or leave text behind.
		("a: Yes", "“Yes” is not a value. Booleans are written true and false, in lowercase"),
		("a: None # Unset", "“None” is not a value. Null is written null, in lowercase"),
		("a: [NaN, 1]", "NaN is not representable. Use null for a missing value"),
		("a: Inf", "“Inf” is not a value. Infinity is written infinity, in lowercase"),
		("a: Yes please", "Unexpected “Yes”. A string value must be quoted, as in 'Yes please'"),
		("status: On hold", "Unexpected “On”. A string value must be quoted, as in 'On hold'"),
		("a: None of the above", "Unexpected “None”. A string value must be quoted, as in 'None of the above'"),
		("name: Nan Goldin", "Unexpected “Nan”. A string value must be quoted, as in 'Nan Goldin'"),
		("a: [Inf loop, 1]", "Unexpected “Inf”. A string value must be quoted, as in 'Inf loop'"),
		// A suggested quoted string holds the whole unquoted value that starts with a number.
		("border: 1px solid black", "Invalid number “1px”. A string value must be quoted, as in '1px solid black'"),
		("font: 12pt Arial # Body", "Invalid number “12pt”. A string value must be quoted, as in '12pt Arial'"),
		("a: [1px solid, 2]", "Invalid number “1px”. A string value must be quoted, as in '1px solid'"),
		("a: 1px", "Invalid number “1px”. A string value must be quoted, as in '1px'"),
		("a: 3x it's", "Invalid number “3x”. A string value must be quoted"),
		("phone: 0412 345 678", "Leading zeros are not allowed in a decimal number. Write an identifier, such as a ZIP code, as a string: '0412 345 678'"),
		("date: 01/02/2026", "Leading zeros are not allowed in a decimal number. Write an identifier, such as a ZIP code, as a string: '01/02/2026'"),
		("mode: 0644", "Leading zeros are not allowed in a decimal number. Write an octal number, such as a file mode, as 0o644, and an identifier, such as a ZIP code, as a string: '0644'"),
		("zip: 08901", "Leading zeros are not allowed in a decimal number. Write an identifier, such as a ZIP code, as a string: '08901'"),
		// The digit that is not octal comes after the length that is diagnosed, so the whole number decides that there is no octal suggestion.
		("a: 0\(String(repeating: "0", count: 1100))8", "Leading zeros are not allowed in a decimal number. Write an identifier, such as a ZIP code, as a string: '\(String(repeating: "0", count: 40))…'"),
		("a: 0\(String(repeating: "0", count: 1100))7", "Leading zeros are not allowed in a decimal number. Write an identifier, such as a ZIP code, as a string: '\(String(repeating: "0", count: 40))…'"),
		// A lowercase hexadecimal digit is a digit in the wrong case, so the one named is a character that is no digit in either case.
		("a: 0xffg", "Invalid hexadecimal digit “g”"),
		("a: 0xFfz", "Invalid hexadecimal digit “z”"),
		("a: 0xFG", "Invalid hexadecimal digit “G”"),
		("a: 0o78", "Invalid octal digit “8”"),
		("a: 0b102", "Invalid binary digit “2”"),
		// A value that starts with “#” is only shown quoted when a '...' string can hold it.
		("a: #don't", "Expected a value, but reached the end of the document. “#” starts a comment, so a value that starts with “#” must be quoted"),
		("a: #'x'", "Expected a value, but reached the end of the document. “#” starts a comment, so a value that starts with “#” must be quoted"),
		("a: #it's\nb: 1", "Expected a value, but found the key b. “#” starts a comment, so a value that starts with “#” must be quoted"),
		("{a: #it's\n}", "Expected a value, but found “}”. “#” starts a comment, so a value that starts with “#” must be quoted"),
		("a: #dont", "Expected a value, but reached the end of the document. “#” starts a comment, so a value that starts with “#” must be quoted, as in '#dont'"),
		("a: #say\"hi\"", #"Expected a value, but reached the end of the document. “#” starts a comment, so a value that starts with “#” must be quoted, as in '#say"hi"'"#),
		// A number with thousands separators is only suggested when it is in the int64 range.
		("a: [9,223,372,036,854,775,807]", "Leading zeros are not allowed in a decimal number. A comma separates items, so 9,223,372,036,854,775,807 is not one number. Write it as 9_223_372_036_854_775_807 or 9223372036854775807"),
		("a: [-9,223,372,036,854,775,808]", "Leading zeros are not allowed in a decimal number. A comma separates items, so -9,223,372,036,854,775,808 is not one number. Write it as -9_223_372_036_854_775_808 or -9223372036854775808"),
		("a: [9,223,372,036,854,775,808]", "Leading zeros are not allowed in a decimal number. A comma separates items, so 9,223,372,036,854,775,808 is not one number"),
		("a: [-9,223,372,036,854,775,809]", "Leading zeros are not allowed in a decimal number. A comma separates items, so -9,223,372,036,854,775,809 is not one number"),
		("a: [10,000,000,000,000,000,000]", "Leading zeros are not allowed in a decimal number. A comma separates items, so 10,000,000,000,000,000,000 is not one number"),
	]

	@Test(arguments: otherHints)
	func `a hint suggests only what is valid`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let uppercaseHexadecimals: [(source: String, message: String)] = [
		("a: 0xff", "Hexadecimal digits are uppercase: 0xFF"),
		("a: 0xff_ff", "Hexadecimal digits are uppercase: 0xFF_FF"),
		("a: 0xFf", "Hexadecimal digits are uppercase: 0xFF"),
		("a: 0x00ff", "Hexadecimal digits are uppercase: 0x00FF"),
		// The uppercase spelling would still be invalid, so the underscore is reported.
		("a: 0x_ff", "An underscore in a number must be between two digits"),
		("a: 0xff_", "An underscore in a number must be between two digits"),
		("a: 0xf__f", "An underscore in a number must be between two digits"),
		("a: 0x_FF", "An underscore in a number must be between two digits"),
		// The lowercase digits come after the length that is diagnosed, so the whole number decides the reason.
		("a: 0x\(String(repeating: "1", count: 1100))ff", "Hexadecimal digits are uppercase"),
		("a: 0x\(String(repeating: "1", count: 1100))f_f", "Hexadecimal digits are uppercase"),
		("a: 0x\(String(repeating: "1", count: 1100))f__f", "An underscore in a number must be between two digits"),
	]

	@Test(arguments: uppercaseHexadecimals)
	func `a suggested uppercase hexadecimal integer is valid`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	@Test
	func `every uppercase hexadecimal suggestion parses to the value the lowercase digits mean`() throws {
		for digits in ["a", "f", "0a", "a0", "ab_cd", "a_b_c", "7fffffffffffffff", "dead_beef", "_a", "a_", "a__b", "a_b_", "_"] {
			let message = try #require(parseError("a: 0x\(digits)")?.message)

			guard let suggestion = message.firstMatch(of: /uppercase: (\S+)$/)?.output.1 else {
				continue
			}

			#expect(try parse("a: \(suggestion)") == ["a": .int(try #require(Int64(digits.replacing("_", with: ""), radix: 16)))], "\(message)")
		}
	}

	@Test
	func `every example of a value that starts with a hash is a valid string that holds the value`() throws {
		for value in ["#FFF", #"#a\b"#, "#say\"hi\"", "#1.5", "#é😀"] {
			let message = try #require(parseError("a: \(value)")?.message)
			let example = try #require(message.firstMatch(of: /as in (.+)$/)?.output.1)
			#expect(try parse("a: \(example)") == ["a": .string(value)])
		}
	}

	@Test
	func `every suggestion for a number with thousands separators parses to the number without its commas`() throws {
		for number in ["1,000", "-1,000", "999,000", "12,345,000", "9,223,372,036,854,775,807", "9,223,372,036,854,775,808", "-9,223,372,036,854,775,809"] {
			let message = try #require(parseError("a: [\(number)]")?.message)
			let withoutCommas = number.replacing(",", with: "")

			guard let match = message.firstMatch(of: /Write it as (\S+) or (\S+)$/) else {
				#expect(Int64(withoutCommas) == nil, "\(number)")
				continue
			}

			for suggestion in [match.output.1, match.output.2] {
				#expect(try parse("a: [\(suggestion)]") == ["a": [.int(try #require(Int64(withoutCommas)))]])
			}
		}
	}

	static let spaceSeparatedInstants: [(source: String, message: String)] = [
		("a: 2024-02-29 14:00:00Z", "The date and time separator in an instant is an uppercase “T”, not a space, as in 2024-02-29T14:00:00Z"),
		("a: 2026-01-01 14:00:00.123456789Z", "The date and time separator in an instant is an uppercase “T”, not a space, as in 2026-01-01T14:00:00.123456789Z"),
		("a: 2026-02-30 14:00:00Z", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2025-02-29 14:00:00Z", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2026-01-01 24:00:00Z", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2026-01-01 14:60:00Z", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2026-01-01 14:00:60Z", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2026-01-01 14:00:00.1234567890Z", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2026-01-01 14:00:00-00:00", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2026-01-01 14:00:00+24:00", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 0001-01-01 00:00:00+01:00", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 9999-12-31 23:59:59-01:00", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2024-02-29 14:00:00", "The date and time separator in an instant is an uppercase “T”, not a space, and an instant needs the offset it was meant in, as in 2024-02-29T14:00:00Z for UTC. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2024-02-29 14:00:00'"),
		("a: 2026-02-30 14:00:00", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2026-01-01 25:00:00", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 0000-01-01 00:00:00", "The date and time separator in an instant is an uppercase “T”, not a space. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
	]

	@Test(arguments: spaceSeparatedInstants)
	func `a date and a time with a space between them are only shown as an instant when it is valid`(_ source: String, _ message: String) throws {
		#expect(parseError(source)?.message == message)

		if let instant = message.firstMatch(of: /as in (\S+T\S+?)(?:$| for UTC)/)?.output.1 {
			#expect(throws: Never.self) {
				try parse("a: \(instant)")
			}
		}
	}

	static let unitsAfterSpaces: [(source: String, message: String)] = [
		("a: 1.5 us", "A unit cannot follow a number after a space. Write a duration without the space, as in 1.5us, and anything else, such as a size, as a string, as in '1.5 us'"),
		("a: -5 m", "A unit cannot follow a number after a space. Write a duration without the space, as in -5m, and anything else, such as a size, as a string, as in '-5 m'"),
		("a: 1_000 ms", "A unit cannot follow a number after a space. Write a duration without the space, as in 1_000ms, and anything else, such as a size, as a string, as in '1_000 ms'"),
		("a: 2562047 h", "A unit cannot follow a number after a space. Write a duration without the space, as in 2562047h, and anything else, such as a size, as a string, as in '2562047 h'"),
		("a: 1.5 ns", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s, and anything else, such as a size, as a string, as in '1.5 ns'"),
		("a: 0.0000000001 s", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s, and anything else, such as a size, as a string, as in '0.0000000001 s'"),
		("a: -0.0 s", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s, and anything else, such as a size, as a string, as in '-0.0 s'"),
		("a: 2562048 h", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s, and anything else, such as a size, as a string, as in '2562048 h'"),
		("a: 3000000 h", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s, and anything else, such as a size, as a string, as in '3000000 h'"),
		("a: 1e3 ms", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s, and anything else, such as a size, as a string, as in '1e3 ms'"),
		("a: 0x10 s", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s, and anything else, such as a size, as a string, as in '0x10 s'"),
	]

	@Test(arguments: unitsAfterSpaces)
	func `a duration without the space is only suggested when it is valid`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	@Test
	func `every suggested duration without the space is valid`() throws {
		for number in ["1", "-1", "0", "0.5", "1.5", "-1.5", "1_000", "1e3", "0x1F", "0o7", "0b1", "-0.0", "9223372036854775807", "0.000000001", "0.0000000001"] {
			for unit in ["h", "m", "s", "ms", "us", "ns"] {
				let message = try #require(parseError("a: \(number) \(unit)")?.message)
				let duration = try #require(message.firstMatch(of: /as in (\S+),/)?.output.1)

				#expect(throws: Never.self, "\(message)") {
					try parse("a: \(duration)")
				}
			}
		}
	}

	static let uppercaseUnicodeEscapes: [(source: String, message: String)] = [
		("a: \"\\u{D}\"", "A carriage return (U+000D) cannot be represented, so \\u{D} is not allowed"),
		("a: \"\\u{00D}\"", "A carriage return (U+000D) cannot be represented, so \\u{00D} is not allowed"),
		("a: \"\\u{D800}\"", "\\u{D800} is a surrogate, which is not a Unicode scalar value"),
		("a: \"\\u{dFfF}\"", "\\u{dFfF} is a surrogate, which is not a Unicode scalar value"),
		("a: \"\\u{FFFFFF}\"", "\\u{FFFFFF} is above U+10FFFF, the largest Unicode scalar value"),
		("a: \"\\u{11000F}\"", "\\u{11000F} is above U+10FFFF, the largest Unicode scalar value"),
		("a: \"\"\"\n\t\\u{D}\n\t\"\"\"", "A carriage return (U+000D) cannot be represented, so \\u{D} is not allowed"),
		("\"\\u{D}\": 1", "A carriage return (U+000D) cannot be represented, so \\u{D} is not allowed"),
		("a: \"\\u{E9}\"", "A Unicode escape uses lowercase hexadecimal digits"),
		("a: \"\\u{1F600}\"", "A Unicode escape uses lowercase hexadecimal digits"),
		("a: \"\\u{10FFFF}\"", "A Unicode escape uses lowercase hexadecimal digits"),
		("a: \"\\u{00E9}\"", "A Unicode escape uses lowercase hexadecimal digits"),
		("a: \"\\u{D7FF}\"", "A Unicode escape uses lowercase hexadecimal digits"),
		("a: \"\\u{E000}\"", "A Unicode escape uses lowercase hexadecimal digits"),
		("a: \"\\u{C}\"", "A Unicode escape uses lowercase hexadecimal digits"),
		("a: \"\\u{FFFFFFF}\"", "A Unicode escape uses lowercase hexadecimal digits"),
		("a: \"\\u{1234567}\"", "A Unicode escape has at most six hexadecimal digits"),
	]

	@Test(arguments: uppercaseUnicodeEscapes)
	func `the value of a Unicode escape with uppercase digits is checked before its spelling, so that lowercasing the digits never gives an escape that is not allowed either`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let offsetsAfterSpaces: [(source: String, message: String)] = [
		("a: 2026-09-19T14:00:00 Z", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00Z"),
		("a: 2026-09-19T14:00:00 +02:00", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00+02:00"),
		("a: 2026-09-19T14:00:00.5 -07:30", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00.5-07:30"),
		("a: 2026-09-19T14:00:00\t\tZ # note", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00Z"),
		("a: [2026-09-19T14:00:00 Z, 1]", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00Z"),
		("a: {b: 2026-09-19T14:00:00 Z}", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00Z"),
		("a: [\n\t2026-09-19T14:00:00 Z\n]", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00Z"),
		("a: 2026-02-30T14:00:00 Z", "An instant's offset follows its time directly, without a space"),
		("a: 0001-01-01T00:00:00 +00:01", "An instant's offset follows its time directly, without a space"),
		("a: 2026-09-19T14:00:00 +24:00", "An instant's offset follows its time directly, without a space"),
		("a: 2026-09-19T14:00:00 +02:00 # é", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00+02:00"),
		("a: 2026-09-19T14:00:00", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 2026-09-19T14:00:00 # Z", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 2026-09-19T14:00:00 Zulu", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 2026-09-19T14:00:00 +02:00:00", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 2026-09-19T14:00:00 +0200", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 2026-09-19T14:00:00\nZ: 1", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 2026-09-19T14:00 Z", "Invalid instant “2026-09-19T14:00”. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2026-09-19T14:00:00Z Z", "Expected a line break before the next entry, but found “Z”"),
		("a: 2026-09-19T14:00:00 Montréal", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 2026-09-19T14:00:00 é", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: [2026-09-19 😀😀]", "2026-09-19 is a date, not an instant. Write a date as a string, as in '2026-09-19'. An instant needs a time and an offset, as in 2026-09-19T00:00:00Z"),
		("a: 2026-09-19 Montréal", "2026-09-19 is a date, not an instant. Write a date as a string, as in '2026-09-19'. An instant needs a time and an offset, as in 2026-09-19T00:00:00Z"),
		("a: 2026-09-19T14:00 x日本", "Invalid instant “2026-09-19T14:00”. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		("a: 2026-09-19T14:00:00 Zé", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 2026-09-19T14:00:00 +02:0é", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 1979-05-27 07:32:00 Z", "The date and time separator in an instant is an uppercase “T”, not a space, and an instant needs the offset it was meant in, as in 1979-05-27T07:32:00Z for UTC. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '1979-05-27 07:32:00'"),
	]

	@Test(arguments: offsetsAfterSpaces)
	func `an offset after a space is the offset an instant was meant in, so the instant is not a local time to quote as a string`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let valuesWithColonsAndLeadingZeros: [(source: String, message: String)] = [
		("mac: 00:1A:2B:3C:4D:5E", "Invalid number “00:1A:2B:3C:4D:5E”. A string value must be quoted, as in '00:1A:2B:3C:4D:5E'"),
		("mac: 01:23:45:67:89:AB", "Invalid number “01:23:45:67:89:AB”. A string value must be quoted, as in '01:23:45:67:89:AB'"),
		("a: 0123:abcd::1", "Invalid number “0123:abcd::1”. A string value must be quoted, as in '0123:abcd::1'"),
		("a: [00:1A:2B, 1]", "Invalid number “00:1A:2B”. A string value must be quoted, as in '00:1A:2B'"),
		("a: -01:30", "Invalid number “-01:30”"),
		("a: 01", "Leading zeros are not allowed in a decimal number. Write an octal number, such as a file mode, as 0o1, and an identifier, such as a ZIP code, as a string: '01'"),
		("a: 01A", "Leading zeros are not allowed in a decimal number"),
		("a: 00.5", "Leading zeros are not allowed in a decimal number"),
		("a: 00:11:22:33:44:55", "Invalid number “00:11:22:33:44:55”. A value that contains “:” must be quoted, as in '00:11:22:33:44:55'"),
		("a: 08:30", "A time of day is a string, so it must be quoted"),
		("a: 1:", "Invalid number “1:”"),
		("a: 2001:db8::1", "Invalid number “2001:db8::1”. A string value must be quoted, as in '2001:db8::1'"),
	]

	@Test(arguments: valuesWithColonsAndLeadingZeros)
	func `a value with a “:” that starts with a zero, such as a MAC address, is not a number with a leading zero`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let yearDurations: [(source: String, message: String)] = [
		("a: 1y", "Invalid duration 1y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [1y, 1]", "Invalid duration 1y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 2years", "Invalid duration 2years: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [2years, 1]", "Invalid duration 2years: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 1year", "Invalid duration 1year: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [1year, 1]", "Invalid duration 1year: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 3yr", "Invalid duration 3yr: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [3yr, 1]", "Invalid duration 3yr: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 3yrs", "Invalid duration 3yrs: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [3yrs, 1]", "Invalid duration 3yrs: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 1Y", "Invalid duration 1Y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [1Y, 1]", "Invalid duration 1Y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 1YEAR", "Invalid duration 1YEAR: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [1YEAR, 1]", "Invalid duration 1YEAR: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 1.5y", "Invalid duration 1.5y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [1.5y, 1]", "Invalid duration 1.5y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 1_000y", "Invalid duration 1_000y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [1_000y, 1]", "Invalid duration 1_000y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: -1y", "Invalid duration -1y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [-1y, 1]", "Invalid duration -1y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 1y6m", "Invalid duration 1y6m: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [1y6m, 1]", "Invalid duration 1y6m: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 1h1y", "Invalid duration 1h1y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [1h1y, 1]", "Invalid duration 1h1y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 1y1y", "Invalid duration 1y1y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: [1y1y, 1]", "Invalid duration 1y1y: there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"),
		("a: 100yen", "Invalid number “100yen”. A string value must be quoted, as in '100yen'"),
		("a: 1yard", "Invalid number “1yard”. A string value must be quoted, as in '1yard'"),
		("a: 5yo", "Invalid number “5yo”. A string value must be quoted, as in '5yo'"),
		("a: 1yrsx", "Invalid number “1yrsx”. A string value must be quoted, as in '1yrsx'"),
		("a: 1yearsx", "Invalid number “1yearsx”. A string value must be quoted, as in '1yearsx'"),
		("a: 1y.5", "Invalid number “1y.5”. A string value must be quoted, as in '1y.5'"),
		("a: 1 y", "A unit cannot follow a number after a space. Write a duration without the space, as in 10s, and anything else, such as a size, as a string, as in '1 y'"),
	]

	@Test(arguments: yearDurations)
	func `a duration in years is reported as one, as one in days or weeks is, and a word that only starts with a year unit is a string to quote`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let wordsEndingWithE: [(source: String, message: String)] = [
		("a: 7zip-bin-name", "Invalid number “7zip-bin-name”. A string value must be quoted, as in '7zip-bin-name'"),
		("a: 1byte", "Invalid number “1byte”. A string value must be quoted, as in '1byte'"),
		("a: 3-phase", "Invalid number “3-phase”. A string value must be quoted, as in '3-phase'"),
		("a: 1-time", "Invalid number “1-time”. A string value must be quoted, as in '1-time'"),
		("a: [100-pre, 1]", "Invalid number “100-pre”. A string value must be quoted, as in '100-pre'"),
		("a: 2e-e", "Invalid number “2e-e”. A string value must be quoted, as in '2e-e'"),
		("a: -verbose", "Expected a digit or “infinity” after “-”"),
		("args: [-recursive]", "Expected a digit or “infinity” after “-”"),
		("a: 1e", "Expected digits after the exponent marker “e”"),
		("a: 1e-", "Expected digits after the exponent marker “e”"),
		("a: -1e", "Expected digits after the exponent marker “e”"),
		("a: 1.5e", "Expected digits after the exponent marker “e”"),
		("a: 1.5e-", "Expected digits after the exponent marker “e”"),
		("a: -1_0.5_0e", "Expected digits after the exponent marker “e”"),
		("a: 0e", "Expected digits after the exponent marker “e”"),
		("a: 0.0e-", "Expected digits after the exponent marker “e”"),
	]

	@Test(arguments: wordsEndingWithE)
	func `only a number ends with its exponent marker, so a word that ends with an “e” has no exponent`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let wordsAfterMinus: [(source: String, message: String)] = [
		("a: -nano", "Expected a digit or “infinity” after “-”"),
		("a: -nanny", "Expected a digit or “infinity” after “-”"),
		("a: -info", "Expected a digit or “infinity” after “-”"),
		("a: -INFO", "Expected a digit or “infinity” after “-”"),
		("args: [-inform, PEM]", "Expected a digit or “infinity” after “-”"),
		("a: -infinite", "Expected a digit or “infinity” after “-”"),
		("a: -infinityx", "Expected a digit or “infinity” after “-”"),
		("a: nano", "Unexpected “nano”. A string value must be quoted, as in 'nano'"),
		("a: info", "Unexpected “info”. A string value must be quoted, as in 'info'"),
		("a: -nan", "NaN is not representable. Use null for a missing value"),
		("a: -NaN", "NaN is not representable. Use null for a missing value"),
		("a: -NAN", "NaN is not representable. Use null for a missing value"),
		("a: -inf", "“-inf” is not a value. Negative infinity is written -infinity"),
		("a: -Inf", "“-Inf” is not a value. Negative infinity is written -infinity"),
		("a: -INF", "“-INF” is not a value. Negative infinity is written -infinity"),
		("a: -Infinity", "“-Infinity” is not a value. Negative infinity is written -infinity"),
		("a: -INFINITY", "“-INFINITY” is not a value. Negative infinity is written -infinity"),
		("a: [-inf, 1]", "“-inf” is not a value. Negative infinity is written -infinity"),
		("a: [-Infinity, 1]", "“-Infinity” is not a value. Negative infinity is written -infinity"),
	]

	@Test(arguments: wordsAfterMinus)
	func `a word after “-” is only NaN or infinity when it is the whole word, as for one without the “-”`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let slashesInValues: [(source: String, message: String)] = [
		("speed: 100 km/h", "Expected a line break before the next entry, but found “k”"),
		("a: 5 m/s", "Expected a line break before the next entry, but found “m”"),
		("a: [5 m/s]", "Expected “,”, a line break, or “]” after an array item, but found “m”"),
		("a: 2026-09-19T14:00:00/2026-09-20T15:00:00", "An instant needs an offset: Z or ±HH:MM"),
		("a: [2026-09-19T14:00:00/P1D]", "An instant needs an offset: Z or ±HH:MM"),
		("a: 2026-09-19T14:00:00 Z/x", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 5 m /* c */", "A unit cannot follow a number after a space. Write a duration without the space, as in 5m, and anything else, such as a size, as a string, as in '5 m'"),
		("a: 5 m/* c */", "A unit cannot follow a number after a space. Write a duration without the space, as in 5m, and anything else, such as a size, as a string, as in '5 m'"),
		("a: 2026-09-19T14:00:00/* c */", "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"),
		("a: 2026-09-19T14:00:00 Z/* c */", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00Z"),
		("a: 2026-09-19T14:00:00 Z /* c */", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00Z"),
		("timeout: 5 s // seconds", "A unit cannot follow a number after a space. Write a duration without the space, as in 5s, and anything else, such as a size, as a string, as in '5 s'"),
		("a: 5 m//c", "A unit cannot follow a number after a space. Write a duration without the space, as in 5m, and anything else, such as a size, as a string, as in '5 m'"),
		("a: 2026-09-19T14:00:00 Z//c", "An instant's offset follows its time directly, without a space, as in 2026-09-19T14:00:00Z"),
	]

	@Test(arguments: slashesInValues)
	func `a “/” only ends a value for a suggestion when it starts a comment, so a suggestion never leaves out the text after it`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let underscoresInWords: [(source: String, message: String)] = [
		("a: 4k_video", "Invalid number “4k_video”. A string value must be quoted, as in '4k_video'"),
		("a: 2x_speed", "Invalid number “2x_speed”. A string value must be quoted, as in '2x_speed'"),
		("a: [5k_run, 2]", "Invalid number “5k_run”. A string value must be quoted, as in '5k_run'"),
		("a: 1_", "An underscore in a number must be between two digits"),
		("a: 1__0", "An underscore in a number must be between two digits"),
		("a: 1_.5", "An underscore in a number must be between two digits"),
		("a: 1._5", "An underscore in a number must be between two digits"),
		("a: 1_e5", "An underscore in a number must be between two digits"),
		("a: 1e_5", "An underscore in a number must be between two digits"),
		("a: 1e5_", "An underscore in a number must be between two digits"),
		("a: 1.5_", "An underscore in a number must be between two digits"),
		("a: -1_", "An underscore in a number must be between two digits"),
		("a: 1_000_", "An underscore in a number must be between two digits"),
		("a: 1e-_5", "An underscore in a number must be between two digits"),
	]

	@Test(arguments: underscoresInWords)
	func `an underscore next to a letter is part of a word, not a misplaced separator in a number`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let uppercaseEsInWords: [(source: String, message: String)] = [
		("price: 5EUR", "Invalid number “5EUR”. A string value must be quoted, as in '5EUR'"),
		("disk: 10EB", "Invalid number “10EB”. A string value must be quoted, as in '10EB'"),
		("a: 1.5Ex", "Invalid number “1.5Ex”. A string value must be quoted, as in '1.5Ex'"),
		("a: [3ED, 1]", "Invalid number “3ED”. A string value must be quoted, as in '3ED'"),
		("a: 1E5", "An exponent marker is a lowercase “e”"),
		("a: 1E10", "An exponent marker is a lowercase “e”"),
		("a: 1.5E-3", "An exponent marker is a lowercase “e”"),
		("a: -2E7", "An exponent marker is a lowercase “e”"),
		("a: 1_0E1_0", "An exponent marker is a lowercase “e”"),
		("a: 1E", "An exponent marker is a lowercase “e”"),
		("a: 2E-", "An exponent marker is a lowercase “e”"),
		("a: 1.5E", "An exponent marker is a lowercase “e”"),
	]

	@Test(arguments: uppercaseEsInWords)
	func `an uppercase “E” is only an exponent marker where one goes, so in a word such as 5EUR it is not`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	static let tableHeaders: [(source: String, message: String)] = [
		// A table header is only reported where a table could be written instead. An item of a nested array cannot be a member, so a word in brackets there is an unquoted string, and so is one on the line after a key whose value was left out.
		("[server]\nport: 1", "There are no table headers. Write the table as an object, as in server: {…}"),
		("# The server.\n[server]\nport: 1", "There are no table headers. Write the table as an object, as in server: {…}"),
		("\t[server]\nport: 1", "There are no table headers. Write the table as an object, as in server: {…}"),
		("[[servers]]\nport: 1", "There are no table headers. Write the table as an object, as in servers: {…}"),
		("a: 1\n[server]\nport: 1", "There are no table headers. Write the table as an object, as in server: {…}"),
		("a: {\n\t[server]\n}", "There are no table headers. Write the table as an object, as in server: {…}"),
		("roles: [\n\t[admin]\n]", "Unexpected “admin”. A string value must be quoted, as in 'admin'"),
		("a: [\n\t1,\n\t[x]\n]", "Unexpected “x”. A string value must be quoted, as in 'x'"),
		("[\n\t1,\n\t[x]\n]", "Unexpected “x”. A string value must be quoted, as in 'x'"),
		("[\n\t[[x]]\n]", "Unexpected “x”. A string value must be quoted, as in 'x'"),
		("a:\n[server]\nport: 1", "Unexpected “server”. A string value must be quoted, as in 'server'"),
		("a:\n  [server]", "Unexpected “server”. A string value must be quoted, as in 'server'"),
		("{a:\n[server]\n}", "Unexpected “server”. A string value must be quoted, as in 'server'"),
		// A table header is only reported for a name that is a valid bare key, which has no dot.
		("[a.b]\nport: 1", "Unexpected “a”. A string value must be quoted, as in 'a.b'"),
		("[a.b-c.d_e]\nport: 1", "Unexpected “a”. A string value must be quoted, as in 'a.b-c.d_e'"),
		("[[a.b]]\nport: 1", "Unexpected “a”. A string value must be quoted, as in 'a.b'"),
		("x: 1\n[a.b]\nport: 1", "Expected a key, but found “[”"),
		("[a..b]\nport: 1", "Unexpected “a”. A string value must be quoted, as in 'a..b'"),
		("[a.]\nport: 1", "Unexpected “a”. A string value must be quoted, as in 'a.'"),
		("[[a..b]]\nport: 1", "Unexpected “a”. A string value must be quoted, as in 'a..b'"),
		("x: 1\n[a..b]\nport: 1", "Expected a key, but found “[”"),
		("x: 1\n[a.]\nport: 1", "Expected a key, but found “[”"),
	]

	@Test(arguments: tableHeaders)
	func `a table header is only reported where a table could be written instead, for a name that is a valid key`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	@Test
	func `every key that the table header error suggests is valid`() throws {
		for name in ["a", "a-b", "_a", "a1", "a.b", "a..b", "a."] {
			let message = try #require(parseError("[\(name)]\nport: 1")?.message)

			guard let suggestion = message.firstMatch(of: /as in (\S+): \{…\}/)?.output.1 else {
				continue
			}

			#expect(suggestion == name)
			#expect(throws: Never.self) {
				try parse("\(suggestion): {port: 1}")
			}
		}
	}

	static let indentedKeys: [(source: String, message: String)] = [
		("server:\n  port: 80", "Expected a value, but found the key port. Indentation does not nest objects, so write server: {port: …}"),
		("'a.b':\n  'c.d': 1", #"Expected a value, but found the key "c.d". Indentation does not nest objects, so write 'a.b': {'c.d': …}"#),
		("'the server':\n  'the port': 80", #"Expected a value, but found the key "the port". Indentation does not nest objects, so write 'the server': {'the port': …}"#),
		("\"it's\":\n  b: 1", #"Expected a value, but found the key b. Indentation does not nest objects, so write "it's": {b: …}"#),
		("\"a\\u{1}\":\n  b: 1", #"Expected a value, but found the key b. Indentation does not nest objects, so write "a\u{1}": {b: …}"#),
		("a:\n  \"\\u{8}\\u{c}\\u{7f}\": 1", #"Expected a value, but found the key "\b\f�". Indentation does not nest objects, so write a: {"\u{8}\u{c}\u{7f}": …}"#),
		("a:\n  \"b\\\\c\": 1", #"Expected a value, but found the key "b\\c". Indentation does not nest objects, so write a: {'b\c': …}"#),
		("ports:\n  - 80\n  - 443", "Expected a value, but found a “-” list. An array is written in brackets, as in [80, 443]"),
		("{\n\ta:\n\tb: 1\n}", "Expected a value, but found the key b"),
	]

	@Test(arguments: indentedKeys)
	func `the keys in the suggestion for an indented key are written as in a document`(_ source: String, _ message: String) {
		#expect(parseError(source)?.message == message)
	}

	@Test
	func `the suggestion for an indented key is a valid document with the value nested under the key`() throws {
		for (parent, child) in [("a", "b"), ("'a b'", #""c\u{1}""#), (#""\u{7f}""#, #""\t""#), ("'x.y'", "'é😀'")] {
			let message = try #require(parseError("\(parent):\n  \(child): 1")?.message)
			let match = try #require(message.firstMatch(of: /so write (.+): \{(.+): …\}$/))
			#expect(try parse("\(match.output.1): {\(match.output.2): 1}") == parse("\(parent): {\(child): 1}"))
		}
	}

	/**
	The documents that each fix in a message makes, where the fix is a value or a key. A fix cut short with “…” is left out, because it is not the whole fix.
	*/
	static func suggestedDocuments(_ message: String) -> [String] {
		// Each pattern only runs on a message that has its marker, because regular expressions are slow in a debug build.
		var documents = [String]()

		if message.contains("as in '") {
			documents += message.matches(of: /as in ('[^\n']*')(?:$|, | for )/).map { "a: \($0.output.1)" }
		}

		if message.contains(", and anything else") {
			documents += message.matches(of: /as in (\S+), and anything else/).map { "a: \($0.output.1)" }
		}

		if message.contains("not a space, as in") {
			documents += message.matches(of: /not a space, as in (\S+)$/).map { "a: \($0.output.1)" }
		}

		if message.contains("Z for UTC") {
			documents += message.matches(of: /as in (\S+)Z for UTC/).map { "a: \($0.output.1)Z" }
		}

		if
			message.contains("Write it as"),
			let match = message.firstMatch(of: /Write it as (\S+) or (\S+)$/)
		{
			documents += ["a: \(match.output.1)", "a: \(match.output.2)"]
		}

		if
			message.contains("if you mean"),
			let match = message.firstMatch(of: /Use (-?infinity) if you mean/)
		{
			documents.append("a: \(match.output.1)")
		}

		if
			message.contains("so write "),
			let match = message.firstMatch(of: /so write (.+): \{(.+): …\}$/)
		{
			documents.append("\(match.output.1): {\(match.output.2): 1}")
		}

		if
			message.contains("table headers"),
			let match = message.firstMatch(of: /as in (.+): \{…\}$/)
		{
			documents.append("\(match.output.1): {}")
		}

		return documents.filter { !$0.contains("…") }
	}

	@Test
	func `every fix that an error suggests is valid, in the errors for mutations of every valid conformance case`() throws {
		// Pieces that make the mistakes that the errors suggest fixes for.
		let pieces = [" ", "\n", "\n  ", ",", ":", ".", "..", "'", "\"", "#", "\\", "-", "_", "0", "00", "1", "9", "a", "e", "x", "T", " T", "Z", "z", "s", "m", "h", " h", " ms", " s", " ns", "µs", "0x", "0o", "f", #"\u00"#, #"\u{0"#, #"\u{1}"#, "[", "]", "[a]", "[a..b]", " 14:00:00", ":00", "+02:00", "-00:00", ",000", "0000"]
		var generator = SeededGenerator(seed: 1)
		var checked = 0

		for name in ConformanceTests.validCases {
			let original = Array(try String(contentsOf: ConformanceTests.root.appending(path: "valid/\(name).soml"), encoding: .utf8).unicodeScalars)

			for _ in 0..<25 {
				let position = Int.random(in: 0...original.count, using: &generator)
				let piece = pieces.randomElement(using: &generator)!
				let end = Bool.random(using: &generator) ? position : min(original.count, position + Int.random(in: 1...3, using: &generator))
				let mutated = String(String.UnicodeScalarView(original[..<position])) + piece + String(String.UnicodeScalarView(original[end...]))

				let error: SOML.ParseError

				do {
					_ = try parse(mutated)
					continue
				} catch let parseError as SOML.ParseError {
					error = parseError
				}

				for document in Self.suggestedDocuments(error.message) {
					checked += 1
					#expect(throws: Never.self, "The error for \(mutated.debugDescription), \(error.message.debugDescription), suggests \(document.debugDescription), which is invalid") {
						try parse(document)
					}
				}
			}
		}

		// The mutations reach the suggestions, so the test checks something.
		#expect(checked > 1000, "Only \(checked) suggestions were checked")
	}
}

extension SOML.Value {
	/**
	Whether the value is the string `text`, or holds it at any depth.
	*/
	fileprivate func containsString(_ text: String) -> Bool {
		switch self {
		case .string(let string):
			string == text
		case .array(let items):
			items.contains { $0.containsString(text) }
		case .object(let object):
			object.contains { $0.value.containsString(text) }
		default:
			false
		}
	}
}

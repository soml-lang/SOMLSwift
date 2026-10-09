import Testing
@testable import SOML

/**
The test suite of the first JavaScript parser, ported case by case. The error fragments are this implementation's messages for the same reasons.
*/
@Suite
struct ReferenceSuiteTests {
	static let accepted: [Sample] = [
		// The three document forms.
		Sample("bare object document", "key: 'value'\n"),
		Sample("braced object document", "{a: 1, b: 2}\n"),
		Sample("array document", "[1, 2, 3]\n"),
		Sample("comment before the first entry", "# a comment\nname: 'x'\n"),
		Sample("no trailing newline", "name: 'x'"),
		Sample("the same instant as a value", "at: 2026-09-19T14:00:00Z\n"),
		Sample("the same instant inside an array", "[2026-09-19T14:00:00Z]\n"),

		// Indentation is not significant, and whitespace may be mixed.
		Sample("space indentation", "pool: {\n    min: 2,\n}\n"),
		Sample("tab indentation", "pool: {\n\tmin: 2,\n}\n"),
		Sample("mixed indentation", "pool: {\n\t min: 2,\n  max: 3,\n}\n"),
		Sample("blank lines between entries", "a: 1\n\n\nb: 2\n"),
		Sample("comment-only line between entries", "a: 1\n# note\nb: 2\n"),

		// Trailing commas and comments.
		Sample("trailing comma in an object", "{a: 1,}\n"),
		Sample("trailing comma in an array", "[1,]\n"),
		Sample("empty containers", "{}\n"),
		Sample("empty array", "[]\n"),
		Sample("comment inside an empty array", "[/* x */]\n"),
		Sample("block comment between entries", "a: 1\n/* note */\nb: 2\n"),
		Sample("a hash comment containing a block terminator", "a: 1 #  */ is fine here\n"),
		Sample("a line comment after a block comment", "a: 1 /* x */ # y\n"),

		// Keys.
		Sample("dashes in a bare key", "content-type: 'x'\n"),
		Sample("a key beginning with a digit", "2fa: 1\n"),
		Sample("an HTTP status code as a key", "404: 'not found'\n500: 'server error'\n"),
		Sample("a date-like key", "2024-01-01: 'x'\n"),
		Sample("a key beginning with a hyphen", "-foo: 1\n"),
		Sample("a negative number as a key", "-1: 1\n"),
		Sample("a key of only hyphens", "---: 1\n"),
		Sample("a package name beginning with a digit", "7zip-bin: '^5.0.0'\n"),
		Sample("an underscore-prefixed key", "_private: 1\n"),
		Sample("a numeric key with underscores", "1_000: 1\n"),
		Sample("a hex-looking key", "0x1F: 1\n"),
		Sample("quoted key with a literal dot", "'a.b': 1\n"),
		Sample("a quoted numeric key with a dot", "'3.14': 'x'\n"),
		Sample("quoted key with spaces", "'the name': 'x'\n"),
		Sample("keyword as a key", "true: 1\n"),
		Sample("an infinity-looking key", "-inf: 1\n"),
		Sample("a quoted key containing a dot, next to a nested object", "'a.b': 1\na: {b: 2}\n"),

		// Strings.
		Sample("literal string keeps backslashes", "path: 'C:\\Users\\sindre'\n"),
		Sample("literal string with double quotes", "sh: 'echo \"$HOME\"'\n"),
		Sample("escaped string", "a: \"x\\ny \\\"z\\\" \\u{41} \\u{1f600}\"\n"),
		Sample("a tab escape in a value", "a: \"x\\ty\"\n"),
		Sample("a line feed escape in a value", "a: \"x\\ny\"\n"),

		// One Unicode escape spelling.
		Sample("a braced escape", "a: \"\\u{41}\"\n"),
		Sample("an astral braced escape", "a: \"\\u{1f600}\"\n"),
		Sample("a one digit escape", "a: \"\\u{0}\"\n"),
		Sample("a letter-only escape", "a: \"\\u{a}\"\n"),
		Sample("a six digit escape", "a: \"\\u{10ffff}\"\n"),

		// Block strings.
		Sample("block string", "a: '''\n\tx\n\ty\n\t'''\n"),
		Sample("block string with an inner double quote", "a: \"\"\"\n\tx \"y\"\n\t\"\"\"\n"),
		Sample("block string with a longer inner run", "a: ''''\n\t'''\n\t''''\n"),
		Sample("empty block string", "a: '''\n'''\n"),
		Sample("literal string with a tab", "a: 'x\ty'\n"),

		// Numbers.
		Sample("int forms", "a: 0\nb: 1\nc: -1\nd: 1_000\ne: 0xFF\nf: 0o17\ng: 0b1010\n"),
		Sample("uppercase hexadecimal digits", "a: 0xDEADBEEF\n"),
		Sample("leading zeros after a prefix", "a: 0x00FF\nb: 0o007\nc: 0b00001010\n"),
		Sample("float forms", "a: 1.5\nb: 1e10\nc: 100e2\nd: 1.5e-3\ne: infinity\nf: -infinity\ng: -0.0\nh: -1e10\ni: -1e-10\nj: 1.5e3\nk: 0e0\n"),
		Sample("the maximum instant", "a: 9999-12-31T23:59:59.999999999Z\n"),
		Sample("a zero offset", "a: 2026-01-01T00:00:00+00:00\n"),
		Sample("the infinity spellings", "a: infinity\nb: -infinity\n"),
		Sample("int64 max", "a: 9223372036854775807\n"),

		// Instants.
		Sample("instant with Z", "a: 2026-09-19T14:00:00Z\n"),
		Sample("instant with an offset", "a: 2026-09-19T14:00:00+07:00\n"),
		Sample("instant with a negative offset", "a: 2026-09-19T14:00:00-05:30\n"),
		Sample("instant with nanoseconds", "a: 2026-09-19T14:00:00.123456789Z\n"),
		Sample("February 29 in a leap year", "a: 2024-02-29T00:00:00Z\n"),
		Sample("February 29 in 2000", "a: 2000-02-29T00:00:00Z\n"),
		Sample("a zero offset written as +00:00", "a: 2026-01-01T00:00:00+00:00\n"),

		// Line endings.
		Sample("LF line endings", "a: 1\nb: 2\n"),

		// Noncharacters are scalar values, so they are allowed.
		Sample("a noncharacter", "a: '\u{FFFE}'\n"),
		Sample("a noncharacter, escaped", "a: \"\\u{fffe}\"\n"),

		// Block strings followed by a comma.
		Sample("a block string then a comma in an array", "a: [\n\t'''\n\tx\n\t''',\n\t2,\n]\n"),
		Sample("a block string then a comma in an object", "a: {\n\tb: '''\n\tx\n\t''',\n}\n"),
		Sample("a block string indented more than the delimiter", "a: '''\n\t\tx\n\t'''\n"),
	]

	@Test(arguments: accepted)
	func `accepts`(_ sample: Sample) throws {
		_ = try parse(sample.source)
	}

	static let rejected: [Rejection] = [
		// A bare scalar is not a document.
		Rejection("a bare scalar as a document", "true\n", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("a bare number as a document", "5\n", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("a bare string as a document", "'hello'\n", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),
		Rejection("a bare instant as a document", "2026-09-19T14:00:00Z\n", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`"),

		// Comments.
		Rejection("a nested block comment", "a: 1\n/* x /* y */\n", "Block comments cannot be nested, and their body may not contain “/*”"),
		Rejection("a nested block comment, closed twice", "a: 1\n/* x /* y */ */\n", "Block comments cannot be nested, and their body may not contain “/*”"),
		Rejection("an unterminated block comment", "a: 1\n/* x\n", "Unterminated block comment"),

		// Unicode escapes.
		Rejection("uppercase hex besides the first digit", "a: \"\\u{41F}\"\n", "lowercase"),
		Rejection("uppercase hex in an astral escape", "a: \"\\u{1F600}\"\n", "lowercase"),
		Rejection("the four digit JSON form", "a: \"\\u0041\"\n", #"The four-digit \u0041 form is not an escape. Write \u{41}"#),
		Rejection("a leading zero", "a: \"\\u{0041}\"\n", #"A Unicode escape may not have leading zeros; write \u{41}"#),
		Rejection("an empty escape", "a: \"\\u{}\"\n", "A Unicode escape needs one to six hexadecimal digits"),
		Rejection("a bare u", "a: \"\\u\"\n", "A Unicode escape is written"),
		Rejection("seven hex digits", "a: \"\\u{1000000}\"\n", "at most six"),
		Rejection("a surrogate by code point", "a: \"\\u{d800}\"\n", "surrogate"),
		Rejection("a value above the maximum", "a: \"\\u{110000}\"\n", #"\u{110000} is above U+10FFFF, the largest Unicode scalar value"#),

		// A carriage return is not representable anywhere.
		Rejection("a carriage return escape in a value", "a: \"x\\ry\"\n", "carriage return"),
		Rejection("a carriage return by code point", "a: \"\\u{d}\"\n", "carriage return"),
		Rejection("a carriage return escape in a block string", "a: \"\"\"\n\tx\\ry\n\t\"\"\"\n", "carriage return"),
		Rejection("a carriage return code point in a block string", "a: \"\"\"\n\tx\\u{d}\n\t\"\"\"\n", "carriage return"),
		Rejection("CRLF line endings", "a: 1\r\nb: 2\r\n", "carriage return"),
		Rejection("a lone CR", "a: 1\rb: 2\n", "carriage return"),
		Rejection("a CR inside a literal string", "a: 'x\r'\n", "carriage return"),
		Rejection("a CR inside a block string", "a: '''\r\n\tx\r\n\t'''\r\n", "carriage return"),
		Rejection("a CR after the last entry", "a: 1\n\r", "carriage return"),

		// Numbers.
		Rejection("lowercase hexadecimal digits", "a: 0xff\n", "uppercase"),
		Rejection("an uppercase prefix", "a: 0XFF\n", "lowercase"),
		Rejection("a negative hexadecimal int", "a: -0xFF\n", "cannot have a sign"),
		Rejection("a negative octal int", "a: -0o755\n", "cannot have a sign"),
		Rejection("a negative binary int", "a: -0b1010\n", "cannot have a sign"),
		Rejection("an uppercase exponent with a plus", "a: 1E+10\n", "A “+” sign is not allowed in a number, including in an exponent"),
		Rejection("the plus sign on a number", "a: +1\n", "A “+” sign is not allowed. A number without a sign is positive"),
		Rejection("the plus sign on a float", "a: +1.5\n", "A “+” sign is not allowed. A number without a sign is positive"),
		Rejection("the plus sign in an exponent", "a: 1e+10\n", "A “+” sign is not allowed in a number, including in an exponent"),
		Rejection("the plus sign in a negative exponent", "a: -1e+10\n", "A “+” sign is not allowed in a number, including in an exponent"),
		Rejection("nan", "a: nan\n", "NaN"),
		Rejection("a capitalised nan", "a: NaN\n", "NaN"),
		Rejection("negated nan", "a: -nan\n", "NaN"),
		Rejection("the abbreviated infinity", "a: inf\n", "“inf” is not a value. Infinity is written infinity, in lowercase"),
		Rejection("abbreviated negative infinity", "a: -inf\n", "“-inf” is not a value. Negative infinity is written -infinity"),
		Rejection("a capitalised infinity", "a: Inf\n", "“Inf” is not a value. Infinity is written infinity, in lowercase"),
		Rejection("an uppercase exponent marker", "a: 1E10\n", "An exponent marker is a lowercase “e”"),
		Rejection("an uppercase exponent marker with a sign", "a: 1.5E-3\n", "An exponent marker is a lowercase “e”"),
		Rejection("leading zeros", "a: 01234\n", "Leading zeros"),
		Rejection("minus zero as an int", "a: -0\n", "“-0” is not allowed, because zero has one spelling: 0"),
		Rejection("a leading decimal point", "a: .5\n", "A number cannot begin with “.”; write a digit before it, as in 0.5"),
		Rejection("a trailing decimal point", "a: 5.\n", "A decimal point must be followed by a digit"),
		Rejection("a trailing underscore", "a: 1_\n", "underscore"),
		Rejection("a doubled underscore", "a: 1__0\n", "underscore"),

		// Instants.
		Rejection("month 13", "a: 2026-13-01T00:00:00Z\n", "Invalid instant 2026-13-01T00:00:00Z: the month must be 01 to 12"),
		Rejection("month 00", "a: 2026-00-01T00:00:00Z\n", "Invalid instant 2026-00-01T00:00:00Z: the month must be 01 to 12"),
		Rejection("February 30", "a: 2026-02-30T00:00:00Z\n", "Invalid instant 2026-02-30T00:00:00Z: the day must be 01 to 28 in that month"),
		Rejection("February 29 in a non-leap year", "a: 2026-02-29T00:00:00Z\n", "Invalid instant 2026-02-29T00:00:00Z: the day must be 01 to 28 in that month"),
		Rejection("February 29 in 1900", "a: 1900-02-29T00:00:00Z\n", "Invalid instant 1900-02-29T00:00:00Z: the day must be 01 to 28 in that month"),
		Rejection("day 00", "a: 2026-01-00T00:00:00Z\n", "Invalid instant 2026-01-00T00:00:00Z: the day must be 01 to 31 in that month"),
		Rejection("hour 24", "a: 2026-01-01T24:00:00Z\n", "Invalid instant 2026-01-01T24:00:00Z: the hour must be 00 to 23"),
		Rejection("minute 60", "a: 2026-01-01T00:60:00Z\n", "Invalid instant 2026-01-01T00:60:00Z: the minute must be 00 to 59"),
		Rejection("a leap second", "a: 2026-01-01T00:00:60Z\n", "leap second is not representable"),
		Rejection("year 0000", "a: 0000-01-01T00:00:00Z\n", "Invalid instant 0000-01-01T00:00:00Z: the year must be 0001 to 9999"),
		Rejection("offset hour 24", "a: 2026-01-01T00:00:00+24:00\n", "Invalid instant 2026-01-01T00:00:00+24:00: the offset hour must be 00 to 23"),
		Rejection("offset minute 60", "a: 2026-01-01T00:00:00+01:60\n", "Invalid instant 2026-01-01T00:00:00+01:60: the offset minute must be 00 to 59"),
		Rejection("the unknown offset", "a: 2026-01-01T00:00:00-00:00\n", "Invalid instant 2026-01-01T00:00:00-00:00: -00:00 means “offset unknown” in RFC 3339, which is not representable; use Z or +00:00"),
		Rejection("a date with no time", "a: 2026-09-19\n", "2026-09-19 is a date, not an instant. Write a date as a string, as in '2026-09-19'. An instant needs a time and an offset, as in 2026-09-19T00:00:00Z"),
		Rejection("a lowercase instant separator", "a: 2026-09-19t14:00:00Z\n", "The date and time separator in an instant is an uppercase “T”"),
		Rejection("a lowercase z offset", "a: 2026-09-19T14:00:00z\n", "The UTC offset in an instant is an uppercase “Z”"),
		Rejection("an offset with no colon", "a: 2026-09-19T14:00:00+0700\n", "An instant's offset is written with a colon, as in +07:00"),
		Rejection("ten fractional digits", "a: 2026-09-19T14:00:00.1234567891Z\n", "Invalid instant 2026-09-19T14:00:00.1234567891Z: a fractional second has at most nine digits"),

		// Encoding and whitespace.
		Rejection("a BOM", "\u{FEFF}name: 'x'\n", "byte order mark"),
		Rejection("U+00A0 as whitespace", "a:\u{00A0} 1\n", "Expected a value, but found U+00A0 (NO-BREAK SPACE; only space, tab, and line feed are whitespace)"),
		Rejection("U+2028 is not whitespace", "a: 1\u{2028}b: 2\n", "U+2028"),

		// Documents.
		Rejection("an empty document", "", "empty"),
		Rejection("a comment-only document", "# nothing\n", "A document must contain an object or an array, but this one is empty"),
		Rejection("two entries on one line", "a: 1 b: 2\n", "Expected a line break before the next entry, but found “b”"),
		Rejection("a comma at the top level", "a: 1, b: 2\n", "not commas"),
		Rejection("trailing content after the value", "{a: 1} {b: 2}\n", "Unexpected “{” after the end of the document"),

		// Keys.
		Rejection("a bare key with a space in it", "the name: 1\n", "cannot contain spaces"),
		Rejection("a dot at the start of a key", ".a: 1\n", "Expected a key"),
		Rejection("a dot at the end of a key", "a.: 1\n", "A key cannot contain “.” unless it is quoted"),
		Rejection("a dot in a bare key", "a.b: 1\n", "A bare key cannot contain “.”. Quote it, as in 'a.b', or use braces to nest, as in a: {b: …}"),
		Rejection("a numeric key with a dot", "3.14: 'x'\n", "A bare key cannot contain “.”. Quote it, as in '3.14'"),
		Rejection("a dot after a quoted key", "'a'.b: 1\n", "A key cannot contain “.” unless it is quoted"),
		Rejection("duplicate keys", "a: 1\na: 2\n", "Duplicate key"),
		Rejection("a quoted and bare form of one key", "a: 1\n'a': 2\n", "Duplicate key"),
		Rejection("a quoted key with a dot twice", "'a.b': 1\n'a.b': 2\n", "Duplicate key"),

		// Strings.
		Rejection("an unknown escape", "a: \"\\q\"\n", #"Unknown escape “\q”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#),
		Rejection("an escaped single quote in a double-quoted string", "a: \"\\'\"\n", "needs no escape"),
		Rejection("a string spanning lines", "a: 'x\ny'\n", "Unterminated string"),
		Rejection("an unterminated string", "a: 'x\n", "Unterminated string"),

		// Containers.
		Rejection("a missing comma between members", "a: {b: 1 c: 2}\n", "Expected “,”, a line break, or “}” after an object member, but found “c”"),
		Rejection("a missing comma between array items", "a: [1 2]\n", "Expected “,”, a line break, or “]” after an array item, but found “2”"),
		Rejection("an unterminated object", "a: {\n", "Unterminated object: expected “}”"),

		// Block strings.
		Rejection("content on the block string opening line", "a: '''x\n\t'''\n", "A block string's opening delimiter must be followed directly by a line break, and its content starts on the next line"),
		Rejection("a block string indented less than the delimiter", "a: '''\n\tx\n\t\t'''\n", "This line does not start with the indentation of its block string's closing delimiter. Every line except a blank one must start with exactly the same spaces and tabs"),
		// The first line that is exactly the delimiter closes the block, so the next one is left over.
		Rejection("a block string whose content holds its delimiter", "a: '''\n\t'''\n\t'''\n", "cannot be a key"),
	]

	@Test(arguments: rejected)
	func `rejects`(_ rejection: Rejection) {
		expectRejected(rejection.source, rejection.message)
	}

	static let values: [Expectation] = [
		Expectation("a quoted key with a dot does not nest", "'3.14': 'x'\n", ["3.14": "x"]),
		Expectation("a block string dedents", "a: '''\n\tx\n\ty\n\t'''\n", ["a": "x\ny"]),
		Expectation("trailing commas are allowed", "{a: 1,}\n", ["a": 1]),
		Expectation("an escape decodes", "a: \"\\u{41}\"\n", ["a": "A"]),
		Expectation("an astral escape decodes", "a: \"\\u{1f600}\"\n", ["a": "\u{1F600}"]),
	]

	@Test(arguments: values)
	func `parses to the expected value`(_ expectation: Expectation) throws {
		#expect(try parse(expectation.source) == expectation.value)
	}

	@Test
	func `negative zero is collapsed to zero`() throws {
		let value = try #require(try parse("a: -0.0\n")["a"]?.floatValue)
		#expect(value == 0)
		#expect(value.sign == .plus)
	}

	@Test
	func `a lone surrogate is rejected`() {
		// A Swift string cannot hold a lone surrogate, so this is the UTF-8 encoding of U+D800.
		let bytes = Array("a: '".utf8) + [0xED, 0xA0, 0x80] + Array("'\n".utf8)

		#expect {
			try SOML.Value(parsing: bytes)
		} throws: { error in
			(error as? SOML.ParseError)?.message == "Invalid UTF-8 byte 0xED"
		}
	}
}

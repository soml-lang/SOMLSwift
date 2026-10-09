import Testing
@testable import SOML

@Suite
struct NumberTests {
	static let integers: [(String, Int64)] = [
		("0", 0),
		("1", 1),
		("-1", -1),
		("42", 42),
		("1_000", 1000),
		("1_000_000", 1_000_000),
		("1_2_3", 123),
		("-1_000", -1000),
		("9223372036854775807", .max),
		("-9223372036854775808", .min),
		("9_223_372_036_854_775_807", .max),
		("0x0", 0),
		("0xFF", 255),
		("0x00FF", 255),
		("0xDEAD_BEEF", 0xDEAD_BEEF),
		("0x7FFFFFFFFFFFFFFF", .max),
		("0x7FFF_FFFF_FFFF_FFFF", .max),
		("0o0", 0),
		("0o644", 0o644),
		("0o007", 7),
		("0o777_777", 0o777_777),
		("0o777777777777777777777", .max),
		("0b0", 0),
		("0b1", 1),
		("0b1010", 10),
		("0b1010_1100", 0b1010_1100),
		("0b00001010", 10),
		("0b111111111111111111111111111111111111111111111111111111111111111", .max),
		("10", 10),
		("100", 100),
		("1234567890", 1_234_567_890),
	]

	@Test(arguments: integers)
	func `parses an int`(_ source: String, _ expected: Int64) throws {
		#expect(try parseScalar(source) == .int(expected))
	}

	static let floats: [(String, Double)] = [
		("0.0", 0),
		("-0.0", 0),
		("0.5", 0.5),
		("1.5", 1.5),
		("-1.5", -1.5),
		("3.0", 3),
		("30.0", 30),
		("1e10", 1e10),
		("1e-10", 1e-10),
		("-1e10", -1e10),
		("-1e-10", -1e-10),
		("1.5e3", 1500),
		("1.5e-3", 0.0015),
		("100e2", 10_000),
		("0e0", 0),
		("0.0e0", 0),
		("1_000.5", 1000.5),
		("1.000_001", 1.000001),
		("1e1_0", 1e10),
		("1e0", 1),
		("1e5", 1e5),
		("1e-5", 1e-5),
		("0.1", 0.1),
		("0.2", 0.2),
		("0.30000000000000004", 0.30000000000000004),
		("3.141592653589793", 3.141592653589793),
		("1.7976931348623157e308", .greatestFiniteMagnitude),
		("-1.7976931348623157e308", -.greatestFiniteMagnitude),
		("5e-324", .leastNonzeroMagnitude),
		("2.2250738585072014e-308", .leastNormalMagnitude),
		("9007199254740993.0", 9007199254740992),
		("123456789012345678901234567890.0", 123456789012345678901234567890.0),
		("0.000000000000000000000000000001", 1e-30),
	]

	@Test(arguments: floats)
	func `parses a float`(_ source: String, _ expected: Double) throws {
		#expect(try parseScalar(source) == .float(expected))
	}

	@Test
	func `rounds a float to the nearest double, with ties to even`() throws {
		// 2^53 + 1 is exactly halfway between two doubles, so it rounds to the even one.
		#expect(try parseScalar("9007199254740993.0") == .float(9_007_199_254_740_992))
		#expect(try parseScalar("9007199254740995.0") == .float(9_007_199_254_740_996))
		// Just above halfway rounds up.
		#expect(try parseScalar("9007199254740993.0000001") == .float(9_007_199_254_740_994))
	}

	@Test
	func `int and float are different types`() throws {
		let value = try parse("a: 1\nb: 1.0")
		#expect(value["a"] == .int(1))
		#expect(value["b"] == .float(1))
		#expect(value["a"] != value["b"])
	}

	@Test
	func `infinity`() throws {
		#expect(try parseScalar("infinity") == .float(.infinity))
		#expect(try parseScalar("-infinity") == .float(-.infinity))
		#expect(try parse("[infinity, -infinity]") == [.float(.infinity), .float(-.infinity)])
	}

	@Test
	func `a signed zero is zero`() throws {
		for source in ["-0.0", "-0e0", "-0.0e-5", "-0.000"] {
			let value = try #require(try parseScalar(source).floatValue)
			#expect(value == 0)
			#expect(value.sign == .plus, "\(source) kept its sign")
		}
	}

	static let rejected: [Rejection] = [
		Rejection("int64 max plus one", "9223372036854775808", "The integer 9223372036854775808 is outside the 64-bit range (-9223372036854775808 to 9223372036854775807)"),
		Rejection("int64 min minus one", "-9223372036854775809", "The integer -9223372036854775809 is outside the 64-bit range (-9223372036854775808 to 9223372036854775807)"),
		Rejection("a huge int", "99999999999999999999999999", "The integer 99999999999999999999999999 is outside the 64-bit range (-9223372036854775808 to 9223372036854775807)"),
		Rejection("hex past int64", "0x8000000000000000", "The integer 0x8000000000000000 is outside the 64-bit range (-9223372036854775808 to 9223372036854775807)"),
		Rejection("hex of all ones", "0xFFFFFFFFFFFFFFFF", "The integer 0xFFFFFFFFFFFFFFFF is outside the 64-bit range (-9223372036854775808 to 9223372036854775807)"),
		Rejection("hex past uint64", "0x1_0000_0000_0000_0000", "The integer 0x1_0000_0000_0000_0000 is outside the 64-bit range (-9223372036854775808 to 9223372036854775807)"),
		Rejection("octal past int64", "0o1000000000000000000000", "The integer 0o1000000000000000000000 is outside the 64-bit range (-9223372036854775808 to 9223372036854775807)"),
		Rejection("binary past int64", "0b1000000000000000000000000000000000000000000000000000000000000000", "The integer 0b10000000000000000000000000000000000000… is outside the 64-bit range (-9223372036854775808 to 9223372036854775807)"),
		Rejection("a float too large", "1e999", "too large"),
		Rejection("a negative float too large", "-1e999", "too large"),
		Rejection("a float just past the maximum", "1.8e308", "too large"),
		Rejection("a float that rounds to zero", "1e-400", "too small"),
		Rejection("a negative float that rounds to zero", "-1e-400", "too small"),
		Rejection("a float just under half the smallest subnormal", "2.4703282292062327e-324", "too small"),
		Rejection("leading zeros", "01", "Leading zeros"),
		Rejection("two zeros", "00", "Leading zeros"),
		Rejection("negative leading zeros", "-01", "Leading zeros"),
		Rejection("a leading zero with an underscore", "0_1", "Leading zeros"),
		Rejection("a float with leading zeros", "00.5", "Leading zeros"),
		Rejection("a float with a leading zero", "01.5", "Leading zeros"),
		Rejection("an exponent float with a leading zero", "01e3", "Leading zeros"),
		Rejection("an exponent with a leading zero", "1e05", "Leading zeros"),
		Rejection("a negative exponent with a leading zero", "1e-05", "Leading zeros"),
		Rejection("an exponent of two zeros", "1e00", "Leading zeros"),
		Rejection("a negative zero exponent", "1e-0", "e0"),
		Rejection("a negative zero exponent with a fraction", "1.5e-0", "e0"),
		Rejection("an exponent of zeros with an underscore", "1e0_0", "Leading zeros"),
		Rejection("a fraction with an exponent with a leading zero", "1.5e07", "Leading zeros"),
		Rejection("minus zero", "-0", "“-0” is not allowed, because zero has one spelling: 0"),
		Rejection("a plus sign", "+1", "A “+” sign is not allowed. A number without a sign is positive"),
		Rejection("a plus sign on zero", "+0", "A “+” sign is not allowed. A number without a sign is positive"),
		Rejection("a plus sign on infinity", "+infinity", "A “+” sign is not allowed. A number without a sign is positive"),
		Rejection("a plus sign in an exponent", "1e+5", "exponent"),
		Rejection("an uppercase exponent", "1E5", "An exponent marker is a lowercase “e”"),
		Rejection("an exponent with no digits", "1e", "Expected digits after the exponent marker “e”"),
		Rejection("an exponent with only a sign", "1e-", "Expected digits after the exponent marker “e”"),
		Rejection("a leading dot", ".5", "A number cannot begin with “.”; write a digit before it, as in 0.5"),
		Rejection("a negative leading dot", "-.5", "A number cannot begin with “.”; write a digit before it, as in -0.5"),
		Rejection("a trailing dot", "5.", "A decimal point must be followed by a digit"),
		Rejection("a dot before an exponent", "5.e3", "A decimal point must be followed by a digit"),
		Rejection("two dots", "1.2.3", "Invalid number “1.2.3”. A value with several dots, such as a version number, must be quoted"),
		Rejection("a version", "10.23.1", "Invalid number “10.23.1”. A value with several dots, such as a version number, must be quoted"),
		Rejection("a lone minus", "-", "Expected a digit or “infinity” after “-”"),
		Rejection("a leading underscore", "_1", "Unexpected “_1”. A string value must be quoted, as in '_1'"),
		Rejection("a trailing underscore", "1_", "underscore"),
		Rejection("a doubled underscore", "1__0", "underscore"),
		Rejection("an underscore before the dot", "1_.5", "underscore"),
		Rejection("an underscore after the dot", "1._5", "underscore"),
		Rejection("an underscore before the exponent", "1_e5", "underscore"),
		Rejection("an underscore after the exponent marker", "1e_5", "underscore"),
		Rejection("an underscore at the end of an exponent", "1e5_", "underscore"),
		Rejection("an underscore after a prefix", "0x_FF", "underscore"),
		Rejection("an underscore at the end of a hex int", "0xFF_", "underscore"),
		Rejection("a doubled underscore in a hex int", "0xF__F", "underscore"),
		Rejection("a prefix with no digits", "0x", "Expected hexadecimal digits"),
		Rejection("an octal prefix with no digits", "0o", "Expected octal digits"),
		Rejection("a binary prefix with no digits", "0b", "Expected binary digits"),
		Rejection("lowercase hex digits", "0xff", "uppercase"),
		Rejection("mixed case hex digits", "0xFf", "uppercase"),
		Rejection("a non-hex letter", "0xFG", "Invalid hexadecimal digit “G”"),
		Rejection("an 8 in octal", "0o8", "Invalid octal digit “8”"),
		Rejection("a 2 in binary", "0b102", "Invalid binary digit “2”"),
		Rejection("an uppercase X prefix", "0XFF", "lowercase"),
		Rejection("an uppercase O prefix", "0O7", "lowercase"),
		Rejection("an uppercase B prefix", "0B1", "lowercase"),
		Rejection("a negative hex int", "-0x1", "cannot have a sign"),
		Rejection("a hex float", "0x1.8p3", "Invalid hexadecimal digit “.”"),
		Rejection("a float with a prefix", "0b1.0", "Invalid binary digit “.”"),
		Rejection("a number followed by a letter", "12abc", "Invalid number “12abc”. A string value must be quoted, as in '12abc'"),
		Rejection("a number with an exponent and a unit", "1e3s", "Invalid number “1e3s”. A string value must be quoted, as in '1e3s'"),
		Rejection("a percentage", "50%", "Unexpected “%” after a value"),
		Rejection("a time", "14:00", "A time of day is a string, so it must be quoted"),
		Rejection("NaN", "NaN", "NaN"),
		Rejection("nan", "nan", "NaN"),
		Rejection("negative nan", "-nan", "NaN"),
		Rejection("inf", "inf", "“inf” is not a value. Infinity is written infinity, in lowercase"),
		Rejection("Infinity", "Infinity", "lowercase"),
		Rejection("INFINITY", "INFINITY", "lowercase"),
		Rejection("negative Infinity", "-Infinity", "“-Infinity” is not a value. Negative infinity is written -infinity"),
		Rejection("a thousands comma", "1,000", "not commas"),
	]

	@Test(arguments: rejected)
	func `rejects an invalid number`(_ rejection: Rejection) {
		expectRejected("value: \(rejection.source)", rejection.message)
	}

	@Test
	func `a number is followed by a separator, not by another token`() throws {
		#expect(try parse("[1,2,3]") == [1, 2, 3])
		#expect(try parse("{a:1,b:2.5}") == ["a": 1, "b": 2.5])
		#expect(try parse("a: 1#comment") == ["a": 1])
		#expect(try parse("a: 1/* comment */") == ["a": 1])
		#expect(try parse("[1/* comment */,2]") == [1, 2])
		expectRejected("[1 2]", "Expected “,”, a line break, or “]” after an array item, but found “2”")
		expectRejected("[1'a']", "Unexpected “'” after a value")
	}

	@Test
	func `the error is at the start of the number, as in the reference, and the message names the bad part`() throws {
		for (source, fragment) in [("0xFg", "“g”"), ("1__0", "underscore"), ("1E5", "lowercase “e”")] {
			let error = try #require(scalarError(source))
			#expect(error.location.column == 8)
			#expect(error.message.contains(fragment), "\(error.message)")
		}
	}
}

import Foundation
import Testing
@testable import SOML

@Suite
struct DurationTests {
	static let valid: [(String, Int64, String)] = [
		("0s", 0, "0s"),
		("0ns", 0, "0s"),
		("0h0m", 0, "0s"),
		("0.0s", 0, "0s"),
		("1ns", 1, "0.000000001s"),
		("250us", 250_000, "0.00025s"),
		("10ms", 10_000_000, "0.01s"),
		("30s", 30_000_000_000, "30s"),
		("1h30m", 5_400_000_000_000, "1h30m"),
		("90m", 5_400_000_000_000, "1h30m"),
		("5400s", 5_400_000_000_000, "1h30m"),
		("1500ms", 1_500_000_000, "1.5s"),
		("1_000ms", 1_000_000_000, "1s"),
		("1h0m", 3_600_000_000_000, "1h"),
		("1m1ms", 60_001_000_000, "1m0.001s"),
		("1h2m3s4ms5us6ns", 3_723_004_005_006, "1h2m3.004005006s"),
		("24h", 86_400_000_000_000, "24h"),
		("8760h", 31_536_000_000_000_000, "8760h"),
		("-5m", -300_000_000_000, "-5m"),
		("-1h30m", -5_400_000_000_000, "-1h30m"),
		("-90m", -5_400_000_000_000, "-1h30m"),
		("1_000_000ns", 1_000_000, "0.001s"),
		("1.5s", 1_500_000_000, "1.5s"),
		("1.50s", 1_500_000_000, "1.5s"),
		("1.0s", 1_000_000_000, "1s"),
		("1.000ns", 1, "0.000000001s"),
		("1.500000000000000000000s", 1_500_000_000, "1.5s"),
		("1.5_000_000_000_000_000s", 1_500_000_000, "1.5s"),
		("0.000_000_001_000_000_000_000s", 1, "0.000000001s"),
		("1.5h", 5_400_000_000_000, "1h30m"),
		("0.1h", 360_000_000_000, "6m"),
		("1h1.5m", 3_690_000_000_000, "1h1m30s"),
		("2.5ms", 2_500_000, "0.0025s"),
		("1.5us", 1500, "0.0000015s"),
		("-0.25s", -250_000_000, "-0.25s"),
		("0.000000001s", 1, "0.000000001s"),
		("1_000.000_5ms", 1_000_000_500, "1.0000005s"),
		("0.00000000005m", 3, "0.000000003s"),
		("0.0000000000025h", 9, "0.000000009s"),
		("59m59.999999999s", 3_599_999_999_999, "59m59.999999999s"),
		("9223372036854775807ns", .max, "2562047h47m16.854775807s"),
		("1_000_000_000_000_000_000ns", 1_000_000_000_000_000_000, "277777h46m40s"),
		("2562047h47m16s854ms775us807ns", .max, "2562047h47m16.854775807s"),
		("2562047h47m16.854775807s", .max, "2562047h47m16.854775807s"),
		("-9223372036854775808ns", .min, "-2562047h47m16.854775808s"),
		("-2562047h47m16s854ms775us808ns", .min, "-2562047h47m16.854775808s"),
		("-2562047h47m16.854775808s", .min, "-2562047h47m16.854775808s"),
	]

	@Test(arguments: valid)
	func `parses a duration and writes its canonical form`(_ source: String, _ nanoseconds: Int64, _ canonicalForm: String) throws {
		let value = try parseScalar(source)
		#expect(value == .duration(.nanoseconds(nanoseconds)))
		#expect(value.description == canonicalForm)
		#expect(try canonical("a: \(source)") == "a: \(canonicalForm)\n")
		#expect(try parseScalar(canonicalForm) == value)
	}

	@Test
	func `a duration is a separate type`() throws {
		#expect(try parseScalar("30s") != .int(30_000_000_000))
		#expect(try parseScalar("30s").durationValue == .seconds(30))
		#expect(try parseScalar("30s").intValue == nil)
	}

	@Test
	func `a duration in containers and before a comment`() throws {
		#expect(try parse("a: [1s, 2m,]") == ["a": [.duration(.seconds(1)), .duration(.seconds(120))]])
		#expect(try parse("{a: 1s}") == ["a": .duration(.seconds(1))])
		#expect(try parse("{a:1s,b:2s}") == ["a": .duration(.seconds(1)), "b": .duration(.seconds(2))])
		#expect(try parse("a: 1s # one second") == ["a": .duration(.seconds(1))])
		#expect(try parse("a: 1s/* one second */") == ["a": .duration(.seconds(1))])
	}

	@Test
	func `a key is never a duration`() throws {
		let value = try parse("1h30m: 1h30m")
		#expect(value == ["1h30m": .duration(.seconds(5400))])
		#expect(try canonical(value) == "1h30m: 1h30m\n")
	}

	static let rejected: [Rejection] = [
		Rejection("a leading zero", "05m", "Invalid duration 05m: leading zeros are not allowed"),
		Rejection("a leading zero in a later part", "1h05m", "Invalid duration 1h05m: leading zeros are not allowed"),
		Rejection("a fraction before the last part", "1.5h30m", "Invalid duration 1.5h30m: only the last part may have a fraction"),
		Rejection("two fractions", "1.5h1.5m", "Invalid duration 1.5h1.5m: only the last part may have a fraction"),
		Rejection("a version with a unit", "1.5.5s", "Invalid number “1.5.5s”. A value with several dots, such as a version number, must be quoted"),
		Rejection("half a nanosecond", "0.5ns", "Invalid duration 0.5ns: it is not a whole number of nanoseconds"),
		Rejection("a fraction finer than a nanosecond", "1.0000000001s", "is not a whole number of nanoseconds"),
		Rejection("a fraction of milliseconds finer than a nanosecond", "1.0000005ms", "is not a whole number of nanoseconds"),
		Rejection("a long fraction finer than a nanosecond", "1.\(String(repeating: "0", count: 100))1s", "is not a whole number of nanoseconds"),
		Rejection("a trailing dot", "1.s", "Invalid duration 1.s: a “.” must be followed by a digit"),
		Rejection("a leading dot", ".5s", "A number cannot begin with “.”; write a digit before it, as in 0.5"),
		Rejection("a leading zero before a fraction", "01.5s", "Invalid duration 01.5s: leading zeros are not allowed"),
		Rejection("an underscore after the dot", "1._5s", "Invalid duration 1._5s: a “.” must be followed by a digit"),
		Rejection("an underscore before the dot", "1_.5s", "underscore"),
		Rejection("a trailing underscore in a fraction", "1.5_s", "underscore"),
		Rejection("an exponent in a fraction", "1.5e3s", "Invalid number “1.5e3s”. A string value must be quoted, as in '1.5e3s'"),
		Rejection("negative zero with a fraction", "-0.0s", "Invalid duration -0.0s: “-” is not allowed before zero, because zero has one spelling: 0s"),
		Rejection("a fraction above the maximum", "2562047h47m16.854775808s", "Invalid duration 2562047h47m16.854775808s: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("a fraction below the minimum", "-2562047h47m16.854775809s", "Invalid duration -2562047h47m16.854775809s: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("a fraction with a day", "1.5d", "Invalid duration 1.5d: there is no day unit, because a day is not a fixed length. Write 24h for a fixed 24 hours"),
		Rejection("a day", "1d", "Invalid duration 1d: there is no day unit, because a day is not a fixed length. Write 24h for a fixed 24 hours"),
		Rejection("a week", "1w", "Invalid duration 1w: there is no week unit, because a day is not a fixed length. Write 168h for a fixed 168 hours"),
		Rejection("a spelled out day", "2days", "Invalid duration 2days: there is no day unit, because a day is not a fixed length. Write 24h for a fixed 24 hours"),
		Rejection("an uppercase unit", "1H", "Invalid duration 1H: the units are lowercase: h"),
		Rejection("an uppercase multi-letter unit", "1MS", "Invalid duration 1MS: the units are lowercase: ms"),
		Rejection("an unknown unit", "10sec", "Invalid duration 10sec: “sec” is not a unit. The units are h, m, s, ms, us, and ns, and a string must be quoted"),
		Rejection("a unit with no number", "1hm", "Invalid duration 1hm: “hm” is not a unit. The units are h, m, s, ms, us, and ns, and a string must be quoted"),
		Rejection("units out of order", "30m1h", "Invalid duration 30m1h: the units are in the order h, m, s, ms, us, ns, and each appears at most once"),
		Rejection("milliseconds before seconds", "1ms1s", "Invalid duration 1ms1s: the units are in the order h, m, s, ms, us, ns, and each appears at most once"),
		Rejection("a repeated unit", "1m1m", "Invalid duration 1m1m: the units are in the order h, m, s, ms, us, ns, and each appears at most once"),
		Rejection("a missing last unit", "1h30", "Invalid duration 1h30: every number needs a unit: h, m, s, ms, us, or ns"),
		Rejection("a sign on a later part", "1h-30m", "Invalid duration 1h-30m: only the whole duration takes a sign, as in -1h30m"),
		Rejection("a plus between parts", "1h+30m", "Invalid duration 1h+30m: a “+” sign is not allowed"),
		Rejection("a leading plus", "+1h", "A “+” sign is not allowed. A number without a sign is positive"),
		Rejection("a trailing underscore", "1_s", "underscore"),
		Rejection("a doubled underscore", "1__000ms", "underscore"),
		Rejection("an underscore before a later part", "1h_30m", "Invalid duration 1h_30m: expected a number at “_30m”"),
		Rejection("negative zero", "-0s", "Invalid duration -0s: “-” is not allowed before zero, because zero has one spelling: 0s"),
		Rejection("negative zero in several parts", "-0h0m", "Invalid duration -0h0m: “-” is not allowed before zero, because zero has one spelling: 0s"),
		Rejection("above the maximum", "9223372036854775808ns", "Invalid duration 9223372036854775808ns: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("below the minimum", "-9223372036854775809ns", "Invalid duration -9223372036854775809ns: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("hours above the maximum", "2562048h", "Invalid duration 2562048h: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("parts that add up to above the maximum", "2562047h47m16s854ms775us808ns", "Invalid duration 2562047h47m16s854ms775us808ns: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("a huge part", "100000000000000000000000000000000000000000ns", "Invalid duration 1000000000000000000000000000000000000000…: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("a part of twenty nines", "99999999999999999999ns", "Invalid duration 99999999999999999999ns: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("a part of twenty nines in hours", "99999999999999999999h", "Invalid duration 99999999999999999999h: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("a part of nineteen nines in hours", "9999999999999999999h", "Invalid duration 9999999999999999999h: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("a part of nineteen digits in microseconds", "1_000_000_000_000_000_000us", "Invalid duration 1_000_000_000_000_000_000us: it is outside the 64-bit range of nanoseconds, about 292 years either way"),
		Rejection("the micro sign", "1µs", "written us"),
		Rejection("the Greek mu", "1μs", "The unit for microseconds is written us, as in 1us"),
		Rejection("a space before the unit", "1 s", "A unit cannot follow a number after a space. Write a duration without the space, as in 1s, and anything else, such as a size, as a string, as in '1 s'"),
		Rejection("a space between parts", "1h 30m", "Expected a line break"),
		Rejection("a radix prefix", "0x10s", "Invalid hexadecimal digit “s”"),
		Rejection("an exponent", "1e3s", "Invalid number “1e3s”. A string value must be quoted, as in '1e3s'"),
		Rejection("a dot after a unit", "1h.5m", "Invalid duration 1h.5m: expected a number at “.5m”"),
		Rejection("a version with a suffix", "1.2.3-beta", "Invalid number “1.2.3-beta”. A value with several dots, such as a version number, must be quoted"),
		Rejection("a version with a letter", "2.1.0b1", "Invalid number “2.1.0b1”. A value with several dots, such as a version number, must be quoted"),
	]

	@Test(arguments: rejected)
	func `rejects an invalid duration`(_ rejection: Rejection) {
		expectRejected("value: \(rejection.source)", rejection.message)
	}

	@Test
	func `the error is at the start of the duration, as in the reference, and the message names the bad part`() throws {
		for (source, fragment) in [("30m1h", "the units are in the order"), ("1h05m", "leading zeros are not allowed"), ("-9223372036854775809ns", "outside the 64-bit range"), ("1.5h30m", "only the last part"), ("1h0.5ns", "whole number of nanoseconds"), ("1m1m", "each appears at most once"), ("10sec", "“sec” is not a unit")] {
			let error = try #require(scalarError(source))
			#expect(error.location.column == 8)
			#expect(error.message.contains(fragment), "\(error.message)")
		}
	}

	static let precedence: [Rejection] = [
		Rejection("a bad unit after a part out of range", "2562048h30x", "Invalid duration 2562048h30x: “x” is not a unit. The units are h, m, s, ms, us, and ns, and a string must be quoted"),
		Rejection("a repeated unit after a part out of range", "2562048h1h", "Invalid duration 2562048h1h: the units are in the order h, m, s, ms, us, ns, and each appears at most once"),
		Rejection("a trailing minus after a fraction", "1.5s-", "Invalid duration 1.5s-: expected a number at “-”"),
		Rejection("a trailing minus", "30s-", "Invalid duration 30s-: expected a number at “-”"),
		Rejection("a missing unit after a fraction", "1.5s5", "Invalid duration 1.5s5: only the last part may have a fraction"),
		Rejection("a trailing minus after a fraction finer than a nanosecond", "0.5ns-", "Invalid duration 0.5ns-: expected a number at “-”"),
		Rejection("a fraction finer than a nanosecond and out of range", "-9223372036854775809ns0.5ns", "Invalid duration -9223372036854775809ns0.5ns: the units are in the order h, m, s, ms, us, ns, and each appears at most once"),
		Rejection("negative zero with a fraction finer than a nanosecond", "-0.1ns", "is not a whole number of nanoseconds"),
	]

	/**
	The syntax of every part is checked before the value, so the error names the real problem.
	*/
	@Test(arguments: precedence)
	func `a syntax error comes before a value error`(_ rejection: Rejection) {
		expectRejected("value: \(rejection.source)", rejection.message)
	}

	@Test
	func `an error message does not repeat a huge token`() throws {
		let sources = [
			"-0." + String(repeating: "0", count: 100_000) + "s",
			"1" + String(repeating: "s", count: 100_000),
			String(repeating: "1", count: 100_000) + "h1",
			"1." + String(repeating: "0", count: 100_000) + "1s",
			String(repeating: "9", count: 100_000) + "h",
		]

		for source in sources {
			let error = try #require(scalarError(source))
			#expect(error.message.count < 300, "\(error.message.prefix(300))")
		}
	}

	@Test
	func `a bare duration is not a document`() {
		expectRejected("1h30m", "A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`")
	}

	@Test
	func `a duration SOML cannot hold is not written`() throws {
		let half = Duration.nanoseconds(1) / 2
		let large = Duration.seconds(Int64.max)
		#expect(throws: EncodingError.self) {
			try canonical(["a": .duration(half)])
		}
		#expect(throws: EncodingError.self) {
			try canonical(["a": .duration(large)])
		}

		// A description still shows it.
		#expect(SOML.Value.duration(half).description == String(describing: half))
	}
}

@Suite
struct DurationCodingTests {
	struct Config: Codable, Equatable {
		var timeout: Duration
	}

	@Test
	func `a Duration property is written as a duration, not as Duration's two integers`() throws {
		let config = Config(timeout: .seconds(5400))
		let text = try SOML.Encoder().encodeToString(config)
		#expect(text == "timeout: 1h30m\n")
		#expect(try SOML.Decoder().decode(Config.self, from: text) == config)
	}

	@Test
	func `durations in containers round-trip`() throws {
		struct Model: Codable, Equatable {
			var list: [Duration]
			var map: [String: Duration]
			var optional: Duration?
		}

		let model = Model(list: [.zero, .milliseconds(-1500), .nanoseconds(Int64.min), .nanoseconds(Int64.max)], map: ["a": .microseconds(250)], optional: .seconds(1))
		let text = try SOML.Encoder().encodeToString(model)
		#expect(text.contains("\t-1.5s\n"))
		#expect(text.contains("\t-2562047h47m16.854775808s\n"))
		#expect(try SOML.Decoder().decode(Model.self, from: text) == model)
		#expect(try SOML.Encoder().encodeToValue(Duration.seconds(1)) == .duration(.seconds(1)))
		#expect(try SOML.Decoder().decode(Duration.self, from: .duration(.seconds(1))) == .seconds(1))
	}

	@Test
	func `optional durations and a dictionary under a key strategy`() throws {
		struct Model: Codable, Equatable {
			var missing: Duration?
			var items: [Duration?]
			var timeouts: [String: Duration]
		}

		let model = Model(missing: nil, items: [.seconds(1), nil], timeouts: ["readTimeout": .milliseconds(1500)])
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		let text = try encoder.encodeToString(model)
		#expect(text == "items: [\n\t1s\n\tnull\n]\ntimeouts: {\n\treadTimeout: 1.5s\n}\n")
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		#expect(try decoder.decode(Model.self, from: text) == model)
	}

	@Test
	func `a Duration that SOML cannot hold is an encoding error`() throws {
		let cases: [(Duration, String)] = [
			(.nanoseconds(1) / 2, "fraction of a nanosecond"),
			(Duration(attoseconds: 1), "fraction of a nanosecond"),
			(.seconds(Int64.max), "outside the range of a SOML duration"),
			(.nanoseconds(Int64.min) - .nanoseconds(1), "outside the range of a SOML duration"),
		]

		for (duration, fragment) in cases {
			do {
				_ = try SOML.Encoder().encode(Config(timeout: duration))
				Issue.record("Expected an error for \(duration)")
			} catch EncodingError.invalidValue(_, let context) {
				#expect(context.debugDescription.contains(fragment), "\(context.debugDescription)")
				#expect(context.codingPath.map(\.stringValue) == ["timeout"])
			}
		}
	}

	@Test
	func `only a duration decodes as a Duration`() throws {
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(Config.self, from: "timeout: 30")
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(Config.self, from: "timeout: '30s'")
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(Config.self, from: "timeout: [30, 0]")
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode([String: Int].self, from: "timeout: 30s")
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode([String: String].self, from: "timeout: 30s")
		}

		do {
			_ = try SOML.Decoder().decode(Config.self, from: "timeout: 30")
			Issue.record("Expected an error")
		} catch DecodingError.typeMismatch(_, let context) {
			#expect(context.debugDescription == "Expected a duration for Duration, but found the int 30 (line 1, column 1)")
		}
	}

	@Test
	func `other encoders get the canonical text`() throws {
		let value: SOML.Value = ["timeout": .duration(.seconds(5400))]
		#expect(String(decoding: try JSONEncoder().encode(value), as: UTF8.self) == #"{"timeout":"1h30m"}"#)
		#expect(String(decoding: try JSONEncoder().encode(["timeout": Duration.seconds(5)]), as: UTF8.self) == #"{"timeout":[0,5000000000000000000]}"#)
		#expect(throws: EncodingError.self) {
			try JSONEncoder().encode(SOML.Value.array([.duration(Duration(attoseconds: 1))]))
		}
	}

	/**
	Calls `Duration.encode(to:)` directly, with a super encoder for one key and with the encoder itself for the other.
	*/
	struct DirectDuration: Encodable {
		enum CodingKeys: CodingKey {
			case viaSuperEncoder
			case viaContainer
		}

		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try Duration.seconds(5).encode(to: container.superEncoder(forKey: .viaSuperEncoder))
			try container.encode(Duration.seconds(5), forKey: .viaContainer)
		}
	}

	/**
	Calls `Duration.encode(to:)` with its own encoder.
	*/
	struct WholeDuration: Encodable {
		func encode(to encoder: any Encoder) throws {
			try Duration.seconds(5).encode(to: encoder)
		}
	}

	@Test
	func `a Duration that encodes itself directly with an encoder gets its own two integers`() throws {
		#expect(try SOML.Encoder().encodeToString(DirectDuration()) == "viaSuperEncoder: [\n\t0\n\t5000000000000000000\n]\nviaContainer: 5s\n")
		#expect(try SOML.Encoder().encodeToString(WholeDuration()) == "[\n\t0\n\t5000000000000000000\n]\n")
	}
}

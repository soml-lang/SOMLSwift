import Foundation
import Testing
@testable import SOML

@Suite
struct InstantTests {
	static let valid: [(String, String)] = [
		("2026-09-19T14:00:00Z", "2026-09-19T14:00:00Z"),
		("2026-09-19T14:00:00+00:00", "2026-09-19T14:00:00Z"),
		("2026-09-19T16:00:00+02:00", "2026-09-19T14:00:00Z"),
		("2026-09-19T08:30:00-05:30", "2026-09-19T14:00:00Z"),
		("2026-09-19T14:00:00.5Z", "2026-09-19T14:00:00.5Z"),
		("2026-09-19T14:00:00.500Z", "2026-09-19T14:00:00.5Z"),
		("2026-09-19T14:00:00.000Z", "2026-09-19T14:00:00Z"),
		("2026-09-19T14:00:00.000000001Z", "2026-09-19T14:00:00.000000001Z"),
		("2026-09-19T14:00:00.123456789Z", "2026-09-19T14:00:00.123456789Z"),
		("2026-09-19T14:00:00.120Z", "2026-09-19T14:00:00.12Z"),
		("2026-01-01T00:30:00+01:00", "2025-12-31T23:30:00Z"),
		("2025-12-31T23:30:00-01:00", "2026-01-01T00:30:00Z"),
		("2024-03-01T00:00:00+00:01", "2024-02-29T23:59:00Z"),
		("2024-02-29T12:00:00Z", "2024-02-29T12:00:00Z"),
		("2000-02-29T00:00:00Z", "2000-02-29T00:00:00Z"),
		("1970-01-01T00:00:00Z", "1970-01-01T00:00:00Z"),
		("1969-12-31T23:59:59.999999999Z", "1969-12-31T23:59:59.999999999Z"),
		("0001-01-01T00:00:00Z", "0001-01-01T00:00:00Z"),
		("0001-01-01T00:00:00-01:00", "0001-01-01T01:00:00Z"),
		("9999-12-31T23:59:59.999999999Z", "9999-12-31T23:59:59.999999999Z"),
		("9999-12-31T22:59:59+01:00", "9999-12-31T21:59:59Z"),
		("2026-09-19T14:00:00+23:59", "2026-09-18T14:01:00Z"),
		("2026-09-19T14:00:00-23:59", "2026-09-20T13:59:00Z"),
		("1582-10-10T00:00:00Z", "1582-10-10T00:00:00Z"),
		("1900-03-01T00:00:00Z", "1900-03-01T00:00:00Z"),
	]

	@Test(arguments: valid)
	func `parses an instant and normalises it to UTC`(_ source: String, _ canonicalForm: String) throws {
		let instant = try #require(try parseScalar(source).instantValue)
		#expect(instant.description == canonicalForm)
		#expect(SOML.Instant(source) == instant)
		#expect(SOML.Instant(canonicalForm) == instant)
	}

	@Test
	func `two spellings of one instant are the same value`() throws {
		#expect(try parseScalar("2026-09-19T14:00:00Z") == parseScalar("2026-09-19T16:00:00+02:00"))
		#expect(try parseScalar("2026-09-19T14:00:00Z") == parseScalar("2026-09-19T14:00:00.000Z"))
		#expect(try parseScalar("2026-09-19T14:00:00Z") == parseScalar("2026-09-19T14:00:00+00:00"))
	}

	static let invalid: [Rejection] = [
		Rejection("a date only", "2026-09-19", "2026-09-19 is a date, not an instant. Write a date as a string, as in '2026-09-19'. An instant needs a time and an offset, as in 2026-09-19T00:00:00Z"),
		Rejection("no seconds", "2026-09-19T14:00Z", "Invalid instant “2026-09-19T14:00Z”. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		Rejection("no offset", "2026-09-19T14:00:00", "needs an offset"),
		Rejection("no offset after a fraction", "2026-09-19T14:00:00.5", "needs an offset"),
		Rejection("a lowercase t", "2026-09-19t14:00:00Z", "The date and time separator in an instant is an uppercase “T”"),
		Rejection("a space separator", "2026-09-19 14:00:00Z", "The date and time separator in an instant is an uppercase “T”, not a space, as in 2026-09-19T14:00:00Z"),
		Rejection("a lowercase z", "2026-09-19T14:00:00z", "The UTC offset in an instant is an uppercase “Z”"),
		Rejection("an offset without a colon", "2026-09-19T14:00:00+0200", "An instant's offset is written with a colon, as in +07:00"),
		Rejection("an offset with only hours", "2026-09-19T14:00:00+02", "±HH:MM"),
		Rejection("the unknown offset", "2026-09-19T14:00:00-00:00", "Invalid instant 2026-09-19T14:00:00-00:00: -00:00 means “offset unknown” in RFC 3339, which is not representable; use Z or +00:00"),
		Rejection("a ten digit fraction", "2026-09-19T14:00:00.1234567890Z", "Invalid instant 2026-09-19T14:00:00.1234567890Z: a fractional second has at most nine digits"),
		Rejection("an empty fraction", "2026-09-19T14:00:00.Z", "Invalid instant “2026-09-19T14:00:00.Z”. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		Rejection("a one digit month", "2026-9-19T14:00:00Z", "Invalid number “2026-9-19T14:00:00Z”. A string value must be quoted, as in '2026-9-19T14:00:00Z'"),
		Rejection("a two digit year", "26-09-19T14:00:00Z", "Invalid number “26-09-19T14:00:00Z”. A string value must be quoted, as in '26-09-19T14:00:00Z'"),
		Rejection("a five digit year", "12026-09-19T14:00:00Z", "Invalid number “12026-09-19T14:00:00Z”. A string value must be quoted, as in '12026-09-19T14:00:00Z'"),
		Rejection("year zero", "0000-01-01T00:00:00Z", "year must be"),
		Rejection("month zero", "2026-00-01T00:00:00Z", "month must be"),
		Rejection("month thirteen", "2026-13-01T00:00:00Z", "month must be"),
		Rejection("day zero", "2026-01-00T00:00:00Z", "Invalid instant 2026-01-00T00:00:00Z: the day must be 01 to 31 in that month"),
		Rejection("January 32", "2026-01-32T00:00:00Z", "Invalid instant 2026-01-32T00:00:00Z: the day must be 01 to 31 in that month"),
		Rejection("April 31", "2026-04-31T00:00:00Z", "Invalid instant 2026-04-31T00:00:00Z: the day must be 01 to 30 in that month"),
		Rejection("June 31", "2026-06-31T00:00:00Z", "Invalid instant 2026-06-31T00:00:00Z: the day must be 01 to 30 in that month"),
		Rejection("September 31", "2026-09-31T00:00:00Z", "Invalid instant 2026-09-31T00:00:00Z: the day must be 01 to 30 in that month"),
		Rejection("November 31", "2026-11-31T00:00:00Z", "Invalid instant 2026-11-31T00:00:00Z: the day must be 01 to 30 in that month"),
		Rejection("February 29 in 2026", "2026-02-29T00:00:00Z", "Invalid instant 2026-02-29T00:00:00Z: the day must be 01 to 28 in that month"),
		Rejection("February 29 in 2100", "2100-02-29T00:00:00Z", "Invalid instant 2100-02-29T00:00:00Z: the day must be 01 to 28 in that month"),
		Rejection("February 30 in a leap year", "2024-02-30T00:00:00Z", "Invalid instant 2024-02-30T00:00:00Z: the day must be 01 to 29 in that month"),
		Rejection("hour 24", "2026-01-01T24:00:00Z", "hour must be"),
		Rejection("minute 60", "2026-01-01T00:60:00Z", "minute must be"),
		Rejection("second 60", "2026-12-31T23:59:60Z", "leap second"),
		Rejection("second 61", "2026-12-31T23:59:61Z", "second must be"),
		Rejection("offset hour 24", "2026-01-01T00:00:00+24:00", "offset hour"),
		Rejection("offset minute 60", "2026-01-01T00:00:00+00:60", "offset minute"),
		Rejection("text after the offset", "2026-01-01T00:00:00Zx", "Invalid instant “2026-01-01T00:00:00Zx”. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		Rejection("a second offset", "2026-01-01T00:00:00Z+01:00", "Invalid instant “2026-01-01T00:00:00Z+01:00”. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"),
		Rejection("before year 1 in UTC", "0001-01-01T00:00:00+00:01", "Invalid instant 0001-01-01T00:00:00+00:01: in UTC it falls outside the years 0001 to 9999"),
		Rejection("after year 9999 in UTC", "9999-12-31T23:59:59-00:01", "Invalid instant 9999-12-31T23:59:59-00:01: in UTC it falls outside the years 0001 to 9999"),
		Rejection("a week date", "2026-W38-6T00:00:00Z", "Invalid number “2026-W38-6T00:00:00Z”. A string value must be quoted, as in '2026-W38-6T00:00:00Z'"),
		Rejection("an ordinal date", "2026-262T00:00:00Z", "Invalid number “2026-262T00:00:00Z”. A string value must be quoted, as in '2026-262T00:00:00Z'"),
	]

	@Test(arguments: invalid)
	func `rejects an invalid instant`(_ rejection: Rejection) {
		expectRejected("value: \(rejection.source)", rejection.message)
		#expect(SOML.Instant(rejection.source) == nil)
	}

	@Test
	func `the error is at the start of the instant, as in the reference, and the message names the bad component`() throws {
		for (source, fragment) in [("2026-13-01T00:00:00Z", "month"), ("2026-01-01T00:00:60Z", "leap second"), ("2026-01-01T00:00:00+24:00", "offset hour")] {
			let error = try #require(scalarError(source))
			#expect(error.location.column == 8)
			#expect(error.message.contains(fragment), "\(error.message)")
		}
	}

	@Test
	func `every day of a leap year and a common year exists exactly once`() throws {
		for year in [2023, 2024] {
			var previous: SOML.Instant?

			for month in 1...12 {
				for day in 1...31 {
					let text = "\(year)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day)T00:00:00Z"

					guard let instant = SOML.Instant(text) else {
						continue
					}

					if let previous {
						#expect(instant.secondsSince1970 - previous.secondsSince1970 == 86_400, "\(text)")
					}

					#expect(instant.description == text)
					previous = instant
				}
			}

			#expect(previous?.description == "\(year)-12-31T00:00:00Z")
		}
	}

	@Test
	func `matches Foundation's calendar across the whole range`() throws {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!

		for year in stride(from: 1601, through: 9999, by: 37) {
			for (month, day) in [(1, 1), (2, 28), (3, 1), (7, 15), (12, 31)] {
				let instant = try #require(SOML.Instant(year: year, month: month, day: day, hour: 13, minute: 7, second: 9))
				let date = try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 13, minute: 7, second: 9)))
				#expect(instant.secondsSince1970 == Int64(date.timeIntervalSince1970), "\(year)-\(month)-\(day)")
			}
		}
	}

	@Test
	func `seconds since 1970`() throws {
		#expect(SOML.Instant("1970-01-01T00:00:00Z")?.secondsSince1970 == 0)
		#expect(SOML.Instant("1970-01-01T00:00:01Z")?.secondsSince1970 == 1)
		#expect(SOML.Instant("1969-12-31T23:59:59Z")?.secondsSince1970 == -1)
		#expect(SOML.Instant("2001-01-01T00:00:00Z")?.secondsSince1970 == 978_307_200)
		#expect(SOML.Instant("2026-09-19T14:00:00Z")?.secondsSince1970 == 1_789_826_400)
		#expect(SOML.Instant.minimum.secondsSince1970 == -62_135_596_800)
		#expect(SOML.Instant.maximum.secondsSince1970 == 253_402_300_799)
		#expect(SOML.Instant.maximum.nanoseconds == 999_999_999)
	}

	@Test
	func `minimum and maximum`() {
		#expect(SOML.Instant.minimum.description == "0001-01-01T00:00:00Z")
		#expect(SOML.Instant.maximum.description == "9999-12-31T23:59:59.999999999Z")
		#expect(SOML.Instant(secondsSince1970: SOML.Instant.minimum.secondsSince1970 - 1) == nil)
		#expect(SOML.Instant(secondsSince1970: SOML.Instant.maximum.secondsSince1970 + 1) == nil)
		#expect(SOML.Instant(secondsSince1970: SOML.Instant.minimum.secondsSince1970) == .minimum)
	}

	@Test
	func `nanoseconds must be in range`() {
		#expect(SOML.Instant(secondsSince1970: 0, nanoseconds: -1) == nil)
		#expect(SOML.Instant(secondsSince1970: 0, nanoseconds: 1_000_000_000) == nil)
		#expect(SOML.Instant(secondsSince1970: 0, nanoseconds: 999_999_999) != nil)
	}

	@Test
	func `components`() throws {
		let instant = try #require(SOML.Instant("2024-02-29T23:59:58.25+00:00"))
		let components = instant.components
		#expect(components.year == 2024)
		#expect(components.month == 2)
		#expect(components.day == 29)
		#expect(components.hour == 23)
		#expect(components.minute == 59)
		#expect(components.second == 58)
		#expect(components.nanosecond == 250_000_000)

		let early = try #require(SOML.Instant("0001-01-01T00:00:00Z")).components
		#expect(early.year == 1)
		#expect(early.month == 1)
		#expect(early.day == 1)
	}

	@Test
	func `component initializer validates`() {
		#expect(SOML.Instant(year: 2026, month: 9, day: 19, hour: 14)?.description == "2026-09-19T14:00:00Z")
		#expect(SOML.Instant(year: 2026, month: 9, day: 19, nanosecond: 1)?.description == "2026-09-19T00:00:00.000000001Z")
		#expect(SOML.Instant(year: 0, month: 1, day: 1) == nil)
		#expect(SOML.Instant(year: 10_000, month: 1, day: 1) == nil)
		#expect(SOML.Instant(year: 2026, month: 2, day: 29) == nil)
		#expect(SOML.Instant(year: 2026, month: 1, day: 1, hour: 24) == nil)
		#expect(SOML.Instant(year: 2026, month: 1, day: 1, minute: 60) == nil)
		#expect(SOML.Instant(year: 2026, month: 1, day: 1, second: 60) == nil)
		#expect(SOML.Instant(year: 2026, month: 1, day: 1, nanosecond: 1_000_000_000) == nil)
		#expect(SOML.Instant(year: 2026, month: 1, day: 1, nanosecond: -1) == nil)
	}

	@Test
	func `ordering`() throws {
		let instants = try ["2026-09-19T14:00:00.000000001Z", "1970-01-01T00:00:00Z", "2026-09-19T14:00:00Z", "1969-12-31T23:59:59.5Z", "0001-01-01T00:00:00Z"].map { try #require(SOML.Instant($0)) }
		#expect(instants.sorted().map(\.description) == ["0001-01-01T00:00:00Z", "1969-12-31T23:59:59.5Z", "1970-01-01T00:00:00Z", "2026-09-19T14:00:00Z", "2026-09-19T14:00:00.000000001Z"])
	}

	@Test
	func `converts to and from Date`() throws {
		let instant = try #require(SOML.Instant("2026-09-19T14:00:00.25Z"))
		#expect(instant.date == Date(timeIntervalSince1970: 1_789_826_400.25))
		#expect(SOML.Instant(instant.date) == instant)
		#expect(SOML.Instant(Date(timeIntervalSince1970: 0))?.description == "1970-01-01T00:00:00Z")
		#expect(SOML.Instant(Date(timeIntervalSince1970: -0.5))?.description == "1969-12-31T23:59:59.5Z")
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: 0.000_000_000_4))?.description == "2001-01-01T00:00:00Z")
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: 0.999_999_999_9))?.description == "2001-01-01T00:00:01Z")
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: -0.000_000_000_4))?.description == "2001-01-01T00:00:00Z")
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: -0.000_000_000_6))?.description == "2000-12-31T23:59:59.999999999Z")
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: -0.1))?.description == "2000-12-31T23:59:59.9Z")
		#expect(SOML.Instant(Date.distantPast) == nil)
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: -.infinity)) == nil)
		#expect(SOML.Instant(Date.distantFuture)?.description == "4001-01-01T00:00:00Z")
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: 1e12)) == nil)
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: -1e12)) == nil)
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: .infinity)) == nil)
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: .nan)) == nil)
		// Large enough to overflow Int64 arithmetic if it were not checked first.
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: 9.2233720368e18)) == nil)
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: -9.2233720368e18)) == nil)
		#expect(SOML.Instant(Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude)) == nil)
	}

	@Test(arguments: [0.001, 0.4, 0.49, 0.6, 1])
	func `a Date just before the minimum is not rounded into range`(_ secondsBefore: Double) {
		#expect(SOML.Instant(SOML.Instant.minimum.date.addingTimeInterval(-secondsBefore)) == nil)
	}

	@Test
	func `the range ends convert from Date`() {
		#expect(SOML.Instant(SOML.Instant.minimum.date) == SOML.Instant.minimum)
		#expect(SOML.Instant(SOML.Instant.maximum.date.addingTimeInterval(-0.5))?.secondsSince1970 == SOML.Instant.maximum.secondsSince1970)
		#expect(SOML.Instant(SOML.Instant.maximum.date.addingTimeInterval(0.001)) == nil)
	}

	@Test
	func `a Date of an instant near the maximum stays in range, so it encodes again`() throws {
		struct Moment: Codable {
			var date: Date
		}

		#expect(SOML.Instant(SOML.Instant.maximum.date)?.secondsSince1970 == SOML.Instant.maximum.secondsSince1970)
		let moment = try SOML.Decoder().decode(Moment.self, from: "date: 9999-12-31T23:59:59.99999Z")
		#expect(try SOML.Encoder().encodeToString(moment).hasPrefix("date: 9999-12-31T23:59:59.9999"))
	}

	@Test
	func `a Date round-trips at microsecond precision near now`() throws {
		var generator = SeededGenerator(seed: 7)

		for _ in 0..<1000 {
			let interval = Double.random(in: -1_000_000_000...1_000_000_000, using: &generator)
			let date = Date(timeIntervalSinceReferenceDate: interval)
			let instant = try #require(SOML.Instant(date))
			#expect(abs(instant.date.timeIntervalSince(date)) < 0.000_001)
		}
	}

	@Test
	func `a Date is as precise as documented far from 2001`() throws {
		// The error of the date of an instant, in seconds, measured from the exact seconds and nanoseconds.
		func error(_ text: String) throws -> Double {
			let instant = try #require(SOML.Instant(text))
			let exact = Double(instant.secondsSince1970 - 978_307_200) + Double(instant.nanoseconds) / 1_000_000_000
			return abs(instant.date.timeIntervalSinceReferenceDate - exact)
		}

		#expect(try error("9999-06-15T12:00:00.123456789Z") < 0.000_016)
		#expect(try error("0001-06-15T12:00:00.123456789Z") < 0.000_016)

		// The last instants of the range are clamped so the date never rounds past the end, which costs up to one step of a `Double` there.
		let end = try error("9999-12-31T23:59:59.999999999Z")
		#expect(end > 0.000_016)
		#expect(end < 0.000_031)
	}

	@Test
	func `description parses back for random instants`() throws {
		var generator = SeededGenerator(seed: 11)

		for _ in 0..<2000 {
			let seconds = Int64.random(in: SOML.Instant.minimum.secondsSince1970...SOML.Instant.maximum.secondsSince1970, using: &generator)
			let nanoseconds = Bool.random(using: &generator) ? 0 : Int.random(in: 0..<1_000_000_000, using: &generator)
			let instant = try #require(SOML.Instant(secondsSince1970: seconds, nanoseconds: nanoseconds))
			#expect(SOML.Instant(instant.description) == instant, "\(instant)")
		}
	}

	@Test
	func `the lossless string initializer rejects anything that is not exactly an instant`() {
		#expect(SOML.Instant("") == nil)
		#expect(SOML.Instant(" 2026-09-19T14:00:00Z") == nil)
		#expect(SOML.Instant("2026-09-19T14:00:00Z ") == nil)
		#expect(SOML.Instant("value: 2026-09-19T14:00:00Z") == nil)
		#expect(SOML.Instant("2026-09-19T14:00:00Z\n") == nil)
		#expect(SOML.Instant("2026-09-19") == nil)
	}

	@Test
	func `codable with other coders uses the canonical string`() throws {
		let instant = try #require(SOML.Instant("2026-09-19T16:00:00.5+02:00"))
		let json = try JSONEncoder().encode([instant])
		#expect(String(decoding: json, as: UTF8.self) == #"["2026-09-19T14:00:00.5Z"]"#)
		#expect(try JSONDecoder().decode([SOML.Instant].self, from: json) == [instant])
		#expect(throws: DecodingError.self) {
			try JSONDecoder().decode([SOML.Instant].self, from: Data(#"["2026-09-19"]"#.utf8))
		}
	}

	@Test
	func `an invalid instant string from another decoder gives a short message`() throws {
		let long = String(repeating: "9", count: 10_000)

		do {
			_ = try JSONDecoder().decode([SOML.Instant].self, from: Data(#"["\#(long)"]"#.utf8))
			Issue.record("Expected an error")
		} catch DecodingError.dataCorrupted(let context) {
			#expect(context.debugDescription.contains("is not a valid SOML instant"))
			#expect(context.debugDescription.utf8.count < 500)
		}
	}
}

/**
A small deterministic random generator, so that randomized tests are reproducible. This is SplitMix64.
*/
struct SeededGenerator: RandomNumberGenerator {
	private var state: UInt64

	init(seed: UInt64) {
		self.state = seed
	}

	mutating func next() -> UInt64 {
		state &+= 0x9E37_79B9_7F4A_7C15
		var value = state
		value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
		value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
		return value ^ (value >> 31)
	}
}

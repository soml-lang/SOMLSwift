#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import struct Foundation.Date

extension SOML {
	/**
	The error for a malformed date or instant token.
	*/
	struct TemporalSyntaxError: Error {
		/**
		What is wrong with a token that has the form of a date or an instant, like `the month must be 01 to 12`, or `nil` when the text does not have the form of one. The text is the same as the reason in the reference implementation.
		*/
		let reason: String?
	}

	/**
	A calendar date in the proleptic Gregorian calendar, without a time or timezone. This is the value of a SOML `date`, distinct from Foundation's `Date`, which represents an instant.

	The year is `1...9999`. Invalid components are rejected rather than normalised.

	```swift
	let birthday = SOML.Date(year: 2000, month: 2, day: 29)!
	print(birthday)
	//=> 2000-02-29
	```
	*/
	public struct Date: Sendable, Hashable, Comparable {
		/**
		The year, from `1` through `9999`.
		*/
		public let year: Int

		/**
		The month, from `1` through `12`.
		*/
		public let month: Int

		/**
		The day, from `1` through the last day of the month.
		*/
		public let day: Int

		/**
		Creates a calendar date, or returns `nil` for invalid components. Validation uses Gregorian arithmetic for every year, independently of the locale and timezone.
		*/
		public init?(year: Int, month: Int, day: Int) {
			guard Self.validationFailure(year: year, month: month, day: day) == nil else {
				return nil
			}

			self.year = year
			self.month = month
			self.day = day
		}

		/**
		Orders dates by year, then month, then day.
		*/
		public static func < (lhs: Self, rhs: Self) -> Bool {
			(lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
		}
	}
}

extension SOML.Date: LosslessStringConvertible {
	/**
	Parses exactly `YYYY-MM-DD` using ASCII digits, or returns `nil` for invalid syntax or components.
	*/
	public init?(_ description: String) {
		guard description.utf8.count == 10 else {
			return nil
		}

		guard let date = description.withUTF8Buffer({ try? Self.parse($0) }) else {
			return nil
		}

		self = date
	}

	/**
	The canonical form, `YYYY-MM-DD`, preserving all three components.
	*/
	public var description: String {
		var output = [UInt8]()
		output.reserveCapacity(10)
		appendCanonical(to: &output)
		return String(decoding: output, as: UTF8.self)
	}

	/**
	Appends the canonical spelling without constructing an intermediate string.
	*/
	func appendCanonical(to output: inout [UInt8]) {
		Self.appendCanonical(
			year: year,
			month: month,
			day: day,
			to: &output
		)
	}

	/**
	Appends a year, a month, and a day as `YYYY-MM-DD`, the date part of the canonical form of a date and of an instant.
	*/
	static func appendCanonical(
		year: Int,
		month: Int,
		day: Int,
		to output: inout [UInt8]
	) {
		output.appendDecimal(UInt64(year), minimumDigitCount: 4)
		output.append(.hyphen)
		output.appendDecimal(UInt64(month), minimumDigitCount: 2)
		output.append(.hyphen)
		output.appendDecimal(UInt64(day), minimumDigitCount: 2)
	}
}

extension SOML.Date: Codable {
	/**
	Decodes a native SOML date. Other decoders read its canonical string, validating it strictly.
	*/
	public init(from decoder: any Swift.Decoder) throws {
		if let decoder = decoder as? DecoderImplementation {
			self = try decoder.unboxDate(decoder.value, key: nil)
			return
		}

		let container = try decoder.singleValueContainer()
		let text = try container.decode(String.self)

		guard let date = Self(text) else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "“\(text.forMessage)” is not a valid SOML date")
		}

		self = date
	}

	/**
	Encodes a native SOML date. Other encoders get its canonical string.
	*/
	public func encode(to encoder: any Swift.Encoder) throws {
		if let encoder = encoder as? EncoderImplementation {
			encoder.result = .value(.date(self))
			return
		}

		var container = encoder.singleValueContainer()
		try container.encode(description)
	}
}

extension SOML.Date {
	/**
	Parses a whole date token, sharing the component checks with instants.
	*/
	static func parse<Bytes: RandomAccessCollection<UInt8>>(_ bytes: Bytes) throws(SOML.TemporalSyntaxError) -> Self where Bytes.Index == Int {
		guard bytes.hasASCIIPattern("0000-00-00") else {
			throw SOML.TemporalSyntaxError(reason: nil)
		}

		let start = bytes.startIndex

		func number(at offset: Int, length: Int) -> Int {
			var value = 0

			for byte in bytes[(start + offset)..<(start + offset + length)] {
				value = value * 10 + Int(byte - .digitZero)
			}

			return value
		}

		let year = number(at: 0, length: 4)
		let month = number(at: 5, length: 2)
		let day = number(at: 8, length: 2)

		guard let date = Self(year: year, month: month, day: day) else {
			throw SOML.TemporalSyntaxError(reason: validationFailure(year: year, month: month, day: day))
		}

		return date
	}

	/**
	The first invalid Gregorian date component, or `nil` when all components are valid. Ranges are checked before calendar arithmetic, including for extreme native integer inputs.
	*/
	static func validationFailure(year: Int, month: Int, day: Int) -> String? {
		guard (1...9999).contains(year) else {
			return "the year must be 0001 to 9999"
		}

		guard (1...12).contains(month) else {
			return "the month must be 01 to 12"
		}

		let lastDay = daysInMonth(year: year, month: month)

		guard (1...lastDay).contains(day) else {
			return "the day must be 01 to \(lastDay) in that month"
		}

		return nil
	}

	/**
	The number of days in a Gregorian month, for a month in `1...12`.
	*/
	static func daysInMonth(year: Int, month: Int) -> Int {
		switch month {
		case 2:
			let isLeapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
			return isLeapYear ? 29 : 28
		case 4, 6, 9, 11:
			return 30
		default:
			return 31
		}
	}
}

extension SOML {
	/**
	A point in time with nanosecond precision. This is the value of a SOML `instant`.

	The offset in the source text is not part of the value, so `2026-09-19T14:00:00Z` and `2026-09-19T16:00:00+02:00` are the same instant.

	The range is `0001-01-01T00:00:00Z` through `9999-12-31T23:59:59.999999999Z`.

	```swift
	let instant = SOML.Instant("2026-09-19T14:00:00.5+02:00")!
	print(instant)
	//=> 2026-09-19T12:00:00.5Z
	```
	*/
	public struct Instant: Sendable, Hashable, Comparable {
		/**
		Whole seconds since 1970-01-01T00:00:00Z.
		*/
		public let secondsSince1970: Int64

		/**
		The fraction of a second, in nanoseconds, from `0` through `999_999_999`.
		*/
		public let nanoseconds: Int

		/**
		The earliest instant SOML can represent: `0001-01-01T00:00:00Z`.
		*/
		public static let minimum = Self(uncheckedSecondsSince1970: Self.minimumSeconds, nanoseconds: 0)

		/**
		The latest instant SOML can represent: `9999-12-31T23:59:59.999999999Z`.
		*/
		public static let maximum = Self(uncheckedSecondsSince1970: Self.maximumSeconds, nanoseconds: 999_999_999)

		private static let minimumSeconds = daysSince1970(year: 1, month: 1, day: 1) * 86_400
		private static let maximumSeconds = daysSince1970(year: 9999, month: 12, day: 31) * 86_400 + 86_399
		private static let secondsFrom1970To2001: Int64 = 978_307_200

		private init(uncheckedSecondsSince1970 seconds: Int64, nanoseconds: Int) {
			self.secondsSince1970 = seconds
			self.nanoseconds = nanoseconds
		}

		/**
		Creates an instant from seconds and nanoseconds since 1970-01-01T00:00:00Z.

		Returns `nil` if `nanoseconds` is not in `0..<1_000_000_000` or if the instant is outside the range SOML can represent.
		*/
		public init?(secondsSince1970: Int64, nanoseconds: Int = 0) {
			guard
				(0..<1_000_000_000).contains(nanoseconds),
				(Self.minimumSeconds...Self.maximumSeconds).contains(secondsSince1970)
			else {
				return nil
			}

			self.init(uncheckedSecondsSince1970: secondsSince1970, nanoseconds: nanoseconds)
		}

		/**
		Creates an instant from UTC date and time components.

		Returns `nil` if a component is out of range or the date does not exist.

		```swift
		let instant = SOML.Instant(year: 2026, month: 9, day: 19, hour: 14)!
		```
		*/
		public init?(
			year: Int,
			month: Int,
			day: Int,
			hour: Int = 0,
			minute: Int = 0,
			second: Int = 0,
			nanosecond: Int = 0
		) {
			guard
				SOML.Date(year: year, month: month, day: day) != nil,
				(0...23).contains(hour),
				(0...59).contains(minute),
				(0...59).contains(second)
			else {
				return nil
			}

			let days = Self.daysSince1970(year: Int64(year), month: Int64(month), day: Int64(day))
			self.init(secondsSince1970: days * 86_400 + Int64(hour * 3600 + minute * 60 + second), nanoseconds: nanosecond)
		}

		/**
		Creates an instant from a `Date`, with the fewest fractional digits that convert back to the same `Date`.

		A `Date` stores a binary `Double` measured from 2001. The fewest fractional digits preserve that stored value without displaying unnecessary rounding error. Where a `Date` is finer than a nanosecond, near 2001, the closest nanosecond is used.

		Returns `nil` if the date is outside the range SOML can represent.
		*/
		public init?(_ date: Foundation.Date) {
			// The reference date is the date's own storage, so this keeps the most precision.
			let interval = date.timeIntervalSinceReferenceDate

			// Bound the interval before converting to integer seconds, which also rejects nonfinite dates.
			guard
				interval >= Double(Self.minimumSeconds - Self.secondsFrom1970To2001),
				interval < Double(Self.maximumSeconds + 1 - Self.secondsFrom1970To2001)
			else {
				return nil
			}

			let wholeSeconds = interval.rounded(.down)
			let secondsSince1970 = Int64(wholeSeconds) + Self.secondsFrom1970To2001

			// A date before the minimum is out of range, even when its fraction rounds up to the minimum.
			guard secondsSince1970 >= Self.minimumSeconds else {
				return nil
			}

			let fraction = interval - wholeSeconds
			var nanosecondsPerUnit = 1_000_000_000

			for _ in 0...9 {
				defer {
					nanosecondsPerUnit /= 10
				}
				let unitsPerSecond = 1_000_000_000 / nanosecondsPerUnit
				let units = Int((fraction * Double(unitsPerSecond)).rounded())
				let candidate = units == unitsPerSecond ? Self(secondsSince1970: secondsSince1970 + 1) : Self(secondsSince1970: secondsSince1970, nanoseconds: units * nanosecondsPerUnit)

				guard let candidate else {
					continue
				}

				if candidate.date == date {
					self = candidate
					return
				}
			}

			// The fraction and its product above are rounded, which can give the nanosecond next to the closest, so the closest is computed exactly.
			var (seconds, nanoseconds) = interval.closestNanoseconds.quotientAndRemainder(dividingBy: 1_000_000_000)

			if nanoseconds < 0 {
				seconds -= 1
				nanoseconds += 1_000_000_000
			}

			self.init(secondsSince1970: Int64(seconds) + Self.secondsFrom1970To2001, nanoseconds: Int(nanoseconds))
		}

		/**
		The instant as a `Date`.

		A `Date` stores a `Double`, so far from 2001 it can be off by a few microseconds, and by up to about 15 microseconds in the year 9999. An instant at the end of that year never rounds past it, so its date converts back, which makes the last instants of the range off by up to about 30 microseconds.
		*/
		public var date: Foundation.Date {
			// Use the date's own reference point so a Unix timestamp does not discard precision near 2001.
			let referenceSeconds = secondsSince1970 - Self.secondsFrom1970To2001
			let interval: Double

			if referenceSeconds < 0 {
				// Subtract the complementary fraction to avoid cancellation for dates just before the reference point.
				interval = Double(referenceSeconds + 1) - Double(1_000_000_000 - nanoseconds) / 1_000_000_000
			} else {
				// Rounding to a `Double` could take the last instants of the range past its end, where the date would not convert back.
				interval = min(Double(referenceSeconds) + Double(nanoseconds) / 1_000_000_000, Double(Self.maximumSeconds + 1 - Self.secondsFrom1970To2001).nextDown)
			}

			return Foundation.Date(timeIntervalSinceReferenceDate: interval)
		}

		/**
		The UTC date and time components of the instant.
		*/
		public var components: (year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, nanosecond: Int) {
			let days = secondsSince1970.floorDivided(by: 86_400)
			let secondOfDay = Int(secondsSince1970 - days * 86_400)
			let (year, month, day) = Self.civilDate(daysSince1970: days)
			return (year, month, day, secondOfDay / 3600, secondOfDay / 60 % 60, secondOfDay % 60, nanoseconds)
		}

		/**
		Orders instants from the earliest to the latest.
		*/
		public static func < (lhs: Self, rhs: Self) -> Bool {
			(lhs.secondsSince1970, lhs.nanoseconds) < (rhs.secondsSince1970, rhs.nanoseconds)
		}
	}
}

extension SOML.Instant: LosslessStringConvertible {
	/**
	Parses an instant written as SOML writes it, like `2026-09-19T14:00:00Z` or `2026-09-19T16:00:00.25+02:00`.

	Returns `nil` if the text is not a valid SOML instant.
	*/
	public init?(_ description: String) {
		guard
			(20...35).contains(description.utf8.count),
			let instant = description.withUTF8Buffer({ try? Self.parse($0) })
		else {
			return nil
		}

		self = instant
	}

	/**
	The canonical form: UTC with `Z`, and the fraction only when it is not zero, with no trailing zeros.
	*/
	public var description: String {
		var bytes = [UInt8]()
		bytes.reserveCapacity(30)
		appendCanonical(to: &bytes)
		return String(decoding: bytes, as: UTF8.self)
	}

	/**
	Appends the canonical form, as `description` gives it, without making a string.
	*/
	func appendCanonical(to output: inout [UInt8]) {
		// Formatting through Date loses nanoseconds; Swift 6.4's ISO8601FormatStyle emitted .123Z for an instant ending in .123456789Z.
		let (year, month, day, hour, minute, second, nanosecond) = components
		SOML.Date.appendCanonical(
			year: year,
			month: month,
			day: day,
			to: &output
		)
		output.append(.uppercaseT)
		output.appendDecimal(UInt64(hour), minimumDigitCount: 2)
		output.append(.colon)
		output.appendDecimal(UInt64(minute), minimumDigitCount: 2)
		output.append(.colon)
		output.appendDecimal(UInt64(second), minimumDigitCount: 2)
		output.appendFraction(nanoseconds: UInt64(nanosecond))
		output.append(.uppercaseZ)
	}
}

extension SOML.Instant: Codable {
	/**
	Decodes an instant. `SOML.Decoder` reads a SOML instant directly. Other decoders read a string with the text of a SOML instant, like `2026-09-19T14:00:00Z`, in any of its spellings, so also with an offset.
	*/
	public init(from decoder: any Swift.Decoder) throws {
		if let decoder = decoder as? DecoderImplementation {
			self = try decoder.unboxInstant(decoder.value, key: nil)
			return
		}

		let container = try decoder.singleValueContainer()
		let text = try container.decode(String.self)

		guard let instant = Self(text) else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "“\(text.forMessage)” is not a valid SOML instant")
		}

		self = instant
	}

	/**
	Encodes the instant. `SOML.Encoder` writes a SOML instant. Other encoders get the canonical string.
	*/
	public func encode(to encoder: any Swift.Encoder) throws {
		if let encoder = encoder as? EncoderImplementation {
			encoder.result = .value(.instant(self))
			return
		}

		var container = encoder.singleValueContainer()
		try container.encode(description)
	}
}

extension SOML.Instant {
	/**
	Parses the text of an instant token. The form is checked first, and then the values, in the order of the reference implementation, so that both report the same problem.
	*/
	static func parse<Bytes: RandomAccessCollection<UInt8>>(_ bytes: Bytes) throws(SOML.TemporalSyntaxError) -> Self where Bytes.Index == Int {
		let start = bytes.startIndex

		func number(at index: Int, length: Int) -> Int? {
			guard index + length <= bytes.endIndex else {
				return nil
			}

			var value = 0

			for byte in bytes[index..<(index + length)] {
				guard byte.isASCIIDigit else {
					return nil
				}

				value = value * 10 + Int(byte - .digitZero)
			}

			return value
		}

		func expect(_ byte: UInt8, at index: Int) -> Bool {
			index < bytes.endIndex && bytes[index] == byte
		}

		guard
			let year = number(at: start, length: 4),
			expect(.hyphen, at: start + 4),
			let month = number(at: start + 5, length: 2),
			expect(.hyphen, at: start + 7),
			let day = number(at: start + 8, length: 2),
			expect(.uppercaseT, at: start + 10),
			let hour = number(at: start + 11, length: 2),
			expect(.colon, at: start + 13),
			let minute = number(at: start + 14, length: 2),
			expect(.colon, at: start + 16),
			let second = number(at: start + 17, length: 2)
		else {
			throw SOML.TemporalSyntaxError(reason: nil)
		}

		var index = start + 19
		var fractionDigitCount = 0
		var nanosecond = 0

		if expect(.dot, at: index) {
			index += 1
			let fractionStart = index

			while
				index < bytes.endIndex,
				bytes[index].isASCIIDigit
			{
				index += 1
			}

			fractionDigitCount = index - fractionStart

			guard fractionDigitCount > 0 else {
				throw SOML.TemporalSyntaxError(reason: nil)
			}

			// Only the first nine digits are read, because more is an error below.
			for byte in bytes[fractionStart..<(fractionStart + min(fractionDigitCount, 9))] {
				nanosecond = nanosecond * 10 + Int(byte - .digitZero)
			}

			for _ in min(fractionDigitCount, 9)..<9 {
				nanosecond *= 10
			}
		}

		var offset: (isNegative: Bool, hour: Int, minute: Int)?

		if expect(.uppercaseZ, at: index) {
			index += 1
		} else if
			expect(.plus, at: index) || expect(.hyphen, at: index),
			let offsetHour = number(at: index + 1, length: 2),
			expect(.colon, at: index + 3),
			let offsetMinute = number(at: index + 4, length: 2)
		{
			offset = (bytes[index] == .hyphen, offsetHour, offsetMinute)
			index += 6
		} else {
			throw SOML.TemporalSyntaxError(reason: nil)
		}

		guard index == bytes.endIndex else {
			throw SOML.TemporalSyntaxError(reason: nil)
		}

		// The reason is only made for an instant that is not valid.
		func check(_ isValid: Bool, _ reason: @autoclosure () -> String) throws(SOML.TemporalSyntaxError) {
			guard isValid else {
				throw SOML.TemporalSyntaxError(reason: reason())
			}
		}

		try check(fractionDigitCount <= 9, "a fractional second has at most nine digits")
		// Validate the Gregorian date directly, including years before the calendar was historically adopted.
		if let reason = SOML.Date.validationFailure(year: year, month: month, day: day) {
			throw SOML.TemporalSyntaxError(reason: reason)
		}
		try check(hour <= 23, "the hour must be 00 to 23")
		try check(minute <= 59, "the minute must be 00 to 59")
		try check(second <= 59, "the second must be 00 to 59, and a leap second is not representable")
		var offsetSeconds = 0

		if let offset {
			try check(offset.hour <= 23, "the offset hour must be 00 to 23")
			try check(offset.minute <= 59, "the offset minute must be 00 to 59")
			try check(!(offset.isNegative && offset.hour == 0 && offset.minute == 0), "-00:00 means “offset unknown” in RFC 3339, which is not representable; use Z or +00:00")
			offsetSeconds = (offset.hour * 3600 + offset.minute * 60) * (offset.isNegative ? -1 : 1)
		}

		let days = daysSince1970(year: Int64(year), month: Int64(month), day: Int64(day))
		let seconds = days * 86_400 + Int64(hour * 3600 + minute * 60 + second) - Int64(offsetSeconds)

		guard let instant = Self(secondsSince1970: seconds, nanoseconds: nanosecond) else {
			throw SOML.TemporalSyntaxError(reason: "in UTC it falls outside the years 0001 to 9999")
		}

		return instant
	}

	/*
	The days-from-civil and civil-from-days algorithms by Howard Hinnant, for the proleptic Gregorian calendar.
	https://howardhinnant.github.io/date_algorithms.html
	*/
	private static func daysSince1970(year: Int64, month: Int64, day: Int64) -> Int64 {
		let year = month <= 2 ? year - 1 : year
		let era = year.floorDivided(by: 400)
		let yearOfEra = year - era * 400
		let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
		let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
		return era * 146_097 + dayOfEra - 719_468
	}

	private static func civilDate(daysSince1970: Int64) -> (year: Int, month: Int, day: Int) {
		let days = daysSince1970 + 719_468
		let era = days.floorDivided(by: 146_097)
		let dayOfEra = days - era * 146_097
		let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
		let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
		let monthIndex = (5 * dayOfYear + 2) / 153
		let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
		let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
		let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
		return (Int(year), Int(month), Int(day))
	}
}

extension Int64 {
	/**
	Division that rounds toward negative infinity.
	*/
	fileprivate func floorDivided(by divisor: Self) -> Self {
		let quotient = self / divisor
		return (self % divisor != 0 && (self < 0) != (divisor < 0)) ? quotient - 1 : quotient
	}
}

extension Double {
	/**
	The value in nanoseconds, with the value in seconds, rounded to the closest integer, and a tie to the even one. Unlike multiplying by 10⁹ and rounding, which rounds twice, it is computed exactly.
	*/
	fileprivate var closestNanoseconds: Int128 {
		// A subnormal is far below half a nanosecond.
		guard isNormal else {
			return 0
		}

		// The value is the significand times 2 to the power of `shift`, and the significand has 53 bits, so its product with 10⁹ fits.
		let product = Int128(1 << 52 | significandBitPattern) * 1_000_000_000
		let shift = Int(exponent) - 52
		let magnitude: Int128

		if shift >= 0 {
			magnitude = product << shift
		} else if shift > -100 {
			let quotient = product >> -shift
			let remainder = product - quotient << -shift
			let half = Int128(1) << (-shift - 1)
			magnitude = remainder > half || (remainder == half && quotient & 1 == 1) ? quotient + 1 : quotient
		} else {
			magnitude = 0
		}

		return sign == .minus ? -magnitude : magnitude
	}
}

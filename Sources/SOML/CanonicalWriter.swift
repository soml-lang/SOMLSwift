/**
Writes SOML canonical form, as the spec's "Canonical form" section defines it, or the same layout with members in their given order, which the spec allows for a file that people read.

Every rule below applies in all modes, except that members keep their order when `sortsMembers` is off. With sorted members, two writers given the same value produce the same bytes:

- One entry per line, indented with one tab per level.
- No commas: a line break separates members and items, inside braces and brackets as at the top level.
- Members are sorted by the Unicode scalars of their keys, when `sortsMembers` is on. Otherwise, they keep their order in the object.
- No comments or block strings.
- A string is `'...'` unless it contains `'` or a character that must be escaped.
- An int is plain decimal. A float is the shortest decimal that reads back as the same value.
- An instant is UTC, with `Z`.
- A duration is hours, minutes, and seconds with a fraction, like `1h30m` or `1.5s`, and zero is `0s`.
- The file ends with exactly one line feed.

For a value that an edit puts in a container on one line, a third mode writes a container on one line instead, with a comma and a space between its members or items, and otherwise the same.
*/
struct CanonicalWriter {
	/**
	The UTF-8 bytes written so far.
	*/
	private var output = [UInt8]()
	private var codingPath = [SOMLCodingKey]()

	/**
	Levels of nesting around the written values that do not appear in the output: 1 under a brace-less top-level object, which counts toward the nesting limit like a braced one.
	*/
	private var unwrittenLevels = 0

	/**
	Whether to throw for a value that SOML cannot represent. Descriptions do not check, so that any value can be printed.
	*/
	private let validates: Bool

	/**
	Whether to sort members by key, as canonical form requires. Otherwise, they keep their order in the object.
	*/
	private let sortsMembers: Bool

	/**
	Whether to write a container on one line, as in `[1, {a: 2}]`, with a comma and a space between its members or items.
	*/
	private let isOneLine: Bool

	private init(validates: Bool, sortsMembers: Bool, isOneLine: Bool = false) {
		self.validates = validates
		self.sortsMembers = sortsMembers
		self.isOneLine = isOneLine
	}

	/**
	The bytes of a document. The value must be an object or an array. With `sortsMembers`, they are the canonical bytes.
	*/
	static func document(_ value: SOML.Value, sortsMembers: Bool) throws(SOML.InvalidValueError) -> [UInt8] {
		var writer = Self(validates: true, sortsMembers: sortsMembers)

		switch value {
		case .object(let object) where !object.isEmpty:
			// The top-level braces are omitted, and the entries are not indented, but the object still counts toward the nesting limit.
			writer.unwrittenLevels = 1

			// The sorted member positions, or nil to use the object's existing indices in insertion order.
			let order = writer.sortsMembers ? object.canonicalOrder : nil

			for index in object.indices {
				let position = order?[index] ?? index
				let (key, value) = object[position]
				try writer.writeMember(key: key, value: value, depth: 0)
				writer.output.append(.lineFeed)
			}
		case .object, .array:
			// An empty top-level object keeps its braces, because a document cannot be empty.
			try writer.writeValue(value, depth: 0)
			writer.output.append(.lineFeed)
		default:
			throw SOML.InvalidValueError(message: "A SOML document must be an object or an array, not \(value.briefDescription)", codingPath: [])
		}

		return writer.output
	}

	/**
	The text of a value as it appears after a key, with members in their order, without checking that SOML can represent it.
	*/
	static func valueDescription(_ value: SOML.Value) -> String {
		var writer = Self(validates: false, sortsMembers: false)
		try? writer.writeValue(value, depth: 0)
		return String(decoding: writer.output, as: UTF8.self)
	}

	/**
	The bytes of a value as it appears after a key, with members in their order, after checking that SOML can represent it. A container counts its own nesting from 1, so a value nested more than 100 levels deep on its own throws.

	With `isOneLine`, a container is written on one line, as in `[1, {a: 2}]`, for a value that goes in a container on one line.
	*/
	static func value(_ value: SOML.Value, isOneLine: Bool = false) throws(SOML.InvalidValueError) -> [UInt8] {
		var writer = Self(validates: true, sortsMembers: false, isOneLine: isOneLine)
		try writer.writeValue(value, depth: 0)
		return writer.output
	}

	/**
	A string in its canonical quoted form.
	*/
	static func string(_ string: String) -> String {
		var output = [UInt8]()
		output.reserveCapacity(string.utf8.count + 2)
		appendString(string, to: &output)
		return String(decoding: output, as: UTF8.self)
	}

	/**
	A key in canonical form: bare when it can be, and quoted otherwise.
	*/
	static func key(_ key: String) -> String {
		var output = [UInt8]()
		output.reserveCapacity(key.utf8.count + 2)
		appendKey(key, to: &output)
		return String(decoding: output, as: UTF8.self)
	}

	// MARK: Writing

	private mutating func writeMember(key: String, value: SOML.Value, depth: Int) throws(SOML.InvalidValueError) {
		codingPath.append(SOMLCodingKey(stringValue: key))
		defer {
			codingPath.removeLast()
		}

		guard Self.appendKey(key, to: &output, rejectsCarriageReturn: validates) else {
			throw SOML.InvalidValueError(message: "A key cannot contain a carriage return, because SOML cannot represent one", codingPath: codingPath)
		}
		output.append(.colon)
		output.append(.space)
		try writeValue(value, depth: depth)
	}

	private mutating func writeValue(_ value: SOML.Value, depth: Int) throws(SOML.InvalidValueError) {
		if
			!validates,
			depth >= Parser.maximumDepth,
			value.isContainer
		{
			output.appendUTF8("…")
			return
		}

		switch value {
		case .string(let string):
			guard Self.appendString(string, to: &output, rejectsCarriageReturn: validates) else {
				throw SOML.InvalidValueError(message: "A string cannot contain a carriage return, because SOML cannot represent one", codingPath: codingPath)
			}
		case .int(let int):
			// The magnitude, because negating `Int64.min` overflows.
			output.appendSignedDecimal(int)
		case .float(let float):
			if
				validates,
				float.isNaN
			{
				throw SOML.InvalidValueError(message: "NaN is not a SOML value", codingPath: codingPath)
			}

			float.appendCanonical(to: &output)
		case .bool(let bool):
			output.appendUTF8(bool ? "true" : "false")
		case .null:
			output.appendUTF8("null")
		case .instant(let instant):
			instant.appendCanonical(to: &output)
		case .duration(let duration):
			guard let nanoseconds = duration.exactNanoseconds else {
				if validates {
					throw SOML.InvalidValueError(message: duration.unrepresentableReason, codingPath: codingPath)
				}

				// A description shows the value even though SOML cannot represent it.
				String(describing: duration).withUTF8Buffer { output.append(contentsOf: $0) }
				return
			}

			Duration.appendCanonical(nanoseconds: nanoseconds, to: &output)
		case .array(let items):
			try checkDepth(depth)

			guard !items.isEmpty else {
				output += [.openBracket, .closeBracket]
				return
			}

			output.append(.openBracket)
			appendLineFeed()

			for (index, item) in items.enumerated() {
				codingPath.append(SOMLCodingKey(intValue: index))
				appendSeparator(index: index)
				appendIndentation(depth + 1)
				try writeValue(item, depth: depth + 1)
				appendLineFeed()
				codingPath.removeLast()
			}

			appendIndentation(depth)
			output.append(.closeBracket)
		case .object(let object):
			try checkDepth(depth)

			guard !object.isEmpty else {
				output += [.openBrace, .closeBrace]
				return
			}

			output.append(.openBrace)
			appendLineFeed()

			let order = sortsMembers ? object.canonicalOrder : nil

			for index in object.indices {
				let position = order?[index] ?? index
				let (key, value) = object[position]
				appendSeparator(index: index)
				appendIndentation(depth + 1)
				try writeMember(key: key, value: value, depth: depth + 1)
				appendLineFeed()
			}

			appendIndentation(depth)
			output.append(.closeBrace)
		}
	}

	/**
	A container written at `depth` is at nesting level `depth + 1 + unwrittenLevels`. The output must stay within the parser's limit, or it could not be read back.
	*/
	private func checkDepth(_ depth: Int) throws(SOML.InvalidValueError) {
		guard !validates || depth + unwrittenLevels < Parser.maximumDepth else {
			throw SOML.InvalidValueError(message: "The value is nested more than \(Parser.maximumDepth) levels deep, which is the most a SOML reader accepts", codingPath: codingPath)
		}
	}

	/**
	The indentation of a line inside a container, which a container on one line does not have.
	*/
	private mutating func appendIndentation(_ depth: Int) {
		guard !isOneLine else {
			return
		}

		output.appendIndentation(depth)
	}

	/**
	The line feed after an opening bracket, a member, or an item, which a container on one line does not have.
	*/
	private mutating func appendLineFeed() {
		guard !isOneLine else {
			return
		}

		output.append(.lineFeed)
	}

	/**
	The comma and the space before every member or item but the first, which only a container on one line has.
	*/
	private mutating func appendSeparator(index: Int) {
		guard
			isOneLine,
			index > 0
		else {
			return
		}

		// StaticString wrappers helped long batches of two-byte literals but slowed short batches; keep these fixed byte pairs inline.
		output += [.comma, .space]
	}

	/**
	Appends a canonical key, returning false before writing when a carriage return is rejected.
	*/
	@discardableResult
	static func appendKey(_ key: String, to output: inout [UInt8], rejectsCarriageReturn: Bool = false) -> Bool {
		// A bare key has at least one character, so the empty key is written quoted, as `''`.
		return key.withUTF8Buffer { bytes in
			guard
				!bytes.isEmpty,
				bytes.allSatisfy(\.isBareKeyByte)
			else {
				return appendString(key, to: &output, rejectsCarriageReturn: rejectsCarriageReturn)
			}

			output.append(contentsOf: bytes)
			return true
		}
	}

	/**
	Uses `'...'` unless the string contains `'` or a character that must be escaped, which are the C0 controls and U+007F. A `\` or a `"` does not need the escaped form, because `'...'` is literal.
	*/
	@discardableResult
	private static func appendString(_ string: String, to output: inout [UInt8], rejectsCarriageReturn: Bool = false) -> Bool {
		string.withUTF8Buffer { bytes in
			let needsEscaping = bytes.contains { $0 == .singleQuote || $0 < 0x20 || $0 == 0x7F }

			// A literal string cannot contain a carriage return, so only strings needing escapes require a separate validation scan.
			if
				rejectsCarriageReturn,
				needsEscaping,
				bytes.contains(.carriageReturn)
			{
				return false
			}

			guard needsEscaping else {
				output.append(.singleQuote)
				output.append(contentsOf: bytes)
				output.append(.singleQuote)
				return true
			}

			output.append(.doubleQuote)

			var runStart = 0

			for (index, byte) in bytes.enumerated() {
				guard byte == .backslash || byte == .doubleQuote || byte < 0x20 || byte == 0x7F else {
					continue
				}

				output.append(contentsOf: bytes[runStart..<index])
				runStart = index + 1

				switch byte {
				case .backslash:
					output += [.backslash, .backslash]
				case .doubleQuote:
					output += [.backslash, .doubleQuote]
				case .lineFeed:
					output += [.backslash, .lowercaseN]
				case .tab:
					output += [.backslash, .lowercaseT]
				case 0..<0x20, 0x7F:
					output.append(.backslash)
					output.append(.lowercaseU)
					output.append(.openBrace)

					if byte >= 16 {
						output.append((byte >> 4).lowercaseHexadecimalDigit)
					}

					output.append((byte & 0xF).lowercaseHexadecimalDigit)
					output.append(.closeBrace)
				default:
					break
				}
			}

			output.append(contentsOf: bytes[runStart..<bytes.count])
			output.append(.doubleQuote)
			return true
		}
	}

}

// MARK: Durations

/**
Canonical duration writing from an exact nanosecond count.
*/
extension Duration {
	/**
	Appends the canonical text of a duration: whole hours, whole minutes below 60, and seconds below 60 with a fraction like an instant's, each left out when it is zero, with `-` in front when it is negative. So 90 minutes is `1h30m`, 1500 milliseconds is `1.5s`, and zero is `0s`.
	*/
	static func appendCanonical(nanoseconds: Int64, to output: inout [UInt8]) {
		// Duration's units FormatStyle dropped the final nanosecond of 90000000000001 ns, formatting it as "25h" in the probe; canonical output must preserve every nanosecond.
		guard nanoseconds != 0 else {
			output += [.digitZero, .lowercaseS]
			return
		}

		if nanoseconds < 0 {
			output.append(.hyphen)
		}

		// The magnitude, because negating `Int64.min` overflows.
		let magnitude = nanoseconds.magnitude
		let hours = magnitude / 3_600_000_000_000
		let minutes = magnitude / 60_000_000_000 % 60
		let seconds = magnitude / 1_000_000_000 % 60
		let fraction = magnitude % 1_000_000_000

		if hours > 0 {
			output.appendDecimal(hours)
			output.append(.lowercaseH)
		}

		if minutes > 0 {
			output.appendDecimal(minutes)
			output.append(.lowercaseM)
		}

		if seconds > 0 || fraction > 0 {
			output.appendDecimal(seconds)
			output.appendFraction(nanoseconds: fraction)
			output.append(.lowercaseS)
		}
	}
}

// MARK: Floats

/**
Canonical float writing shared by the SOML and JSON writers.
*/
extension Double {
	/**
	Appends the canonical text of a float.

	The digits are the shortest that read back as the same `Double`. They are laid out with the thresholds of ECMAScript's `Number::toString`, which RFC 8785 also uses: positional notation when the decimal exponent n is in -6 < n <= 21, and exponent notation otherwise. An integral value gets `.0` so that it never reads as an int, and an exponent has no `+` and no leading zeros.
	*/
	func appendCanonical(to output: inout [UInt8]) {
		let value = self
		if value.isInfinite {
			output.appendUTF8(value < 0 ? "-infinity" : "infinity")
			return
		}

		if value.isNaN {
			output.appendUTF8("nan")
			return
		}

		if value == 0 {
			output.appendUTF8("0.0")
			return
		}

		// Swift's description has the shortest round-trip digits, like "1.2345e+16", "0.001", or "5e-324". It uses positional notation only from 0.0001 up to 2^53, which is inside the positional range above, and there it already writes the canonical form, including the ".0" of an integral value.
		var text = value.description

		text.withUTF8 { bytes in
			guard let exponentIndex = bytes.firstIndex(of: .lowercaseE) else {
				output.append(contentsOf: bytes)
				return
			}

			let exponent = bytes[(exponentIndex + 1)...]
			var decimalExponent = 0

			for byte in exponent where byte.isASCIIDigit {
				decimalExponent = decimalExponent * 10 + Int(byte - .digitZero)
			}

			if exponent.first == .hyphen {
				decimalExponent = -decimalExponent
			}

			// The value is 0.digits times 10^decimalExponent. Swift's scientific notation has one digit before the decimal point.
			decimalExponent += 1

			if decimalExponent <= -6 || decimalExponent > 21 {
				// The mantissa already has the shortest digits. Only the exponent's sign and leading zeros need canonicalizing.
				output.append(contentsOf: bytes[..<exponentIndex])
				output.append(.lowercaseE)
				output.appendSignedDecimal(Int64(decimalExponent - 1))
				return
			}

			// The value is `significand` times a power of ten. A Double has at most 17 significant decimal digits, which fit in UInt64 without a scratch buffer.
			var significand: UInt64 = 0
			var digitCount = 0

			for byte in bytes[..<exponentIndex] where byte.isASCIIDigit {
				significand = significand * 10 + UInt64(byte - .digitZero)
				digitCount += 1
			}

			while significand.isMultiple(of: 10) {
				significand /= 10
				digitCount -= 1
			}

			if value < 0 {
				output.append(.hyphen)
			}

			// Use OutputSpan bulk initialization for zero padding; tiny fills measured similarly to repeatElement, while longer fills benefited.
			if digitCount <= decimalExponent {
				output.appendDecimal(significand)
				output.append(addingCapacity: decimalExponent - digitCount) { padding in
					padding.append(repeating: .digitZero, count: decimalExponent - digitCount)
				}
				output += [.dot, .digitZero]
			} else if decimalExponent > 0 {
				output.appendDecimal(significand)
				output.insert(.dot, at: output.count - digitCount + decimalExponent)
			} else {
				output += [.digitZero, .dot]
				output.append(addingCapacity: -decimalExponent) { padding in
					padding.append(repeating: .digitZero, count: -decimalExponent)
				}
				output.appendDecimal(significand)
			}
		}
	}
}

extension [UInt8] {
	/**
	Appends the UTF-8 bytes of a literal without constructing a dynamic string.
	*/
	mutating func appendUTF8(_ literal: StaticString) {
		literal.withUTF8Buffer { append(contentsOf: $0) }
	}

	/**
	Appends a signed decimal integer without allocating a string or negating `Int64.min`.
	*/
	mutating func appendSignedDecimal(_ value: Int64) {
		if value < 0 {
			append(.hyphen)
		}

		// The magnitude, because negating `Int64.min` overflows.
		appendDecimal(value.magnitude)
	}

	/**
	Appends one tab per indentation level.
	*/
	mutating func appendIndentation(_ depth: Int) {
		append(addingCapacity: depth) { output in
			output.append(repeating: .tab, count: depth)
		}
	}

	/**
	Appends a valid Unicode scalar directly in UTF-8.
	*/
	mutating func appendScalar(_ scalar: Unicode.Scalar) {
		// UTF8.encode(_:into:) is simpler than iterating a UTF8View, but direct OutputSpan initialization measured faster for repeated scalar appends.
		let bytes = scalar.utf8
		append(addingCapacity: bytes.count) { output in
			output.append(contentsOf: bytes)
		}
	}

	/**
	Appends the decimal digits of a number, with leading zeros up to `minimumDigitCount` digits.
	*/
	mutating func appendDecimal(_ value: UInt64, minimumDigitCount: Int = 1) {
		// Write into the destination rather than construct `String(value)` and copy its UTF-8; that alternative measured 10–56% slower in optimized Swift 6.4 builds on an M4 Pro.
		var digitCount = 1
		var remaining = value / 10

		while remaining > 0 {
			digitCount += 1
			remaining /= 10
		}

		let width = Swift.max(digitCount, minimumDigitCount)
		// Initialize and fill the new bytes within one lifetime-checked borrow of the output storage.
		append(addingCapacity: width) { digits in
			digits.append(repeating: .digitZero, count: width)
			var index = digits.count
			var remaining = value

			while remaining > 0 {
				index -= 1
				let division = remaining.quotientAndRemainder(dividingBy: 10)
				digits[index] = .digitZero + UInt8(division.remainder)
				remaining = division.quotient
			}
		}
	}

	/**
	Appends a fraction of a second as SOML writes it in instants and durations: nothing for zero, and otherwise a `.` and up to nine digits, without trailing zeros.
	*/
	mutating func appendFraction(nanoseconds: UInt64) {
		guard nanoseconds > 0 else {
			return
		}

		var digits = nanoseconds
		var digitCount = 9

		while digits % 10 == 0 {
			digits /= 10
			digitCount -= 1
		}

		append(.dot)
		appendDecimal(digits, minimumDigitCount: digitCount)
	}
}

/**
Sequence appending for bounded output initialization.
*/
extension OutputSpan {
	/**
	Appends a sequence of values within the span's remaining capacity.
	*/
	mutating func append(contentsOf elements: some Sequence<Element>) {
		for element in elements {
			append(element)
		}
	}
}

extension SOML {
	/**
	An error thrown when a value cannot be written as SOML, like NaN, a string with a carriage return, or a document that is not an object or an array.

	`SOML.Encoder` reports it as `EncodingError.invalidValue`. `SOML.Value.canonicalDocument()` throws it directly.
	*/
	public struct InvalidValueError: Error, Sendable, Hashable, CustomStringConvertible {
		/**
		What is wrong, as a sentence.
		*/
		public let message: String

		/**
		Where the value is, as keys and array indices from the top.
		*/
		let codingPath: [SOMLCodingKey]

		/**
		The message, followed by where the value is when it is not the whole document, like `NaN is not a SOML value (at limits.ratio)` or `(at labels[2])`.
		*/
		public var description: String {
			message + codingPath.locationSuffix
		}
	}
}

extension [SOMLCodingKey] {
	/**
	Where a value is, for the end of an error message, like ` (at limits.ratio)` or ` (at labels[2])`, with the key path as the reference implementation describes one (see `described`). It is empty for the whole value.
	*/
	var locationSuffix: String {
		guard !isEmpty else {
			return ""
		}

		let segments = map { key in
			key.intValue.map(SOML.KeyPath.Segment.index) ?? .key(key.stringValue)
		}

		return " (at \(segments[...].described))"
	}
}

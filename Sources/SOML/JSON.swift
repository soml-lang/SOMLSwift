extension SOML {
	/**
	How JSON represents SOML values.
	*/
	public enum JSONFormat: Sendable, Hashable {
		/**
		Plain JSON: a SOML int is a JSON number without a fraction or an exponent, a float one with them, and an instant or a duration a string of its canonical text.
		*/
		case plain

		/**
		The tagged JSON of the conformance suite, as in toml-test: every scalar is `{"type": …, "value": …}`, with the value in its canonical text, so every SOML type, including infinity, round-trips. A duration's value is its length in nanoseconds.
		*/
		case tagged
	}

	/**
	An error from reading JSON into a `SOML.Value`, or from writing a value as JSON.
	*/
	public struct JSONError: Error, Sendable, Hashable, CustomStringConvertible {
		/**
		What is wrong, as a sentence.
		*/
		public let message: String

		/**
		Where the problem is in the JSON text, or `nil` for a value that cannot be written as JSON.
		*/
		public let location: SOML.Location?

		/**
		The message, followed by the location when there is one, like `Duplicate key a. SOML does not allow one (line 2, column 3)`.
		*/
		public var description: String {
			guard let location else {
				return message
			}

			return "\(message) (\(location))"
		}
	}
}

extension SOML.Value {
	/**
	Reads JSON text.

	A number with a fraction or an exponent becomes a float, and any other number an int, so `1` is an int and `1.0` a float, which `JSONSerialization` cannot tell apart, and an int keeps every digit. A string stays a string, also when it looks like an instant or a duration, because SOML never types a value by its content. Members keep their order, and keys are compared by their Unicode scalars, as SOML compares them.

	With `.tagged`, the text is the tagged JSON of the conformance suite, as in toml-test: every scalar is `{"type": …, "value": …}`, with the value in its canonical text, and a duration's value is its length in nanoseconds.

	```swift
	try SOML.Value(parsingJSON: #"{"port": 8080, "ratio": 1.0}"#)
	//=> ["port": .int(8080), "ratio": .float(1.0)]
	```

	- Throws: `SOML.JSONError` with a position for text that is not valid JSON, and for what SOML cannot hold: an int outside the 64-bit range, a float that rounds to infinity, or to zero when it is not zero, a duplicate key, a lone surrogate, a carriage return in a string, and nesting deeper than 100 levels.
	*/
	public init(parsingJSON text: String, format: SOML.JSONFormat = .plain) throws(SOML.JSONError) {
		self = try JSONReader.read(Array(text.utf8), isTagged: format == .tagged)
	}

	/**
	Reads JSON text from UTF-8 bytes, like `Data` or `[UInt8]`. See `init(parsingJSON:format:)` for the String version.

	- Throws: `SOML.JSONError`, also when the bytes are not valid UTF-8.
	*/
	public init(parsingJSON bytes: some Sequence<UInt8>, format: SOML.JSONFormat = .plain) throws(SOML.JSONError) {
		self = try JSONReader.read(Array(bytes), isTagged: format == .tagged)
	}

	/**
	The value as JSON text, indented with tabs, with members in their order, and a line feed at the end.

	An int is written with all its digits, also past 2^53, where JavaScript would round it. A float is written in its canonical form, so `1.0` stays `1.0`. An instant or a duration becomes its canonical text, like `"2026-09-19T14:00:00Z"` and `"1h30m"`. Every control character in a string, including the C1 controls, is escaped, so none reaches a terminal raw.

	With `.tagged`, every scalar is written as `{"type": …, "value": …}`, the tagged JSON of the conformance suite.

	```swift
	let value: SOML.Value = ["timeout": .duration(.seconds(90)), "ports": [80, 443]]
	print(try value.jsonText())
	//=> {
	//=> 	"timeout": "1m30s",
	//=> 	"ports": [
	//=> 		80,
	//=> 		443
	//=> 	]
	//=> }
	```

	- Throws: `SOML.JSONError`, with the key path of the value in the message, for infinity and NaN, which JSON has no number for (except when tagged, where infinity is the text `infinity`), and for what SOML cannot represent, so that the JSON always reads back: a duration outside its range, a carriage return in a string or a key, and nesting deeper than 100 levels.
	*/
	public func jsonText(format: SOML.JSONFormat = .plain) throws(SOML.JSONError) -> String {
		var writer = JSONWriter(isTagged: format == .tagged)
		try writer.write(self, level: 0)
		writer.output.append(.lineFeed)
		return String(decoding: writer.output, as: UTF8.self)
	}

	/**
	The type and the text of a scalar in tagged JSON, or `nil` for an array, an object, NaN, or a duration that SOML cannot represent.
	*/
	fileprivate var tag: (type: String, value: String)? {
		switch self {
		case .string(let value):
			("string", value)
		case .int(let value):
			("int", String(value))
		case .float(let value):
			// NaN is not a SOML value, so it has no tag, and writing it is an error.
			value.isNaN ? nil : ("float", description)
		case .bool(let value):
			("bool", String(value))
		case .null:
			("null", "null")
		case .instant:
			("instant", description)
		case .duration(let value):
			value.exactNanoseconds.map { ("duration", String($0)) }
		case .array, .object:
			nil
		}
	}
}

/**
A strict RFC 8259 reader that makes SOML values directly, so that every error has a position.

It is written by hand, because Foundation's readers do not say whether a number was written `1` or `1.0`, they keep the last of two members with the same key, and they compare keys by canonical equivalence, which SOML does not. It uses untyped `throws` inside, as the SOML parser does, to keep the frames of its recursion small in a debug build.
*/
private struct JSONReader {

	private let bytes: [UInt8]
	private let isTagged: Bool
	private var position = 0
	private var depth = 0

	/**
	The offset of the last array or object that opened one level past the maximum depth, which is the one that is too deep when something nests in it.
	*/
	private var firstLevelPastMaximumStart = 0

	private init(bytes: [UInt8], isTagged: Bool) {
		self.bytes = bytes
		self.isTagged = isTagged
	}

	static func read(_ bytes: [UInt8], isTagged: Bool) throws(SOML.JSONError) -> SOML.Value {
		if let offset = Parser.scanEncoding(bytes).invalidUTF8Index {
			throw Self(bytes: bytes, isTagged: isTagged).error("The text is not valid UTF-8", at: offset)
		}

		do {
			var reader = Self(bytes: bytes, isTagged: isTagged)
			reader.skipWhitespace()
			let value = try reader.readValue()
			reader.skipWhitespace()

			guard reader.position == bytes.count else {
				throw reader.error("Expected the end of the JSON text")
			}

			return value
		} catch let error as SOML.JSONError {
			throw error
		} catch {
			preconditionFailure("The JSON reader only throws SOML.JSONError, but it threw \(error).")
		}
	}

	private var current: UInt8? {
		position < bytes.count ? bytes[position] : nil
	}

	private func error(_ message: String, at offset: Int? = nil) -> SOML.JSONError {
		SOML.JSONError(message: message.sanitizedForTerminal, location: SOML.Location(offset: offset ?? position, in: bytes))
	}

	private mutating func skipWhitespace() {
		while
			let byte = current,
			byte.isJSONWhitespace
		{
			position += 1
		}
	}

	/**
	Reads a value where tagged JSON allows only a container or a tagged scalar.
	*/
	private mutating func readValue() throws -> SOML.Value {
		let start = position
		let (value, isPlainScalar) = try readAnyValue()

		guard !isTagged || !isPlainScalar else {
			throw error("Tagged JSON writes every scalar as {\"type\": …, \"value\": …}, so a plain scalar cannot be in it", at: start)
		}

		return value
	}

	/**
	Reads a value, and whether it was written as a plain JSON scalar, which tagged JSON allows only as the type and the value of a tagged scalar.
	*/
	private mutating func readAnyValue() throws -> (value: SOML.Value, isPlainScalar: Bool) {
		let start = position

		switch current {
		case .openBrace?:
			let (object, plainScalars) = try readObject()

			guard isTagged else {
				return (.object(object), false)
			}

			// Only plain strings make a tagged scalar, so an object with the members `type` and `value` that are themselves tagged stays an object.
			if
				plainScalars.count == 2,
				object.count == 2,
				case .string(let type)? = object["type"],
				case .string(let text)? = object["value"]
			{
				return (try taggedScalar(type: type, text: text, at: start), false)
			}

			if let plainScalarOffset = plainScalars.firstOffset {
				throw error("Tagged JSON writes every scalar as {\"type\": …, \"value\": …}, so a plain scalar cannot be in it", at: plainScalarOffset)
			}

			try checkDepthOfContainer(at: start)
			return (.object(object), false)
		case .openBracket?:
			var items = [SOML.Value]()

			try readItems(closing: .closeBracket) { reader in
				items.append(try reader.readValue())
			}

			try checkDepthOfContainer(at: start)
			return (.array(items), false)
		case .doubleQuote?:
			return (.string(try readString()), true)
		default:
			return (try readScalar(), true)
		}
	}

	/**
	Reads an object, and bounded metadata about its member values that are plain scalars.
	*/
	private mutating func readObject() throws -> (object: SOML.Object, plainScalars: (count: Int, firstOffset: Int?)) {
		var members = OrderedMembers<SOML.Value>()
		var plainScalars: (count: Int, firstOffset: Int?) = (0, nil)

		try readItems(closing: .closeBrace) { reader in
			let keyStart = reader.position

			guard reader.current == .doubleQuote else {
				throw reader.error("Expected a key in double quotes")
			}

			let key = try reader.readString()

			guard members.position(of: key) == nil else {
				throw reader.error("Duplicate key \(SOML.KeyPath.Segment.key(key).described). SOML does not allow one", at: keyStart)
			}

			reader.skipWhitespace()

			guard reader.current == .colon else {
				throw reader.error("Expected “:” after the key")
			}

			reader.position += 1
			reader.skipWhitespace()
			let valueStart = reader.position
			let (value, isPlainScalar) = try reader.readAnyValue()

			if
				reader.isTagged,
				isPlainScalar
			{
				plainScalars.count += 1
				if plainScalars.firstOffset == nil {
					plainScalars.firstOffset = valueStart
				}
			}

			members.append(value, forKey: key)
		}

		return (SOML.Object(members), plainScalars)
	}

	/**
	Checks the depth of an array or an object that just closed. In tagged JSON, the reading limit is one level more, for a tagged scalar at the deepest level, so a real array or object that uses that level is refused here.
	*/
	private func checkDepthOfContainer(at start: Int) throws {
		guard depth < Parser.maximumDepth else {
			throw error("The JSON is nested more than \(Parser.maximumDepth) levels deep, which is the most SOML allows", at: start)
		}
	}

	/**
	Reads the items between an opening bracket and its `closing` bracket, separated by commas, with no trailing comma.
	*/
	private mutating func readItems(closing: UInt8, readItem: (inout Self) throws -> Void) throws {
		depth += 1
		defer {
			depth -= 1
		}

		if depth == Parser.maximumDepth + 1 {
			firstLevelPastMaximumStart = position
		}

		// A tagged scalar is an object, one level deeper than the value it stands for. So what fails here in tagged JSON is a container in that extra level, and the error names the container around it, which is the real array or object that is too deep.
		guard depth <= Parser.maximumDepth + (isTagged ? 1 : 0) else {
			throw error("The JSON is nested more than \(Parser.maximumDepth) levels deep, which is the most SOML allows", at: firstLevelPastMaximumStart)
		}

		position += 1
		skipWhitespace()

		if current == closing {
			position += 1
			return
		}

		while true {
			try readItem(&self)
			skipWhitespace()

			if current == closing {
				position += 1
				return
			}

			guard current == .comma else {
				throw error("Expected “,” or “\(Character(Unicode.Scalar(closing)))”")
			}

			position += 1
			skipWhitespace()
		}
	}

	private mutating func readString() throws -> String {
		position += 1
		var runStart = position

		// The bytes of a string with escapes. A string without escapes is decoded from the input directly.
		var unescaped: [UInt8]?

		while true {
			guard let byte = current else {
				throw error("The string has no closing quote")
			}

			switch byte {
			case .doubleQuote:
				defer {
					position += 1
				}

				guard var unescaped else {
					return String(decoding: bytes[runStart..<position], as: UTF8.self)
				}

				unescaped += bytes[runStart..<position]
				return String(decoding: unescaped, as: UTF8.self)
			case .backslash:
				// Appended in place, because a new array for each escape would copy the bytes before it again, which takes quadratic time.
				if unescaped == nil {
					unescaped = []
				}

				unescaped! += bytes[runStart..<position]
				unescaped!.appendScalar(try readEscape())
				runStart = position
			case .carriageReturn:
				// The error of an escaped one, because escaping it, as JSON requires, would not make the string one that SOML can hold.
				throw error("A string cannot contain a carriage return, because SOML cannot represent one")
			case ..<0x20:
				// A raw carriage return is handled above, so this is any other raw control character.
				throw error("A control character must be escaped in a JSON string")
			default:
				position += 1
			}
		}
	}

	/**
	Reads an escape. A `\u` escape of a surrogate must be one of a pair, because SOML, like any Unicode text, has no lone surrogates.
	*/
	private mutating func readEscape() throws -> Unicode.Scalar {
		let start = position
		position += 1

		guard let byte = current else {
			throw error("The string has no closing quote")
		}

		position += 1

		let escapedScalar: Unicode.Scalar? = switch byte {
		case .doubleQuote:
			"\""
		case .backslash:
			"\\"
		case .slash:
			"/"
		case .lowercaseB:
			"\u{8}"
		case .lowercaseF:
			"\u{C}"
		case .lowercaseN:
			"\n"
		case .lowercaseR:
			"\r"
		case .lowercaseT:
			"\t"
		default:
			nil
		}

		if let scalar = escapedScalar {
			guard scalar != "\r" else {
				throw error("A string cannot contain a carriage return, because SOML cannot represent one", at: start)
			}

			return scalar
		}

		guard byte == .lowercaseU else {
			throw error("Invalid escape. The escapes are \\\", \\\\, \\/, \\b, \\f, \\n, \\r, \\t, and \\u with four hex digits", at: start)
		}

		let unit = try readCodeUnit(escapeStart: start)

		guard UTF16.isLeadSurrogate(unit) else {
			guard unit != 0x0D else {
				throw error("A string cannot contain a carriage return, because SOML cannot represent one", at: start)
			}

			guard let scalar = Unicode.Scalar(unit) else {
				throw error("A lone surrogate is not text, so SOML cannot hold it", at: start)
			}

			return scalar
		}

		guard bytes[position...].starts(with: [.backslash, .lowercaseU]) else {
			throw error("A lone surrogate is not text, so SOML cannot hold it", at: start)
		}

		// Bad digits in the trail escape are reported at the trail, not at the lead, whose digits are fine.
		let trailStart = position
		position += 2
		let trail = try readCodeUnit(escapeStart: trailStart)

		guard UTF16.isTrailSurrogate(trail) else {
			throw error("A lone surrogate is not text, so SOML cannot hold it", at: start)
		}

		// Both surrogate ranges were checked above; let the standard UTF-16 codec combine them.
		var encoded = UTF16.EncodedScalar(containing: unit)
		encoded.append(trail)
		return UTF16.decode(encoded)
	}

	/**
	Reads the four hex digits of a `\u` escape.
	*/
	private mutating func readCodeUnit(escapeStart: Int) throws -> UInt16 {
		// UInt16(String(...), radix: 16) accepts signs and measured slower even with separate hex validation; JSON requires exactly four hex digits.
		var unit: UInt16 = 0

		for _ in 0..<4 {
			guard
				let byte = current,
				let digit = byte.hexadecimalDigitValue
			else {
				throw error("Invalid “\\u” escape. It needs four hex digits", at: escapeStart)
			}

			unit = unit << 4 | UInt16(digit)
			position += 1
		}

		return unit
	}

	/**
	Reads `true`, `false`, `null`, or a number as RFC 8259 writes it: `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`.
	*/
	private mutating func readScalar() throws -> SOML.Value {
		let keyword: (text: StaticString, value: SOML.Value)? = switch current {
		case .lowercaseT:
			("true", .bool(true))
		case .lowercaseF:
			("false", .bool(false))
		case .lowercaseN:
			("null", .null)
		default:
			nil
		}

		if let keyword {
			guard keyword.text.withUTF8Buffer({ bytes[position...].starts(with: $0) }) else {
				throw error("Expected a value")
			}

			position += keyword.text.utf8CodeUnitCount
			return keyword.value
		}

		guard
			let byte = current,
			byte == .hyphen || byte.isASCIIDigit
		else {
			throw error(current == nil ? "Expected a value, but the text ended" : "Expected a value")
		}

		let start = position

		if current == .hyphen {
			position += 1
		}

		let integerDigits = try skipDigits(numberStart: start)

		guard integerDigits.count == 1 || integerDigits.first != .digitZero else {
			throw error("Invalid number. A number cannot have a leading zero", at: start)
		}

		var isFloat = false

		if current == .dot {
			isFloat = true
			position += 1
			_ = try skipDigits(numberStart: start)
		}

		if current?.isASCIIExponentMarker == true {
			isFloat = true
			position += 1

			if current == .plus || current == .hyphen {
				position += 1
			}

			_ = try skipDigits(numberStart: start)
		}

		let token = bytes[start..<position]

		guard isFloat else {
			let isNegative = token.first == .hyphen
			guard let value = Int64(validatedDigits: token.dropFirst(isNegative ? 1 : 0), isNegative: isNegative) else {
				throw error("The int \(token.abbreviatedASCII) is outside the 64-bit range of a SOML int", at: start)
			}

			return .int(value)
		}

		guard
			let value = Parser.double(fromDecimal: token),
			value.isFinite
		else {
			throw error("The float \(token.abbreviatedASCII) is too large for a 64-bit float", at: start)
		}

		// A literal with a nonzero digit before its exponent is not zero, so it must not silently become zero, as in SOML.
		guard
			value != 0 || !token.hasNonzeroSignificand
		else {
			throw error("The float \(token.abbreviatedASCII) is too small for a 64-bit float, so it would become 0.0", at: start)
		}

		return .float(value)
	}

	private mutating func skipDigits(numberStart: Int) throws -> ArraySlice<UInt8> {
		let digitsStart = position

		while
			let byte = current,
			byte.isASCIIDigit
		{
			position += 1
		}

		guard position > digitsStart else {
			throw error("Invalid number", at: numberStart)
		}

		return bytes[digitsStart..<position]
	}

	/**
	The value of a tagged scalar. Its text must be its canonical text, so `+5` is not an int and `1e-400` is not a float.
	*/
	private func taggedScalar(type: String, text: String, at offset: Int) throws -> SOML.Value {
		// Every type is ASCII. `==` normalizes a string that is not, which takes quadratic time for a long run of combining marks, so such a type goes to the error without a comparison.
		let value: SOML.Value? = switch type.isASCII ? type : "" {
		case "string":
			.string(text)
		case "int":
			Int64(text).map { .int($0) }
		case "float":
			Double(text).flatMap { $0.isNaN ? nil : .float($0) }
		case "bool":
			Bool(text).map { .bool($0) }
		case "null":
			.null
		case "instant":
			SOML.Instant(text).map { .instant($0) }
		case "duration":
			Int64(text).map { .duration(.nanoseconds($0)) }
		default:
			throw error("Unknown type “\(type.forMessage)”. The types are string, int, float, bool, null, instant, and duration", at: offset)
		}

		// Compared by scalars, because canonical form is exact text, and `==` normalizes, which takes quadratic time for a long run of combining marks.
		guard
			let value,
			value.tag?.value.hasSameScalars(as: text) == true
		else {
			// The canonical text of a duration in SOML, like `1h30m`, is not its tagged value.
			let form = type == "duration" ? "A tagged duration is its length in nanoseconds, as an int in canonical form, like “5400000000000”" : "A tagged value must be in canonical form"
			throw error("Invalid \(type) “\(text.forMessage)”. \(form)", at: offset)
		}

		return value
	}
}

/**
Writes JSON text, indented with tabs.
*/
private struct JSONWriter {
	let isTagged: Bool
	var output = [UInt8]()

	/**
	The keys and indices to the value being written, for an error.
	*/
	private var path = [SOMLCodingKey]()

	init(isTagged: Bool) {
		self.isTagged = isTagged
	}

	mutating func write(_ value: SOML.Value, level: Int) throws(SOML.JSONError) {
		if
			case .string(let string) = value,
			string.hasCarriageReturn
		{
			throw unrepresentable("A string cannot contain a carriage return, because SOML cannot represent one")
		}

		if
			isTagged,
			let tag = value.tag
		{
			try writeContainer(count: 2, brackets: (.openBrace, .closeBrace), level: level) { (writer, index) throws(SOML.JSONError) in
				writer.appendString(index == 0 ? "type" : "value")
				writer.output += [.colon, .space]
				writer.appendString(index == 0 ? tag.type : tag.value)
			}

			return
		}

		switch value {
		case .array(let items):
			try checkDepth(level)
			try writeContainer(count: items.count, brackets: (.openBracket, .closeBracket), level: level) { (writer, index) throws(SOML.JSONError) in
				writer.path.append(SOMLCodingKey(intValue: index))
				try writer.write(items[index], level: level + 1)
				writer.path.removeLast()
			}
		case .object(let object):
			try checkDepth(level)
			try writeContainer(count: object.count, brackets: (.openBrace, .closeBrace), level: level) { (writer, index) throws(SOML.JSONError) in
				let (key, member) = object[index]
				writer.path.append(SOMLCodingKey(stringValue: key))
				defer {
					writer.path.removeLast()
				}

				guard !key.hasCarriageReturn else {
					throw writer.unrepresentable("A key cannot contain a carriage return, because SOML cannot represent one")
				}

				writer.appendString(key)
				writer.output += [.colon, .space]
				try writer.write(member, level: level + 1)
			}
		case .string(let string):
			appendString(string)
		case .int(let int):
			// The magnitude, because negating `Int64.min` overflows.
			output.appendSignedDecimal(int)
		case .float(let float):
			guard float.isFinite else {
				throw unrepresentable("JSON has no \(value.description)")
			}

			float.appendCanonical(to: &output)
		case .bool(let bool):
			output.appendUTF8(bool ? "true" : "false")
		case .null:
			output.appendUTF8("null")
		case .instant(let instant):
			output.append(.doubleQuote)
			instant.appendCanonical(to: &output)
			output.append(.doubleQuote)
		case .duration(let duration):
			guard let nanoseconds = duration.exactNanoseconds else {
				throw unrepresentable(duration.unrepresentableReason)
			}

			output.append(.doubleQuote)
			Duration.appendCanonical(nanoseconds: nanoseconds, to: &output)
			output.append(.doubleQuote)
		}
	}

	private mutating func writeContainer(count: Int, brackets: (opening: UInt8, closing: UInt8), level: Int, writeEntry: (inout Self, Int) throws(SOML.JSONError) -> Void) throws(SOML.JSONError) {
		output.append(brackets.opening)

		guard count > 0 else {
			output.append(brackets.closing)
			return
		}

		for index in 0..<count {
			if index > 0 {
				output.append(.comma)
			}

			output.append(.lineFeed)
			output.appendIndentation(level + 1)
			try writeEntry(&self, index)
		}

		output.append(.lineFeed)
		output.appendIndentation(level)
		output.append(brackets.closing)
	}

	/**
	An array or an object written at `level` is at nesting level `level + 1`, which must be within the limit of the reader, so the JSON reads back.
	*/
	private func checkDepth(_ level: Int) throws(SOML.JSONError) {
		guard level < Parser.maximumDepth else {
			throw unrepresentable("The value is nested more than \(Parser.maximumDepth) levels deep, which is the most SOML allows")
		}
	}

	/**
	The error for a value that JSON cannot hold, with where it is.
	*/
	private func unrepresentable(_ reason: String) -> SOML.JSONError {
		SOML.JSONError(message: reason + path.locationSuffix, location: nil)
	}

	/**
	Appends a JSON string. Every control character, C0, DEL, and C1, is escaped, so no escape sequence reaches a terminal raw. Other invisible characters, such as U+200B, are text, and are written as they are.

	Control escapes are padded with zero bytes directly, without making a padded string.
	*/
	private mutating func appendString(_ string: String) {
		string.withUTF8Buffer { bytes in
			output.append(.doubleQuote)

			// Most strings need no escape, so their bytes are copied as they are. A C1 control is U+0080 to U+009F, which UTF-8 writes as 0xC2 and then 0x80 to 0x9F.
			var runStart = 0
			var index = 0

			while index < bytes.count {
				let byte = bytes[index]
				let isC1Control = byte == 0xC2 && index + 1 < bytes.count && bytes[index + 1] <= 0x9F

				guard byte < 0x20 || byte == 0x7F || isC1Control || byte == .doubleQuote || byte == .backslash else {
					index += 1
					continue
				}

				output.append(contentsOf: bytes[runStart..<index])
				output.append(.backslash)

				switch byte {
				case .doubleQuote, .backslash:
					output.append(byte)
				case .lineFeed:
					output.append(.lowercaseN)
				case .tab:
					output.append(.lowercaseT)
				default:
					let control = isC1Control ? bytes[index + 1] : byte
					output.append(.lowercaseU)
					output.append(.digitZero)
					output.append(.digitZero)
					output.append((control >> 4).lowercaseHexadecimalDigit)
					output.append((control & 0xF).lowercaseHexadecimalDigit)
				}

				index += isC1Control ? 2 : 1
				runStart = index
			}

			output.append(contentsOf: bytes[runStart..<bytes.count])
			output.append(.doubleQuote)
		}

	}
}

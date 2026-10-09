extension SOML {
	/**
	An error thrown when a document is not valid SOML. `SOML.Document.error(_:at:)` also makes one, for a problem that an app finds in a valid document.

	```swift
	do {
		_ = try SOML.Value(parsing: "a: 1\na: 2")
	} catch {
		print(error)
		//=> Duplicate key a (line 2, column 1)
	}
	```
	*/
	public struct ParseError: Error, Sendable, Hashable, CustomStringConvertible {
		/**
		What is wrong, without the position. For a document that is not valid, the message matches the `reason` of the JavaScript reference implementation, except that character names come from Swift’s Unicode properties and can differ.
		*/
		public let message: String

		/**
		Where the problem is in the document.
		*/
		public let location: SOML.Location

		/**
		Up to three lines of the document ending at the problem, with a caret under it. A long line is clipped around the problem. Characters that a terminal acts on rather than shows are replaced with U+FFFD. The format is the same as in the JavaScript reference implementation.

		```
		  1 | name: 'api'
		> 2 | port: eighty
		    |       ^
		```
		*/
		public let codeFrame: String

		/**
		The error for a problem at a byte offset in a document.
		*/
		init(message: String, offset: Int, in bytes: [UInt8]) {
			self.message = message.sanitizedForTerminal
			self.location = SOML.Location(offset: offset, in: bytes)
			self.codeFrame = Self.codeFrame(of: bytes, offset: location.offset, line: location.line)
		}

		/**
		The message followed by the position, like `Duplicate key a (line 2, column 1)`.
		*/
		public var description: String {
			"\(message) (\(location))"
		}
	}
}

extension SOML.ParseError {
	private static let contextLineCount = 2
	private static let maximumLineWidth = 100

	private static func codeFrame(of bytes: [UInt8], offset: Int, line: Int) -> String {
		// The error line and up to two lines before it, found by scanning back from the error, so that an error late in a long document does not split the whole document.
		var lineStarts = [bytes[..<offset].lastIndex(of: .lineFeed).map { $0 + 1 } ?? 0]

		while
			lineStarts.count <= contextLineCount,
			let lineStart = lineStarts.last,
			lineStart > 0
		{
			let previousLineEnd = lineStart - 1
			lineStarts.append(bytes[..<previousLineEnd].lastIndex(of: .lineFeed).map { $0 + 1 } ?? 0)
		}

		lineStarts.reverse()

		let firstLine = line - lineStarts.count + 1
		let gutterWidth = String(line).utf8.count
		var output = [String]()

		for (index, lineStart) in lineStarts.enumerated() {
			let number = firstLine + index
			let isErrorLine = number == line
			let lineEnd = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : bytes.count

			// Only the bytes near the error are decoded, so that a huge line, like a minified document, does not make the error slow. The window holds up to one scalar more than the clipped line shows on each side, so that a cut side still gets its `…` below, and it starts and ends at the start of a scalar or at the ends of the line, so that it decodes to the same scalars as the whole line does there.
			let anchor = isErrorLine ? offset : lineStart
			let window = codeFrameWindow(in: bytes, around: anchor, line: lineStart..<lineEnd)
			let windowStart = window.lowerBound
			let windowEnd = window.upperBound

			let lineText = Array(String(decoding: bytes[windowStart..<windowEnd], as: UTF8.self).sanitizedForTerminal.unicodeScalars)
			let pointer = isErrorLine ? String(decoding: bytes[windowStart..<offset], as: UTF8.self).unicodeScalars.count : 0
			let (text, clippedPointer) = clipped(lineText, pointer: pointer)
			let numberText = String(number)
			let paddedNumber = String(repeating: " ", count: gutterWidth - numberText.utf8.count) + numberText
			let gutter = "\(isErrorLine ? ">" : " ") \(paddedNumber) |"
			output.append(text.isEmpty ? gutter : "\(gutter) \(String(String.UnicodeScalarView(text)))")

			guard isErrorLine else {
				continue
			}

			// Tabs are kept, so that the caret lines up whatever the tab width is.
			let padding = String(String.UnicodeScalarView(text.prefix(clippedPointer).map { $0 == "\t" ? "\t" : " " }))
			output.append("  \(String(repeating: " ", count: gutterWidth)) | \(padding)^")
		}

		return output.joined(separator: "\n")
	}

	/**
	The UTF-8 window decoded for one code-frame line, with enough context on either side for clipping.
	*/
	static func codeFrameWindow(in bytes: [UInt8], around anchor: Int, line: Range<Int>) -> Range<Int> {
		var windowStart = anchor
		var scalarsBefore = 0

		while
			windowStart > line.lowerBound,
			scalarsBefore <= maximumLineWidth,
			anchor - windowStart < 4 * (maximumLineWidth + 1)
		{
			windowStart -= 1

			if !bytes[windowStart].isUTF8ContinuationByte {
				scalarsBefore += 1
			}
		}

		var windowEnd = anchor
		var scalarsAfter = 0

		while
			windowEnd < line.upperBound,
			windowEnd - anchor < 4 * (maximumLineWidth + 1),
			bytes[windowEnd] != .lineFeed
		{
			if !bytes[windowEnd].isUTF8ContinuationByte {
				guard scalarsAfter <= maximumLineWidth else {
					break
				}

				scalarsAfter += 1
			}

			windowEnd += 1
		}

		return windowStart..<windowEnd
	}

	/**
	A long line, such as a minified document, cut to a window around the pointer, with `…` where it was cut.

	As in the reference implementation, the width is counted in UTF-16 code units, and a scalar that the window would cut in half is left out.
	*/
	private static func clipped(_ text: [Unicode.Scalar], pointer: Int) -> (text: [Unicode.Scalar], pointer: Int) {
		// Each astral scalar adds a second UTF-16 code unit. Lines that fit need no offset storage.
		let utf16Count = text.count + text.count(where: { UTF16.width($0) == 2 })

		guard utf16Count > maximumLineWidth else {
			return (text, pointer)
		}

		// The UTF-16 offset of the start of each scalar, and of the end of the text. A running-sum map followed by [0] + allocates a second array; initialize the exact storage in one borrowed span instead.
		let offsets = [Int](capacity: text.count + 1) { output in
			output.append(0)
			var offset = 0

			for scalar in text {
				offset += UTF16.width(scalar)
				output.append(offset)
			}
		}

		let startOffset = max(0, min(offsets[pointer] - maximumLineWidth / 2, utf16Count - maximumLineWidth))
		let start = offsets.firstIndex { $0 >= startOffset } ?? 0
		let end = offsets.lastIndex { $0 <= startOffset + maximumLineWidth } ?? text.count
		let prefix: [Unicode.Scalar] = start > 0 ? ["…"] : []
		let suffix: [Unicode.Scalar] = end < text.count ? ["…"] : []
		return (prefix + text[start..<end] + suffix, pointer - start + prefix.count)
	}
}

extension Unicode.Scalar {
	/**
	Whether a terminal acts on the scalar rather than shows it: a control character other than tab, or a bidirectional control, which can reorder the text around it.
	*/
	fileprivate var isUnsafeForTerminal: Bool {
		(properties.generalCategory == .control && self != "\t") || properties.isBidiControl
	}
}

/**
A recursive-descent parser over the UTF-8 bytes of a document.

It works on bytes rather than `Character`s, because Swift treats `"\r\n"` as one character and joins a combining mark to the quote before it.
*/
struct Parser {
	/**
	The supported parse entry points, with their names in diagnostics.
	*/
	private enum TextKind: String {
		case document
		case value
		case keyPath = "key path"
	}

	/**
	The nesting limit from the spec, which also keeps hostile input from overflowing the stack.

	Every array and object is one level, including the top-level collection, with or without braces. The limit is exact: a reader must accept this depth and reject anything deeper. The parser, the decoder, and the canonical writer recurse once per level, and 100 levels fit comfortably in the 512 KB stack of a secondary thread, even in a debug build, where frames are large.
	*/
	static let maximumDepth = 100

	/**
	The most that a diagnosis scans for the text it shows or suggests, as in the reference implementation, so that a huge token does not make an error slow. A suggestion that long is cut short in the message anyway. The reference implementation counts UTF-16 code units, which `diagnosisLimit(from:)` measures for text that can hold any character, and which are bytes for the ASCII tokens of numbers, instants, durations, and bare keys.
	*/
	private static let maximumDiagnosedLength = 1000

	/**
	The hint for a character that a bare key cannot hold, where a key was meant.
	*/
	private static let keyQuotingHint = ". A key that contains characters other than letters, digits, “_”, and “-” must be quoted"

	/**
	The message for a backslash at the end of a line or of the document in a `"..."` string.
	*/
	private static let backslashAtEndMessage = #"A backslash must be followed by an escape character. Use \\ for a literal backslash, or a '...' string"#

	/**
	How an instant is written, for the messages about one that is not.
	*/
	private static let instantForm = "An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"

	private let bytes: [UInt8]
	private var position = 0
	private var depth = 0

	/**
	What the text is, for messages about its end, like “the end of the document”.
	*/
	private let textKind: TextKind

	private init(bytes: [UInt8], textKind: TextKind = .document) {
		self.bytes = bytes
		self.textKind = textKind
	}

	/**
	Parses a whole document.
	*/
	static func parseDocument(_ bytes: [UInt8]) throws(SOML.ParseError) -> SOML.Value {
		try parse(bytes, textKind: .document) { try $0.parseDocument() }
	}

	/**
	Parses text that is keys joined with `.`, each written as a SOML key, like `server.'the name'`, and nothing else. It is the syntax of `SOML.KeyPath`, not of a document, where a key is never a path.
	*/
	static func parseKeyPath(_ bytes: [UInt8]) throws(SOML.ParseError) -> [String] {
		try parse(bytes, textKind: .keyPath) { parser in
			var keys = [try parser.parseKey()]

			while parser.byte(at: parser.position) == .dot {
				parser.position += 1
				keys.append(try parser.parseKey(isAfterDot: true))
			}

			try parser.expectEnd()
			return keys
		}
	}

	/**
	Parses text that is one value, like `0o644` or `[1, 2]`, and nothing else.
	*/
	static func parseValue(_ bytes: [UInt8]) throws(SOML.ParseError) -> SOML.Value {
		try parse(bytes, textKind: .value) { parser in
			let value = try parser.parseValue()
			try parser.expectEnd()
			return value
		}
	}

	/**
	Checks the encoding and runs a parse.

	The parser uses untyped `throws` inside, because in a debug build every `try` of a typed throw reserves stack space for the error, which made each nesting level cost about 3 KB.
	*/
	private static func parse<Result>(_ bytes: [UInt8], textKind: TextKind, _ body: (inout Parser) throws -> Result) throws(SOML.ParseError) -> Result {
		do {
			var parser = Parser(bytes: bytes, textKind: textKind)
			try parser.checkEncoding()
			return try body(&parser)
		} catch let error as SOML.ParseError {
			throw error
		} catch {
			preconditionFailure("The parser only throws SOML.ParseError, but it threw \(error).")
		}
	}

	private func expectEnd() throws {
		guard position == bytes.count else {
			throw error("Unexpected \(describeCharacter(at: position)) after the end of the \(textKind.rawValue)", at: position)
		}
	}

	// MARK: Encoding

	/**
	Rejects a BOM, any raw control character other than tab and LF (which includes a carriage return), and invalid UTF-8, before anything else, so the rest of the parser can rely on valid input.
	*/
	private func checkEncoding() throws {
		// One pass finds the first invalid UTF-8 sequence and the first raw control character. Tab and LF are the only control characters SOML allows raw.
		let (invalidUTF8Index, controlIndex) = Self.scanEncoding(bytes)

		// The reference implementation decodes the bytes before it reads the text, so invalid UTF-8 anywhere in the document is reported before a BOM or a control character.
		if let offset = invalidUTF8Index {
			guard !Self.isTruncatedUTF8(bytes[offset...]) else {
				throw error("Incomplete UTF-8 sequence at the end of the input", at: offset)
			}

			throw error("Invalid UTF-8 byte 0x\(String(bytes[offset], radix: 16, uppercase: true))", at: offset)
		}

		if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
			throw error("A byte order mark (BOM) is not allowed", at: 0)
		}

		guard let index = controlIndex else {
			return
		}

		if bytes[index] == .carriageReturn {
			throw error("A carriage return (U+000D) is not allowed anywhere. Use LF line endings", at: index)
		}

		let scalar = Unicode.Scalar(bytes[index])
		throw error("A raw control character (U+\(scalar.hexadecimal)) is not allowed anywhere, including in strings and comments. In a string, write it as the escape \\u{\(String(scalar.value, radix: 16))} inside \"...\"", at: index)
	}

	/**
	Whether `bytes`, the rest of a document from its first invalid UTF-8 sequence, are the start of one sequence that the end of the document cuts short.
	*/
	private static func isTruncatedUTF8(_ bytes: ArraySlice<UInt8>) -> Bool {
		guard let lead = bytes.first else {
			return false
		}

		let (length, second) = lead.utf8Sequence

		guard bytes.count < length else {
			return false
		}

		return bytes.dropFirst().enumerated().allSatisfy { index, byte in
			index == 0 ? second.contains(byte) : byte.isUTF8ContinuationByte
		}
	}

	/**
	Finds, in one pass, the first invalid UTF-8 sequence, and the first control character other than tab and LF before it. A sequence is checked with the table of RFC 3629, so it is invalid at the offset where `UTF8.ForwardParser` would fail to decode it. The pass stops at invalid UTF-8, because that is reported first, wherever it is.
	*/
	static func scanEncoding(_ bytes: [UInt8]) -> (invalidUTF8Index: Int?, controlIndex: Int?) {
		// String(validating:as:) plus a control-byte search helped Unicode-heavy input but measured about 3 times slower for long ASCII and 8–12 times slower for short input; invalid input would still need a scan to recover its offset.
		// Keeping the RFC 3629 checks here avoids decoding scalars: substituting `UTF8.ForwardParser` measured 18–138% slower on Unicode input in optimized Swift 6.4 builds on an M4 Pro.
		bytes.withUnsafeBufferPointer { pointer in
			let buffer = pointer.span
			let rawBytes = buffer.bytes
			var controlIndex: Int?
			var index = 0

			while index < buffer.count {
				// ASCII without control characters other than tab and LF, which is most of a document, is skipped eight bytes at a time.
				if buffer.count - index >= 8 {
					#if compiler(>=6.4)
					let word = rawBytes.load(fromByteOffset: index, as: UInt64.self)
					#else
					let word = rawBytes.unsafeLoadUnaligned(fromByteOffset: index, as: UInt64.self)
					#endif

					if !word.hasByteOutsidePrintableASCIITabAndLineFeed {
						index += 8
						continue
					}
				}

				let byte = buffer[index]

				// One comparison catches every byte below 0x20 and every byte from 0x7F up, so printable ASCII takes a single branch.
				guard byte &- 0x20 >= 0x5F else {
					index += 1
					continue
				}

				guard byte >= 0x80 else {
					if
						byte != .tab,
						byte != .lineFeed,
						controlIndex == nil
					{
						controlIndex = index
					}

					index += 1
					continue
				}

				let (length, second) = byte.utf8Sequence

				guard
					length > 0,
					length <= buffer.count - index,
					second.contains(buffer[index + 1])
				else {
					return (index, controlIndex)
				}

				for offset in 2..<length {
					guard buffer[index + offset].isUTF8ContinuationByte else {
						return (index, controlIndex)
					}
				}

				index += length
			}

			return (nil, controlIndex)
		}
	}

	// MARK: Document

	private mutating func parseDocument() throws -> SOML.Value {
		try skipWhitespace(acrossLines: true)

		guard position < bytes.count else {
			throw error("A document must contain an object or an array, but this one is empty", at: position)
		}

		let start = position
		let value: SOML.Value

		switch bytes[position] {
		case .openBrace:
			value = .object(try parseObject())
		case .openBracket:
			value = .array(try parseArray())
		default:
			do {
				value = .object(try parseBareObject())
			} catch {
				if let betterError = bareScalarError(from: start) {
					throw betterError
				}

				throw error
			}
		}

		try skipWhitespace(acrossLines: true)

		guard position == bytes.count else {
			throw error("Unexpected \(describeCharacter(at: position)) after the end of the document", at: position)
		}

		return value
	}

	/**
	A better error for a document that is only a scalar, like `5` or `'hello'`, which is not a document.
	*/
	private func bareScalarError(from start: Int) -> SOML.ParseError? {
		var parser = Parser(bytes: bytes)
		parser.position = start

		guard
			(try? parser.parseValue()) != nil,
			(try? parser.skipWhitespace(acrossLines: true)) != nil,
			parser.position == bytes.count
		else {
			return nil
		}

		return error("A bare value is not a document. A document is an object or an array, so write it as `key: value` or `[value]`", at: start)
	}

	/**
	A brace-less top-level object. Its entries are separated by line breaks, and commas are not allowed.
	*/
	private mutating func parseBareObject() throws -> SOML.Object {
		// The top-level object is a level of nesting, with or without its braces.
		try enterNesting()
		defer {
			depth -= 1
		}

		var members = OrderedMembers<SOML.Value>()
		try parseMember(into: &members)
		var isLineBreakAfter = try skipWhitespaceAfterItem()

		while position < bytes.count {
			guard
				bytes[position] != .comma,
				isLineBreakAfter
			else {
				throw unexpectedAfterEntry()
			}

			try parseMember(into: &members)
			isLineBreakAfter = try skipWhitespaceAfterItem()
		}

		return SOML.Object(members)
	}

	/**
	The error for something other than a line break after a top-level entry.
	*/
	private func unexpectedAfterEntry() -> SOML.ParseError {
		if bytes[position] == .comma {
			return error("Top-level entries are separated by line breaks, not commas. Use braces for a one-line object", at: position)
		}

		return error("Expected a line break before the next entry, but found \(describeCharacter(at: position))\(slashCommentHint(at: position))", at: position)
	}

	// MARK: Whitespace and comments

	/**
	Skips spaces, tabs, and comments, and also line feeds if `acrossLines` is true.
	*/
	private mutating func skipWhitespace(acrossLines: Bool) throws {
		while position < bytes.count {
			switch bytes[position] {
			case .space, .tab:
				position += 1
			case .lineFeed where acrossLines:
				position += 1
			case .hash:
				position = bytes.lineEnd(from: position)
			case .slash where byte(at: position + 1) == .asterisk:
				try skipBlockComment()
			default:
				return
			}
		}
	}

	/**
	Skips the whitespace and comments after a member or an item inside braces or brackets, and returns whether a line break was among them, which separates the item from the next one, as a comma does. A comma must come before any such line break. A line break inside a `/* */` comment does not count, as at the top level, and the line break that ends a `#` comment does.
	*/
	private mutating func skipWhitespaceAfterItem() throws -> Bool {
		var isLineBreakAfter = false

		while position < bytes.count {
			switch bytes[position] {
			case .space, .tab:
				position += 1
			case .lineFeed:
				isLineBreakAfter = true
				position += 1
			case .hash:
				position = bytes.lineEnd(from: position)
			case .slash where byte(at: position + 1) == .asterisk:
				try skipBlockComment()
			default:
				return isLineBreakAfter
			}
		}

		return isLineBreakAfter
	}

	/**
	Skips a block comment. It ends at the first closing delimiter, and the text between the two delimiters cannot contain an opening delimiter. A slash just before the closing delimiter is part of the body, so it does not start a nested comment.
	*/
	private mutating func skipBlockComment() throws {
		let start = position
		var end = start + 2
		var nestedStart: Int?

		while end + 1 < bytes.count, !(bytes[end] == .asterisk && bytes[end + 1] == .slash) {
			if
				nestedStart == nil,
				bytes[end] == .slash,
				bytes[end + 1] == .asterisk
			{
				nestedStart = end
			}

			end += 1
		}

		guard end + 1 < bytes.count else {
			throw error("Unterminated block comment", at: start)
		}

		if
			let nestedStart,
			nestedStart + 1 < end
		{
			throw error("Block comments cannot be nested, and their body may not contain “/*”", at: nestedStart)
		}

		position = end + 2
	}

	// MARK: Members

	/**
	Parses one member and adds it to `members`.
	*/
	private mutating func parseMember(into members: inout OrderedMembers<SOML.Value>) throws {
		let keyStart = position
		let key = try parseKey()

		if byte(at: position) == .dot {
			throw dotInKey(keyStart: keyStart)
		}

		guard byte(at: position) == .colon else {
			throw missingColon(keyStart: keyStart)
		}

		position += 1
		try skipWhitespace(acrossLines: true)

		let value: SOML.Value

		// A scalar value is followed by what can end it, which `parseValue()` checks, so an error there comes before one about the key, as in the reference implementation. A quoted key, like `'b'` in `a:` followed by `'b': 1` on the next line, reads as a string value that a “:” follows.
		do {
			value = try parseValue()
		} catch {
			try diagnoseBadValue(keyStart: keyStart, valueError: error)
			throw error
		}

		guard members.position(of: key) == nil else {
			throw error("Duplicate key \(Self.describeKey(key))", at: keyStart)
		}

		members.append(value, forKey: key)
	}

	/**
	Whether the “:” at `colon` can end a key, because whitespace, a line break, or the end follows it.
	*/
	private func isKeyEnd(colon: Int) -> Bool {
		byte(at: colon + 1).map { $0.isSpaceOrTab || $0 == .lineFeed } ?? true
	}

	/**
	Throws an error that says what the entry at `keyStart` was meant to be when that is clear, as the reference implementation does. `valueError` is the error of its value. Otherwise it changes nothing.

	It reads the key again rather than taking what `parseMember(into:)` knows, so that the frame of that recursive function stays small.
	*/
	private mutating func diagnoseBadValue(keyStart: Int, valueError: any Error) throws {
		let end = position
		position = keyStart

		defer {
			position = end
		}

		let key = try parseKey()
		let colon = position
		position += 1
		try skipWhitespace(acrossLines: false)
		let isValueOnNextLine = byte(at: position) == .lineFeed
		try skipWhitespace(acrossLines: true)
		let valueStart = position

		// A key that contains a “:”, like `12:30: 'lunch'`, ends at the first “:”, and the rest is read as the value.
		if byte(at: colon + 1)?.isBareKeyByte == true {
			try diagnoseKeyWithColon(keyStart: keyStart)
		}

		let commentNote = commentAsValueNote(colon: colon)

		if isValueOnNextLine {
			try diagnoseMissingValue(at: valueStart, parent: key, keyStart: keyStart, commentNote: commentNote)
		}

		// A value that was left out at the end of the document or of an object.
		guard
			let commentNote,
			let valueError = valueError as? SOML.ParseError,
			valueError.location.offset == valueStart,
			byte(at: valueStart) == nil || byte(at: valueStart) == .closeBrace
		else {
			return
		}

		throw error("\(valueError.message)\(commentNote)", at: valueStart)
	}

	/**
	Throws when the bare key at `keyStart` is followed directly by a “:” and more of a key, up to a “:” that ends the key, as in `a:b: 1`.
	*/
	private func diagnoseKeyWithColon(keyStart: Int) throws {
		for index in keyStart..<min(bytes.count, keyStart + Self.maximumDiagnosedLength) {
			let byte = bytes[index]

			if byte == .colon {
				if isKeyEnd(colon: index) {
					throw error("A key that contains “:” must be quoted, as in '\(makeString(keyStart..<index).shortened())'", at: keyStart)
				}
			} else if !byte.isBareKeyByte {
				return
			}
		}
	}

	/**
	The note for a “#” directly after the “:” at `colon`, as in `color: #FFF`, which starts a comment rather than a value, or `nil` when there is none.
	*/
	private func commentAsValueNote(colon: Int) -> String? {
		var hash = colon + 1

		while byte(at: hash)?.isSpaceOrTab == true {
			hash += 1
		}

		// A “#” followed by a space, or by another “#”, starts an ordinary comment. A separator or a closing bracket after the value is not part of it.
		func endsValue(_ byte: UInt8) -> Bool {
			byte.isSOMLWhitespace || byte == .comma || byte == .closeBracket || byte == .closeBrace
		}

		guard
			byte(at: hash) == .hash,
			let first = byte(at: hash + 1),
			first != .hash,
			!endsValue(first)
		else {
			return nil
		}

		var end = hash + 2
		let limit = diagnosisLimit(from: hash)

		while
			end < limit,
			!endsValue(bytes[end])
		{
			end += 1
		}

		return ". “#” starts a comment, so a value that starts with “#” must be quoted\(Self.quotingExample(makeString(hash..<end)))"
	}

	/**
	Throws when the text at `start`, where a value on the line after its key starts, is a key followed by a “:”, because then the value was left out, as in `a:` followed by `b: 1` on the next line, and the next key was read as the value, or when it is a YAML list. The reference implementation reports that failure as what it is, at the key. Otherwise it changes nothing.

	The note is the one for a value that starts with “#”, from `commentAsValueNote(colon:)`.
	*/
	private mutating func diagnoseMissingValue(at start: Int, parent: String, keyStart: Int, commentNote: String?) throws {
		// A YAML block sequence.
		if
			byte(at: start) == .hyphen,
			byte(at: start + 1)?.isSpaceOrTab == true
		{
			throw error("Expected a value, but found a “-” list. An array is written in brackets, as in [80, 443]", at: start)
		}

		let end = position
		position = start

		defer {
			position = end
		}

		guard let key = try? parseKey() else {
			return
		}

		// Whitespace or the end follows the “:” of a bare key. A digit follows the “:” in an instant, like `2026-09-19T25:00:00Z`, whose own error is more precise. A quoted key cannot be part of a value, so anything may follow its “:”.
		guard
			byte(at: position) == .colon,
			bytes[start] == .singleQuote
				|| bytes[start] == .doubleQuote
				|| isKeyEnd(colon: position)
		else {
			return
		}

		let hint = commentNote ?? indentedKeyNote(parent: parent, child: key, keyStart: keyStart, start: start) ?? ""
		throw error("Expected a value, but found the key \(Self.describeKey(key).shortened(to: 200))\(hint)", at: start)
	}

	/**
	The note for the key `child` at `start` when it is indented under the entry with the key `parent` at `keyStart`, whose value is missing, as YAML nests an object, or `nil` when it is not.
	*/
	private func indentedKeyNote(parent: String, child: String, keyStart: Int, start: Int) -> String? {
		guard
			let keyIndentation = indentation(before: keyStart),
			let indentation = indentation(before: start),
			indentation > keyIndentation
		else {
			return nil
		}

		// The keys are written as in a document, so that the suggestion is valid, rather than as JSON strings like the rest of the message.
		return ". Indentation does not nest objects, so write \(CanonicalWriter.key(parent).shortened(to: 200)): {\(CanonicalWriter.key(child).shortened(to: 200)): …}"
	}

	/**
	The number of spaces and tabs before `offset` on its line, or `nil` when something else comes before it.
	*/
	private func indentation(before offset: Int) -> Int? {
		var lineStart = offset

		while
			lineStart > 0,
			bytes[lineStart - 1].isSpaceOrTab
		{
			lineStart -= 1
		}

		guard lineStart == 0 || bytes[lineStart - 1] == .lineFeed else {
			return nil
		}

		return offset - lineStart
	}

	/**
	The error for a `.` after the key at `keyStart`, as in `example.com: 1`, at the `.`. A key is never a path, so the `.` is meant either as part of the key or as nesting.
	*/
	private func dotInKey(keyStart: Int) -> SOML.ParseError {
		let limit = min(bytes.count, keyStart + Self.maximumDiagnosedLength)
		var end = position

		while
			end < limit,
			bytes[end].isBareKeyByte || bytes[end] == .dot
		{
			end += 1
		}

		let key = makeString(keyStart..<end)
		let segments = key.split(separator: ".", omittingEmptySubsequences: false)

		// The suggestions are only given for a bare key whose dots each have a word on both sides, so that both are valid.
		guard
			byte(at: end) == .colon,
			bytes[keyStart].isBareKeyByte,
			!segments.contains(where: \.isEmpty)
		else {
			return error("A key cannot contain “.” unless it is quoted. Quote the whole key, or use braces to nest, as in a: {b: …}", at: position)
		}

		let nested = segments.joined(separator: ": {") + ": …" + String(repeating: "}", count: segments.count - 1)
		return error("A bare key cannot contain “.”. Quote it, as in '\(key.shortened())', or use braces to nest, as in \(nested.shortened())", at: position)
	}

	/**
	The error for a key that a “:” does not follow, in the order of the reference implementation's checks. A problem after spaces is mostly reported where the spaces end.
	*/
	private func missingColon(keyStart: Int) -> SOML.ParseError {
		var next = position

		while next < bytes.count, bytes[next].isSpaceOrTab {
			next += 1
		}

		let nextByte = byte(at: next)

		if
			next > position,
			nextByte == .colon
		{
			return error("Whitespace is not allowed between a key and its “:”", at: position)
		}

		// A block comment followed by the “:” was meant to come before it.
		if
			nextByte == .slash,
			byte(at: next + 1) == .asterisk,
			let commentEnd = firstCommentEnd(from: next + 2),
			byte(at: skipSpaces(from: commentEnd + 2)) == .colon
		{
			return error("A comment is not allowed between a key and its “:”", at: next)
		}

		// A key with a space in it, like `the name: 1`, is reported at the start of the key, where the quote goes. Only a “:” that ends a key counts, because in `server localhost:8080` it does not.
		if
			next > position,
			nextByte?.isBareKeyByte == true,
			let colon = bytes[next...].prefix(while: { $0 != .lineFeed }).firstIndex(of: .colon),
			isKeyEnd(colon: colon),
			bytes[keyStart..<colon].allSatisfy({ $0.isBareKeyByte || $0.isSpaceOrTab })
		{
			let key = bytes[keyStart..<colon].withoutTrailingWhitespace.shortenedASCII()
			return error("A bare key cannot contain spaces. Quote it, as in '\(key.shortened())'", at: keyStart)
		}

		guard
			let current = byte(at: position),
			current != .lineFeed
		else {
			return error("Expected “:” after the key", at: position)
		}

		// A character directly after a bare key is most likely meant to be part of it.
		let previous = bytes[position - 1]
		let isKeyCharacter = previous != .singleQuote && previous != .doubleQuote && next == position && isQuotableKeyStart(at: next)
		return error("Expected “:” after the key, but found \(describeCharacter(at: next))\(isKeyCharacter ? Self.keyQuotingHint : "")", at: next)
	}

	/**
	The offset of the first closing delimiter of a block comment from `start`, or `nil` when there is none.
	*/
	private func firstCommentEnd(from start: Int) -> Int? {
		var index = start

		while index + 1 < bytes.count {
			if
				bytes[index] == .asterisk,
				bytes[index + 1] == .slash
			{
				return index
			}

			index += 1
		}

		return nil
	}

	/**
	The offset after the spaces and tabs from `start` on.
	*/
	private func skipSpaces(from start: Int) -> Int {
		var index = start

		while byte(at: index)?.isSpaceOrTab == true {
			index += 1
		}

		return index
	}

	/**
	Whether the character at `index` may be meant as part of a key: a visible one that has no meaning in the grammar, which includes every bare key character. A `=` is left out, because after a key, as in `name=foo`, it was most likely meant as the `:` of INI and TOML.
	*/
	private func isQuotableKeyStart(at index: Int) -> Bool {
		guard index < bytes.count else {
			return false
		}

		let scalar = scalar(at: index)

		guard
			scalar.properties.generalCategory.isVisible,
			!scalar.properties.isDefaultIgnorableCodePoint,
			!scalar.properties.isWhitespace
		else {
			return false
		}

		return switch scalar {
		case "\"", "#", "'", "*", ",", "/", ":", "=", "[", "]", "{", "}":
			false
		default:
			true
		}
	}

	/**
	The hint for a key that starts with a character a bare key cannot hold, like the `$` in `$schema`, or an empty string for a character with another meaning, like `}`. A key up to a “:” is shown quoted.
	*/
	private func keyQuotingHint() -> String {
		guard isQuotableKeyStart(at: position) else {
			return ""
		}

		let limit = diagnosisLimit(from: position)
		var end = position

		while
			end < limit,
			isQuotableKeyStart(at: end)
		{
			end += scalarLength(at: end)
		}

		guard
			end < limit,
			bytes[end] == .colon
		else {
			return Self.keyQuotingHint
		}

		return "\(Self.keyQuotingHint), as in '\(makeString(position..<end).shortened())'"
	}

	/**
	Parses a key. `isAfterDot` is for a key after the `.` of a key path.
	*/
	private mutating func parseKey(isAfterDot: Bool = false) throws -> String {
		if
			let first = byte(at: position),
			first == .singleQuote || first == .doubleQuote
		{
			if quoteRunLength(at: position) >= 3 {
				throw error("A block string cannot be a key", at: position)
			}

			return try parseSingleLineString()
		}

		let start = position

		while position < bytes.count, bytes[position].isBareKeyByte {
			position += 1
		}

		guard position > start else {
			throw missingKey(isAfterDot: isAfterDot)
		}

		return makeString(start..<position)
	}

	/**
	The error for a character that cannot start a key, or for the end of the text where a key should be.
	*/
	private func missingKey(isAfterDot: Bool) -> SOML.ParseError {
		// A key path is not a document, so it has no table headers.
		if
			textKind == .document,
			byte(at: position) == .openBracket,
			let tableHeaderError = tableHeaderError(at: position, isValue: false)
		{
			return tableHeaderError
		}

		let expectation = isAfterDot ? "Expected a key after “.”" : "Expected a key"

		guard position < bytes.count else {
			return error(expectation, at: position)
		}

		return error("\(expectation), but found \(describeCharacter(at: position))\(keyQuotingHint())\(slashCommentHint(at: position))", at: position)
	}

	// MARK: Values

	private mutating func parseValue() throws -> SOML.Value {
		switch byte(at: position) {
		case .openBrace:
			return .object(try parseObject())
		case .openBracket:
			return .array(try parseArray())
		default:
			return try parseScalar()
		}
	}

	/**
	Parses a string, a keyword, a number, an instant, or a duration, and checks that what follows it can end a value, as the reference implementation does.
	*/
	private mutating func parseScalar() throws -> SOML.Value {
		guard let first = byte(at: position) else {
			throw unexpectedValue()
		}

		let start = position
		let value: SOML.Value
		// An int or a float written with digits.
		var isNumber = false

		if first == .singleQuote || first == .doubleQuote {
			value = .string(try parseString())
		} else if
			first == .lowercaseT,
			skipKeyword("true")
		{
			value = .bool(true)
		} else if
			first == .lowercaseF,
			skipKeyword("false")
		{
			value = .bool(false)
		} else if
			first == .lowercaseN,
			skipKeyword("null")
		{
			value = .null
		} else if
			first == .lowercaseI,
			skipKeyword("infinity")
		{
			value = .float(.infinity)
		} else if
			first == .hyphen,
			skipKeyword("-infinity")
		{
			value = .float(-.infinity)
		} else if first == .hyphen || first.isASCIIDigit {
			value = try parseNumberOrInstant()

			switch value {
			case .int, .float:
				isNumber = true
			default:
				break
			}
		} else {
			throw unexpectedValue()
		}

		if
			let next = byte(at: position),
			!next.isValueEnd
		{
			throw afterValueError(start: start, isNumber: isNumber)
		}

		if
			isNumber,
			byte(at: position)?.isSpaceOrTab == true
		{
			try diagnoseUnitAfterSpace(numberStart: start)
		}

		return value
	}

	/**
	Moves past `word` if it is at the current position, and not the start of a longer word, like `nullable`, and returns whether it did.
	*/
	private mutating func skipKeyword(_ word: StaticString) -> Bool {
		let end = position + word.utf8CodeUnitCount

		guard
			end <= bytes.count,
			word.withUTF8Buffer({ bytes[position..<end].elementsEqual($0) }),
			byte(at: end)?.isBareKeyByte != true
		else {
			return false
		}

		position = end
		return true
	}

	/**
	The error for a character that cannot start a value, or for the end of the text where a value should be.
	*/
	private func unexpectedValue() -> SOML.ParseError {
		guard let first = byte(at: position) else {
			return error("Expected a value, but reached the end of the \(textKind.rawValue)", at: position)
		}

		if first == .plus {
			return error("A “+” sign is not allowed. A number without a sign is positive", at: position)
		}

		// A “.” that no digit follows begins a string, like `.env` or `./foo`, rather than a number.
		if first == .dot {
			return error(byte(at: position + 1)?.isASCIIDigit == true ? "A number cannot begin with “.”; write a digit before it, as in 0.5" : Self.unknownWordMessage(".", text: unquotedText(from: position)), at: position)
		}

		var wordEnd = position

		while byte(at: wordEnd)?.isBareKeyByte == true {
			wordEnd += 1
		}

		guard wordEnd > position else {
			let hint = isBlockScalarIndicator(at: position) ? ". Write a multiline string as a block string, between ''' lines" : slashCommentHint(at: position)
			return error("Expected a value, but found \(describeCharacter(at: position))\(hint)", at: position)
		}

		let word = makeString(position..<min(wordEnd, position + 41))

		// A key where a value should be, as when the value of an entry is left out and the next line has a key, or as in `[a: 1]`, is reported as a key. A word after the “:” of a member and a space is that member's value instead, an unquoted string. Without the space, as in `a:b: 1`, the first “:” was most likely meant as part of the key.
		if
			!isMemberValue(at: position),
			byte(at: wordEnd) == .colon
		{
			return error("Expected a value, but found the key \(word.shortened())", at: position)
		}

		if let tableHeaderError = tableHeaderError(at: position, isValue: true) {
			return tableHeaderError
		}

		return error(Self.unknownWordMessage(word, text: unquotedText(from: position)), at: position)
	}

	/**
	The message for a word where a value should be. `text` is the unquoted string that `word` begins, which the suggestion quotes.
	*/
	private static func unknownWordMessage(_ word: String, text: String) -> String {
		// A keyword hint is only for the word on its own. In `Yes please` or `Nan Goldin`, following it would leave text behind or change the value.
		switch word.utf8.count <= 9 && text.hasSameScalars(as: word) ? word.lowercased() : "" {
		case "true", "false", "yes", "no", "on", "off":
			"“\(word)” is not a value. Booleans are written true and false, in lowercase"
		case "null", "nil", "none", "undefined":
			"“\(word)” is not a value. Null is written null, in lowercase"
		case "nan":
			"NaN is not representable. Use null for a missing value"
		case "inf", "infinity":
			"“\(word)” is not a value. Infinity is written infinity, in lowercase"
		default:
			"Unexpected “\(word.shortened())”. A string value must be quoted\(quotingExample(text))"
		}
	}

	/**
	The error for a character that cannot follow the value that starts at `start`.
	*/
	private func afterValueError(start: Int, isNumber: Bool) -> SOML.ParseError {
		// Go writes microseconds as `µs`, with the micro sign or the Greek letter mu. The duration is only suggested when it is valid, which a number with an exponent or a radix prefix, for example, is not.
		if
			isNumber,
			bytes[position...].starts(with: "\u{B5}s".utf8) || bytes[position...].starts(with: "\u{3BC}s".utf8)
		{
			let number = makeString(start..<position)
			let example = Self.isValidValue(number + "us") ? ", as in \(number.shortened())us" : ""
			return error("The unit for microseconds is written us\(example)", at: position)
		}

		// A `''` inside a '...' string, as SQL and YAML escape a quote, ends the string.
		if
			bytes[position] == .singleQuote,
			bytes[start] == .singleQuote
		{
			return error("There is no '' escape in a '...' string. Write a string that contains ' as \"...\", as in \"it's\"", at: position)
		}

		return error("Unexpected \(describeCharacter(at: position)) after a value", at: position)
	}

	/**
	Whether a YAML literal block scalar indicator, as in `key: |` or `key: |-`, is at `index`, at the end of its line. A folded block scalar, `>`, joins its lines, which a block string does not, so only `|` counts.
	*/
	private func isBlockScalarIndicator(at index: Int) -> Bool {
		guard byte(at: index) == .pipe else {
			return false
		}

		var end = index + 1

		if byte(at: end) == .hyphen || byte(at: end) == .plus {
			end += 1
		}

		while byte(at: end)?.isSpaceOrTab == true {
			end += 1
		}

		return byte(at: end) == nil || byte(at: end) == .lineFeed
	}

	/**
	The hint for a `//` comment at `index`, as in JavaScript, or an empty string when there is none.
	*/
	private func slashCommentHint(at index: Int) -> String {
		byte(at: index) == .slash && byte(at: index + 1) == .slash ? ". A comment starts with “#”" : ""
	}

	private mutating func enterNesting() throws {
		depth += 1

		guard depth <= Self.maximumDepth else {
			throw tooDeep(at: position)
		}
	}

	private mutating func parseObject() throws -> SOML.Object {
		try enterNesting()
		defer {
			depth -= 1
		}

		let start = position
		position += 1
		var members = OrderedMembers<SOML.Value>()

		while true {
			try skipWhitespace(acrossLines: true)

			guard let next = byte(at: position) else {
				throw unterminated("object", "}", start: start)
			}

			if next == .closeBrace {
				position += 1
				return SOML.Object(members)
			}

			try parseMember(into: &members)
			let memberEnd = position
			let isLineBreakAfter = try skipWhitespaceAfterItem()

			guard let separator = byte(at: position) else {
				throw unterminated("object", "}", start: start)
			}

			switch separator {
			case .comma:
				guard !isLineBreakAfter else {
					throw commaOnNextLine()
				}

				position += 1
			case .closeBrace:
				position += 1
				return SOML.Object(members)
			default:
				guard isLineBreakAfter else {
					throw missingSeparator(closing: "}", item: "an object member", itemEnd: memberEnd)
				}
			}
		}
	}

	private mutating func parseArray() throws -> [SOML.Value] {
		try enterNesting()
		defer {
			depth -= 1
		}

		let start = position
		position += 1
		var items = [SOML.Value]()

		while true {
			try skipWhitespace(acrossLines: true)

			guard let next = byte(at: position) else {
				throw unterminated("array", "]", start: start)
			}

			if next == .closeBracket {
				position += 1
				return items
			}

			let item = try parseValue()

			// Room for a few items up front saves the array from growing one step at a time, and an empty array allocates nothing.
			if items.isEmpty {
				items.reserveCapacity(4)
			}

			items.append(item)

			let itemEnd = position
			let isLineBreakAfter = try skipWhitespaceAfterItem()

			guard let separator = byte(at: position) else {
				throw unterminated("array", "]", start: start)
			}

			switch separator {
			case .comma:
				guard !isLineBreakAfter else {
					throw commaOnNextLine()
				}

				position += 1
			case .closeBracket:
				position += 1
				return items
			default:
				guard isLineBreakAfter else {
					throw missingSeparator(closing: "]", item: "an array item", itemEnd: itemEnd)
				}
			}
		}
	}

	/**
	The error for two members or items that nothing separates. A line break between them that does not separate them is inside a block comment, so the hint says that instead.

	Error messages are built in functions like this one rather than inline, which keeps the frames of the recursive functions small, so that deep nesting fits on a secondary thread's stack in a debug build.
	*/
	private func missingSeparator(closing: String, item: String, itemEnd: Int) -> SOML.ParseError {
		let hint = bytes[itemEnd..<position].contains(.lineFeed) ? ". A line break inside a block comment does not separate items" : slashCommentHint(at: position)
		return error("Expected “,”, a line break, or “\(closing)” after \(item), but found \(describeCharacter(at: position))\(hint)", at: position)
	}

	/**
	The error for a comma on a later line than the item before it, as in the comma-first style.
	*/
	private func commaOnNextLine() -> SOML.ParseError {
		error("A comma must be on the same line as the item before it. The line break already separates the items, so remove the comma", at: position)
	}

	private func tooDeep(at offset: Int) -> SOML.ParseError {
		error("The document is nested more than \(Self.maximumDepth) levels deep", at: offset)
	}

	/**
	The error for an object or an array that the document ends inside. It is reported at the opening bracket, as the reference implementation does, because that is the one place that can be fixed.
	*/
	private func unterminated(_ kind: String, _ closing: String, start: Int) -> SOML.ParseError {
		error("Unterminated \(kind): expected “\(closing)”", at: start)
	}

	// MARK: Scalars

	/**
	Parses a number, an instant, or a duration, which starts with a digit or a “-”.

	The token is the longest run of characters that can appear in any of them. No valid document has such a character directly after a scalar, so taking the whole run accepts exactly the documents the grammar accepts, and it lets an error name the whole token. Every problem in it is reported at its start, as the reference implementation does, and the message says which part is wrong.
	*/
	private mutating func parseNumberOrInstant() throws -> SOML.Value {
		let start = position
		position += 1

		while position < bytes.count, bytes[position].isScalarTokenByte {
			position += 1
		}

		let token = bytes[start..<position]

		if token.prefix(10).hasASCIIPattern("0000-00-00") {
			return .instant(try parseInstant(token))
		}

		let kind = Self.numberKind(token)

		if
			kind == nil,
			Self.isDurationLike(token)
		{
			return .duration(.nanoseconds(try parseDuration(token)))
		}

		switch kind {
		case .int:
			return .int(try parseInteger(token))
		case .float:
			return .float(try parseFloat(token))
		case nil:
			throw error(thousandsSeparatorMessage(token) ?? badNumberMessage(token), at: start)
		}
	}

	/**
	Throws for a number followed by a space and a word, like `512 MiB` or `10 seconds`, which is an error anyway. A word followed by more than spaces, a separator, or a comment is left to the general errors, because it may be a key, as in `a: 1 b: 2`, or a sentence.
	*/
	private func diagnoseUnitAfterSpace(numberStart: Int) throws {
		let unitStart = skipSpaces(from: position)
		var unitEnd = unitStart

		while byte(at: unitEnd)?.isASCIILetter == true {
			unitEnd += 1
		}

		let next = skipSpaces(from: unitEnd)
		let unit = makeString(unitStart..<min(unitEnd, unitStart + 41))

		// A keyword after a number is a missing comma.
		guard
			!unit.isEmpty,
			isValueEnd(at: next),
			!["true", "false", "null", "infinity"].contains(unit)
		else {
			return
		}

		let number = makeString(numberStart..<min(position, numberStart + 41))
		// The duration is only suggested when it is valid, which a number with an exponent or a radix prefix, a fraction of a nanosecond, a negative zero, or a value outside the 64-bit range is not. The string is always offered, because a unit like `m` may mean meters rather than minutes.
		let isDurationUnit = Duration.somlUnits.contains { $0.symbol == unit }
		let duration = isDurationUnit && position - numberStart <= 40 && Self.isValidValue(number + unit) ? number.shortened() + unit : "10s"
		throw error("A unit cannot follow a number after a space. Write a duration without the space, as in \(duration), and anything else, such as a size, as a string, as in '\("\(number) \(unit)".shortened())'", at: unitStart)
	}

	/**
	Parses the token of an instant, which starts with a date.
	*/
	private func parseInstant(_ token: ArraySlice<UInt8>) throws -> SOML.Instant {
		let start = token.startIndex

		// A longer token is described from its first part, as in the reference implementation.
		guard token.count <= Self.maximumDiagnosedLength else {
			throw error(badInstantMessage(token), at: start)
		}

		do throws(SOML.Instant.SyntaxError) {
			return try SOML.Instant.parse(token)
		} catch {
			guard let reason = error.reason else {
				throw self.error(badInstantMessage(token), at: start)
			}

			throw self.error("Invalid instant \(token.shortenedASCII()): \(reason)", at: start)
		}
	}

	/**
	The message for a token that starts with a date but does not have the form of an instant. The token ends at the current position.
	*/
	private func badInstantMessage(_ token: ArraySlice<UInt8>) -> String {
		guard token.count <= Self.maximumDiagnosedLength else {
			return "Invalid instant “\(token.shortenedASCII())”. \(Self.instantForm)"
		}

		let text = String(decoding: token, as: UTF8.self)

		// A date, a space, and a time, as TOML and Python write a date and time.
		let timeStart = position + 1
		var timeEnd = position

		if
			byte(at: position) == .space,
			byte(at: timeStart)?.isASCIIDigit == true
		{
			timeEnd = timeStart + 1

			while
				timeEnd - timeStart <= Self.maximumDiagnosedLength,
				byte(at: timeEnd)?.isScalarTokenByte == true
			{
				timeEnd += 1
			}
		}

		let time = timeEnd > timeStart ? bytes[timeStart..<timeEnd] : []
		let isWholeValue = isWholeInstant(endingAt: timeEnd)

		if token.hasASCIIPattern("0000-00-00") {
			guard time.prefix(5).hasASCIIPattern("00:00") else {
				return Self.dateMessage(text)
			}

			return spaceSeparatedInstantMessage(date: text, time: String(decoding: time, as: UTF8.self), isWholeValue: isWholeValue)
		}

		if
			token.count > 10,
			token[token.startIndex + 10] == .lowercaseT
		{
			return "The date and time separator in an instant is an uppercase “T”"
		}

		if token.last == .lowercaseZ {
			return "The UTC offset in an instant is an uppercase “Z”"
		}

		let offset = token.suffix(5)

		if
			offset.count == 5,
			offset.first == .plus || offset.first == .hyphen,
			offset.dropFirst().allSatisfy(\.isASCIIDigit)
		{
			return "An instant's offset is written with a colon, as in +07:00"
		}

		guard Self.isLocalDateTime(token) else {
			return "Invalid instant “\(text.shortened())”. \(Self.instantForm)"
		}

		if let offset = offsetAfterSpace() {
			// The instant has the offset it was meant in, so it is not a local time to write as a string.
			let reason = "An instant's offset follows its time directly, without a space"
			let instant = text + offset
			return Self.isValidValue(instant) ? "\(reason), as in \(instant.shortened())" : reason
		}

		guard isWholeValue else {
			return "An instant needs an offset: Z or ±HH:MM"
		}

		return "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '\(text.shortened())', or add the offset it was meant in"
	}

	/**
	The message for a date alone, which is not an instant. The instant it could be is only shown when the date exists, so that the example is valid.
	*/
	private static func dateMessage(_ date: String) -> String {
		// ISO8601FormatStyle parsing accepts nonexistent dates such as 2026-02-30 by normalizing them; this hint must suggest an instant only when the written date exists.
		let parts = date.split(separator: "-").map { Int($0) ?? 0 }
		let (year, month, day) = (parts[0], parts[1], parts[2])
		let isExisting = year >= 1 && (1...12).contains(month) && day >= 1 && day <= SOML.Instant.daysInMonth(year: year, month: month)
		return "\(date) is a date, not an instant. Write a date as a string, as in '\(date)'\(isExisting ? ". An instant needs a time and an offset, as in \(date)T00:00:00Z" : "")"
	}

	/**
	Whether nothing that may be part of an instant follows an instant token that ends at `end`. More of it may follow, as in `14:00:00,5Z` or `14:00:00[Europe/Oslo]`, and then it may have an offset.
	*/
	private func isWholeInstant(endingAt end: Int) -> Bool {
		isValueEnd(at: end) && !(byte(at: end) == .comma && byte(at: end + 1)?.isASCIIDigit == true)
	}

	/**
	An offset on its own after spaces, as in `2026-09-19T14:00:00 Z`, which belongs directly after the time, or `nil`. The instant token ends at the current position.
	*/
	private func offsetAfterSpace() -> String? {
		let start = skipSpaces(from: position)

		guard
			start > position,
			let first = byte(at: start)
		else {
			return nil
		}

		let isSigned = first == .plus || first == .hyphen
		let end = start + (isSigned ? 6 : 1)

		guard
			first == .uppercaseZ || (isSigned && bytes[(start + 1)...].prefix(5).hasASCIIPattern("00:00")),
			isValueEnd(at: end)
		else {
			return nil
		}

		return makeString(start..<end)
	}

	/**
	The message for a date and a time with a space between them, where an instant has a “T”. Following the example must not turn a local time into UTC silently, so a time without an offset is described as what it is. An instant is only shown when it is valid, so a date that does not exist, a time out of range, or an instant outside the years 0001 to 9999 in UTC gets the general form instead.
	*/
	private func spaceSeparatedInstantMessage(date: String, time: String, isWholeValue: Bool) -> String {
		let separator = "The date and time separator in an instant is an uppercase “T”, not a space"
		let instant = "\(date)T\(time)"

		guard instant.utf8.count <= Self.maximumDiagnosedLength else {
			return "\(separator). \(Self.instantForm)"
		}

		if Self.isValidValue(instant) {
			return "\(separator), as in \(instant.shortened())"
		}

		guard
			isWholeValue,
			Self.isLocalDateTime(instant.utf8),
			Self.isValidValue(instant + "Z")
		else {
			return "\(separator). \(Self.instantForm)"
		}

		return "\(separator), and an instant needs the offset it was meant in, as in \(instant.shortened())Z for UTC. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '\("\(date) \(time)".shortened())'"
	}

	/**
	Whether `text` is a date and a time without an offset, like `2026-09-19T14:00:00` or `2026-09-19T14:00:00.5`.
	*/
	private static func isLocalDateTime(_ text: some Collection<UInt8>) -> Bool {
		let dateTimeLength = 19
		let fraction = text.dropFirst(dateTimeLength)

		guard text.prefix(dateTimeLength).hasASCIIPattern("0000-00-00T00:00:00") else {
			return false
		}

		return fraction.isEmpty || (fraction.first == .dot && fraction.count > 1 && fraction.dropFirst().allSatisfy(\.isASCIIDigit))
	}

	/**
	Whether `text` is one valid value, so that an error message only suggests a fix that works.
	*/
	private static func isValidValue(_ text: String) -> Bool {
		guard case .array(let items) = try? parseDocument(Array("[\(text)]".utf8)) else {
			return false
		}

		return items.count == 1
	}

	/**
	The example in a message that a string must be quoted, which quotes `text` as a `'...'` string. That cannot hold a `'`, so then there is no example.
	*/
	private static func quotingExample(_ text: String) -> String {
		text.contains("'") ? "" : ", as in '\(text.shortened())'"
	}

	/**
	The text from `start` that was most likely meant as one unquoted string, like `John Smith`: up to the end of the line, a comma, a closing bracket, or a comment after a space or a tab, without the spaces and tabs at its end.
	*/
	private func unquotedText(from start: Int) -> String {
		let limit = diagnosisLimit(from: start)
		var end = start

		while end < limit {
			let byte = bytes[end]
			let isComment = byte == .hash || (byte == .slash && self.byte(at: end + 1) == .asterisk)

			if
				byte == .lineFeed
					|| byte == .comma
					|| byte == .closeBracket
					|| byte == .closeBrace
					|| (isComment && end > 0 && bytes[end - 1].isSpaceOrTab)
			{
				break
			}

			end += 1
		}

		while
			end > start,
			bytes[end - 1].isSpaceOrTab
		{
			end -= 1
		}

		return makeString(start..<end)
	}

	/**
	Whether the token at `offset` is the value of a member after its “:” and a space, as in `msg: Error: file not found` or `url: https://example.com`, rather than a key where a value should be.
	*/
	private func isMemberValue(at offset: Int) -> Bool {
		var spacesStart = offset

		while
			spacesStart > 0,
			bytes[spacesStart - 1].isSpaceOrTab
		{
			spacesStart -= 1
		}

		return spacesStart < offset && byte(at: spacesStart - 1) == .colon
	}

	/**
	Where the document's collection starts, after the comments and whitespace before it. It is found again when needed, rather than kept, because every member of the parser is copied into the frames of its recursive functions in a debug build.
	*/
	private var documentStart: Int {
		var parser = Parser(bytes: bytes)
		try? parser.skipWhitespace(acrossLines: true)
		return parser.position
	}

	/**
	The error for a TOML table header, like `[server]` or `[[servers]]` on a line of its own, which reads as an array that holds a word, or as a key that starts with “[”, at `offset`, or `nil` when there is none. Where a value is expected, `isValue`, it is only a table header when its bracket opens the document, because a table cannot be written as an item of an array inside it.
	*/
	private func tableHeaderError(at offset: Int, isValue: Bool) -> SOML.ParseError? {
		let lineStart = bytes[..<offset].lastIndex(of: .lineFeed).map { $0 + 1 } ?? 0
		var index = lineStart

		while byte(at: index)?.isSpaceOrTab == true {
			index += 1
		}

		guard
			!isValue || index == documentStart,
			byte(at: index) == .openBracket
		else {
			return nil
		}

		let diagnosedLine = bytes[lineStart...].prefix(Self.maximumDiagnosedLength)
		let limit = diagnosedLine.firstIndex(of: .lineFeed) ?? diagnosedLine.endIndex
		index += byte(at: index + 1) == .openBracket ? 2 : 1
		let nameStart = index

		// The name is a valid key, so that the suggestion is valid: it starts with a letter or “_”.
		guard
			index < limit,
			bytes[index].isASCIILetter || bytes[index] == .underscore
		else {
			return nil
		}

		while
			index < limit,
			bytes[index].isBareKeyByte
		{
			index += 1
		}

		let nameEnd = index

		guard
			index < limit,
			bytes[index] == .closeBracket
		else {
			return nil
		}

		index += 1

		if
			index < limit,
			bytes[index] == .closeBracket
		{
			index += 1
		}

		while
			index < limit,
			bytes[index].isSpaceOrTab
		{
			index += 1
		}

		guard index == limit else {
			return nil
		}

		let name = makeString(nameStart..<nameEnd).shortened()
		return error("There are no table headers. Write the table as an object, as in \(name): {…}", at: offset)
	}

	// MARK: Numbers

	private enum NumberKind {
		case int
		case float
	}

	/**
	Whether `token` is an int, in any radix, or a float, following the grammar, or `nil` when it is neither. A run of digits may have single underscores between digits.
	*/
	private static func numberKind(_ token: ArraySlice<UInt8>) -> NumberKind? {
		let start = token.startIndex
		let end = token.endIndex

		if
			token[start] == .digitZero,
			let marker = token.dropFirst().first,
			let radix = Int64.SOMLRadix(marker: marker)
		{
			let digitsEnd = skipDigits(token, from: start + 2, where: radix.contains)
			return digitsEnd > start + 2 && digitsEnd == end ? .int : nil
		}

		var index = token[start] == .hyphen ? start + 1 : start

		// The integer part is `0` or has no leading zero.
		let integerEnd = skipIntegerPart(token, from: index)

		guard integerEnd > index else {
			return nil
		}

		index = integerEnd
		var kind = NumberKind.int

		if
			index < end,
			token[index] == .dot
		{
			let fractionEnd = skipDigits(token, from: index + 1, where: \.isASCIIDigit)

			guard fractionEnd > index + 1 else {
				return nil
			}

			index = fractionEnd
			kind = .float
		}

		if
			index < end,
			token[index] == .lowercaseE
		{
			let isNegative = index + 1 < end && token[index + 1] == .hyphen
			let exponentStart = index + (isNegative ? 2 : 1)
			// The exponent follows the same leading-zero rule as the integer part, and its zero has one spelling, `e0`, so `e-0` is not an exponent.
			let exponentEnd = isNegative && exponentStart < end && token[exponentStart] == .digitZero ? exponentStart : skipIntegerPart(token, from: exponentStart)

			guard exponentEnd > exponentStart else {
				return nil
			}

			index = exponentEnd
			kind = .float
		}

		return index == end ? kind : nil
	}

	/**
	Returns the index after a run of digits that may have single underscores between them, or `index` when there is no digit there.
	*/
	private static func skipDigits(_ token: ArraySlice<UInt8>, from index: Int, where isValidDigit: (UInt8) -> Bool) -> Int {
		guard
			index < token.endIndex,
			isValidDigit(token[index])
		else {
			return index
		}

		var index = index + 1

		while index < token.endIndex {
			if isValidDigit(token[index]) {
				index += 1
			} else if
				token[index] == .underscore,
				index + 1 < token.endIndex,
				isValidDigit(token[index + 1])
			{
				index += 2
			} else {
				break
			}
		}

		return index
	}

	/**
	Returns the index after an integer part, which is `0` or digits without a leading zero, or `index` when there is none. Anything after a leading `0`, like the `5` in `05`, is left for the caller to reject.
	*/
	private static func skipIntegerPart(_ token: ArraySlice<UInt8>, from index: Int) -> Int {
		index < token.endIndex && token[index] == .digitZero ? index + 1 : skipDigits(token, from: index, where: \.isASCIIDigit)
	}

	/**
	The value of an int token, which `numberKind(_:)` has checked.
	*/
	private func parseInteger(_ token: ArraySlice<UInt8>) throws -> Int64 {
		let start = token.startIndex

		if token.elementsEqual("-0") {
			throw error("“-0” is not allowed, because zero has one spelling: 0", at: start)
		}

		let isNegative = token[start] == .hyphen
		var radix = Int64.SOMLRadix.decimal
		var digitsStart = isNegative ? start + 1 : start

		// A radix prefix, which `numberKind(_:)` has checked.
		if
			token.count > 2,
			token[start] == .digitZero,
			let prefixedRadix = Int64.SOMLRadix(marker: token[start + 1])
		{
			radix = prefixedRadix
			digitsStart = start + 2
		}

		guard let value = Int64(validatedDigits: token[digitsStart...], radix: radix, isNegative: isNegative) else {
			throw outOfRange(token)
		}

		return value
	}

	private func outOfRange(_ token: ArraySlice<UInt8>) -> SOML.ParseError {
		error("The integer \(token.shortenedASCII()) is outside the 64-bit range (-9223372036854775808 to 9223372036854775807)", at: token.startIndex)
	}

	/**
	The value of a float token, which `numberKind(_:)` has checked.
	*/
	private func parseFloat(_ token: ArraySlice<UInt8>) throws -> Double {
		let digits = token.contains(.underscore) ? token.filter { $0 != .underscore }[...] : token
		guard
			let value = Self.double(fromDecimal: digits),
			value.isFinite
		else {
			let text = token.shortenedASCII()
			throw error("\(text) is too large to be a finite float. Use \(token.first == .hyphen ? "-infinity" : "infinity") if you mean it", at: token.startIndex)
		}

		guard value == 0 else {
			return value
		}

		// A literal with a nonzero digit before its exponent is not zero, so it must not silently become zero.
		guard !digits.hasNonzeroSignificand else {
			let text = token.shortenedASCII()
			throw error("\(text) is too small to be told apart from zero. Write 0.0 if you mean zero", at: token.startIndex)
		}

		// A zero is zero whatever its sign.
		return 0
	}

	/**
	Converts a validated SOML or JSON decimal float literal, without underscores, to the closest `Double`, with ties to even.

	`Double(String)` has two bugs with long text, which I measured with Swift 6.4: it returns `nil` for more than about 10,000 characters, and from 769 significant digits on, it rounds an exact halfway value up instead of to even when the digits past its cutoff are zeros. So text longer than 700 bytes, which is the only text that can have that many digits, is normalized first. Leading and trailing zeros are removed, which does not change the value. A decimal halfway point between two doubles has at most 767 significant digits, so the first 800 significant digits decide the rounding, as long as one more digit records whether anything after them was nonzero.
	*/
	static func double(fromDecimal bytes: ArraySlice<UInt8>) -> Double? {
		// Decimal cannot replace this rounding path: the exact halfway value 1.00000000000000011102230246251565404236316680908203125 became 1.0000000000000004 through Decimal instead of the ties-to-even result 1.0 in Swift 6.4.
		guard bytes.count > 700 else {
			return Double(String(decoding: bytes, as: UTF8.self))
		}

		var index = bytes.startIndex
		let isNegative = bytes.first == .hyphen

		if isNegative {
			index += 1
		}

		// Only the first 800 significant digits and a sticky digit can affect rounding.
		var digits = [UInt8]()
		digits.reserveCapacity(801)
		var leadingZeros = 0
		var hasSignificantDigit = false
		var hasNonzeroRest = false
		var isFraction = false
		// The value is 0.digits times 10^decimalExponent.
		var decimalExponent = 0

		while index < bytes.endIndex {
			let byte = bytes[index]

			if byte == .dot {
				isFraction = true
				index += 1
				continue
			}

			guard byte.isASCIIDigit else {
				break
			}

			if !isFraction {
				decimalExponent += 1
			}

			if
				!hasSignificantDigit,
				byte == .digitZero
			{
				leadingZeros += 1
			} else {
				hasSignificantDigit = true

				if digits.count < 800 {
					digits.append(byte)
				} else if byte != .digitZero {
					hasNonzeroRest = true
				}
			}

			index += 1
		}

		if
			index < bytes.endIndex,
			bytes[index] == .lowercaseE || bytes[index] == .uppercaseE
		{
			index += 1
			let isExponentNegative = index < bytes.endIndex && bytes[index] == .hyphen

			if
				index < bytes.endIndex,
				bytes[index] == .plus || bytes[index] == .hyphen
			{
				index += 1
			}

			// The clamp is far past the range of a double plus any digit count that fits in memory, so the leading-zero adjustment below cannot bring a clamped exponent back into range, and the sum cannot overflow.
			var exponent = 0

			while index < bytes.endIndex, bytes[index].isASCIIDigit {
				exponent = min(exponent, 100_000_000_000_000_000) * 10 + Int(bytes[index] - .digitZero)
				index += 1
			}

			decimalExponent += isExponentNegative ? -exponent : exponent
		}

		decimalExponent -= leadingZeros

		if hasNonzeroRest {
			digits.append(.digitOne)
		} else {
			while digits.last == .digitZero {
				digits.removeLast()
			}
		}

		guard !digits.isEmpty else {
			return 0
		}

		let text = "\(isNegative ? "-" : "")0.\(String(decoding: digits, as: UTF8.self))e\(decimalExponent)"
		return Double(text)
	}

	/**
	The message for a comma used as a thousands separator, as in `[1,000]`, which makes the group after it a separate item that fails only when it has a leading zero, or `nil` when the leading zero of `token` is not after such a comma. Writing that item as a string, as the leading zero message suggests, would parse to the wrong items.
	*/
	private func thousandsSeparatorMessage(_ token: ArraySlice<UInt8>) -> String? {
		let start = token.startIndex

		guard
			token.count == 3,
			token.first == .digitZero,
			token.allSatisfy(\.isASCIIDigit),
			byte(at: start - 1) == .comma
		else {
			return nil
		}

		func groupStart(endingAt groupEnd: Int) -> Int {
			var groupStart = groupEnd

			while
				groupStart > max(0, start - Self.maximumDiagnosedLength),
				bytes[groupStart - 1].isASCIIDigit
			{
				groupStart -= 1
			}

			return groupStart
		}

		var groupEnd = start - 1
		var numberStart = groupStart(endingAt: groupEnd)

		// Earlier groups of three digits, as in `12,345,000`.
		while
			numberStart > max(0, start - Self.maximumDiagnosedLength),
			groupEnd - numberStart == 3,
			byte(at: numberStart - 1) == .comma,
			byte(at: numberStart - 2)?.isASCIIDigit == true
		{
			groupEnd = numberStart - 1
			numberStart = groupStart(endingAt: groupEnd)
		}

		let before = byte(at: numberStart - 1)

		// The first group has one to three digits, which are not the end of a float, of a number with underscores, or of a number with a radix prefix.
		guard
			numberStart < groupEnd,
			numberStart >= groupEnd - 3,
			before != .dot,
			before != .underscore,
			before?.isASCIILetter != true
		else {
			return nil
		}

		// The sign belongs to the number, as in `-1,000`.
		if before == .hyphen {
			numberStart -= 1
		}

		// The groups after it, up to the diagnosed length, as in the reference implementation, which looks at that much of the text.
		let groupsLimit = token.endIndex + Self.maximumDiagnosedLength
		var numberEnd = token.endIndex

		while
			numberEnd + 4 <= groupsLimit,
			byte(at: numberEnd) == .comma,
			(1...3).allSatisfy({ byte(at: numberEnd + $0)?.isASCIIDigit == true }),
			numberEnd + 4 == groupsLimit || byte(at: numberEnd + 4)?.isASCIIDigit != true
		{
			numberEnd += 4
		}

		let number = makeString(numberStart..<numberEnd)
		let message = "Leading zeros are not allowed in a decimal number. A comma separates items, so \(number.shortened()) is not one number"
		// Both spellings are the same int, so they are suggested only when it is in range.
		let withUnderscores = number.replacing(",", with: "_")

		guard Self.isValidValue(withUnderscores) else {
			return message
		}

		return "\(message). Write it as \(withUnderscores.shortened()) or \(number.replacing(",", with: "").shortened())"
	}

	/**
	The message for a token that starts like a number but is not one, nor an instant or a duration, in the order of the reference implementation's checks.
	*/
	private func badNumberMessage(_ token: ArraySlice<UInt8>) -> String {
		// The token is ASCII, so a character is a byte.
		let diagnosed = token.prefix(Self.maximumDiagnosedLength)
		let text = String(decoding: diagnosed, as: UTF8.self)
		var unquoted: String { unquotedText(from: token.startIndex) }

		if text.utf8.contains(.plus) {
			return "A “+” sign is not allowed in a number, including in an exponent"
		}

		let unsigned = token.first == .hyphen ? token.dropFirst() : token

		if
			unsigned.first == .digitZero,
			let marker = unsigned.dropFirst().first,
			"BOX".utf8.contains(marker)
		{
			return "A number prefix is lowercase: 0x, 0o, or 0b"
		}

		// The whole number, not the part cut at the diagnosed length, because a cut can end before the digit or the underscore that the message is about.
		if
			unsigned.count >= 2,
			unsigned.first == .digitZero,
			let radix = Int64.SOMLRadix(marker: unsigned[unsigned.startIndex + 1])
		{
			let digits = unsigned.dropFirst(2)
			let name = radix.name

			if token.first == .hyphen {
				return "\(radix == .octal ? "An" : "A") \(name) integer cannot have a sign, because it states a bit pattern rather than a quantity"
			}

			if digits.isEmpty {
				return "Expected \(name) digits after “0\(Character(Unicode.Scalar(unsigned[unsigned.startIndex + 1])))”"
			}

			if
				radix == .hexadecimal,
				digits.contains(where: { $0 &- .lowercaseA < 6 }),
				digits.allSatisfy({ $0.isHexadecimalDigit || $0 == .underscore })
			{
				// The uppercase spelling is only suggested when it is valid, so a misplaced underscore is reported first, and a value outside the 64-bit range gets no example.
				guard Self.skipDigits(digits, from: digits.startIndex, where: \.isHexadecimalDigit) == digits.endIndex else {
					return "An underscore in a number must be between two digits"
				}

				// Only a bounded suggestion can be shown. More than sixteen significant hex digits is already out of range.
				let significant = digits.drop(while: { $0 == .digitZero || $0 == .underscore })
				guard significant.count(where: { $0 != .underscore }) <= 16 else {
					return "Hexadecimal digits are uppercase"
				}

				let valueText = "0x" + String(decoding: significant, as: UTF8.self).uppercased()
				let uppercase = "0x" + String(decoding: digits.prefix(38), as: UTF8.self).uppercased() + (digits.count > 38 ? "…" : "")
				return Self.isValidValue(valueText) ? "Hexadecimal digits are uppercase: \(uppercase)" : "Hexadecimal digits are uppercase"
			}

			// A lowercase hexadecimal digit is a digit in the wrong case, so the one named is a character that is no digit in either case.
			guard let byte = digits.first(where: { $0 != .underscore && !(radix.contains($0) || (radix == .hexadecimal && $0.isHexadecimalDigit)) }) else {
				return "An underscore in a number must be between two digits"
			}

			return "Invalid \(name) digit “\(Character(Unicode.Scalar(byte)))”"
		}

		// Only when the “E” is where an exponent marker goes, with digits, a `-`, or nothing after it. In `5EUR` or `10EB`, it is part of a word, so lowercasing it would not help.
		let exponent = diagnosed.decimalExponentParts
		let exponentDigits = exponent.map { $0.suffix.first == .hyphen ? $0.suffix.dropFirst() : $0.suffix }

		if
			exponent?.marker == .uppercaseE,
			exponentDigits?.allSatisfy({ $0.isASCIIDigit || $0 == .underscore }) == true
		{
			return "An exponent marker is a lowercase “e”"
		}

		let diagnosedUnsigned = diagnosed.dropFirst(token.first == .hyphen ? 1 : 0)
		let afterDigits = diagnosedUnsigned.drop(while: { $0.isASCIIDigit || $0 == .underscore })

		if
			afterDigits.startIndex > diagnosedUnsigned.startIndex,
			afterDigits.first == .dot,
			afterDigits.dropFirst().first.map({ $0.isASCIIDigit || $0 == .underscore }) != true
		{
			return "A decimal point must be followed by a digit"
		}

		if text.hasPrefix("-.") {
			return "A number cannot begin with “.”; write a digit before it, as in -0.5"
		}

		if diagnosed.contains(.colon) {
			let components = diagnosed.split(separator: .colon, omittingEmptySubsequences: false)

			if components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) {
				let isTime = (2...3).contains(components.count) && (1...2).contains(components[0].count) && components.dropFirst().allSatisfy({ $0.count == 2 })
				return isTime ? "A time of day is a string, so it must be quoted" : "Invalid number “\(text.shortened())”. A value that contains “:” must be quoted, as in '\(text.shortened())'"
			}
		}

		// A value with a `:` that starts with a zero, such as the MAC address `00:1A:2B`, is not a number with a leading zero, because removing the zero would not make it valid.
		if
			unsigned.first == .digitZero,
			let second = unsigned.dropFirst().first,
			second.isASCIIDigit || second == .underscore,
			!text.utf8.contains(.colon)
		{
			// Removing the zero gives a valid number with a different meaning, so the message says what the zero usually meant. A '...' string cannot hold a ', so then there is no example.
			let identifier = "an identifier, such as a ZIP code, as a string\(unquoted.contains("'") ? "" : ": '\(unquoted.shortened())'")"

			// The octal suggestion is only for the number on its own, not for one that more text follows, as in `0412 345 678`, and only when it is in range. It is decided on the whole number, because a cut can end before a digit that is not octal or that changes the value.
			if
				token.count <= Self.maximumDiagnosedLength,
				text.utf8.first == .digitZero,
				text.utf8.dropFirst().allSatisfy({ Int64.SOMLRadix.octal.contains($0) }),
				unquoted.hasSameScalars(as: text)
			{
				let digits = text.drop { $0 == "0" }
				let octal = "0o\(digits.isEmpty ? "0" : digits)"

				if Self.isValidValue(octal) {
					return "Leading zeros are not allowed in a decimal number. Write an octal number, such as a file mode, as \(octal.shortened()), and \(identifier)"
				}
			}

			return text.utf8.allSatisfy(\.isASCIIDigit) ? "Leading zeros are not allowed in a decimal number. Write \(identifier)" : "Leading zeros are not allowed in a decimal number"
		}

		// Only in a number: an underscore next to a letter other than the exponent marker is part of a word, such as `4k_video`.
		if
			diagnosed.contains(.underscore),
			diagnosed.allSatisfy({ $0.isASCIIDigit || $0 == .hyphen || $0 == .dot || $0 == .underscore || $0 == .lowercaseE }),
			diagnosed.indices.contains(where: { index in
				diagnosed[index] == .underscore && (index == diagnosed.startIndex || index + 1 == diagnosed.endIndex || !diagnosed[index - 1].isASCIIDigit || !diagnosed[index + 1].isASCIIDigit)
			})
		{
			return "An underscore in a number must be between two digits"
		}

		if
			exponent?.marker == .lowercaseE,
			let exponentDigits
		{
			let afterZero = exponentDigits.dropFirst()
			let afterSeparator = afterZero.first == .underscore ? afterZero.dropFirst() : afterZero

			if
				exponentDigits.first == .digitZero,
				afterSeparator.first?.isASCIIDigit == true
			{
				return "Leading zeros are not allowed in an exponent"
			}

			if exponent?.suffix.elementsEqual("-0") == true {
				return "“e-0” is not allowed, because an exponent of zero has one spelling: e0"
			}

			// Only a number ends with its exponent marker. A word that ends with an “e”, such as `1byte` or `-verbose`, has no exponent.
			if exponentDigits.isEmpty {
				return "Expected digits after the exponent marker “e”"
			}
		}

		if text.utf8.count(where: { $0 == .dot }) > 1 {
			return "Invalid number “\(text.shortened())”. A value with several dots, such as a version number, must be quoted"
		}

		if
			text.utf8.first == .hyphen,
			text.utf8.dropFirst().first?.isASCIIDigit != true
		{
			// The whole word, as for one without the “-”, so that a word such as `-nano` or `-info` is not taken for NaN or infinity.
			switch text.lowercased() {
			case "-nan":
				return "NaN is not representable. Use null for a missing value"
			case "-inf", "-infinity":
				return "“\(text.shortened())” is not a value. Negative infinity is written -infinity"
			default:
				return "Expected a digit or “infinity” after “-”"
			}
		}

		guard text.utf8.contains(where: \.isASCIILetter) else {
			return "Invalid number “\(text.shortened())”"
		}

		return "Invalid number “\(text.shortened())”. A string value must be quoted\(Self.quotingExample(unquoted))"
	}

	// MARK: Durations

	/**
	Whether a token that is not a number or an instant was meant as a duration: its first letter could begin a unit, or a day or a week, or it is a year unit. A radix prefix, an exponent, and other letters, like the `T` in `20260919T140000Z` or the `x` in `1.5x`, are left to the number errors.
	*/
	private static func isDurationLike(_ token: ArraySlice<UInt8>) -> Bool {
		var index = token.first == .hyphen ? token.startIndex + 1 : token.startIndex

		guard
			index < token.endIndex,
			token[index].isASCIIDigit
		else {
			return false
		}

		func skipDigitsAndUnderscores() {
			while
				index < token.endIndex,
				token[index].isASCIIDigit || token[index] == .underscore
			{
				index += 1
			}
		}

		skipDigitsAndUnderscores()

		if
			index < token.endIndex,
			token[index] == .dot
		{
			index += 1
			skipDigitsAndUnderscores()
		}

		guard index < token.endIndex else {
			return false
		}

		if "dhmnsuwDHMNSUW".utf8.contains(token[index]) {
			return true
		}

		// A year unit, as in `1y` or `2years`, is only one when the token or another part follows it, so that a word such as `100yen` stays a string to quote.
		let unitEnd = token[index...].firstIndex { !$0.isASCIILetter } ?? token.endIndex
		guard unitEnd - index <= 5 else {
			return false
		}

		let unit = String(decoding: token[index..<unitEnd], as: UTF8.self).lowercased()
		return yearUnits.contains(unit) && (unitEnd == token.endIndex || token[unitEnd].isASCIIDigit)
	}

	/**
	The spellings of a year unit, in lowercase, which a duration does not have.
	*/
	private static let yearUnits: Set<String> = ["y", "yr", "yrs", "year", "years"]

	/**
	Parses a duration, like `1h30m`, `1.5s`, or `-500ms`, and returns its value in nanoseconds. The parts are scanned in order, so that each error names the part it is about, as in the reference implementation.

	Each part is a decimal number without a sign and a unit, and the units are in descending order, each at most once. Only the last part may have a fraction. A part is not capped by the next unit, so `90m` is valid. The value is exact, so it must be a whole number of nanoseconds. A `-` at the start negates the whole value.
	*/
	private func parseDuration(_ token: ArraySlice<UInt8>) throws -> Int64 {
		let end = token.endIndex
		let isNegative = token.first == .hyphen
		var index = isNegative ? token.startIndex + 1 : token.startIndex
		var previousRank = -1
		var total: UInt128 = 0
		// The fraction of the last part, without trailing zeros, and that part's unit length. Only the last part may have one, so the value checks wait until every part is read.
		var fraction = token.prefix(0)
		var unitLength: UInt64 = 0

		while index < end {
			let digitsEnd = Self.skipIntegerPart(token, from: index)
			let next = digitsEnd < end ? token[digitsEnd] : nil

			if digitsEnd == index {
				if
					token[index] == .hyphen,
					index + 1 < end,
					token[index + 1].isASCIIDigit
				{
					throw durationError(token, "only the whole duration takes a sign, as in -1h30m")
				}

				throw durationError(token, token[index] == .plus ? "a “+” sign is not allowed" : "expected a number at “\(token[index...].shortenedASCII(to: 10))”")
			}

			if
				token[index] == .digitZero,
				next == .underscore || next?.isASCIIDigit == true
			{
				throw durationError(token, "leading zeros are not allowed")
			}

			if next == .underscore {
				throw durationError(token, "an underscore must be between two digits")
			}

			fraction = token.prefix(0)
			var unitStart = digitsEnd

			if next == .dot {
				unitStart = Self.skipDigits(token, from: digitsEnd + 1, where: \.isASCIIDigit)

				if unitStart == digitsEnd + 1 {
					throw durationError(token, "a “.” must be followed by a digit")
				}

				if
					unitStart < end,
					token[unitStart] == .underscore
				{
					throw durationError(token, "an underscore must be between two digits")
				}

				// Trailing zeros change nothing, and leaving them out keeps the arithmetic small however many there are.
				fraction = token[(digitsEnd + 1)..<unitStart]

				while fraction.last == .digitZero || fraction.last == .underscore {
					fraction = fraction.dropLast()
				}
			}

			var unitEnd = unitStart

			while
				unitEnd < end,
				token[unitEnd].isASCIILetter
			{
				unitEnd += 1
			}

			let unit = token[unitStart..<unitEnd]

			guard let rank = Duration.somlUnits.firstIndex(where: { $0.symbol.utf8.elementsEqual(unit) }) else {
				throw durationError(token, Self.badDurationUnitReason(unit.shortenedASCII(to: 10), token: token))
			}

			if rank <= previousRank {
				throw durationError(token, "the units are in the order h, m, s, ms, us, ns, and each appears at most once")
			}

			if
				next == .dot,
				unitEnd < end,
				token[unitEnd].isASCIIDigit
			{
				throw durationError(token, "only the last part may have a fraction")
			}

			unitLength = Duration.somlUnits[rank].nanoseconds

			// The digits are parsed in place, without an array or a String for them. A run of 19 digits is below `UInt64.max`, so the digits after the nineteenth are counted but not multiplied into the value.
			var digits = UInt64(0)
			var digitCount = 0

			for byte in token[index..<digitsEnd] where byte != .underscore {
				digitCount += 1

				if digitCount <= 19 {
					digits = digits * 10 + UInt64(byte - .digitZero)
				}
			}

			// More than 19 digits is out of range in any unit.
			if digitCount > 19 {
				total += UInt128(UInt64.max)
			} else {
				total += UInt128(digits) * UInt128(unitLength)
			}

			index = unitEnd
			previousRank = rank
		}

		// More than 13 fraction digits without a trailing zero is finer than a nanosecond in any unit: no unit has more than 13 factors of 2 or of 5 (an hour is 2^13 × 3^2 × 5^11 nanoseconds).
		if fraction.lazy.filter({ $0 != .underscore }).prefix(14).count > 13 {
			throw durationError(token, "it is not a whole number of nanoseconds")
		}

		if !fraction.isEmpty {
			var scale: UInt128 = 1
			var numerator: UInt128 = 0

			for digit in fraction where digit != .underscore {
				numerator = numerator * 10 + UInt128(digit - .digitZero)
				scale *= 10
			}

			let (length, remainder) = (numerator * UInt128(unitLength)).quotientAndRemainder(dividingBy: scale)

			guard remainder == 0 else {
				throw durationError(token, "it is not a whole number of nanoseconds")
			}

			total += length
		}

		if
			isNegative,
			total == 0
		{
			throw durationError(token, "“-” is not allowed before zero, because zero has one spelling: 0s")
		}

		// The magnitude is unsigned, because the most negative value has no positive counterpart in an `Int64`.
		let limit = isNegative ? UInt128(Int64.min.magnitude) : UInt128(Int64.max)

		guard total <= limit else {
			throw durationError(token, "it is outside the 64-bit range of nanoseconds, about 292 years either way")
		}

		if isNegative {
			return total == limit ? .min : -Int64(total)
		}

		return Int64(total)
	}

	private func durationError(_ token: ArraySlice<UInt8>, _ reason: String) -> SOML.ParseError {
		error("Invalid duration \(token.shortenedASCII()): \(reason)", at: token.startIndex)
	}

	/**
	What is wrong with `unit`, which is not a unit of a duration, in the duration `token`.
	*/
	private static func badDurationUnitReason(_ unit: String, token: ArraySlice<UInt8>) -> String {
		switch unit {
		case "":
			return "every number needs a unit: h, m, s, ms, us, or ns"
		case "d", "day", "days":
			return "there is no day unit, because a day is not a fixed length. Write 24h for a fixed 24 hours"
		case "w", "week", "weeks":
			return "there is no week unit, because a day is not a fixed length. Write 168h for a fixed 168 hours"
		case _ where yearUnits.contains(unit.lowercased()):
			return "there is no year unit, because a year is not a fixed length. Write 8760h for a fixed 365 days"
		case "M":
			// A number with `M` alone is more often a size, as in `memory: 512M`, and `512m` would read as minutes.
			let isSize = token.count <= maximumDiagnosedLength && token.first?.isASCIIDigit == true && token.dropFirst().dropLast().allSatisfy { $0.isASCIIDigit || $0 == .underscore }
			return "there is no month unit, because a month is not a fixed length\(isSize ? ". A size, such as 512M, is a string: '\(String(decoding: token, as: UTF8.self).shortened())'" : "")"
		default:
			let lowercased = unit.lowercased()
			return Duration.somlUnits.contains { $0.symbol == lowercased } ? "the units are lowercase: \(lowercased)" : "“\(unit.shortened(to: 10))” is not a unit. The units are h, m, s, ms, us, and ns, and a string must be quoted"
		}
	}

	// MARK: Strings

	private func quoteRunLength(at index: Int) -> Int {
		bytes.endOfRun(of: bytes[index], from: index) - index
	}

	private mutating func parseString() throws -> String {
		guard quoteRunLength(at: position) < 3 else {
			return try parseBlockString()
		}

		return try parseSingleLineString()
	}

	/**
	Parses a `'...'` literal string or a `"..."` escaped string.
	*/
	private mutating func parseSingleLineString() throws -> String {
		let quote = bytes[position]
		let start = position
		position += 1
		var contentStart = position
		var decoded: [UInt8]?

		while true {
			guard
				position < bytes.count,
				bytes[position] != .lineFeed
			else {
				throw error(quote == .singleQuote ? "Unterminated string. A '...' string must end on the line it starts on; use a block string (''') for multiple lines" : "Unterminated string. A \"...\" string must end on the line it starts on; use a block string (\"\"\") for multiple lines", at: start)
			}

			let byte = bytes[position]

			if byte == quote {
				let content = bytes[contentStart..<position]
				position += 1

				guard var decoded else {
					return String(decoding: content, as: UTF8.self)
				}

				decoded += content
				return String(decoding: decoded, as: UTF8.self)
			}

			if
				quote == .doubleQuote,
				byte == .backslash
			{
				if decoded == nil {
					decoded = []
				}

				decoded!.append(contentsOf: bytes[contentStart..<position])
				try decodeEscape(into: &decoded!)
				contentStart = position
				continue
			}

			position += 1
		}
	}

	/**
	Decodes the escape at the current position and moves past it.
	*/
	private mutating func decodeEscape(into buffer: inout [UInt8]) throws {
		let start = position
		position += 1

		// A backslash at the end of the document is the same mistake as one at the end of a line.
		guard let marker = byte(at: position) else {
			throw error(Self.backslashAtEndMessage, at: start)
		}

		position += 1

		switch marker {
		case .backslash:
			buffer.append(.backslash)
		case .doubleQuote:
			buffer.append(.doubleQuote)
		case .lowercaseN:
			buffer.append(.lineFeed)
		case .lowercaseT:
			buffer.append(.tab)
		case .lowercaseU:
			try decodeUnicodeEscape(start: start, into: &buffer)
		case .lowercaseR:
			throw error(#"There is no \r escape, because a carriage return cannot be represented"#, at: start)
		case .singleQuote:
			throw error("A ' needs no escape inside \"...\"", at: start)
		case .lineFeed:
			throw error(Self.backslashAtEndMessage, at: start)
		default:
			throw error(#"Unknown escape “\\#(scalar(at: start + 1))”. The escapes are \\, \", \n, \t, and \u{…}; use a '...' string for literal backslashes"#, at: start)
		}
	}

	/**
	Decodes a `\u{…}` escape, whose `u` is just before the current position, and whose backslash is at `start`.
	*/
	private mutating func decodeUnicodeEscape(start: Int, into buffer: inout [UInt8]) throws {
		let digitsStart = position + 1
		var digitsEnd = digitsStart

		// Uppercase digits too, so that the value of such an escape is checked before its spelling.
		while
			digitsEnd - digitsStart < 6,
			byte(at: digitsEnd)?.isHexadecimalDigit == true
		{
			digitsEnd += 1
		}

		guard
			byte(at: position) == .openBrace,
			digitsEnd > digitsStart,
			byte(at: digitsEnd) == .closeBrace
		else {
			throw error(badUnicodeEscapeMessage(at: start + 1), at: start)
		}

		position = digitsEnd + 1
		let digits = bytes[digitsStart..<digitsEnd]
		// The text of the digits only for a message, so that a valid escape makes no string.
		var hex: String { makeString(digitsStart..<digitsEnd) }
		var value: UInt32 = 0

		// One to six hexadecimal digits, checked above, so this cannot overflow.
		for digit in digits {
			value = value << 4 | UInt32(digit.hexadecimalDigitValue!)
		}

		// The value is checked before the spelling, so that the uppercase and leading zeros errors never point to an escape that is not allowed either.
		if value == 0x0D {
			throw error(#"A carriage return (U+000D) cannot be represented, so \u{\#(hex)} is not allowed"#, at: start)
		}

		if (0xD800...0xDFFF).contains(value) {
			throw error(#"\u{\#(hex)} is a surrogate, which is not a Unicode scalar value"#, at: start)
		}

		if value > 0x10FFFF {
			throw error(#"\u{\#(hex)} is above U+10FFFF, the largest Unicode scalar value"#, at: start)
		}

		if digits.contains(where: { (UInt8.uppercaseA...UInt8.uppercaseF).contains($0) }) {
			throw error("A Unicode escape uses lowercase hexadecimal digits", at: start)
		}

		if
			digits.count > 1,
			digits.first == .digitZero
		{
			let withoutZeros = hex.drop { $0 == "0" }
			throw error(#"A Unicode escape may not have leading zeros; write \u{\#(withoutZeros.isEmpty ? "0" : withoutZeros)}"#, at: start)
		}

		// A scalar value, checked above, so this cannot fail.
		buffer.appendScalar(Unicode.Scalar(value)!)
	}

	/**
	The message for a `\u` escape, whose `u` is at `index`, that is not written as `\u{…}` with one to six lowercase hexadecimal digits.
	*/
	private func badUnicodeEscapeMessage(at index: Int) -> String {
		// As much as the reference implementation looks at.
		let rest = bytes[index..<min(bytes.count, index + 12)]

		if
			rest.count >= 5,
			rest.dropFirst().prefix(4).allSatisfy(\.isHexadecimalDigit)
		{
			return fourDigitEscapeMessage(rest)
		}

		guard rest.starts(with: [.lowercaseU, .openBrace]) else {
			return #"A Unicode escape is written \u{…} with one to six lowercase hexadecimal digits"#
		}

		let digits = rest.dropFirst(2).prefix(while: \.isHexadecimalDigit)

		if digits.contains(where: { (UInt8.uppercaseA...UInt8.uppercaseF).contains($0) }) {
			return "A Unicode escape uses lowercase hexadecimal digits"
		}

		if rest.starts(with: [.lowercaseU, .openBrace, .closeBrace]) {
			return "A Unicode escape needs one to six hexadecimal digits"
		}

		return digits.count >= 7 ? "A Unicode escape has at most six hexadecimal digits" : #"A Unicode escape is written \u{…} with one to six lowercase hexadecimal digits"#
	}

	/**
	The message for the JSON form `\uXXXX`, from its `u`, with the escape to write instead. JSON writes a character above U+FFFF as two of them, a surrogate pair, which is one `\u{…}` escape here. Here, a lone surrogate and a carriage return have no escape.
	*/
	private func fourDigitEscapeMessage(_ rest: ArraySlice<UInt8>) -> String {
		let escape = String(decoding: rest.prefix(5), as: UTF8.self)
		let code = UInt32(String(decoding: rest.dropFirst().prefix(4), as: UTF8.self), radix: 16)!
		// A second `\uXXXX` directly after it.
		let second = rest.dropFirst(5)
		let lowDigits = second.dropFirst(2).prefix(4)
		let hasLow = second.starts(with: [.backslash, .lowercaseU]) && lowDigits.count == 4 && lowDigits.allSatisfy(\.isHexadecimalDigit)
		let low = hasLow ? UInt32(String(decoding: lowDigits, as: UTF8.self), radix: 16) : nil

		if
			(0xD800...0xDBFF).contains(code),
			let low,
			(0xDC00...0xDFFF).contains(low)
		{
			let scalar = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
			return #"The four-digit \\#(escape)\u\#(String(decoding: lowDigits, as: UTF8.self)) form is not an escape. Write \u{\#(String(scalar, radix: 16))}"#
		}

		let form = #"The four-digit \\#(escape) form is not an escape"#

		if (0xD800...0xDFFF).contains(code) {
			return #"\#(form), and a lone surrogate is not a Unicode scalar value. Write the character it is half of as one \u{…} escape"#
		}

		if code == 0x0D {
			return "\(form), and a carriage return (U+000D) cannot be represented"
		}

		return #"\#(form). Write \u{\#(String(code, radix: 16))}"#
	}

	/**
	Parses a `'''` or `"""` block string.

	The content is the lines between the delimiters. The closing delimiter's indentation is removed from every line. A blank line, which is empty or holds only spaces and tabs, needs no indentation and becomes an empty line. Blank lines directly inside the delimiters are discarded.
	*/
	private mutating func parseBlockString() throws -> String {
		let start = position
		let quote = bytes[position]
		let delimiterLength = quoteRunLength(at: position)
		position += delimiterLength

		guard byte(at: position) == .lineFeed else {
			if position == bytes.count {
				throw unterminatedBlock(quote: quote, length: delimiterLength, start: start, contentStart: position)
			}

			throw error("A block string's opening delimiter must be followed directly by a line break, and its content starts on the next line", at: position)
		}

		position += 1
		var lines = [Range<Int>]()
		let indentation: Range<Int>

		while true {
			let lineStart = position
			let lineEnd = bytes.lineEnd(from: lineStart)
			var contentStart = lineStart

			while contentStart < lineEnd, bytes[contentStart].isSpaceOrTab {
				contentStart += 1
			}

			var runEnd = contentStart

			while runEnd < lineEnd, bytes[runEnd] == quote {
				runEnd += 1
			}

			if runEnd - contentStart == delimiterLength {
				indentation = lineStart..<contentStart
				position = runEnd
				break
			}

			guard lineEnd < bytes.count else {
				throw unterminatedBlock(quote: quote, length: delimiterLength, start: start, contentStart: start + delimiterLength + 1)
			}

			// A blank line, which is empty or holds only spaces and tabs, needs no indentation and becomes an empty line, so it is kept as an empty range.
			lines.append(contentStart == lineEnd ? lineEnd..<lineEnd : lineStart..<lineEnd)
			position = lineEnd + 1
		}

		let afterClosing = position
		let indentationBytes = bytes[indentation]

		for index in lines.indices {
			let line = lines[index]

			guard !line.isEmpty else {
				continue
			}

			guard bytes[line].starts(with: indentationBytes) else {
				throw error("This line does not start with the indentation of its block string's closing delimiter. Every line except a blank one must start with exactly the same spaces and tabs", at: line.lowerBound)
			}

			lines[index] = (line.lowerBound + indentationBytes.count)..<line.upperBound
		}

		let firstContent = lines.firstIndex { !$0.isEmpty } ?? lines.endIndex
		let lastContent = lines.lastIndex { !$0.isEmpty } ?? firstContent
		let kept = firstContent < lines.endIndex ? lines[firstContent...lastContent] : []
		var buffer = [UInt8]()

		let contentSize = kept.reduce(max(0, kept.count - 1)) { $0 + $1.count }

		buffer.reserveCapacity(contentSize)

		for (index, content) in kept.enumerated() {
			if index > 0 {
				buffer.append(.lineFeed)
			}

			guard quote == .doubleQuote else {
				buffer += bytes[content]
				continue
			}

			position = content.lowerBound
			var segmentStart = position

			while position < content.upperBound {
				if bytes[position] == .backslash {
					buffer += bytes[segmentStart..<position]
					try decodeEscape(into: &buffer)
					segmentStart = position
				} else {
					position += 1
				}
			}

			buffer += bytes[segmentStart..<content.upperBound]
		}

		position = afterClosing
		return String(decoding: buffer, as: UTF8.self)
	}

	/**
	The error for a block string that no line closes. A content line that ends with the delimiter, as TOML allows, gets a note about it, because adding a closing line after it would keep the delimiter as content.
	*/
	private func unterminatedBlock(quote: UInt8, length: Int, start: Int, contentStart: Int) -> SOML.ParseError {
		var line = bytes[..<contentStart].count(where: { $0 == .lineFeed }) + 1
		var lineStart = contentStart

		while lineStart < bytes.count {
			let lineEnd = bytes.lineEnd(from: lineStart)
			let text = bytes[lineStart..<lineEnd].drop(while: \.isSpaceOrTab).reversed().drop(while: \.isSpaceOrTab)

			// A line of only quotes, longer than the delimiter, is content.
			if
				text.prefix(length).count == length,
				text.prefix(length).allSatisfy({ $0 == quote }),
				text.contains(where: { $0 != quote })
			{
				let delimiter = String(decoding: repeatElement(quote, count: min(length, 40)), as: UTF8.self) + (length > 40 ? "…" : "")
				return error("Unterminated block string. Its closing delimiter must start a line, so move the \(delimiter) at the end of line \(line) to a new line", at: start)
			}

			line += 1
			lineStart = lineEnd + 1
		}

		return error("Unterminated block string", at: start)
	}

	// MARK: Helpers

	private func byte(at index: Int) -> UInt8? {
		index >= 0 && index < bytes.count ? bytes[index] : nil
	}

	/**
	Whether a value ends at `index`, so that a suggestion that ends there leaves nothing out. A `/` only starts a comment with a `*` after it, or a `//` comment of another language, which the error for what follows names, so in `km/h` the text goes on.
	*/
	private func isValueEnd(at index: Int) -> Bool {
		guard let byte = byte(at: index) else {
			return true
		}

		return byte.isValueEnd && (byte != .slash || self.byte(at: index + 1) == .asterisk || self.byte(at: index + 1) == .slash)
	}

	private func makeString(_ range: Range<Int>) -> String {
		String(decoding: bytes[range], as: UTF8.self)
	}

	/**
	The Unicode scalar that starts at the given byte offset. The bytes are known to be valid UTF-8.
	*/
	private func scalar(at index: Int) -> Unicode.Scalar {
		var iterator = bytes[index...].makeIterator()
		var decoder = UTF8()

		guard case .scalarValue(let scalar) = decoder.decode(&iterator) else {
			return "\u{FFFD}"
		}

		return scalar
	}

	/**
	Describes the character at an offset for an error message, so that an invisible character is named rather than shown.

	Names come from Swift's Unicode properties and can differ from the reference implementation's selective names or its JavaScript engine's Unicode version.
	*/
	private func describeCharacter(at index: Int) -> String {
		guard index < bytes.count else {
			return "the end of the \(textKind.rawValue)"
		}

		let scalar = scalar(at: index)
		return scalar == "\n" ? "a line break" : scalar.characterDescription
	}

	/**
	The offset `maximumDiagnosedLength` UTF-16 code units after `start`, or the end of the text, because the reference implementation measures the text that a diagnosis looks at in UTF-16 code units. A scalar that the limit would split is left out.
	*/
	private func diagnosisLimit(from start: Int) -> Int {
		var index = start
		var length = 0

		while index < bytes.count {
			// A scalar of four UTF-8 bytes is two UTF-16 code units.
			let width = bytes[index] >= 0xF0 ? 2 : 1

			guard length + width <= Self.maximumDiagnosedLength else {
				break
			}

			length += width
			index += scalarLength(at: index)
		}

		return index
	}

	/**
	The length in bytes of the UTF-8 scalar that starts at `index`.
	*/
	private func scalarLength(at index: Int) -> Int {
		// UTF-8 was validated before parsing. Leading one bits give a multibyte scalar's width; ASCII occupies one byte.
		max(1, (~bytes[index]).leadingZeroBitCount)
	}

	/**
	A key as an error message shows it, as the reference implementation does: bare when it can be, and otherwise as a JSON string, cut short when it is long.
	*/
	static func describeKey(_ key: String) -> String {
		let shortened = key.shortened()
		return key.isBareSOMLKey ? shortened : shortened.jsonQuoted
	}

	private func error(_ message: String, at offset: Int) -> SOML.ParseError {
		SOML.ParseError(message: message, offset: offset, in: bytes)
	}
}

/**
ASCII decimal-prefix queries for numeric diagnostics.
*/
extension ArraySlice<UInt8> {
	/**
	The exponent marker and the text after it when the prefix has the diagnostic decimal form: an optional minus, a digit followed by digits or underscores, and an optional nonempty fraction. The suffix is left unchecked so each diagnostic can apply its own rule.
	*/
	fileprivate var decimalExponentParts: (marker: UInt8, suffix: Self)? {
		let unsigned = first == .hyphen ? dropFirst() : self

		guard unsigned.first?.isASCIIDigit == true else {
			return nil
		}

		var remainder = unsigned.drop(while: { $0.isASCIIDigit || $0 == .underscore })

		if remainder.first == .dot {
			let fraction = remainder.dropFirst()
			remainder = fraction.drop(while: { $0.isASCIIDigit || $0 == .underscore })

			guard remainder.startIndex > fraction.startIndex else {
				return nil
			}
		}

		guard
			let marker = remainder.first,
			marker.isASCIIExponentMarker
		else {
			return nil
		}

		return (marker, remainder.dropFirst())
	}
}

extension UInt64 {
	/**
	Whether any of the eight bytes is not printable ASCII, tab, or LF: a byte from 0x80 up, DEL, or another control character.

	Each test sets the top bit of the bytes it finds. Only the low seven bits of a byte are added to, so no carry crosses into the next byte, and every byte is tested exactly.
	*/
	fileprivate var hasByteOutsidePrintableASCIITabAndLineFeed: Bool {
		// A SIMD8 comparison with any(mask) measured slower than this packed-word test in Swift 6.4 probes; keep the scalar scan until a vector implementation demonstrates a win.
		let topBits: UInt64 = 0x8080_8080_8080_8080
		let lowBits: UInt64 = 0x7F7F_7F7F_7F7F_7F7F

		// The top bit is set for a byte whose low seven bits are 0x20 or more.
		func isAtLeastSpace(_ word: UInt64) -> UInt64 {
			(word & lowBits) &+ 0x6060_6060_6060_6060
		}

		// The top bit is set for a zero byte.
		func isZero(_ word: UInt64) -> UInt64 {
			~(((word & lowBits) &+ lowBits) | word)
		}

		let isControl = ~isAtLeastSpace(self) & ~self & ~isZero(self ^ 0x0909_0909_0909_0909) & ~isZero(self ^ 0x0A0A_0A0A_0A0A_0A0A)
		let isDeleteOrAbove = ((self & lowBits) &+ 0x0101_0101_0101_0101) | self
		return (isControl | isDeleteOrAbove) & topBits != 0
	}
}

/**
SOML integer grammar and checked byte conversion, shared with the JSON reader.
*/
extension Int64 {
	/**
	The integer radices SOML supports, with the prefix and digit rules owned by the radix.
	*/
	enum SOMLRadix: UInt64 {
		case binary = 2
		case octal = 8
		case decimal = 10
		case hexadecimal = 16

		/**
		The radix and digit test after the prefix `0` and `marker`, or `nil` when `marker` is not a radix marker.
		*/
		init?(marker: UInt8) {
			switch marker {
			case .lowercaseB:
				self = .binary
			case .lowercaseO:
				self = .octal
			case .lowercaseX:
				self = .hexadecimal
			default:
				return nil
			}
		}

		/**
		The radix's name in an integer diagnostic.
		*/
		var name: String {
			switch self {
			case .binary:
				"binary"
			case .octal:
				"octal"
			case .decimal:
				"decimal"
			case .hexadecimal:
				"hexadecimal"
			}
		}

		/**
		Whether the byte is a digit in the SOML spelling of this radix.
		*/
		func contains(_ byte: UInt8) -> Bool {
			switch self {
			case .binary:
				byte == .digitZero || byte == .digitOne
			case .octal:
				byte &- .digitZero < 8
			case .decimal:
				byte.isASCIIDigit
			case .hexadecimal:
				byte.isASCIIDigit || byte &- .uppercaseA < 6
			}
		}
	}

	/**
	Parses validated ASCII digits, ignoring underscores, without allocating a string. The caller checks spelling, radix, and underscore placement before calling. Returns `nil` on overflow.
	*/
	@inline(__always)
	init?(validatedDigits digits: ArraySlice<UInt8>, radix: SOMLRadix = .decimal, isNegative: Bool = false) {
		var magnitude: UInt64 = 0

		for byte in digits where byte != .underscore {
			let digit = byte.isASCIIDigit ? UInt64(byte - .digitZero) : UInt64(byte - .uppercaseA) + 10
			// Full-width multiplication still needs separate carry checks; exact narrowing of the UInt128 result removes that overflow state and measured faster for long integers.
			guard let next = UInt64(exactly: UInt128(magnitude) * UInt128(radix.rawValue) + UInt128(digit)) else {
				return nil
			}

			magnitude = next
		}

		// Int128 holds every UInt64 magnitude and its negation; exact narrowing handles both Int64 bounds without a special case for Int64.min.
		guard let value = Self(exactly: isNegative ? -Int128(magnitude) : Int128(magnitude)) else {
			return nil
		}

		self = value
	}
}

extension UInt8 {
	static let tab = UInt8(ascii: "\t")
	static let lineFeed = UInt8(ascii: "\n")
	static let carriageReturn = UInt8(ascii: "\r")
	static let space = UInt8(ascii: " ")
	static let doubleQuote = UInt8(ascii: "\"")
	static let hash = UInt8(ascii: "#")
	static let singleQuote = UInt8(ascii: "'")
	static let asterisk = UInt8(ascii: "*")
	static let plus = UInt8(ascii: "+")
	static let comma = UInt8(ascii: ",")
	static let hyphen = UInt8(ascii: "-")
	static let dot = UInt8(ascii: ".")
	static let slash = UInt8(ascii: "/")
	static let digitZero = UInt8(ascii: "0")
	static let colon = UInt8(ascii: ":")
	static let openBracket = UInt8(ascii: "[")
	static let backslash = UInt8(ascii: "\\")
	static let closeBracket = UInt8(ascii: "]")
	static let underscore = UInt8(ascii: "_")
	static let openBrace = UInt8(ascii: "{")
	static let closeBrace = UInt8(ascii: "}")

	/**
	ASCII symbols shared by the parser, lexer, and writers.
	*/
	static let digitOne = UInt8(ascii: "1")
	static let digitSeven = UInt8(ascii: "7")
	static let digitNine = UInt8(ascii: "9")
	static let uppercaseA = UInt8(ascii: "A")
	static let uppercaseE = UInt8(ascii: "E")
	static let uppercaseF = UInt8(ascii: "F")
	static let uppercaseT = UInt8(ascii: "T")
	static let uppercaseZ = UInt8(ascii: "Z")
	static let lowercaseA = UInt8(ascii: "a")
	static let lowercaseB = UInt8(ascii: "b")
	static let lowercaseE = UInt8(ascii: "e")
	static let lowercaseF = UInt8(ascii: "f")
	static let lowercaseH = UInt8(ascii: "h")
	static let lowercaseI = UInt8(ascii: "i")
	static let lowercaseM = UInt8(ascii: "m")
	static let lowercaseN = UInt8(ascii: "n")
	static let lowercaseO = UInt8(ascii: "o")
	static let lowercaseR = UInt8(ascii: "r")
	static let lowercaseS = UInt8(ascii: "s")
	static let lowercaseT = UInt8(ascii: "t")
	static let lowercaseU = UInt8(ascii: "u")
	static let lowercaseX = UInt8(ascii: "x")
	static let lowercaseZ = UInt8(ascii: "z")
	static let pipe = UInt8(ascii: "|")

	/**
	Whether the byte is a space or a tab, the whitespace of a line.
	*/
	var isSpaceOrTab: Bool {
		self == .space || self == .tab
	}

	/**
	Whether the byte is whitespace in SOML, where carriage returns are rejected.
	*/
	var isSOMLWhitespace: Bool {
		isSpaceOrTab || self == .lineFeed
	}

	/**
	Whether the byte is whitespace in JSON, which also permits carriage returns.
	*/
	var isJSONWhitespace: Bool {
		isSOMLWhitespace || self == .carriageReturn
	}

	/**
	Whether the byte opens a quoted SOML string or key.
	*/
	var isQuote: Bool {
		self == .singleQuote || self == .doubleQuote
	}

	/**
	Whether the byte is a decimal digit other than zero.
	*/
	var isASCIINonzeroDigit: Bool {
		self &- .digitOne < 9
	}

	/**
	Whether the byte is either spelling of a decimal exponent marker.
	*/
	var isASCIIExponentMarker: Bool {
		self == .lowercaseE || self == .uppercaseE
	}

	/**
	The lowercase spelling of an ASCII letter, with every other byte unchanged.
	*/
	var asciiLowercased: Self {
		isASCIIUppercase ? self + 32 : self
	}

	/**
	The uppercase spelling of an ASCII letter, with every other byte unchanged.
	*/
	var asciiUppercased: Self {
		isASCIILowercase ? self - 32 : self
	}

	/**
	Whether the byte may directly follow a value: whitespace, a separator, a closing bracket, or the start of a comment.
	*/
	var isValueEnd: Bool {
		switch self {
		case .space, .tab, .lineFeed, .comma, .closeBracket, .closeBrace, .hash, .slash:
			true
		default:
			false
		}
	}

	var isUTF8ContinuationByte: Bool {
		self & 0xC0 == 0x80
	}

	/**
	The UTF-8 sequence that the byte starts, by the table of RFC 3629: its length, and the range of its second byte, which excludes overlong forms, surrogates, and scalars above U+10FFFF. The length is 0 for a byte that cannot start a sequence of more than one byte.
	*/
	fileprivate var utf8Sequence: (length: Int, second: ClosedRange<UInt8>) {
		switch self {
		case 0xC2...0xDF:
			(2, 0x80...0xBF)
		case 0xE0:
			(3, 0xA0...0xBF)
		case 0xED:
			(3, 0x80...0x9F)
		case 0xE1...0xEF:
			(3, 0x80...0xBF)
		case 0xF0:
			(4, 0x90...0xBF)
		case 0xF4:
			(4, 0x80...0x8F)
		case 0xF1...0xF3:
			(4, 0x80...0xBF)
		default:
			(0, 0x80...0xBF)
		}
	}

	var isASCIIDigit: Bool {
		(UInt8.digitZero...UInt8.digitNine).contains(self)
	}

	/**
	The lowercase ASCII spelling of a hexadecimal digit from 0 through 15.
	*/
	var lowercaseHexadecimalDigit: UInt8 {
		self < 10 ? .digitZero + self : .lowercaseA + self - 10
	}

	var isHexadecimalDigit: Bool {
		hexadecimalDigitValue != nil
	}

	/**
	The value of an ASCII hexadecimal digit in either case, or `nil` for any other byte.
	*/
	var hexadecimalDigitValue: Int? {
		// Character(Unicode.Scalar(self)).hexDigitValue agrees for bytes but measured about four times slower than this ASCII switch in Swift 6.4 probes.
		switch self {
		case UInt8.digitZero...UInt8.digitNine:
			Int(self - .digitZero)
		case UInt8.lowercaseA...UInt8.lowercaseF:
			Int(self - .lowercaseA + 10)
		case UInt8.uppercaseA...UInt8.uppercaseF:
			Int(self - .uppercaseA + 10)
		default:
			nil
		}
	}

	var isASCIILowercase: Bool {
		(UInt8.lowercaseA...UInt8.lowercaseZ).contains(self)
	}

	var isASCIIUppercase: Bool {
		(UInt8.uppercaseA...UInt8.uppercaseZ).contains(self)
	}

	var isASCIILetter: Bool {
		isASCIILowercase || isASCIIUppercase
	}

	/**
	A byte that can appear in a bare key: an ASCII letter, a digit, `_`, or `-`.
	*/
	var isBareKeyByte: Bool {
		isASCIILetter || isASCIIDigit || self == .underscore || self == .hyphen
	}

	/**
	A byte that can appear in a keyword, a number, an instant, or a duration.
	*/
	var isScalarTokenByte: Bool {
		isBareKeyByte || self == .dot || self == .colon || self == .plus
	}
}

extension Unicode.Scalar {
	/**
	The scalar value in uppercase hexadecimal with at least four digits, as in `U+00A0`.
	*/
	fileprivate var hexadecimal: String {
		let digits = String(value, radix: 16, uppercase: true)
		return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
	}

	/**
	The scalar as an error message shows it: quoted, like `"$"`, or by its code point and native Unicode name when it is invisible or ambiguous, like `U+00A0 (NO-BREAK SPACE; only space, tab, and line feed are whitespace)`.
	*/
	fileprivate var characterDescription: String {
		// Control, format, private-use, unassigned, separator, and default-ignorable characters are invisible or ambiguous, so they are shown by code point.
		guard
			self != " ",
			!properties.generalCategory.isVisible || properties.isDefaultIgnorableCodePoint
		else {
			return "“\(self)”"
		}

		// Native Unicode names replace the reference's selective name table. U+0085 has no native name or alias, while U+2061 gains FUNCTION APPLICATION; these minor wording differences are intentional.
		let whitespaceHint = properties.isWhitespace || value == 0x200B || value == 0xFEFF ? "only space, tab, and line feed are whitespace" : nil

		if let name = properties.name ?? properties.nameAlias {
			return "U+\(hexadecimal) (\(name)\(whitespaceHint.map { "; " + $0 } ?? ""))"
		}

		return "U+\(hexadecimal)\(whitespaceHint.map { " (" + $0 + ")" } ?? "")"
	}
}

extension Unicode.GeneralCategory {
	/**
	Whether a character of this category is visible when printed.
	*/
	fileprivate var isVisible: Bool {
		switch self {
		case .control, .format, .surrogate, .privateUse, .unassigned, .spaceSeparator, .lineSeparator, .paragraphSeparator:
			false
		default:
			true
		}
	}
}

extension String {
	/**
	The string, cut to 40 Unicode scalars for an error message, so that a huge token does not make a huge message. The start and the end stay, with `…` between them, because the end of a long key path is usually the part that matters. Scalars rather than characters, because one character can hold any number of combining marks.

	It is for the messages that only this implementation has. A message that matches the reference implementation uses `shortened(to:)`.
	*/
	var abbreviated: String {
		let scalars = unicodeScalars

		guard scalars.prefix(41).count > 40 else {
			return self
		}

		return String(scalars.prefix(20)) + "…" + String(scalars.suffix(19))
	}

	/**
	The string cut to `maximumLength` UTF-16 code units, with `…` after it, as the reference implementation shortens text in an error message, so that a huge token does not make a huge message. The cut never splits a scalar.
	*/
	func shortened(to maximumLength: Int = 40) -> String {
		// Keep the scan bounded by the message limit. `utf16.index(_:offsetBy:limitedBy:)` can scan the entire string to resolve the UTF-16 offset of its limiting end index. Truncating one million emoji to 200 UTF-16 units measured about 2.8 ms versus 1.1 µs here in optimized Swift 6.4 builds on an M4 Pro; repeated calls can hide this first-call cost.
		var length = 0
		var end = unicodeScalars.startIndex

		while end < unicodeScalars.endIndex {
			length += UTF16.width(unicodeScalars[end])

			guard length <= maximumLength else {
				return String(self[..<end]) + "…"
			}

			unicodeScalars.formIndex(after: &end)
		}

		return self
	}

	/**
	The string as `JSON.stringify()` writes it in JavaScript, for error messages that match the reference implementation: in double quotes, with `"`, `\`, and the control characters below U+0020 escaped.
	*/
	var jsonQuoted: String {
		// String(reflecting:) emits Swift escapes such as \0 and \u{08}, which are not JSON escapes; it also measured slower for ordinary short text.
		var output = "\""

		for scalar in unicodeScalars {
			switch scalar {
			case "\"":
				output += "\\\""
			case "\\":
				output += "\\\\"
			case "\u{8}":
				output += "\\b"
			case "\u{C}":
				output += "\\f"
			case "\n":
				output += "\\n"
			case "\r":
				output += "\\r"
			case "\t":
				output += "\\t"
			case _ where scalar.value < 0x20:
				let digits = String(scalar.value, radix: 16)
				output += "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
			default:
				output.unicodeScalars.append(scalar)
			}
		}

		return output + "\""
	}

	/**
	The string with every character that a terminal acts on rather than shows replaced with U+FFFD: the control characters other than tab, and the bidirectional controls, which can reorder the text around them. The replacement is one scalar, so a caret under the text still lines up.
	*/
	var sanitizedForTerminal: String {
		// A Unicode-scalar regex replacement matched the tested behavior but measured 8–226 times slower than this scan and lazy map.
		guard unicodeScalars.contains(where: \.isUnsafeForTerminal) else {
			return self
		}

		return String(String.UnicodeScalarView(unicodeScalars.lazy.map { $0.isUnsafeForTerminal ? "\u{FFFD}" : $0 }))
	}

	/**
	Text from a document, ready to quote in an error message: cut to 40 scalars, with the characters a terminal acts on replaced.
	*/
	var forMessage: String {
		abbreviated.sanitizedForTerminal
	}
}

extension ArraySlice<UInt8> {
	/**
	The ASCII slice shortened to 40 bytes, preserving its start and end without decoding undisplayed bytes. The caller must ensure the bytes are ASCII.
	*/
	var abbreviatedASCII: String {
		guard count > 40 else {
			return String(decoding: self, as: UTF8.self)
		}

		return "\(String(decoding: prefix(20), as: UTF8.self))…\(String(decoding: suffix(19), as: UTF8.self))"
	}

	/**
	The ASCII slice cut to `maximumLength` bytes with an ellipsis when truncated, without allocating a string for bytes that will not be displayed. The caller must ensure the bytes are ASCII.
	*/
	func shortenedASCII(to maximumLength: Int = 40) -> String {
		String(decoding: prefix(maximumLength), as: UTF8.self) + (count > maximumLength ? "…" : "")
	}
}

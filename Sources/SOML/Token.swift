extension SOML {
	/**
	A token of SOML source text, for syntax highlighting.

	The lexer is tolerant: it never fails, so it also highlights text that is not valid while the user types. It does not check the rules that only the parser checks, like the range of an int or the order of duration units.

	Whitespace is not a token, so the tokens do not cover the text. Use `parts(in:)` to get the whole text.
	*/
	public struct Token: Hashable, Sendable {
		/**
		The token category, independent of any editor theme.
		*/
		public enum Kind: CaseIterable, Sendable {
			case comment
			case key
			case string
			case escape
			case number
			case keyword
			case date
			case instant
			case duration
			case punctuation
			case invalid
		}

		/**
		The token category.
		*/
		public let kind: Kind

		/**
		The range in UTF-8 bytes.
		*/
		public let range: Range<Int>
	}
}

extension SOML.Token {
	/**
	The tokens of SOML source text, in order.
	*/
	public static func tokens(in text: String) -> [Self] {
		text.withUTF8Buffer { bytes in
			var lexer = Lexer(text: bytes)
			return lexer.tokenize()
		}
	}

	/**
	The parts of SOML source text, in order, with the kind of each token, or `nil` for the text between tokens, like whitespace. Together, the parts are the whole text, so a highlighter can show each part without tracking UTF-8 offsets.
	*/
	public static func parts(in text: String) -> [(text: Substring, kind: Kind?)] {
		let utf8 = text.utf8
		var parts = [(text: Substring, kind: Kind?)]()
		var index = utf8.startIndex
		var offset = 0

		// Advances from the end of the previous part, so the text is walked once.
		func append(upTo end: Int, kind: Kind?) {
			let endIndex = utf8.index(index, offsetBy: end - offset)
			parts.append((text[index..<endIndex], kind))
			index = endIndex
			offset = end
		}

		let tokens = tokens(in: text)

		// The parts are the tokens and the gaps between them, counted first, so that the array is made once at its size, rather than growing by doubling past it, which for text of one token for each byte took most of the memory.
		var gapCount = 0
		var previousEnd = 0

		for token in tokens {
			if token.range.lowerBound > previousEnd {
				gapCount += 1
			}

			previousEnd = token.range.upperBound
		}

		parts.reserveCapacity(tokens.count + gapCount + (utf8.count > previousEnd ? 1 : 0))

		for token in tokens {
			if token.range.lowerBound > offset {
				append(upTo: token.range.lowerBound, kind: nil)
			}

			append(upTo: token.range.upperBound, kind: token.kind)
		}

		if utf8.count > offset {
			append(upTo: utf8.count, kind: nil)
		}

		return parts
	}
}

extension SOML {
	/**
	The lexical context at an insertion point, including incomplete source. Ranges use UTF-8 byte offsets. Quoted keys have the same context as strings; a delimiter contains one quote for a single-line string and three or more for a block string.
	*/
	public enum LexicalContext: Hashable, Sendable {
		case code
		case comment
		case string(delimiter: String, closingDelimiterRange: Range<Int>?)
	}

	/**
	Classifies a UTF-8 insertion offset without requiring a valid document. Opening delimiter positions are outside the token, also those between the characters of a delimiter of more than one character, like a block comment's or a block string's, closing delimiter positions are inside it, and an unfinished token includes its end. Offsets outside the source return `nil`.
	*/
	public static func lexicalContext(in text: String, atUTF8Offset offset: Int) -> LexicalContext? {
		text.withUTF8Buffer { bytes in
			guard (0...bytes.count).contains(offset) else {
				return nil
			}

			var lexer = Lexer(text: bytes)
			return lexer.lexicalContext(at: offset)
		}
	}
}

private struct Lexer {
	private enum Container {
		case object
		case array
	}

	/**
	What the syntax allows next. It decides whether a word is a key or a value.
	*/
	private enum Expectation {
		case key

		/**
		The colon after a key. A word here is lexed as a value, as after the colon, but a line break ends the member, which is missing its colon while it is typed.
		*/
		case colon

		case value
		case separator
	}

	let text: UnsafeBufferPointer<UInt8>
	private var index = 0
	var contextOffset: Int?
	private(set) var context = SOML.LexicalContext.code
	private var tokens = [SOML.Token]()
	private var containers = [Container]()
	private var expectation = Expectation.value

	/**
	Whether the document is an object without braces, whose object is the first of `containers`.
	*/
	private var isBraceless = false

	init(text: UnsafeBufferPointer<UInt8>) {
		self.text = text
	}

	mutating func tokenize() -> [SOML.Token] {
		startDocument()

		while index < text.count {
			let character = text[index]

			switch character {
			// A carriage return is not whitespace, so it is an invalid token, as the parser refuses it.
			case .space, .tab:
				index += 1
			case .lineFeed:
				index += 1

				switch expectation {
				case .colon, .separator:
					expectNextEntry()
				case .value where containers.last == .object && looksLikeMember(at: endOfSpacesAndBlockComments(from: index)):
					// The value of the member before is missing while it is typed.
					expectation = .key
				case .key, .value:
					break
				}
			case .hash:
				lexLineComment()
			case .slash where peek(1) == .asterisk:
				lexBlockComment()
			case .openBrace, .openBracket:
				lexPunctuation()
				containers.append(character == .openBrace ? .object : .array)
				expectation = character == .openBrace ? .key : .value
			case .closeBrace, .closeBracket:
				lexPunctuation()

				// It also closes the unfinished containers inside the one that it matches, like a `{` without its `}` in an array, and a stray one closes nothing, also when it would match the object of a document without braces, which has no `{`.
				// Recovery only looks back through the supported nesting depth, so repeated unmatched brackets cannot repeatedly scan an unbounded stack.
				if
					let opening = containers.suffix(Parser.maximumDepth).lastIndex(of: character == .closeBrace ? .object : .array),
					opening > 0 || !isBraceless
				{
					containers.removeSubrange(opening...)
				}

				expectation = .separator
			case .comma:
				lexPunctuation()
				expectNextEntry()
			case .colon:
				lexPunctuation()
				expectation = .value
			case .singleQuote, .doubleQuote:
				lexQuoted()
			default:
				lexWord()
			}
		}

		return tokens
	}

	/**
	Finds an insertion point's string or comment context without building highlighting tokens or container state.
	*/
	mutating func lexicalContext(at offset: Int) -> SOML.LexicalContext {
		contextOffset = offset

		while
			index < text.count,
			index < offset
		{
			switch text[index] {
			case .hash:
				lexLineComment()
			case .slash where peek(1) == .asterisk:
				lexBlockComment()
			case .singleQuote, .doubleQuote:
				lexQuoted()
			default:
				index += 1
			}
		}

		return context
	}

	/**
	A document that does not begin with a bracket is an object without braces, so it begins with a key.
	*/
	private mutating func startDocument() {
		var lookahead = 0

		while index + lookahead < text.count {
			let character = text[index + lookahead]

			switch character {
			case .space, .tab, .lineFeed, .carriageReturn:
				lookahead += 1
			case .hash:
				lookahead = text.lineEnd(from: index + lookahead) - index
			case .slash where peek(lookahead + 1) == .asterisk:
				lookahead = text.blockCommentEnd(from: index + lookahead + 2) - index
			default:
				if character != .openBrace, character != .openBracket {
					containers.append(.object)
					expectation = .key
					isBraceless = true
				}

				return
			}
		}
	}

	private mutating func expectNextEntry() {
		expectation = containers.last == .array ? .value : .key
	}

	private func peek(_ offset: Int) -> UInt8? {
		let position = index + offset

		guard position < text.count else {
			return nil
		}

		return text[position]
	}

	private mutating func add(_ kind: SOML.Token.Kind, _ range: Range<Int>) {
		guard
			contextOffset == nil,
			!range.isEmpty
		else {
			return
		}

		tokens.append(SOML.Token(kind: kind, range: range))
	}

	private mutating func lexPunctuation() {
		add(.punctuation, index..<(index + 1))
		index += 1
	}

	private mutating func lexLineComment() {
		let start = index

		index = text.lineEnd(from: index)

		add(.comment, start..<index)
		recordContext(.comment, contentStart: start + 1, throughEnd: true)
	}

	private mutating func lexBlockComment() {
		let start = index
		index = text.blockCommentEnd(from: start + 2)
		let isClosed = index >= start + 4 && text[index - 2] == .asterisk && text[index - 1] == .slash
		add(.comment, start..<index)
		recordContext(.comment, contentStart: start + 2, throughEnd: !isClosed)
	}

	private mutating func lexQuoted() {
		let quote = text[index]
		let start = index
		let quoteCount = text.endOfRun(of: quote, from: index) - index

		let isKey = expectation == .key
		let kind: SOML.Token.Kind = isKey ? .key : .string

		if quoteCount >= 3 {
			lexBlockString(quote: quote, delimiterLength: quoteCount)
		} else if quoteCount == 2 {
			// An empty string.
			index += 2
			recordStringContext(quote: quote, delimiterLength: 1, closingRange: (index - 1)..<index, from: start, throughEnd: false)
			add(kind, start..<index)
		} else {
			index += 1

			while index < text.count, text[index] != quote, text[index] != .lineFeed {
				if
					quote == .doubleQuote,
					text[index] == .backslash,
					peek(1) != .lineFeed
				{
					index += 1
				}

				index += 1
			}

			let isClosed = index < text.count && text[index] == quote
			if isClosed {
				index += 1
			}

			index = min(index, text.count)
			recordStringContext(quote: quote, delimiterLength: 1, closingRange: isClosed ? (index - 1)..<index : nil, from: start, throughEnd: !isClosed)

			if quote == .doubleQuote {
				addEscapedString(start..<index, contentEnd: isClosed ? index - 1 : index, kind: kind)
			} else {
				add(kind, start..<index)
			}
		}

		expectation = isKey ? .colon : .separator
	}

	/**
	A block string ends at the first line that holds, after spaces and tabs, a run of exactly as many quotes as the opening delimiter.
	*/
	private mutating func lexBlockString(quote: UInt8, delimiterLength: Int) {
		let start = index
		index += delimiterLength

		// Skip the rest of the opening line.
		index = text.lineEnd(from: index)

		var end = text.count
		var closingRange: Range<Int>?

		while index < text.count {
			// At a line feed. Look at the next line.
			index += 1

			var position = index

			while position < text.count, text[position].isSpaceOrTab {
				position += 1
			}

			let runLength = text.endOfRun(of: quote, from: position) - position

			if runLength == delimiterLength {
				end = position + runLength
				closingRange = position..<end
				break
			}

			index = text.lineEnd(from: index)
		}

		index = end
		recordStringContext(quote: quote, delimiterLength: delimiterLength, closingRange: closingRange, from: start, throughEnd: closingRange == nil)

		if quote == .doubleQuote {
			addEscapedString(start..<end, contentEnd: closingRange?.lowerBound ?? end, kind: .string)
		} else {
			add(.string, start..<end)
		}
	}

	/**
	Whether the requested insertion point is inside the current token, whose content starts after its opening delimiter at `contentStart`. Opening delimiters are outside, also between their characters, where typing breaks them, and only unfinished tokens include their end.
	*/
	private func containsContext(contentStart: Int, throughEnd: Bool) -> Bool {
		guard let contextOffset else {
			return false
		}

		return contextOffset >= contentStart && (contextOffset < index || (throughEnd && contextOffset == index))
	}

	/**
	Records the lexical context of an insertion point. Inserting at an opening delimiter is outside it; an unfinished token includes its end.
	*/
	private mutating func recordContext(_ context: SOML.LexicalContext, contentStart: Int, throughEnd: Bool) {
		guard containsContext(contentStart: contentStart, throughEnd: throughEnd) else {
			return
		}

		self.context = context
	}

	/**
	Builds a string context only when the insertion point is inside it.
	*/
	private mutating func recordStringContext(quote: UInt8, delimiterLength: Int, closingRange: Range<Int>?, from start: Int, throughEnd: Bool) {
		guard containsContext(contentStart: start + delimiterLength, throughEnd: throughEnd) else {
			return
		}

		// Decode repeated bytes directly: `String(repeating:count:)` measured substantially slower for long quote delimiters in optimized Swift 6.4 builds on an M4 Pro.
		context = .string(delimiter: String(decoding: repeatElement(quote, count: delimiterLength), as: UTF8.self), closingDelimiterRange: closingRange)
	}

	/**
	Adds a string or a quoted key with its escapes as separate tokens. An escape ends by `contentEnd`, the start of the closing delimiter, so an unfinished one does not take the delimiter.
	*/
	private mutating func addEscapedString(_ range: Range<Int>, contentEnd: Int, kind: SOML.Token.Kind) {
		guard contextOffset == nil else {
			return
		}

		var segmentStart = range.lowerBound
		var position = range.lowerBound

		while position < contentEnd {
			guard text[position] == .backslash else {
				position += 1
				continue
			}

			add(kind, segmentStart..<position)

			// A `\` before a line feed, which is not an escape, is one character.
			var escapeEnd = position + 1 < contentEnd && text[position + 1] != .lineFeed ? position + 2 : position + 1

			if
				text[escapeEnd - 1] == .lowercaseU,
				escapeEnd < contentEnd,
				text[escapeEnd] == .openBrace
			{
				// `\u{…}`, up to its hex digits and its `}`, as far as they are typed.
				escapeEnd += 1

				while escapeEnd < contentEnd, text[escapeEnd].isHexadecimalDigit {
					escapeEnd += 1
				}

				if escapeEnd < contentEnd, text[escapeEnd] == .closeBrace {
					escapeEnd += 1
				}
			}

			// Do not split a Unicode scalar, like a `\` before an emoji, which is not a valid escape.
			while escapeEnd < contentEnd, text[escapeEnd].isUTF8ContinuationByte {
				escapeEnd += 1
			}

			add(.escape, position..<escapeEnd)
			position = escapeEnd
			segmentStart = escapeEnd
		}

		add(kind, segmentStart..<range.upperBound)
	}

	private mutating func lexWord() {
		let start = index

		if expectation == .key {
			while index < text.count, text[index].isBareKeyByte {
				index += 1
			}

			if index > start {
				add(.key, start..<index)
				expectation = .colon
				return
			}
		} else {
			while index < text.count, text[index].isScalarTokenByte {
				index += 1
			}

			// After a key, a word is a mistake, like the `.com` of `example.com:`, and the colon after it is punctuation, unless the word is an instant, which holds colons.
			if
				expectation == .colon,
				let colon = text[start..<index].firstIndex(of: .colon),
				!Self.isInstant(text[start..<index])
			{
				index = colon
			}

			if index > start {
				add(Self.kind(ofValueWord: text[start..<index]), start..<index)
				expectation = .separator
				return
			}
		}

		// A character that cannot begin a token. Mark the run up to the next whitespace or punctuation.
		while
			index < text.count,
			!text[index].isTokenBoundary,
			!(text[index] == .slash && peek(1) == .asterisk)
		{
			index += 1
		}

		index = max(index, start + 1)
		add(.invalid, start..<index)

		// An invalid value is a value, so the line break after it ends the member.
		if expectation != .key {
			expectation = .separator
		}
	}

	/**
	The offset after the spaces, tabs, and block comments from `offset`, where a key can begin.
	*/
	private func endOfSpacesAndBlockComments(from offset: Int) -> Int {
		var end = text.endOfSpacesAndTabs(from: offset)

		while
			end + 1 < text.count,
			text[end] == .slash,
			text[end + 1] == .asterisk
		{
			end = text.endOfSpacesAndTabs(from: text.blockCommentEnd(from: end + 2))
		}

		return end
	}

	/**
	Whether a key and its colon begin at `position`, like `port:` or `'the name':`, but not an instant, which also begins with bare key characters and a colon.
	*/
	private func looksLikeMember(at position: Int) -> Bool {
		guard position < text.count else {
			return false
		}

		let quote = text[position]
		var end = position

		if quote == .singleQuote || quote == .doubleQuote {
			// A block string is a value.
			guard text.endOfRun(of: quote, from: position) - position < 3 else {
				return false
			}

			end += 1

			// As in `lexQuoted(_:)`, a `\` does not escape a line feed, so the string ends there.
			while end < text.count, text[end] != quote, text[end] != .lineFeed {
				end += quote == .doubleQuote && text[end] == .backslash && end + 1 < text.count && text[end + 1] != .lineFeed ? 2 : 1
			}

			guard end < text.count, text[end] == quote else {
				return false
			}

			end += 1
		} else {
			while end < text.count, text[end].isBareKeyByte {
				end += 1
			}

			// `2026-09-19T14` is followed by a colon too.
			if
				end - position == 13,
				text[position].isASCIIDigit
			{
				var wordEnd = end

				while wordEnd < text.count, text[wordEnd].isScalarTokenByte {
					wordEnd += 1
				}

				if Self.isInstant(text[position..<wordEnd]) {
					return false
				}
			}
		}

		return end > position && end < text.count && text[end] == .colon
	}

	private static func kind(ofValueWord word: Slice<UnsafeBufferPointer<UInt8>>) -> SOML.Token.Kind {
		// A String switch requires conversion and regressed the common true token in paired probes; compare static UTF-8 literals directly.
		if word.elementsEqual("true") || word.elementsEqual("false") || word.elementsEqual("null") {
			return .keyword
		}

		if word.hasASCIIPattern("0000-00-00") {
			return .date
		}

		if isInstant(word) {
			return .instant
		}

		if isDuration(word) {
			return .duration
		}

		if isNumber(word) {
			return .number
		}

		return .invalid
	}

	/**
	`2026-09-19T14:00:00Z`, with an optional fraction of a second and an offset instead of `Z`.
	*/
	private static func isInstant(_ word: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
		let characters = word
		let start = word.startIndex

		guard characters.count >= 20 else {
			return false
		}

		let pattern: StaticString = "0000-00-00T00:00:00"

		guard characters.prefix(pattern.utf8CodeUnitCount).hasASCIIPattern(pattern) else {
			return false
		}

		var position = start + pattern.utf8CodeUnitCount

		if characters[position] == .dot {
			position += 1
			let fractionStart = position

			while position < characters.endIndex, characters[position].isASCIIDigit {
				position += 1
			}

			guard position > fractionStart else {
				return false
			}
		}

		guard position < characters.endIndex else {
			return false
		}

		if characters[position] == .uppercaseZ {
			return position + 1 == characters.endIndex
		}

		guard
			characters[position] == .plus || characters[position] == .hyphen,
			characters.endIndex == position + 6
		else {
			return false
		}

		let offset = characters[(position + 1)...]
		return offset.hasASCIIPattern("00:00")
	}

	/**
	`1h30m`, `1.5s`, `-250ms`. Units are `h`, `m`, `s`, `ms`, `us`, and `ns`.
	*/
	private static func isDuration(_ word: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
		var position = word.startIndex

		if position < word.endIndex, word[position] == .hyphen {
			position += 1
		}

		var hasPart = false

		while position < word.endIndex {
			let digitsStart = position

			while position < word.endIndex, word[position].isASCIIDigit || word[position] == .underscore || word[position] == .dot {
				position += 1
			}

			guard
				position > digitsStart,
				position < word.endIndex
			else {
				return false
			}

			let unit = word[position]
			let next: UInt8? = position + 1 < word.endIndex ? word[position + 1] : nil

			if
				unit == .lowercaseM || unit == .lowercaseU || unit == .lowercaseN,
				next == .lowercaseS
			{
				position += 2
			} else if unit == .lowercaseH || unit == .lowercaseM || unit == .lowercaseS {
				position += 1
			} else {
				return false
			}

			hasPart = true
		}

		return hasPart
	}

	/**
	An int or a float in any spelling. Loose, because the parser reports the details.
	*/
	private static func isNumber(_ word: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
		var characters = word

		if characters.first == .hyphen {
			characters = characters.dropFirst()
		}

		if characters.elementsEqual("infinity") {
			return true
		}

		guard let first = characters.first, first.isASCIIDigit else {
			return false
		}

		if
			first == .digitZero,
			characters.count > 2
		{
			let prefix = characters[characters.startIndex + 1]
			let digits = characters.dropFirst(2)

			switch prefix {
			case .lowercaseX:
				return digits.allSatisfy { $0.isHexadecimalDigit || $0 == .underscore }
			case .lowercaseO, .lowercaseB:
				return digits.allSatisfy { $0.isASCIIDigit || $0 == .underscore }
			default:
				break
			}
		}

		var hasExponent = false
		var previous: UInt8?

		for character in characters {
			if character.isASCIIDigit || character == .underscore || character == .dot {
				// Valid anywhere in the loose form.
			} else if character == .lowercaseE, !hasExponent {
				hasExponent = true
			} else if character == .hyphen, previous == .lowercaseE {
				// A negative exponent.
			} else {
				return false
			}

			previous = character
		}

		return true
	}
}

extension UInt8 {
	fileprivate var isTokenBoundary: Bool {
		switch self {
		case .space, .tab, .lineFeed, .comma, .colon, .openBrace, .closeBrace, .openBracket, .closeBracket, .singleQuote, .doubleQuote, .hash:
			true
		default:
			false
		}
	}
}

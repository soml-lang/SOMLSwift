extension SOML {
	/**
	A token of SOML source text, for syntax highlighting.

	The lexer is tolerant: it never fails, so it also highlights text that is not valid while the user types. It does not check the rules that only the parser checks, like the range of an int or the order of duration units.

	Whitespace is not a token, so the tokens do not cover the text.
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
	Classifies a UTF-8 insertion offset without requiring a valid document. Opening delimiter positions are outside the token, closing delimiter positions are inside it, and an unfinished token includes its end. Offsets outside the source return `nil`.
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

	init(text: UnsafeBufferPointer<UInt8>) {
		self.text = text
	}

	mutating func tokenize() -> [SOML.Token] {
		startDocument()

		while index < text.count {
			let character = text[index]

			switch character {
			case .space, .tab, .carriageReturn:
				index += 1
			case .lineFeed:
				index += 1
				if expectation == .separator {
					expectNextEntry()
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
				_ = containers.popLast()
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
		recordContext(.comment, from: start, throughEnd: true)
	}

	private mutating func lexBlockComment() {
		let start = index
		index = text.blockCommentEnd(from: start + 2)
		let isClosed = index >= start + 4 && text[index - 2] == .asterisk && text[index - 1] == .slash
		add(.comment, start..<index)
		recordContext(.comment, from: start, throughEnd: !isClosed)
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

			if quote == .doubleQuote, !isKey {
				addEscapedString(start..<index)
			} else {
				add(kind, start..<index)
			}
		}

		expectation = isKey ? .value : .separator
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
			addEscapedString(start..<end)
		} else {
			add(.string, start..<end)
		}
	}

	/**
	Whether the requested insertion point is inside the current token. Opening delimiters are outside, and only unfinished tokens include their end.
	*/
	private func containsContext(from start: Int, throughEnd: Bool) -> Bool {
		guard let contextOffset else {
			return false
		}

		return contextOffset > start && (contextOffset < index || (throughEnd && contextOffset == index))
	}

	/**
	Records the lexical context of an insertion point. Inserting at an opening delimiter is outside it; an unfinished token includes its end.
	*/
	private mutating func recordContext(_ context: SOML.LexicalContext, from start: Int, throughEnd: Bool) {
		guard containsContext(from: start, throughEnd: throughEnd) else {
			return
		}

		self.context = context
	}

	/**
	Builds a string context only when the insertion point is inside it.
	*/
	private mutating func recordStringContext(quote: UInt8, delimiterLength: Int, closingRange: Range<Int>?, from start: Int, throughEnd: Bool) {
		guard containsContext(from: start, throughEnd: throughEnd) else {
			return
		}

		// Decode repeated bytes directly: `String(repeating:count:)` measured substantially slower for long quote delimiters in optimized Swift 6.4 builds on an M4 Pro.
		context = .string(delimiter: String(decoding: repeatElement(quote, count: delimiterLength), as: UTF8.self), closingDelimiterRange: closingRange)
	}

	/**
	Adds a string with its escapes as separate tokens.
	*/
	private mutating func addEscapedString(_ range: Range<Int>) {
		guard contextOffset == nil else {
			return
		}

		var segmentStart = range.lowerBound
		var position = range.lowerBound

		while position < range.upperBound {
			guard text[position] == .backslash else {
				position += 1
				continue
			}

			add(.string, segmentStart..<position)

			var escapeEnd = min(position + 2, range.upperBound)

			if text[escapeEnd - 1] == .lowercaseU {
				// `\u{…}`
				while escapeEnd < range.upperBound, text[escapeEnd - 1] != .closeBrace, text[escapeEnd] != .lineFeed {
					escapeEnd += 1
				}
			}

			// Do not split a Unicode scalar, like a `\` before an emoji, which is not a valid escape.
			while escapeEnd < range.upperBound, text[escapeEnd].isUTF8ContinuationByte {
				escapeEnd += 1
			}

			add(.escape, position..<escapeEnd)
			position = escapeEnd
			segmentStart = escapeEnd
		}

		add(.string, segmentStart..<range.upperBound)
	}

	private mutating func lexWord() {
		let start = index

		if expectation == .key {
			while index < text.count, text[index].isBareKeyByte {
				index += 1
			}

			if index > start {
				add(.key, start..<index)
				expectation = .value
				return
			}
		} else {
			while index < text.count, text[index].isScalarTokenByte {
				index += 1
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
	}

	private static func kind(ofValueWord word: Slice<UnsafeBufferPointer<UInt8>>) -> SOML.Token.Kind {
		// A String switch requires conversion and regressed the common true token in paired probes; compare static UTF-8 literals directly.
		if word.elementsEqual("true") || word.elementsEqual("false") || word.elementsEqual("null") {
			return .keyword
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
		case .space, .tab, .lineFeed, .carriageReturn, .comma, .colon, .openBrace, .closeBrace, .openBracket, .closeBracket, .singleQuote, .doubleQuote, .hash:
			true
		default:
			false
		}
	}
}

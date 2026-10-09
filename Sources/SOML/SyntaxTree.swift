/**
A SOML document as nodes with their byte ranges in the source, and its comments, for `SOML.Document`, which keeps the author's text.

It is a port of `parseTree` in the JS reference implementation. The parser reads the document first and checks every rule, so the builder can trust its input, and the two cannot disagree about whether a document is valid.
*/
struct SyntaxTree: Sendable {
	/**
	A `#` comment, which runs to the end of its line, or a `/* */` comment.
	*/
	struct Comment: Sendable {
		let isBlock: Bool

		/**
		The bytes of the comment, including its delimiters, but not the line feed after a `#` comment.
		*/
		let range: Range<Int>
	}

	struct Member: Sendable {
		/**
		The decoded key, without quotes and with escapes resolved.
		*/
		let key: String

		/**
		The bytes of the key, including its quotes, without the `:`.
		*/
		let keyRange: Range<Int>

		let value: Node

		/**
		The bytes from the key to the end of the value.
		*/
		var range: Range<Int> {
			keyRange.lowerBound..<value.range.upperBound
		}
	}

	struct Node: Sendable {
		enum Kind: Sendable {
			/**
			`isBraced` is `false` only for a top-level object written without braces.
			*/
			case object(members: [Member], isBraced: Bool)

			case array(items: [Node])
			case blockString
			case scalar
		}

		let kind: Kind

		/**
		The bytes of the value. An object's or an array's range includes its brackets, except for a top-level object without braces, which runs from its first member to its last.
		*/
		let range: Range<Int>
	}

	/**
	The UTF-8 bytes of the document. Every range in the tree is an offset into them.
	*/
	let text: [UInt8]

	/**
	The document's collection: an object or an array.
	*/
	let body: Node

	/**
	Every comment, in source order.
	*/
	let comments: [Comment]

	/**
	The offsets of the line feeds in the text, in order, so that finding the line of an offset takes logarithmic time. Without them, a formatter or an edit that asks about many places on one long line takes quadratic time.
	*/
	let lineFeeds: [Int]

	/**
	Builds the tree of a document that the parser has accepted.
	*/
	init(validDocument text: [UInt8], value: SOML.Value) {
		var builder = Builder(text: text)
		self.body = builder.document(value: value)
		self.comments = builder.comments
		self.text = text
		self.lineFeeds = text.indices.filter { text[$0] == .lineFeed }
	}
}

extension SyntaxTree {
	/**
	Whether no line feed is in the range.
	*/
	func isSameLine(_ start: Int, _ end: Int) -> Bool {
		guard start < end else {
			return true
		}

		let next = lineFeeds.partitioningIndex { $0 >= start }
		return next == lineFeeds.endIndex || lineFeeds[next] >= end
	}

	/**
	The location of an offset. Finding the line takes logarithmic time, and counting the column takes linear time in the length of the line.
	*/
	func location(at offset: Int) -> SOML.Location {
		let offset = max(0, min(offset, text.count))
		let line = lineFeeds.partitioningIndex { $0 >= offset }
		let lineStart = line == 0 ? 0 : lineFeeds[line - 1] + 1
		return SOML.Location(offset: offset, line: line + 1, lineStart: lineStart, in: text)
	}

	/**
	The offset of the start of the line that holds `offset`.
	*/
	func lineStart(at offset: Int) -> Int {
		let next = lineFeeds.partitioningIndex { $0 >= offset }
		return next == lineFeeds.startIndex ? 0 : lineFeeds[next - 1] + 1
	}

	/**
	The offset of the line feed that ends the line holding `offset`, or the end of the text on the last line.
	*/
	func lineEnd(from offset: Int) -> Int {
		let next = lineFeeds.partitioningIndex { $0 >= offset }
		return next == lineFeeds.endIndex ? text.count : lineFeeds[next]
	}

	/**
	The comments directly above the member or item that starts at `offset`, in source order: a run of comments with only spaces, tabs, and single line breaks between them and the member or item, without the ones at the start of the run that follow something else on their line, like the comma of the item before it.
	*/
	func comments(before offset: Int) -> ArraySlice<Comment> {
		let end = comments.partitioningIndex { $0.range.lowerBound >= offset }
		var start = end
		var position = offset

		while start > comments.startIndex {
			let comment = comments[start - 1]
			let gap = text[comment.range.upperBound..<position]

			guard
				gap.allSatisfy({ $0.isSpaceOrTab || $0 == .lineFeed }),
				gap.count(where: { $0 == .lineFeed }) <= 1
			else {
				break
			}

			start -= 1
			position = comment.range.lowerBound
		}

		// The comments on the line of what comes before the run belong to that line. Only the spaces and tabs directly before each comment are read, so that many comments on one line take linear time.
		while start < end {
			var lineOffset = comments[start].range.lowerBound

			while
				lineOffset > 0,
				text[lineOffset - 1].isSpaceOrTab
			{
				lineOffset -= 1
			}

			guard
				lineOffset > 0,
				text[lineOffset - 1] != .lineFeed
			else {
				break
			}

			start += 1
		}

		return comments[start..<end]
	}

	/**
	The end of the comment that starts at `offset`, or `nil` when no comment starts there.
	*/
	func commentEnd(startingAt offset: Int) -> Int? {
		let index = comments.partitioningIndex { $0.range.lowerBound >= offset }

		guard
			index < comments.endIndex,
			comments[index].range.lowerBound == offset
		else {
			return nil
		}

		return comments[index].range.upperBound
	}
}

extension SyntaxTree.Comment {
	/**
	The text of the comment without its `#` or `/* */`, and without one space after the `#` or `/*` and one space before the `*/`.
	*/
	func text(in bytes: [UInt8]) -> String {
		var content = bytes[range].dropFirst(isBlock ? 2 : 1)

		if isBlock {
			content = content.dropLast(2)
		}

		if content.first == .space {
			content = content.dropFirst()
		}

		if
			isBlock,
			content.last == .space
		{
			content = content.dropLast()
		}

		return String(decoding: content, as: UTF8.self)
	}
}

private struct Builder {
	let text: [UInt8]
	var index = 0
	var comments = [SyntaxTree.Comment]()

	init(text: [UInt8]) {
		self.text = text
	}

	/**
	The byte at an offset, or `nil` past the end.
	*/
	func byte(at offset: Int) -> UInt8? {
		offset < text.count ? text[offset] : nil
	}

	var current: UInt8? {
		byte(at: index)
	}

	mutating func document(value: SOML.Value) -> SyntaxTree.Node {
		skipTrivia()

		let body: SyntaxTree.Node

		if
			case .object(let object) = value,
			current != .openBrace
		{
			body = bareObject(object)
		} else {
			body = node(for: value)
		}

		skipTrivia()
		return body
	}

	mutating func skipTrivia() {
		while let byte = current {
			let start = index

			if byte.isSOMLWhitespace {
				index += 1
			} else if byte == .hash {
				index = text.lineEnd(from: start)
				comments.append(.init(isBlock: false, range: start..<index))
			} else if
				byte == .slash,
				self.byte(at: start + 1) == .asterisk
			{
				index = text.blockCommentEnd(from: start + 2)
				comments.append(.init(isBlock: true, range: start..<index))
			} else {
				return
			}
		}
	}

	mutating func bareObject(_ object: SOML.Object) -> SyntaxTree.Node {
		let start = index
		var members = [SyntaxTree.Member]()
		members.reserveCapacity(object.count)

		repeat {
			members.append(member(object[members.count]))
			skipTrivia()
		} while index < text.count

		return .init(kind: .object(members: members, isBraced: false), range: start..<(members.last?.range.upperBound ?? start))
	}

	/*
	`object(_:)` and `array(_:)` repeat the loop over the items instead of sharing a generic function that takes a closure, because in a debug build the closure adds stack frames on every level of nesting.
	*/

	mutating func object(_ object: SOML.Object) -> SyntaxTree.Node {
		let start = index
		var members = [SyntaxTree.Member]()
		members.reserveCapacity(object.count)
		openBracket()

		while let byte = current, byte != .closeBrace {
			members.append(member(object[members.count]))
			skipSeparator()
		}

		index += 1
		return .init(kind: .object(members: members, isBraced: true), range: start..<index)
	}

	mutating func array(_ values: [SOML.Value]) -> SyntaxTree.Node {
		let start = index
		var items = [SyntaxTree.Node]()
		items.reserveCapacity(values.count)
		openBracket()

		while let byte = current, byte != .closeBracket {
			items.append(node(for: values[items.count]))
			skipSeparator()
		}

		index += 1
		return .init(kind: .array(items: items), range: start..<index)
	}

	mutating func openBracket() {
		index += 1
		skipTrivia()
	}

	/**
	Skips the trivia after an item, and its comma when it has one. A line break may separate items instead, and the parser has already checked the separators.
	*/
	mutating func skipSeparator() {
		skipTrivia()

		if current == .comma {
			index += 1
			skipTrivia()
		}
	}

	mutating func member(_ member: SOML.Object.Element) -> SyntaxTree.Member {
		let keyStart = index
		skipKey()
		let keyEnd = index
		index += 1 // The `:`.
		skipTrivia()

		return .init(key: member.key, keyRange: keyStart..<keyEnd, value: node(for: member.value))
	}

	/**
	Moves past a key whose decoded text is shared with the parsed value. It is a separate function from `member(_:)` so that its locals are not on the stack once per level of nesting.

	The value of a quoted key is reused from the parsed object, so even escaped keys need no second parse.
	*/
	mutating func skipKey() {
		if current?.isQuote == true {
			singleLineString()
			return
		}

		while let byte = current, byte.isBareKeyByte {
			index += 1
		}
	}

	mutating func node(for value: SOML.Value) -> SyntaxTree.Node {
		let start = index

		switch value {
		case .object(let object):
			return self.object(object)
		case .array(let values):
			return array(values)
		case .string:
			let quote = text[start]
			if
				byte(at: start + 1) == quote,
				byte(at: start + 2) == quote
			{
				blockString(quote: quote)
				return .init(kind: .blockString, range: start..<index)
			}

			singleLineString()
			return .init(kind: .scalar, range: start..<index)
		default:
			// A keyword, a number, an instant, or a duration, which is one run of these characters. `infinity` is a float.
			while let byte = current, byte.isScalarTokenByte {
				index += 1
			}

			return .init(kind: .scalar, range: start..<index)
		}
	}

	/**
	`'...'` ends at the next `'`. `"..."` ends at the next `"` that is not escaped, and `\` always starts a two-character escape or a `\u{…}`, which holds no quote.
	*/
	mutating func singleLineString() {
		let quote = current
		index += 1

		while let byte = current, byte != quote {
			index += quote == .doubleQuote && byte == .backslash ? 2 : 1
		}

		index += 1
	}

	/**
	The block ends at the first line whose first non-whitespace content is a run of exactly as many quotes as the opening delimiter.
	*/
	mutating func blockString(quote: UInt8) {
		let delimiterLength = text.endOfRun(of: quote, from: index) - index

		var lineStart = text.lineEnd(from: index) + 1

		while lineStart < text.count {
			var delimiterStart = lineStart

			while byte(at: delimiterStart)?.isSpaceOrTab == true {
				delimiterStart += 1
			}

			let runLength = text.endOfRun(of: quote, from: delimiterStart) - delimiterStart

			if runLength == delimiterLength {
				index = delimiterStart + delimiterLength
				return
			}

			lineStart = text.lineEnd(from: lineStart) + 1
		}

		index = text.count
	}

}

/**
Byte scans shared by the lexer and syntax tree builder. The collection must have consecutive integer indices.
*/
extension Collection<UInt8> where Index == Int {
	/**
	The offset of the line feed that ends the line holding `offset`, or the end of the text on the last line.
	*/
	@inline(always)
	func lineEnd(from offset: Int) -> Int {
		var end = offset

		while
			end < endIndex,
			self[end] != .lineFeed
		{
			end += 1
		}

		return end
	}

	/**
	The offset just after the end of a block comment whose body starts at `offset`.
	*/
	@inline(always)
	func blockCommentEnd(from offset: Int) -> Int {
		// `firstRange(of: [UInt8.asterisk, .slash])` uses a generic pattern search; it measured substantially slower than this two-byte scan in optimized Swift 6.4 builds on an M4 Pro.
		var end = offset

		while
			end + 1 < endIndex,
			!(self[end] == .asterisk && self[end + 1] == .slash)
		{
			end += 1
		}

		return Swift.min(end + 2, endIndex)
	}

	/**
	The offset after a run of the same byte, including a run ending at the end of the collection.
	*/
	@inline(always)
	func endOfRun(of byte: UInt8, from offset: Int) -> Int {
		var end = offset

		while
			end < endIndex,
			self[end] == byte
		{
			end += 1
		}

		return end
	}
}

/**
ASCII grammar queries shared by the SOML and JSON readers.
*/
extension Collection<UInt8> {
	/**
	Whether the bytes exactly match a static UTF-8 literal, without constructing a string or an array for the pattern.
	*/
	@inline(always)
	func elementsEqual(_ literal: StaticString) -> Bool {
		count == literal.utf8CodeUnitCount && literal.withUTF8Buffer { elementsEqual($0) }
	}

	/**
	Whether the bytes have the exact form of `pattern`, where `0` stands for any ASCII digit.
	*/
	@inline(always)
	func hasASCIIPattern(_ pattern: StaticString) -> Bool {
		guard count == pattern.utf8CodeUnitCount else {
			return false
		}

		return pattern.withUTF8Buffer { pattern in
			elementsEqual(pattern) { $1 == .digitZero ? $0.isASCIIDigit : $0 == $1 }
		}
	}

	/**
	Whether a decimal significand contains a nonzero digit before its exponent, in either exponent spelling.
	*/
	var hasNonzeroSignificand: Bool {
		for byte in self {
			if byte.isASCIIExponentMarker {
				return false
			}

			if byte.isASCIINonzeroDigit {
				return true
			}
		}

		return false
	}
}

extension RandomAccessCollection {
	/**
	The index of the first element for which `predicate` is true, in a collection where every such element comes after every other, found by binary search. It is `endIndex` when there is none.
	*/
	func partitioningIndex(where predicate: (Element) -> Bool) -> Index {
		var low = startIndex
		var count = self.count

		while count > 0 {
			let half = count / 2
			let middle = index(low, offsetBy: half)

			if predicate(self[middle]) {
				count = half
			} else {
				low = index(after: middle)
				count -= half + 1
			}
		}

		return low
	}
}

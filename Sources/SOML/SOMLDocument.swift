extension SOML {
	/**
	A SOML document that keeps its source text, for tools that must keep what the author wrote, such as a formatter or a command that changes one setting in a config file.

	`SOML.Value(parsing:)` keeps only the value. This type also keeps the comments, the member order, and the spelling of every key and value.

	```swift
	let document = try SOML.Document(parsing: "pool: {\nmin: 2, max: 16} # Connections")

	print(document.formatted())
	//=> pool: {
	//=> 	min: 2
	//=> 	max: 16
	//=> } # Connections
	```
	*/
	public struct Document: Sendable {
		/**
		The value of the document.
		*/
		public let value: SOML.Value

		let tree: SyntaxTree

		/**
		Parses a SOML document.

		- Throws: `SOML.ParseError` if the text is not a valid SOML document.
		*/
		public init(parsing text: String) throws(SOML.ParseError) {
			try self.init(parsing: Array(text.utf8))
		}

		/**
		Parses a SOML document from UTF-8 bytes.

		- Throws: `SOML.ParseError` if the bytes are not a valid SOML document, including when they are not valid UTF-8.
		*/
		public init(parsing bytes: some Sequence<UInt8>) throws(SOML.ParseError) {
			let bytes = Array(bytes)

			// The parser checks every rule first, so the tree builder can trust its input, and the two cannot disagree about whether a document is valid.
			self.value = try Parser.parseDocument(bytes)
			self.tree = SyntaxTree(validDocument: bytes, value: value)
		}

		/**
		Builds source metadata around a value already validated by the parser, without parsing it a second time.
		*/
		init(validDocument bytes: [UInt8], value: SOML.Value) {
			self.value = value
			self.tree = SyntaxTree(validDocument: bytes, value: value)
		}
	}
}

extension SOML.Document {
	/**
	The document with its layout normalized as the spec's formatter defines it, keeping comments, member order, block strings, and the spelling of every value. With the default options, byte-identical to `format()` in the JavaScript reference implementation.

	The layout follows the formatter in the spec: one tab per level, every member and item on its own line with no commas, one space after `:`, and no trailing whitespace or runs of blank lines. An object or an array whose brackets are on one line stays on one line, as in `ports: [80, 443]`, with a comma and a space between its members or items and no trailing comma. To give a one-line container one member or item per line, put a line break anywhere inside it. The output ends with one line feed. The value never changes.

	Pass `expandingContainers: true` to put every nonempty object and array on separate lines without commas, including containers originally written on one line. Empty containers without comments remain compact. The default follows the reference formatter unchanged.

	In detail, as the spec states:

	- A comment at the end of a line stays at the end of that line. A block comment that a value follows on the same line, as in `1, /* note */ 2`, stays in front of that value when each item goes on its own line.
	- A value on the line after its `key:` moves up to that line, unless a comment comes between them. Then it stays on its own line, one level deeper than the key.
	- A block string begins on the line after its key, and its delimiters and content have the indentation of that line. Its lines are not otherwise changed.
	- There are no blank lines at the start of the file or directly inside brackets.
	*/
	public func formatted(expandingContainers: Bool = false) -> String {
		var printer = Printer(tree: tree, expandingContainers: expandingContainers)
		return String(decoding: printer.format(), as: UTF8.self)
	}
}

/**
A port of the `Printer` of `format()` in the JS reference implementation.

It recurses once per level of nesting through `list(_:start:end:level:isBraced:)` or `writeOneLine(_:start:end:level:)`, and the two `write(_:level:)` functions. Their other work is in separate functions, so that a level takes little stack, and 100 levels fit in the 512 KB stack of a secondary thread even in a debug build, where every local and temporary has its own stack slot.
*/
private struct Printer {
	let tree: SyntaxTree
	let expandingContainers: Bool
	var output = [UInt8]()

	/**
	The next comment to write. Comments are written in source order, each before the item that follows it.
	*/
	var commentIndex = 0

	var text: [UInt8] {
		tree.text
	}

	mutating func format() -> [UInt8] {
		output.reserveCapacity(text.count)
		let items: [Item] = if case .object(_, isBraced: false) = tree.body.kind {
			Item.items(in: tree.body)
		} else {
			[.value(tree.body)]
		}

		// The document is a list without commas: the members of a brace-less object, or one braced collection.
		list(items, start: 0, end: text.count, level: 0, isBraced: false)
		output.append(.lineFeed)
		return output
	}

	/**
	A member of an object or an item of an array.
	*/
	enum Item {
		case member(SyntaxTree.Member)
		case value(SyntaxTree.Node)

		/**
		The members of an object or the items of an array, and nothing for a scalar.
		*/
		static func items(in node: SyntaxTree.Node) -> [Self] {
			switch node.kind {
			case .object(let members, _):
				members.map(Self.member)
			case .array(let nodes):
				nodes.map(Self.value)
			case .blockString, .scalar:
				[]
			}
		}

		var range: Range<Int> {
			switch self {
			case .member(let member):
				member.range
			case .value(let node):
				node.range
			}
		}
	}

	/**
	Starts a new line at `level`, with one blank line before it when the source had one. At the start of the output it does nothing, so the file never starts with a blank line.
	*/
	mutating func newLine(level: Int, isBlank: Bool) {
		guard !output.isEmpty else {
			return
		}

		output.append(.lineFeed)

		if isBlank {
			output.append(.lineFeed)
		}

		output.appendIndentation(level)
	}

	/**
	Whether the source has a blank line between `start` and `end`: two line feeds with only spaces and tabs between them.
	*/
	func hasBlankLine(_ start: Int, _ end: Int) -> Bool {
		var lineFeeds = 0

		for byte in text[start..<max(start, end)] {
			if byte == .lineFeed {
				lineFeeds += 1

				if lineFeeds == 2 {
					return true
				}
			} else if !byte.isSpaceOrTab {
				lineFeeds = 0
			}
		}

		return false
	}

	/**
	The next comment that ends at or before `end`, without consuming it.
	*/
	func peekComment(before end: Int) -> SyntaxTree.Comment? {
		guard
			commentIndex < tree.comments.count,
			tree.comments[commentIndex].range.upperBound <= end
		else {
			return nil
		}

		return tree.comments[commentIndex]
	}

	mutating func write(_ comment: SyntaxTree.Comment) {
		commentIndex += 1

		guard comment.isBlock else {
			output.append(contentsOf: text[comment.range].withoutTrailingWhitespace)
			return
		}

		// The lines of a block comment keep their own indentation. Trailing whitespace is removed, and runs of blank lines collapse to one, as everywhere outside a block string.
		var previousLine: ArraySlice<UInt8>?

		for (index, line) in text[comment.range].split(separator: .lineFeed, omittingEmptySubsequences: false).enumerated() {
			let line = line.withoutTrailingWhitespace

			if
				line.isEmpty,
				previousLine?.isEmpty == true
			{
				continue
			}

			if index > 0 {
				output.append(.lineFeed)
			}

			output.append(contentsOf: line)
			previousLine = line
		}
	}

	/**
	The offset of the `,` after an item in the source, or `nil` when there is none. Only whitespace and comments come between items, besides the comma.
	*/
	func comma(from start: Int, to end: Int) -> Int? {
		var index = start

		while index < end {
			switch text[index] {
			case .comma:
				return index
			case .hash:
				index = text.lineEnd(from: index)
			case .slash:
				index = text.blockCommentEnd(from: index + 2)
			default:
				index += 1
			}
		}

		return nil
	}

	/**
	Writes `items` one per line at `level`, with the comments between them, from `start` to `end` in the source.

	A comment on the line of the item before it, or of the opening bracket, stays at the end of that line. The exception is a block comment after the comma that the next item follows on the same line, as in `[1, /* note */ 2]`: it stays in front of that item. Every other comment gets its own line.
	*/
	mutating func list(_ items: [Item], start: Int, end: Int, level: Int, isBraced: Bool) {
		var position = ListPosition(previousEnd: start, canTrail: isBraced)

		for item in items {
			writeGap(before: item.range.lowerBound, isBeforeItem: true, level: level, isBraced: isBraced, position: &position)

			switch item {
			case .member(let member):
				write(member, level: level)
			case .value(let node):
				write(node, level: level)
			}

			position = ListPosition(previousEnd: item.range.upperBound, itemEnd: item.range.upperBound, canTrail: true, hasWritten: true)
		}

		writeGap(before: end, isBeforeItem: false, level: level, isBraced: isBraced, position: &position)
	}

	/**
	Where `list(_:start:end:level:isBraced:)` is in the source and in the output.
	*/
	struct ListPosition {
		/**
		The end of the last item or comment.
		*/
		var previousEnd: Int

		/**
		The end of the last item.
		*/
		var itemEnd: Int?

		/**
		Whether a comment may stay at the end of the line before it, which needs an item or an opening bracket there.
		*/
		var canTrail: Bool

		var hasWritten = false

		/**
		Whether the next comment or item goes on the line of the comment before it.
		*/
		var isOnSameLine = false
	}

	/**
	Writes what comes before the item that starts at `itemStart`, or before the end of the list when `isBeforeItem` is false: the comments, and then the line break or space before the item.

	It is a separate function from `list(_:start:end:level:isBraced:)` so that its locals are not on the stack once per level of nesting.
	*/
	mutating func writeGap(before itemStart: Int, isBeforeItem: Bool, level: Int, isBraced: Bool, position: inout ListPosition) {
		let comma = isBraced ? comma(from: position.previousEnd, to: itemStart) : nil

		while let comment = peekComment(before: itemStart) {
			let staysOnLine = position.canTrail
				&& !position.isOnSameLine
				&& isTrailing(comment, previousEnd: position.previousEnd, itemEnd: position.itemEnd, itemStart: isBeforeItem ? itemStart : nil, comma: comma)

			if staysOnLine || position.isOnSameLine {
				output.append(.space)
			} else {
				newLine(level: level, isBlank: position.hasWritten && hasBlankLine(position.previousEnd, comment.range.lowerBound))
			}

			write(comment)
			position.hasWritten = position.hasWritten || !staysOnLine

			// A block comment that the next comment or item follows on the same line keeps it on that line.
			let nextStart = peekComment(before: itemStart)?.range.lowerBound ?? itemStart
			position.isOnSameLine = comment.isBlock
				&& !staysOnLine
				&& (isBeforeItem || nextStart < itemStart)
				&& tree.isSameLine(comment.range.upperBound, nextStart)
			position.previousEnd = comment.range.upperBound
		}

		guard isBeforeItem else {
			return
		}

		if position.isOnSameLine {
			output.append(.space)
		} else {
			newLine(level: level, isBlank: position.hasWritten && hasBlankLine(position.previousEnd, itemStart))
		}
	}

	/**
	Whether a comment stays at the end of the line before it. That line ends at the item before it, or at the comma after that item.
	*/
	func isTrailing(_ comment: SyntaxTree.Comment, previousEnd: Int, itemEnd: Int?, itemStart: Int?, comma: Int?) -> Bool {
		let isAfterComma = comma.map { comment.range.lowerBound > $0 } ?? false

		// A block comment after the comma that the next item follows on the same line stays in front of that item.
		if
			let itemStart,
			comment.isBlock,
			comma == nil || isAfterComma,
			tree.isSameLine(comment.range.upperBound, itemStart)
		{
			return false
		}

		// A comment after the comma ends the comma's line, which is later than the item's when a block comment that spans lines comes between them. The comma goes after the item, so that only holds when nothing came between them.
		let lineEnd = if isAfterComma, previousEnd == itemEnd, let comma {
			comma + 1
		} else {
			previousEnd
		}

		return tree.isSameLine(lineEnd, comment.range.lowerBound)
	}

	mutating func write(_ member: SyntaxTree.Member, level: Int) {
		output.append(contentsOf: text[member.keyRange])
		output.append(.colon)

		guard peekComment(before: member.value.range.lowerBound) != nil else {
			// A block string begins on the next line, one level deeper, so its delimiters and content line up.
			if case .blockString = member.value.kind {
				newLine(level: level + 1, isBlank: false)
				write(member.value, level: level + 1)
				return
			}

			output.append(.space)
			write(member.value, level: level)
			return
		}

		write(member.value, level: writeCommentsAfterColon(of: member, level: level))
	}

	/**
	Writes the comments between the `:` of a member and its value, and returns the level of the value. It is a separate function from `write(_:level:)` so that its locals are not on the stack once per level of nesting.
	*/
	mutating func writeCommentsAfterColon(of member: SyntaxTree.Member, level: Int) -> Int {
		let valueStart = member.value.range.lowerBound

		// With comments between the `:` and the value, the line breaks between them are kept, and a value on a new line is one level deeper.
		var previousEnd = member.keyRange.upperBound + 1
		var valueLevel = level

		while let comment = peekComment(before: valueStart) {
			if !tree.isSameLine(previousEnd, comment.range.lowerBound) {
				valueLevel = level + 1
			}

			writeSeparator(previousEnd, comment.range.lowerBound, level: level + 1)
			write(comment)
			previousEnd = comment.range.upperBound
		}

		// A block string begins on its own line, as without comments.
		if case .blockString = member.value.kind {
			newLine(level: level + 1, isBlank: false)
			return level + 1
		}

		if !tree.isSameLine(previousEnd, valueStart) {
			valueLevel = level + 1
		}

		writeSeparator(previousEnd, valueStart, level: level + 1)
		return valueLevel
	}

	/**
	A space when `end` is on the line of `start` in the source, and otherwise a new line at `level`.
	*/
	mutating func writeSeparator(_ start: Int, _ end: Int, level: Int) {
		if tree.isSameLine(start, end) {
			output.append(.space)
		} else {
			newLine(level: level, isBlank: false)
		}
	}

	mutating func write(_ node: SyntaxTree.Node, level: Int) {
		switch node.kind {
		case .blockString, .scalar:
			writeScalar(node, level: level)
			return
		case .object, .array:
			break
		}

		let items = Item.items(in: node)

		// A braced object or an array starts and ends with its brackets in the source.
		output.append(text[node.range.lowerBound])

		if
			items.isEmpty,
			peekComment(before: node.range.upperBound) == nil
		{
			output.append(text[node.range.upperBound - 1])
			return
		}

		if
			!expandingContainers,
			tree.isSameLine(node.range.lowerBound, node.range.upperBound)
		{
			writeOneLine(items, start: node.range.lowerBound + 1, end: node.range.upperBound - 1, level: level)
		} else {
			list(items, start: node.range.lowerBound + 1, end: node.range.upperBound - 1, level: level + 1, isBraced: true)
			newLine(level: level, isBlank: false)
		}

		output.append(text[node.range.upperBound - 1])
	}

	/**
	Writes the members or items of a container that is on one line in the source on one line, from `start` to `end` in the source, with a comma and a space between them and no trailing comma. Only a block comment can be inside it, and each one stays where it is among the items and commas.
	*/
	mutating func writeOneLine(_ items: [Item], start: Int, end: Int, level: Int) {
		var previousEnd = start
		var hasWrittenToken = false

		for index in 0...items.count {
			let item = index < items.count ? items[index] : nil
			let itemStart = item?.range.lowerBound ?? end

			// The comma after the last item is left out.
			var comma = item == nil ? nil : comma(from: previousEnd, to: itemStart)

			while let comment = peekComment(before: itemStart) {
				if
					let commaOffset = comma,
					commaOffset < comment.range.lowerBound
				{
					output.append(.comma)
					comma = nil
				}

				if hasWrittenToken {
					output.append(.space)
				}

				write(comment)
				hasWrittenToken = true
			}

			guard let item else {
				return
			}

			if comma != nil {
				output += [.comma, .space]
			} else if hasWrittenToken {
				output.append(.space)
			}

			switch item {
			case .member(let member):
				write(member, level: level)
			case .value(let node):
				write(node, level: level)
			}

			previousEnd = item.range.upperBound
			hasWrittenToken = true
		}
	}

	/**
	Writes a value that is not an object or an array.
	*/
	mutating func writeScalar(_ node: SyntaxTree.Node, level: Int) {
		guard case .blockString = node.kind else {
			output += text[node.range]
			return
		}

		output += text[node.range].reindentingBlockString(with: repeatElement(.tab, count: level))
	}
}

extension ArraySlice<UInt8> {
	/**
	Whether the text begins with a block string. Only a block string starts with three quotes, because `''` followed by a quote is not a value.
	*/
	var startsBlockString: Bool {
		// Fixed three-byte starts(with:) literals outperformed prefix/allSatisfy and StaticString wrappers for block delimiters in Swift 6.4 probes.
		starts(with: [.singleQuote, .singleQuote, .singleQuote]) || starts(with: [.doubleQuote, .doubleQuote, .doubleQuote])
	}

	/**
	The block string moved to `indentation`, for its content lines and its closing delimiter. Its content is relative to the closing delimiter's indentation, so replacing that indentation on every line keeps the value. A blank line is left as it is, because it becomes an empty line either way.
	*/
	func reindentingBlockString(with indentation: some Collection<UInt8>) -> [UInt8] {
		let lines = split(separator: .lineFeed, omittingEmptySubsequences: false)
		let oldIndentationLength = lines.last?.prefix(while: \.isSpaceOrTab).count ?? 0
		let contentLineCount = lines.dropFirst().count(where: { !$0.allSatisfy(\.isSpaceOrTab) })
		let capacity = count + contentLineCount * (indentation.count - oldIndentationLength)

		// A lazy map/joined pipeline allocates each transformed line and measured slower; one OutputSpan also avoids repeated array-capacity checks. Count only nonblank content lines when sizing it.
		return [UInt8](capacity: capacity) { output in
			for (index, line) in lines.enumerated() {
				if index > 0 {
					output.append(.lineFeed)
				}

				if index == 0 || line.allSatisfy(\.isSpaceOrTab) {
					output.append(contentsOf: line)
				} else {
					output.append(contentsOf: indentation)
					output.append(contentsOf: line.dropFirst(oldIndentationLength))
				}
			}
		}
	}

	/**
	The text without its trailing spaces and tabs. Only those are whitespace in SOML, so any other character, such as a no-break space, is content.
	*/
	var withoutTrailingWhitespace: Self {
		// Counting a reversed whitespace prefix and passing it to dropLast measured slower on long suffixes; lastIndex finds the same boundary in one backward scan.
		self[..<((lastIndex { !$0.isSpaceOrTab }).map { $0 + 1 } ?? startIndex)]
	}
}

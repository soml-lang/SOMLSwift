extension SOML {
	/**
	A place in a text: a line and a column, which people read, and the byte offset, which code uses.

	```swift
	do {
		_ = try SOML.Value(parsing: "a: 1\na: 2")
	} catch {
		error.location
		//=> line 2, column 1
	}
	```
	*/
	public struct Location: Sendable, Hashable, Comparable, CustomStringConvertible {
		/**
		The line, starting at 1.
		*/
		public let line: Int

		/**
		The column, starting at 1 and counted in Unicode scalars, so an emoji is one column.
		*/
		public let column: Int

		/**
		The offset in the UTF-8 bytes of the text, starting at 0.
		*/
		public let offset: Int

		/**
		The location of a byte offset in UTF-8 text. An offset past the end is the end.
		*/
		init(offset: Int, in bytes: [UInt8]) {
			let offset = max(0, min(offset, bytes.count))
			var line = 1
			var lineStart = 0

			for index in 0..<offset where bytes[index] == .lineFeed {
				line += 1
				lineStart = index + 1
			}

			self.init(offset: offset, line: line, lineStart: lineStart, in: bytes)
		}

		/**
		The location of a byte offset whose line and line start are known.
		*/
		init(offset: Int, line: Int, lineStart: Int, in bytes: [UInt8]) {
			self.line = line
			// Count scalars, which are the bytes that are not UTF-8 continuation bytes.
			self.column = bytes[lineStart..<offset].count(where: { !$0.isUTF8ContinuationByte }) + 1
			self.offset = offset
		}

		/**
		The location as people read it, like `line 2, column 1`.
		*/
		public var description: String {
			"line \(line), column \(column)"
		}

		public static func < (lhs: Self, rhs: Self) -> Bool {
			// In one text, the offset decides the order. The line and column only break ties between locations in different texts, so that the order agrees with `==`, as `Comparable` requires.
			(lhs.offset, lhs.line, lhs.column) < (rhs.offset, rhs.line, rhs.column)
		}
	}
}

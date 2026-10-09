extension SOML {
	/**
	A path to a value through nested objects and arrays, written as keys joined with `.`, each written as a SOML key, with array indices in brackets, like `server.port`, `server.'the name'`, or `servers[0].host`.

	This is the syntax of a path, not of a document, where a key is never a path. A key that contains a `.` is quoted, so `'example.com'.port` is the key `port` in the object `example.com`. The keys are decoded, so `'the name'` is the key `the name`. Keys are compared by their Unicode scalars, as SOML compares keys. An index is always in brackets, so `servers.0` is the key `0` of the object `servers`, and `servers[0]` is the first item of the array `servers`.

	```swift
	let path = try SOML.KeyPath(parsing: "servers[0].'the name'")

	path.segments
	//=> [.key("servers"), .index(0), .key("the name")]

	SOML.KeyPath(["server", "port"]).description
	//=> "server.port"
	```
	*/
	public struct KeyPath: Sendable, Hashable, CustomStringConvertible, ExpressibleByArrayLiteral {
		/**
		One step of a key path: a key of an object, or the index of an item in an array.

		A string literal is a key and an integer literal is an index, so a path can be written as `SOML.KeyPath(["servers", 0, "host"])`.
		*/
		public enum Segment: Sendable, Hashable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
			/**
			A key of an object.
			*/
			case key(String)

			/**
			The index of an item in an array, from 0.
			*/
			case index(Int)

			/**
			A key, from a string literal.
			*/
			public init(stringLiteral key: String) {
				self = .key(key)
			}

			/**
			An index, from an integer literal.
			*/
			public init(integerLiteral index: Int) {
				self = .index(index)
			}

			/**
			Whether two segments are the same key, compared by Unicode scalars, or the same index.
			*/
			public static func == (lhs: Self, rhs: Self) -> Bool {
				switch (lhs, rhs) {
				case (.key(let lhsKey), .key(let rhsKey)):
					lhsKey.hasSameScalars(as: rhsKey)
				case (.index(let lhsIndex), .index(let rhsIndex)):
					lhsIndex == rhsIndex
				default:
					false
				}
			}

			/**
			Hashes a key by its Unicode scalars, as `==` compares it.
			*/
			public func hash(into hasher: inout Hasher) {
				switch self {
				case .key(let key):
					hasher.combine(0)
					hasher.combine(ExactKey(key))
				case .index(let index):
					hasher.combine(1)
					hasher.combine(index)
				}
			}
		}

		/**
		The keys and indices, from the outermost value inward. There is at least one.
		*/
		public let segments: [Segment]

		/**
		Creates a key path of keys and indices.

		- Precondition: `segments` is not empty, and no index is negative.
		*/
		public init(_ segments: [Segment]) {
			precondition(!segments.isEmpty, "A key path needs at least one key or index.")

			precondition(
				!segments.contains {
					guard case .index(let index) = $0 else {
						return false
					}

					return index < 0
				},
				"An index in a key path is 0 or more."
			)

			self.segments = segments
		}

		/**
		Creates a key path from an array literal of keys and indices, so an API that takes a key path takes a literal: `document.setting(8080, at: ["servers", 0, "port"])`.

		The compiler checks the literal, unlike a string that `init(parsing:)` reads at run time.

		- Precondition: The literal is not empty, and no index is negative.
		*/
		public init(arrayLiteral segments: Segment...) {
			self.init(segments)
		}

		/**
		Creates a key path of keys only.

		- Precondition: `keys` is not empty.
		*/
		public init(_ keys: [String]) {
			self.init(keys.map(Segment.key))
		}

		/**
		Parses a key path of keys joined with `.`, each written as a SOML key, where an array index can follow any key in brackets, like `servers[0].host`. A path can also start with an index, like `[0].name`, for a document that is an array.

		Each key is read exactly as SOML reads a key, so a key that contains a `.`, like `'example.com'`, must be quoted.

		- Throws: `SOML.ParseError` if the text is not a key path, with a position in the text.
		*/
		public init(parsing text: String) throws(SOML.ParseError) {
			let bytes = Array(text.utf8)
			var segments = [Segment]()
			var position = 0

			repeat {
				if
					position < bytes.count,
					bytes[position] == .openBracket
				{
					segments.append(.index(try Self.index(in: bytes, at: &position)))

					guard position < bytes.count else {
						break
					}

					switch bytes[position] {
					case .openBracket:
						continue
					case .dot:
						position += 1
					default:
						throw SOML.ParseError(message: "Expected “.”, “[”, or the end of the key path after an index", offset: position, in: bytes)
					}
				}

				// A key runs to the first `[` that is outside its quotes. When it is empty, the parser reads from the `[`, so its error names what it found.
				let end = Self.keyEnd(in: bytes, from: position)

				do throws(SOML.ParseError) {
					segments.append(contentsOf: try Parser.parseKeyPath(Array(end > position ? bytes[position..<end] : bytes[position...])).lazy.map(Segment.key))
				} catch {
					throw SOML.ParseError(message: error.message, offset: position + error.location.offset, in: bytes)
				}

				position = end
			} while position < bytes.count

			self.segments = segments
		}

		/**
		The key path with each key as SOML writes it in canonical form, bare when it can be, and quoted otherwise, joined with `.`, and each index in brackets, like `servers[0].'the name'`. A key that contains a `.` is quoted, like `'example.com'.port`, so the description parses back to the same path.

		A path of one key is the canonical spelling of that key, like `port` or `'the name'`.
		*/
		public var description: String {
			var text = [UInt8]()

			for segment in segments {
				switch segment {
				case .key(let key):
					if !text.isEmpty {
						text.append(.dot)
					}

					CanonicalWriter.appendKey(key, to: &text)
				case .index(let index):
					text.append(.openBracket)
					text.appendDecimal(UInt64(index))
					text.append(.closeBracket)
				}
			}

			return String(decoding: text, as: UTF8.self)
		}

		/**
		Reads `[digits]` at `position`, and moves past it.
		*/
		private static func index(in bytes: [UInt8], at position: inout Int) throws(SOML.ParseError) -> Int {
			// Int(String(decoding: ...)) measured 2–4 times slower for short indices; checked byte arithmetic also detects overflow before scanning an arbitrarily long digit run.
			let start = position + 1
			var end = start
			var index = 0

			while
				end < bytes.count,
				bytes[end].isASCIIDigit
			{
				let (product, isProductOverflow) = index.multipliedReportingOverflow(by: 10)
				let (sum, isSumOverflow) = product.addingReportingOverflow(Int(bytes[end] - .digitZero))

				guard
					!isProductOverflow,
					!isSumOverflow
				else {
					throw SOML.ParseError(message: "The array index is too large", offset: start, in: bytes)
				}

				index = sum
				end += 1
			}

			guard end > start else {
				throw SOML.ParseError(message: "Expected an array index after “[”, as in [0]", offset: start, in: bytes)
			}

			guard bytes[start] != .digitZero || end == start + 1 else {
				throw SOML.ParseError(message: "An array index cannot start with 0, as in [01]. Write it as [1]", offset: start, in: bytes)
			}

			guard
				end < bytes.count,
				bytes[end] == .closeBracket
			else {
				throw SOML.ParseError(message: "Expected “]” after the array index", offset: end, in: bytes)
			}

			position = end + 1
			return index
		}

		/**
		The offset of the first `[` from `start` that is outside a quoted key, or the end of the text. A quoted key ends as in SOML: `'...'` at the next `'`, and `"..."` at the next `"` that a `\` does not escape.
		*/
		private static func keyEnd(in bytes: [UInt8], from start: Int) -> Int {
			var position = start
			var quote: UInt8?

			while position < bytes.count {
				let byte = bytes[position]

				if let currentQuote = quote {
					if
						currentQuote == .doubleQuote,
						byte == .backslash
					{
						position += 1
					} else if byte == currentQuote {
						quote = nil
					}
				} else if
					byte == .singleQuote
						|| byte == .doubleQuote
				{
					quote = byte
				} else if byte == .openBracket {
					return position
				}

				position += 1
			}

			return bytes.count
		}
	}
}

/**
Collection operations and composition of nonempty key paths.
*/
extension SOML.KeyPath: RandomAccessCollection {
	/**
	The position of the first segment.
	*/
	public var startIndex: Int {
		segments.startIndex
	}

	/**
	The position after the last segment.
	*/
	public var endIndex: Int {
		segments.endIndex
	}

	/**
	The segment at a valid collection position.
	*/
	public subscript(position: Int) -> Segment {
		segments[position]
	}
}

/**
Composition and ancestry of nonempty paths.
*/
extension SOML.KeyPath {
	/**
	The enclosing path, or `nil` for a path with only one segment, whose parent is the document itself.
	*/
	public var parent: Self? {
		guard segments.count > 1 else {
			return nil
		}

		return Self(Array(segments.dropLast()))
	}

	/**
	Appends one key or array index. As with the initializer, an index must be nonnegative.
	*/
	public func appending(_ segment: Segment) -> Self {
		var segments = segments
		segments.append(segment)
		return Self(segments)
	}

	/**
	Appends another path, preserving scalar-distinct keys.
	*/
	public func appending(_ path: Self) -> Self {
		Self(segments + path.segments)
	}

	/**
	Whether this path starts with all segments of `prefix`, comparing keys by Unicode scalars.
	*/
	public func hasPrefix(_ prefix: Self) -> Bool {
		segments.starts(with: prefix.segments)
	}
}

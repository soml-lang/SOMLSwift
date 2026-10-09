extension SOML.Document {
	/**
	The line and column of the member or array item at a coding path, like the `codingPath` of a `DecodingError` from `SOML.Decoder`, to show where a value that does not decode is written.

	The location of a member is the start of its key, and the location of an item is the start of the item. Both start at 1, and the column is counted in Unicode scalars, as in `SOML.ParseError`. When the document has no member or item for the whole path, like for a missing key, it is the location of the deepest one that it has, or the start of the document's collection.

	Pass the decoder's key strategy, so that a coding key like `maxConnections` finds the member `max-connections`, as the decoder found it. A key that the decoder took from the document as it is, like the key of a `[String: T]` or an unknown key, is not converted.

	```swift
	let document = try SOML.Document(parsing: "name: 'api'\nports: [80, 'eighty']")

	do {
		_ = try SOML.Decoder().decode(Config.self, from: document.value)
	} catch let DecodingError.typeMismatch(_, context) {
		document.location(of: context.codingPath)
		//=> line 2, column 13
	}
	```
	*/
	public func location(of codingPath: [any CodingKey], keyDecodingStrategy: SOML.Decoder.KeyDecodingStrategy = .useDefaultKeys) -> SOML.Location {
		let separator = keyDecodingStrategy.separator

		return location(
			of: codingPath,
			key: { $0.documentKey(separator: separator) },
			index: \.intValue
		)
	}

	/**
	The line and column of the member or array item at a key path, as `location(of:keyDecodingStrategy:)` finds it for a coding path. A key finds a member, and an index finds an array item.

	```swift
	let document = try SOML.Document(parsing: "name: 'api'\nports: [80, 443]")

	document.location(of: ["ports", 1])
	//=> line 2, column 13
	```
	*/
	public func location(of path: SOML.KeyPath) -> SOML.Location {
		location(
			of: path.segments,
			key: { segment in
				guard case .key(let key) = segment else {
					return nil
				}

				return key
			},
			index: { segment in
				guard case .index(let index) = segment else {
					return nil
				}

				return index
			}
		)
	}

	/**
	An error at the member or array item at a key path, for a check that an app makes after it reads the document, so that the problem is shown as a parse error is, with its line, column, and code frame.

	The location is the one that `location(of:)` gives, so when nothing is at the path, it is the deepest member or item on the way.

	```swift
	let document = try SOML.Document(parsing: "server: {\n\thost: 'a'\n\tport: 0\n}")

	print(document.error("Port 0 is reserved", at: ["server", "port"]))
	//=> Port 0 is reserved (line 3, column 2)
	```
	*/
	public func error(_ message: String, at path: SOML.KeyPath) -> SOML.ParseError {
		SOML.ParseError(message: message, offset: location(of: path).offset, in: tree.text)
	}

	/**
	The shared part of the `location(of:)` functions. `key` gives the document's spelling of a path element that can name a member, and `index` gives the index of one that can name an array item.
	*/
	private func location<Path: Collection>(of path: Path, key: (Path.Element) -> String?, index: (Path.Element) -> Int?) -> SOML.Location {
		var node = tree.body
		var offset = node.range.lowerBound
		var value = self.value

		find: for element in path {
			switch (node.kind, value) {
			case (.object(let members, _), .object(let object)):
				guard
					let elementKey = key(element),
					let memberIndex = object.index(forKey: elementKey)
				else {
					break find
				}

				let member = members[memberIndex]
				value = object[memberIndex].value
				offset = member.keyRange.lowerBound
				node = member.value
			case (.array(let items), .array(let values)):
				guard
					let index = index(element),
					items.indices.contains(index)
				else {
					break find
				}

				node = items[index]
				value = values[index]
				offset = node.range.lowerBound
			default:
				break find
			}
		}

		return tree.location(at: offset)
	}
}

extension SOML.Document {
	/**
	Where the member or array item at a key path is written: for a member, from the start of its key to the end of its value, and for an item, the item. It is `nil` when nothing is at the path.

	An editor can use it to select a setting or to show where it is.

	```swift
	let document = try SOML.Document(parsing: "name: 'api'\nports: [80, 443]")

	document.range(of: ["ports"])
	//=> line 2, column 1..<line 2, column 17
	```

	The end is the location after the last character of the value, so a comment or a comma after it is not in the range.
	*/
	public func range(of path: SOML.KeyPath) -> Range<SOML.Location>? {
		node(at: path).map { location(of: $0.range) }
	}

	/**
	Where the value at a key path is written, without the key of a member. It is `nil` when nothing is at the path.

	It is the text that a person wrote for the value, so a tool can show it as written, like `0x1F90` for the int 8080. A block string runs from its opening delimiter to its closing one, and an object or an array from its opening bracket to its closing one.

	```swift
	let document = try SOML.Document(parsing: "port: 0x1F90 # The default")

	document.valueRange(of: ["port"])
	//=> line 1, column 7..<line 1, column 13
	```
	*/
	public func valueRange(of path: SOML.KeyPath) -> Range<SOML.Location>? {
		node(at: path).map { location(of: $0.value.range) }
	}

	/**
	The source text of the value at a key path, without the key, surrounding whitespace, or trailing comments. It is `nil` when nothing is at the path.

	The spelling is preserved, including quotes, escapes, and the layout of containers and block strings. Only the requested value's bytes are decoded, so looking up many values does not repeatedly copy the document's text.

	```swift
	let document = try SOML.Document(parsing: "port: 0x1F90 # The default")

	document.valueText(at: ["port"])
	//=> "0x1F90"
	```
	*/
	public func valueText(at path: SOML.KeyPath) -> String? {
		node(at: path).map { String(decoding: tree.text[$0.value.range], as: UTF8.self) }
	}

	/**
	The key path of the deepest member or array item whose range holds a byte offset in the text, like for the caret in an editor. It is `nil` when no member or item holds it, like in a comment or white space outside the members or items of the document.

	The range of a member or an item is the one that `range(of:)` gives, and an offset at its end belongs to it, so a caret directly after a value is on that value. An offset in a comment or white space inside an object or an array gives the member or item that holds that object or array.

	```swift
	let document = try SOML.Document(parsing: "server: {host: 'a', port: 80}")

	document.path(atOffset: 27)
	//=> server.port
	```

	It takes logarithmic time in the number of members and items on the way.
	*/
	public func path(atOffset offset: Int) -> SOML.KeyPath? {
		var node = tree.body
		var segments = [SOML.KeyPath.Segment]()

		find: while true {
			switch node.kind {
			case .object(let members, _):
				let index = members.partitioningIndex { $0.range.upperBound >= offset }

				guard
					index < members.endIndex,
					members[index].range.lowerBound <= offset
				else {
					break find
				}

				segments.append(.key(members[index].key))
				node = members[index].value
			case .array(let items):
				let index = items.partitioningIndex { $0.range.upperBound >= offset }

				guard
					index < items.endIndex,
					items[index].range.lowerBound <= offset
				else {
					break find
				}

				segments.append(.index(index))
				node = items[index]
			case .blockString, .scalar:
				break find
			}
		}

		return segments.isEmpty ? nil : SOML.KeyPath(segments)
	}

	/**
	The member or item at a key path: the bytes of the member or the item, and its value.
	*/
	private func node(at path: SOML.KeyPath) -> (range: Range<Int>, value: SyntaxTree.Node)? {
		var node = tree.body
		var range = node.range
		var value = self.value

		// The value and syntax tree have the same source order. Reuse the object's key index instead of scanning its members for every lookup.
		for segment in path.segments {
			switch (node.kind, value, segment) {
			case (.object(let members, _), .object(let object), .key(let key)):
				guard let index = object.index(forKey: key) else {
					return nil
				}

				let member = members[index]
				range = member.range
				node = member.value
				value = object[index].value
			case (.array(let items), .array(let values), .index(let index)):
				guard items.indices.contains(index) else {
					return nil
				}

				node = items[index]
				range = node.range
				value = values[index]
			default:
				return nil
			}
		}

		return (range, node)
	}

	private func location(of range: Range<Int>) -> Range<SOML.Location> {
		tree.location(at: range.lowerBound)..<tree.location(at: range.upperBound)
	}
}

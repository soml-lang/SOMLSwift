extension SOML {
	/**
	An error thrown when `SOML.Document` cannot make a change, like setting a member inside a value that is not an object, or renaming a member that does not exist.
	*/
	public struct EditError: Error, Sendable, Hashable, CustomStringConvertible {
		/**
		What is wrong, in plain sentences.
		*/
		public let message: String

		/**
		An error with a message. Characters that a terminal acts on rather than shows are replaced, as in `SOML.ParseError`.
		*/
		init(message: String) {
			self.message = message.sanitizedForTerminal
		}

		/**
		The message.
		*/
		public var description: String {
			message
		}
	}
}

extension SOML.Document {
	/**
	The document's source text, so that an edited document can be written out.
	*/
	public var text: String {
		String(decoding: tree.text, as: UTF8.self)
	}

	/**
	A copy changed through a `Codable` model of the document, with every other byte unchanged, so code can change a config file with the compiler checking the names and types.

	The document is decoded as `type`, `change` changes the model, and the difference between the model encoded before and after the change becomes edits with `setting(_:at:)` and `removing(at:)`, which keep the comments and the spelling of every value that did not change. Members the model does not read stay as they are.

	- A changed member or array item is replaced, and a new one is added.
	- A member that the model no longer encodes, like an optional set to `nil`, is removed.
	- An array that gets longer gets items appended, and one that gets shorter loses items from the end.
	- A member that the document leaves out, or writes as `null`, and the model gives a default, like with `decodeIfPresent(_:forKey:) ?? []`, is set whole when it changes, and stays as it is when it does not.

	```swift
	struct Config: Codable {
		var name: String
		var port: Int
	}

	let document = try SOML.Document(parsing: "name: 'api' # The service\nport: 80\n")

	let edited = try document.updating(as: Config.self) {
		$0.port = 8080
	}

	print(edited.text)
	//=> name: 'api' # The service
	//=> port: 8080
	```

	Pass the decoder and the encoder with the key strategies and options the document needs, like `.convertFromKebabCase` and `.convertToKebabCase`. Each edit reads the document back, so a change of many values costs one parse each.

	- Throws: A `DecodingError` when the document does not decode as `type`, an `EncodingError` when the model cannot be encoded, `SOML.EditError` when an edit cannot be made, and whatever `change` throws.
	*/
	public func updating<Model: Codable>(as type: Model.Type, decoder: SOML.Decoder = SOML.Decoder(), encoder: SOML.Encoder = SOML.Encoder(), _ change: (inout Model) throws -> Void) throws -> SOML.Document {
		var model = try decoder.decode(type, from: value)
		let before = try encoder.encodeToValue(model)
		try change(&model)
		let after = try encoder.encodeToValue(model)

		guard let differences = after.differences(from: before) else {
			throw SOML.EditError(message: "The model encodes the document as \(after.briefDescription), but the document is \(before.briefDescription), so it cannot be changed in place")
		}

		var document = self

		// Removals go last, so an object whose members are all replaced, like `{a: 1}` that becomes `{b: 2}`, is never empty in between, which would change its layout. A removed path has nothing else changed under it, and an array either grows or shrinks, so the order does not change the value.
		for isRemoval in [false, true] {
			for difference in differences where difference.isRemoval == isRemoval {
				let path = difference.path
				let current = document.value

				// A member or item that the document leaves out, or writes as a value that the path cannot go into, like null that `decodeIfPresent(_:forKey:)` reads as absent, is set whole, because what is inside it is not in the document to change one by one.
				let missingPath = current.firstMissingContainer(in: path)

				if let missingPath {
					if let value = after[path: missingPath] {
						document = try document.setting(value, at: missingPath)
					}

					continue
				}

				// Like a later item of an array that was set whole, or a removed member that the document leaves out.
				guard current[path: path] != after[path: path] else {
					continue
				}

				document = try document.applying(difference)
			}
		}

		return document
	}

	/**
	A copy with the value at `path` replaced or added, and every other byte unchanged.

	- An existing value is replaced in place, so the comments around it stay. This includes an array item, like `servers[0]`. The exception is a block string on the line after its key, as the formatter writes it: a new value that is not a block string goes on the key's line, as `key: value`.
	- A missing member is added after the last member of the deepest object that exists, and the objects that do not exist yet are written with braces, so setting `postgres.tls.enabled` in `postgres: {host: 'db'}` adds the member `tls: {enabled: true}` after `host`.
	- A new member or item goes on a line of its own without a comma, after the comments that the one before it owns (see `removing(at:)`), so before a comment on a line of its own that follows them, and the commas of the others stay as they are. When something follows the one before it on its line, like the closing brace of `{a: 1}`, it goes on that line after a comma, as in `{a: 1, b: 2}`. In an object or an array with no members or items, it goes on a line of its own, unless the container stays on one line: its brackets are on one line with a comment between them, as in `{/* note */}`, or it is inside a container on one line, so `a: [1, {}]` gets `a: [1, {b: 2}]`.
	- An index that is the number of items in an array, like `servers[2]` for an array of two items, adds an item at the end. When the path goes on with keys, like `servers[2].host`, the new item is an object with those keys.
	- The value is written in the spelling and layout of canonical form, as `SOML.Value.description` writes it, without block strings, so `0xFF` set to 255 becomes `255`. The members of an object keep their order. A multi-line value is indented to fit the line it goes on. In a container on one line, the value is written on one line too, so `[1, 2]` with a new item `{a: 3}` becomes `[1, 2, {a: 3}]`. Use `setting(valueText:at:)` to write the value as typed instead.

	The result is read back and compared with the same change made to `value`, so a bug here cannot return a wrong document.

	```swift
	let document = try SOML.Document(parsing: "port: 80 # The default\n")

	print(try document.setting(8080, at: SOML.KeyPath(["port"])).text)
	//=> port: 8080 # The default
	```

	- Throws: `SOML.EditError` when the path goes through a value that is not an object or an array, when it has a key where an array is or an index where an object is, when an index is past the end of its array, or under a value that does not exist, when the value cannot be written as SOML, like NaN or a string with a carriage return, and when the result is not a valid document, like one nested more than 100 levels deep.
	*/
	public func setting(_ value: SOML.Value, at path: SOML.KeyPath) throws(SOML.EditError) -> SOML.Document {
		try setting(value, at: path) { (indentation, isOneLine) throws(SOML.EditError) in
			do throws(SOML.InvalidValueError) {
				let text = try CanonicalWriter.value(value, isOneLine: isOneLine)
				return isOneLine ? text : text.indentingLines(with: indentation)
			} catch {
				throw SOML.EditError(message: "Cannot set \(path.segments[...].described), because the value cannot be written as SOML. \(error.description)")
			}
		}
	}

	/**
	A copy with the value at `path` replaced or added, written exactly as `valueText` spells it, like `0o644`, `1h30m`, or `['a', 'b']` on one line.

	It is for a tool that takes a value from a person, like a `set` command, and keeps their spelling. It follows the same rules as `setting(_:at:)`, except that the text is not changed, so a multi-line array or object is not indented to fit the line it goes on.

	A block string is the exception, and it is written as the formatter writes it. As the value of a member, it begins on the line after the key, or after a comment that comes between them, one level deeper than the key, and as an array item, it stays on the item's line. Its content and its closing delimiter get the indentation of the line where it begins, each content line keeps its indentation relative to the closing delimiter, and a blank line stays as it is, so the value does not change. So `a: 1` set to `'''\nx\n'''` becomes `a:\n\t'''\n\tx\n\t'''`.

	```swift
	let document = try SOML.Document(parsing: "mode: 420 # Permissions\n")

	print(try document.setting(valueText: "0o644", at: SOML.KeyPath(["mode"])).text)
	//=> mode: 0o644 # Permissions
	```

	- Throws: `SOML.EditError` when `valueText` is not one SOML value with nothing around it, with the parser's message, and in the cases of `setting(_:at:)`.
	*/
	public func setting(valueText: String, at path: SOML.KeyPath) throws(SOML.EditError) -> SOML.Document {
		let value: SOML.Value

		do throws(SOML.ParseError) {
			value = try SOML.Value(parsingValue: valueText)
		} catch {
			throw SOML.EditError(message: "Cannot set \(path.segments[...].described), because the value text is not one SOML value. \(error.message) (at \(error.location) of the value text)")
		}

		let bytes = Array(valueText.utf8)

		// A block string's content is relative to its closing delimiter, so it moves to the indentation it gets, as the formatter moves it.
		guard bytes[...].startsBlockString else {
			return try setting(value, at: path) { _, _ in bytes }
		}

		return try setting(value, at: path) { indentation, _ in bytes[...].reindentingBlockString(with: indentation) }
	}

	/**
	The shared part of the two `setting` functions, which differ only in how the value is written. `valueText` gets the indentation of the line where the value goes, and whether the value goes in a container that stays on one line.
	*/
	private func setting(_ value: SOML.Value, at path: SOML.KeyPath, valueText: (ArraySlice<UInt8>, _ isOneLine: Bool) throws(SOML.EditError) -> [UInt8]) throws(SOML.EditError) -> SOML.Document {
		// Each segment of a path is a level of nesting, so a longer path can only make a document that is nested too deeply. It is checked first, because the expected value is made by recursion.
		guard path.segments.count <= Parser.maximumDepth else {
			throw SOML.EditError(message: "Cannot set \(path.segments[...].described), because the path is nested more than \(Parser.maximumDepth) levels deep, which is the most a SOML reader accepts")
		}

		guard !path.segments.contains(where: \.hasCarriageReturn) else {
			throw SOML.EditError(message: "Cannot set \(path.segments[...].described), because a key cannot contain a carriage return, which SOML cannot represent")
		}

		var editor = Editor(tree: tree, value: self.value, path: path)
		try editor.set(valueText)
		return try editor.result(expecting: self.value.setting(value, at: path.segments[...]))
	}

	/**
	A copy without the member or array item at `path`, and every other byte unchanged as far as possible.

	- The member or item goes with the comments that it owns, which are the ones that the formatter keeps with it: the comments after it on its line, before its comma, or after its comma when nothing else follows on that line, and the block comments before it on its line, back to the comma or bracket before it. So removing `2` from `[1, /* note */ 2]` gives `[1]`. A comment on a line of its own belongs to no member or item, so it stays.
	- The member or item goes with its comma, which is the comma after it. When the removed members or items are the last ones in their container and have no comma after them, they take the comma directly before them instead, when only spaces, tabs, and the comments they own are between, so `[1, 2]` becomes `[1]`. Every other comma stays. When nothing else is on its lines, its lines go too.
	- A blank line that would be left next to another one, directly inside a bracket, or at the start or end of the document goes too, the one before when there is a choice.
	- Removing the last member of a braced object or the last item of an array leaves `{}` or `[]`, unless a comment is left inside, like one on a line of its own or one after the opening bracket on its line.
	- Removing the only member of a document without braces leaves `{}`, and keeps the comments that the removed member owned, so `a: 1 # note` without `a` gives `{} # note`.

	Removing a value that does not exist changes nothing and is not an error: a missing member, a missing object or array on the way, or an index at or past the end of its array. So removing the same path twice is safe, and `document.removing(at: path).text == document.text` tells that nothing was removed.

	```swift
	let document = try SOML.Document(parsing: "port: 80\n")
	let edited = try document.removing(at: SOML.KeyPath(["host"]))

	print(edited.text == document.text)
	//=> true
	```

	The result is read back and compared with the same change made to `value`, so a bug here cannot return a wrong document.

	- Throws: `SOML.EditError` when the path goes through a value that is not an object or an array, and when it has a key where an array is or an index where an object is.
	*/
	public func removing(at path: SOML.KeyPath) throws(SOML.EditError) -> SOML.Document {
		var editor = Editor(tree: tree, value: self.value, path: path)
		try editor.remove()

		guard !editor.replacements.isEmpty else {
			return self
		}

		return try editor.result(expecting: value.removing(at: path.segments[...]))
	}

	/**
	A copy with the member at `path` under a new key, and its value, its comments, and every other byte unchanged.

	Only the last key of the path changes, and it is written in canonical form, like `'the name'`. Renaming a key to itself writes it in canonical form.

	```swift
	let document = try SOML.Document(parsing: "server: {host: 'a'} # Primary\n")

	print(try document.renamingKey(at: SOML.KeyPath(["server", "host"]), to: "hostname").text)
	//=> server: {hostname: 'a'} # Primary
	```

	- Throws: `SOML.EditError` when nothing is at the path, like a member that does not exist or an index at or past the end of its array, when the path names an array item, which has no key, when a member with the new key already exists, when the new key has a carriage return, which SOML cannot represent, and in the cases of `removing(at:)`.
	*/
	public func renamingKey(at path: SOML.KeyPath, to newKey: String) throws(SOML.EditError) -> SOML.Document {
		let newPath = SOML.KeyPath(path.segments.dropLast() + [.key(newKey)])

		guard !newKey.hasCarriageReturn else {
			throw SOML.EditError(message: "Cannot rename \(path.segments[...].described) to \(newPath.segments.suffix(1).described), because a key cannot contain a carriage return, which SOML cannot represent")
		}

		var editor = Editor(tree: tree, value: self.value, path: path)
		try editor.renameKey(to: Array(CanonicalWriter.key(newKey).utf8))

		// The path exists, so its last segment is a key of an object.
		if
			case .key(let oldKey) = path.segments.last,
			!oldKey.hasSameScalars(as: newKey),
			value.value(at: newPath.segments[...]) != nil
		{
			throw SOML.EditError(message: "Cannot rename \(path.segments[...].described) to \(newPath.segments.suffix(1).described), because \(newPath.segments[...].described) already exists")
		}

		return try editor.result(expecting: value.renamingKey(at: path.segments[...], to: newKey))
	}

	/**
	A copy with the `#` comment at the end of the line where the member or array item at `path` ends set to `comment`, or removed when it is `nil`, and every other byte unchanged.

	- The comment goes after the comma of the member or item, if it has one on that line, with one space before it, as `# ` followed by `comment`.
	- An existing `#` comment at the end of that line is replaced. A `/* */` comment there stays.
	- Removing a comment that is not there changes nothing, also when nothing is at the path, as with `removing(at:)`. It still throws when something other than a comment follows the member or item on its line, like the closing brace of `{a: 1}`.
	- For a member whose value spans lines, like an object in braces, the line is the one with its closing brace.

	It does not change the comment lines above a member.

	```swift
	let document = try SOML.Document(parsing: "port: 8080 # The default\n")

	print(try document.settingComment("Set by the deploy script", at: SOML.KeyPath(["port"])).text)
	//=> port: 8080 # Set by the deploy script
	```

	- Throws: `SOML.EditError` when `comment` contains a line break, when something other than a comment follows the member or item on its line, like the next member in `{a: 1, b: 2}`, when a comment is set and nothing is at the path, and in the cases of `removing(at:)`.
	*/
	public func settingComment(_ comment: String?, at path: SOML.KeyPath) throws(SOML.EditError) -> SOML.Document {
		let verb = comment == nil ? "remove the comment of" : "set the comment of"

		guard comment?.utf8.contains(where: { $0 == .lineFeed || $0 == .carriageReturn }) != true else {
			throw SOML.EditError(message: "Cannot \(verb) \(path.segments[...].described), because a comment cannot contain a line break")
		}

		var editor = Editor(tree: tree, value: self.value, path: path)
		try editor.setComment(comment.map { Array($0.utf8) }, verb: verb)

		guard !editor.replacements.isEmpty else {
			return self
		}

		return try editor.result(expecting: value)
	}

	/**
	The comments of the member or array item at `path`, like for a settings screen that shows the comments in a config file as help text.

	- `leading`: The comments directly above it, in order. These are the comments on the lines above it, up to a blank line or a line with something other than comments, and a `/* */` comment in front of it on its line. A comment after the member or item before it on its line, or after an opening bracket on its line, is not one of them, like `/* a */` in `[1, /* a */ 2]`.
	- `trailing`: The `#` comment at the end of the line where it ends, after its comma, which is the comment that `settingComment(_:at:)` changes. For a member whose value spans lines, like an object in braces, the line is the one with its closing brace.

	The text of a comment is without its `#` or `/* */`, and without one space after the `#` or `/*` and one space before the `*/`. A `/* */` comment that spans lines keeps its line breaks.

	```swift
	let document = try SOML.Document(parsing: "# The port to listen on.\n# Ports below 1024 need root.\nport: 8080 # The default\n")

	let comments = document.comments(at: ["port"])

	comments?.leading
	//=> ["The port to listen on.", "Ports below 1024 need root."]

	comments?.trailing
	//=> "The default"
	```

	A comment between a key and its value, as in `port: # The port` followed by the value on the next line, is in neither.

	It is `nil` when nothing is at the path.
	*/
	public func comments(at path: SOML.KeyPath) -> Comments? {
		let editor = Editor(tree: tree, value: self.value, path: path)
		let verb = "read the comments of"

		guard
			let target = try? editor.target(verb: verb),
			let range = editor.existingNode(in: target)
		else {
			return nil
		}

		return Comments(
			leading: tree.comments(before: range.lowerBound).map { $0.text(in: tree.text) },
			trailing: editor.lineComment(after: range, in: target.container).comment?.text(in: tree.text)
		)
	}

	/**
	The comments of a member or an array item, from `comments(at:)`.
	*/
	public struct Comments: Sendable, Hashable {
		/**
		The comments directly above the member or item, in order.
		*/
		public var leading: [String]

		/**
		The `#` comment at the end of the line where the member or item ends.
		*/
		public var trailing: String?

		/**
		Creates the comments of a member or an item.
		*/
		public init(leading: [String] = [], trailing: String? = nil) {
			self.leading = leading
			self.trailing = trailing
		}
	}
}

/**
Makes a change to a document's text as replacements of byte ranges, which leave every other byte as it is.

It follows the spec's "Editing" section, as a port of `edit()` in the JS reference implementation. It walks the path in a loop rather than by recursion, so any nesting the parser accepts fits on a small stack.
*/
private struct Editor {
	/**
	A replacement of the bytes in a range. An insertion has an empty range.
	*/
	struct Replacement {
		let range: Range<Int>
		let text: [UInt8]
	}

	/**
	A range of the text to remove.
	*/
	struct Removal {
		var start: Int
		var end: Int

		/**
		Whether it takes whole lines, which may leave a blank line next to another one.
		*/
		var isWholeLines: Bool
	}

	/**
	An object or an array, whose members or items a change adds or removes.
	*/
	struct Container {
		let node: SyntaxTree.Node

		/**
		`false` only for a top-level object written without braces.
		*/
		let isBraced: Bool

		/**
		The number of members or items.
		*/
		let count: Int

		/**
		The range of the last member or item, or `nil` when there is none.
		*/
		var lastItemRange: Range<Int>? {
			switch node.kind {
			case .object(let members, _):
				members.last?.range
			case .array(let items):
				items.last?.range
			case .blockString, .scalar:
				nil
			}
		}
	}

	/**
	Where the path ends, in the container that holds its last step.
	*/
	enum Place {
		/**
		In an object: the member with the key that starts `remaining`, or `nil` when there is none. More segments follow the key only when it is `nil`.
		*/
		case member(SyntaxTree.Member?, members: [SyntaxTree.Member], remaining: ArraySlice<SOML.KeyPath.Segment>)

		/**
		In an array: the item at the index that starts `remaining`, or `nil` when the index is at or past the end of the array. The number of items is where a new item goes. More segments follow the index only when it is `nil`.
		*/
		case item(SyntaxTree.Node?, items: [SyntaxTree.Node], remaining: ArraySlice<SOML.KeyPath.Segment>)
	}

	/**
	The container where the path ends, and the place in it.
	*/
	struct Target {
		let container: Container
		let place: Place

		/**
		Whether the container stays on one line, so that a value added or replaced in it is written on one line too: its brackets are on one line and something other than spaces and tabs is between them, or it is inside a container that stays on one line.
		*/
		let staysOnOneLine: Bool
	}

	let tree: SyntaxTree
	let value: SOML.Value
	let path: SOML.KeyPath

	/**
	The replacements, in ascending order of their ranges, which do not overlap.
	*/
	var replacements = [Replacement]()

	init(tree: SyntaxTree, value: SOML.Value, path: SOML.KeyPath) {
		self.tree = tree
		self.value = value
		self.path = path
	}

	var text: [UInt8] {
		tree.text
	}

	/**
	The first `count` segments of the path as the reference implementation describes them in the errors that it shares with this editor, or “the document” when `count` is zero.
	*/
	func describedPrefix(_ count: Int) -> String {
		count == 0 ? "the document" : path.segments.prefix(count).described
	}

	/**
	The array that the first `count` segments of the path lead to, as the reference implementation describes it, like “the array at servers”, or “the document” when `count` is zero.
	*/
	func describedArray(_ count: Int) -> String {
		count == 0 ? "the document" : "the array at \(describedPrefix(count))"
	}

	// MARK: Finding

	/**
	Follows the path through members and array items, to the object where its last key is, or the first one that does not exist, or to the array where its last index is.

	- Parameter verb: What the change does, like `rename`, for the error messages. It is `edit` for a change that the reference implementation's `edit()` can make, setting or removing, whose errors here have the same text as there.
	*/
	func target(verb: String) throws(SOML.EditError) -> Target {
		let segments = path.segments
		var node = tree.body
		var value = self.value
		var remaining = segments[...]
		var isInsideOneLine = false

		while let segment = remaining.first {
			let parentCount = segments.count - remaining.count

			switch (node.kind, value) {
			case (.object(let members, let isBraced), .object(let object)):
				let container = Container(node: node, isBraced: isBraced, count: members.count)

				guard case .key(let key) = segment else {
					throw SOML.EditError(message: "Cannot \(verb) \(segments[...].described), because \(describedPrefix(parentCount)) is an object, so it needs a key, not an index")
				}

				let memberIndex = object.index(forKey: key)
				let member = memberIndex.map { members[$0] }

				// The path continues in the value of the member.
				guard
					remaining.count > 1,
					let memberIndex,
					let member
				else {
					return Target(container: container, place: .member(member, members: members, remaining: remaining), staysOnOneLine: isInsideOneLine || isOneLine(container))
				}

				isInsideOneLine = isInsideOneLine || isOneLine(container)
				node = member.value
				value = object[memberIndex].value
				remaining = remaining.dropFirst()
			case (.array(let items), .array(let values)):
				let container = Container(node: node, isBraced: true, count: items.count)

				guard case .index(let index) = segment else {
					throw SOML.EditError(message: "Cannot \(verb) \(segments[...].described), because \(describedPrefix(parentCount)) is an array, so it needs an index, not a key")
				}

				guard
					index < items.count,
					remaining.count > 1
				else {
					let item = index < items.count ? items[index] : nil
					return Target(container: container, place: .item(item, items: items, remaining: remaining), staysOnOneLine: isInsideOneLine || isOneLine(container))
				}

				isInsideOneLine = isInsideOneLine || isOneLine(container)
				node = items[index]
				value = values[index]
				remaining = remaining.dropFirst()
			default:
				throw SOML.EditError(message: "Cannot \(verb) \(segments[...].described), because \(describedPrefix(parentCount)) is not an object or an array")
			}
		}

		preconditionFailure("A key path has at least one segment, and the loop returns at its last one.")
	}

	/**
	Whether the brackets of `container` are on one line and something other than spaces and tabs is between them, as in `[1, 2]` and `[/* note */]`, which the formatter keeps on one line. An empty `[]` or `{}` says nothing about layout, because the formatter writes every empty container that way, and a document without braces never counts.
	*/
	func isOneLine(_ container: Container) -> Bool {
		let range = container.node.range

		return container.isBraced
			&& skipSpaces(from: range.lowerBound + 1) < range.upperBound - 1
			&& tree.isSameLine(range.lowerBound, range.upperBound)
	}

	/**
	The error for a path that leads to nothing in `target`: a member that does not exist, or an index at or past the end of its array.
	*/
	func missingError(verb: String, in target: Target) -> SOML.EditError {
		switch target.place {
		case .member(nil, _, let remaining):
			let missingCount = path.segments.count - remaining.count + 1

			guard missingCount < path.segments.count else {
				return SOML.EditError(message: "Cannot \(verb) \(path.segments[...].described), because it does not exist")
			}

			return SOML.EditError(message: "Cannot \(verb) \(path.segments[...].described), because \(describedPrefix(missingCount)) does not exist")
		case .item(_, let items, let remaining):
			return SOML.EditError(message: "Cannot \(verb) \(path.segments[...].described), because \(describedArray(path.segments.count - remaining.count)) has \(items.count.itemCountDescription)")
		case .member:
			preconditionFailure("A path that names a member leads to something.")
		}
	}

	/**
	The member or item at the path in `target`, or `nil` when the path leads to nothing, like a member that does not exist or an index at or past the end of its array.
	*/
	func existingNode(in target: Target) -> Range<Int>? {
		switch target.place {
		case .member(let member, _, _):
			member?.range
		case .item(let item, _, _):
			item?.range
		}
	}

	// MARK: Setting

	/**
	Replaces the value at the path with the text that `valueText` makes for the indentation of its line and whether its container stays on one line, or adds a member or an item for it.
	*/
	mutating func set(_ valueText: (ArraySlice<UInt8>, _ isOneLine: Bool) throws(SOML.EditError) -> [UInt8]) throws(SOML.EditError) {
		let target = try target(verb: "edit")
		let isOneLine = target.staysOnOneLine

		func text(_ indentation: ArraySlice<UInt8>) throws(SOML.EditError) -> [UInt8] {
			try valueText(indentation, isOneLine)
		}

		switch target.place {
		case .member(let member, let members, let remaining):
			if let member {
				try replaceValue(of: member, with: text)
				return
			}

			// A new member goes at the end, and the rest of the path becomes nested objects.
			let keys = try newKeys(remaining)
			let key = keys[0]

			try insert(after: members.last?.range, in: target.container, isOneLine: isOneLine) { (indentation) throws(SOML.EditError) in
				try Self.memberText(key: key, indentation: indentation) { (valueIndentation) throws(SOML.EditError) in
					try Self.nestedText(keys: keys.dropFirst(), indentation: valueIndentation, isOneLine: isOneLine, text)
				}
			}
		case .item(let item, let items, let remaining):
			if let item {
				try replace(item, with: text)
				return
			}

			guard remaining.first?.indexValue == items.count else {
				throw SOML.EditError(message: "Cannot edit \(path.segments[...].described), because \(describedArray(path.segments.count - remaining.count)) has \(items.count.itemCountDescription). Add an item at index \(items.count)")
			}

			let keys = try newKeys(remaining.dropFirst())

			guard !keys.isEmpty else {
				try insert(after: items.last?.range, in: target.container, isOneLine: isOneLine, text)
				return
			}

			// The rest of the path makes a new object, with nested objects as for a missing member.
			try insert(after: items.last?.range, in: target.container, isOneLine: isOneLine) { (indentation) throws(SOML.EditError) in
				try Self.nestedText(keys: keys[...], indentation: indentation, isOneLine: isOneLine, text)
			}
		}
	}

	/**
	The keys of the objects that a change makes for the end of the path, `segments`, which cannot have an index, because no array is there yet.

	The error names the last index, as the reference implementation does, because it builds the new value from the end of the path.
	*/
	func newKeys(_ segments: ArraySlice<SOML.KeyPath.Segment>) throws(SOML.EditError) -> [String] {
		var keys = [String]()
		keys.reserveCapacity(segments.count)

		for offset in segments.indices.reversed() {
			let segment = segments[offset]
			guard case .key(let key) = segment else {
				throw SOML.EditError(message: "Cannot edit \(path.segments[...].described), because \(describedPrefix(offset)) does not exist, so it has no index \(segment.indexValue ?? 0)")
			}

			keys.append(key)
		}

		keys.reverse()
		return keys
	}

	/**
	Replaces a value with the text that `valueText` makes for the indentation of its line.
	*/
	mutating func replace(_ node: SyntaxTree.Node, with valueText: (ArraySlice<UInt8>) throws(SOML.EditError) -> [UInt8]) throws(SOML.EditError) {
		let range = node.range
		replacements.append(.init(range: range, text: try valueText(tree.indentation(ofLineAt: range.lowerBound))))
	}

	/**
	Replaces the value of `member`. The formatter writes a block string on a line of its own after its key and any comments there, one level deeper than the key, so a new block string goes there. Any other value goes on the key's line when only whitespace comes between, so a new value that is not a block string moves there from a block string, and otherwise stays where the old one was.
	*/
	mutating func replaceValue(of member: SyntaxTree.Member, with valueText: (ArraySlice<UInt8>) throws(SOML.EditError) -> [UInt8]) throws(SOML.EditError) {
		let colonEnd = member.keyRange.upperBound + 1
		let value = member.value
		let keyIndentation = tree.indentation(ofLineAt: member.keyRange.lowerBound)
		let newText = try valueText(keyIndentation)

		if newText[...].startsBlockString {
			let inner = Array(keyIndentation) + [.tab]

			// The whitespace before the old value goes, so the new one begins on the next line after the `:` or the last comment.
			var start = value.range.lowerBound

			while
				start > colonEnd,
				text[start - 1].isSOMLWhitespace
			{
				start -= 1
			}

			replacements.append(.init(range: start..<value.range.upperBound, text: [.lineFeed] + inner + (try valueText(inner[...]))))
			return
		}

		guard
			case .blockString = value.kind,
			text[colonEnd..<value.range.lowerBound].allSatisfy({ $0.isSpaceOrTab || $0 == .lineFeed })
		else {
			try replace(value, with: valueText)
			return
		}

		replacements.append(.init(range: colonEnd..<value.range.upperBound, text: [.space] + newText))
	}

	/**
	The text of a member with `key` and the value that `valueText` makes, for a line with `indentation`. A block string begins on the line after the key, one level deeper, as the formatter writes it, and any other value on the key's line.
	*/
	static func memberText(key: String, indentation: ArraySlice<UInt8>, _ valueText: (ArraySlice<UInt8>) throws(SOML.EditError) -> [UInt8]) throws(SOML.EditError) -> [UInt8] {
		let newText = try valueText(indentation)
		var output = [UInt8]()
		CanonicalWriter.appendKey(key, to: &output)
		output.append(.colon)

		guard newText[...].startsBlockString else {
			output.append(.space)
			output.append(contentsOf: newText)
			return output
		}

		let inner = Array(indentation) + [.tab]
		output.append(.lineFeed)
		output.append(contentsOf: inner)
		output.append(contentsOf: try valueText(inner[...]))
		return output
	}

	/**
	The value that `valueText` makes inside objects with `keys`, one in another, as a serializer writes them, for a line with `indentation`, like `{b: {c: 1}}` on one line, `isOneLine`, and with each member on a line of its own otherwise. Without keys, it is the value.
	*/
	static func nestedText(keys: ArraySlice<String>, indentation: ArraySlice<UInt8>, isOneLine: Bool, _ valueText: (ArraySlice<UInt8>) throws(SOML.EditError) -> [UInt8]) throws(SOML.EditError) -> [UInt8] {
		guard !keys.isEmpty else {
			return try valueText(indentation)
		}

		var output = [UInt8]()
		var inner = Array(indentation)

		for index in keys.indices {
			output.append(.openBrace)

			if !isOneLine {
				inner.append(.tab)
				output.append(.lineFeed)
				output.append(contentsOf: inner)
			}

			if index == keys.index(before: keys.endIndex) {
				output.append(contentsOf: try memberText(key: keys[index], indentation: inner[...], valueText))
			} else {
				CanonicalWriter.appendKey(keys[index], to: &output)
				output.append(contentsOf: [.colon, .space])
			}
		}

		for _ in keys {
			if !isOneLine {
				inner.removeLast()
				output.append(.lineFeed)
				output.append(contentsOf: inner)
			}

			output.append(.closeBrace)
		}

		return output
	}

	/**
	Adds a member or an item after `anchor` and the comments that it owns, or into the empty braced container when there is none. When something follows the anchor and its comments on its line, like the closing bracket in `{a: 1}` or `[\n\t1\n\t2]`, the new item goes on that line after a comma. Otherwise it goes on a line of its own with no comma, because a line break separates it, and the items around it keep theirs. An item in an empty container goes on a line of its own, unless the container stays on one line, `isOneLine`: then it goes before the closing bracket, so `[/* note */]` becomes `[/* note */ 1]`, and `[1, []]` becomes `[1, [2]]`. `makeItem` gets the indentation of the line where it goes.
	*/
	mutating func insert(after anchor: Range<Int>?, in container: Container, isOneLine: Bool, _ makeItem: (ArraySlice<UInt8>) throws(SOML.EditError) -> [UInt8]) throws(SOML.EditError) {
		guard let anchor else {
			// An empty braced container. The top level without braces always has a member. The comments inside stay where they are.
			let open = container.node.range.lowerBound
			let close = container.node.range.upperBound - 1

			if isOneLine {
				let start = skipSpacesBack(from: close)
				let space: [UInt8] = start > open + 1 ? [.space] : []
				replacements.append(.init(range: start..<close, text: space + (try makeItem(tree.indentation(ofLineAt: open)))))
				return
			}

			let outer = Array(tree.indentation(ofLineAt: open))
			let inner = outer + [.tab]
			let line = inner + (try makeItem(inner[...]))
			let closeLineStart = tree.lineStart(at: close)

			// A closing bracket on its own line keeps that line, and the item goes on a new line before it.
			if
				closeLineStart > open,
				text[closeLineStart..<close].allSatisfy(\.isSpaceOrTab)
			{
				replacements.append(.init(range: closeLineStart..<closeLineStart, text: line + [.lineFeed]))
				return
			}

			let contentEnd = skipSpacesBack(from: close)
			replacements.append(.init(range: contentEnd..<close, text: [.lineFeed] + line + [.lineFeed] + outer))
			return
		}

		// The new item goes after the comments that the anchor owns, so that they stay with it.
		let anchorEnd = ownedEnd(anchor.upperBound)

		// The comma after the anchor, which can be on a later line when a block comment that spans lines comes between them, as in `a: 1 /*\n*/,`.
		let next = skipTrivia(from: anchorEnd, crossesLines: true)
		let comma = container.isBraced && next < text.count && text[next] == .comma ? next : nil
		let afterComma = comma.map { $0 + 1 } ?? anchorEnd

		guard let lineEnd = lineEndAfterTrivia(from: afterComma) else {
			// Something follows on the same line, as in `{a: 1, b: 2}`, so the new item goes on that line too.
			let newItem = try makeItem(tree.indentation(ofLineAt: afterComma))

			guard let comma else {
				replacements.append(.init(range: anchorEnd..<anchorEnd, text: [.comma, .space] + newItem))
				return
			}

			replacements.append(.init(range: (comma + 1)..<(comma + 1), text: [.space] + newItem + [.comma]))
			return
		}

		let indentation = tree.indentation(ofLineAt: anchor.lowerBound)
		let line: [UInt8] = [.lineFeed] + indentation + (try makeItem(indentation))
		replacements.append(.init(range: lineEnd..<lineEnd, text: line))
	}

	// MARK: Removing

	/**
	Removes the member or item at the path. A path that leads to nothing, like a member that does not exist or an index at or past the end of its array, changes nothing.

	Removing the only member of a document without braces leaves `{}` in its place, because a document is never empty, and the comments that the member owned stay.
	*/
	mutating func remove() throws(SOML.EditError) {
		let target = try target(verb: "edit")

		guard let range = existingNode(in: target) else {
			return
		}

		guard
			!target.container.isBraced,
			target.container.count == 1
		else {
			removeNode(range, in: target.container)
			return
		}

		replacements.append(.init(range: range, text: [.openBrace, .closeBrace]))
	}

	/**
	Removes the member or item at `range` from `container`.

	The removal also takes a blank line that would be left next to another one or directly inside a bracket. When the only member or item of a braced container goes and no comment is left inside, its brackets close up, as `{}` or `[]`.
	*/
	mutating func removeNode(_ range: Range<Int>, in container: Container) {
		// When the removed item is the last one and has no comma after it, it takes the comma before it, so that no trailing comma is left, as `[1, 2]` becomes `[1]`.
		let next = skipTrivia(from: range.upperBound, crossesLines: true)

		let takesCommaBefore = range == container.lastItemRange
			&& (next == text.count || text[next] != .comma)

		var removal = removal(of: range, takesCommaBefore: takesCommaBefore)

		// A removal that starts a line is of whole lines, or leaves only the closing bracket on its line, like `2` in `[\n\t1,\n\n\t2]`, which is the same for the blank lines around it.
		if removal.start == tree.lineStart(at: removal.start) {
			takeBlankLine(&removal, in: container)
		} else if
			container.isBraced,
			removal.end < text.count,
			text[removal.end] == .lineFeed,
			skipSpaces(from: container.node.range.lowerBound + 1) >= removal.start,
			isBlankLine(at: removal.end + 1)
		{
			// It leaves only the opening bracket on its line, like `1,` in `[1,\n\n\t2\n]`, so a blank line after it would be directly inside the bracket.
			removal.end = tree.lineEnd(from: removal.end + 1)
		}

		if
			container.isBraced,
			container.count == 1,
			!isCommentLeft(in: container.node, outside: removal)
		{
			let range = container.node.range
			replacements.append(.init(range: (range.lowerBound + 1)..<(range.upperBound - 1), text: []))
			return
		}

		replacements.append(.init(range: removal.start..<removal.end, text: []))
	}

	/**
	Whether a comment inside `node` is outside `removal`.
	*/
	func isCommentLeft(in node: SyntaxTree.Node, outside removal: Removal) -> Bool {
		let start = tree.comments.partitioningIndex { $0.range.lowerBound > node.range.lowerBound }
		let end = tree.comments.partitioningIndex { $0.range.lowerBound >= node.range.upperBound }
		return tree.comments[start..<end].contains { $0.range.lowerBound < removal.start || $0.range.lowerBound >= removal.end }
	}

	/**
	What removing a member or an item at `range`, with the comments it owns and its comma, takes out of the text. With `takesCommaBefore`, a comma directly before it goes too.
	*/
	func removal(of range: Range<Int>, takesCommaBefore: Bool) -> Removal {
		let start = ownedStart(range.lowerBound)
		let end = ownedEnd(range.upperBound)
		let next = skipSpaces(from: end)

		// Only a braced container can have commas.
		let hasComma = next < text.count && text[next] == .comma

		// The comma before it is only taken when spaces alone are between them and the comments it owns. The scan back only crosses spaces, so it stays short on a long line.
		let before = skipSpacesBack(from: start)

		let removalStart = takesCommaBefore
			&& before > 0
			&& text[before - 1] == .comma
			? before - 1
			: start

		// The comments after its comma go with it when they end its line, as the formatter keeps them after it.
		let removalEnd = hasComma ? lineEndAfterTrivia(from: next + 1) ?? next + 1 : end
		var removal = removal(from: removalStart, to: removalEnd)

		// When it takes the comma before it, the spaces before a comment after it stay, so that the comment does not join the item before the comma.
		if
			removalStart != start,
			!removal.isWholeLines,
			tree.commentEnd(startingAt: removal.end) != nil
		{
			removal.end = skipSpacesBack(from: removal.end)
		}

		return removal
	}

	/**
	The start of the block comments that a member or an item at `offset` owns before it: those on its line after the comma or the opening bracket before it, like `/* note */` in `[1, /* note */ 2]`. The formatter keeps them in front of it. It is `offset` when there are none.
	*/
	func ownedStart(_ offset: Int) -> Int {
		var start = offset

		while let commentStart = tree.blockCommentStart(endingAt: skipSpacesBack(from: start)) {
			start = commentStart
		}

		return start
	}

	/**
	The end of the comments that a member or an item ending at `offset` owns after it: those on its line before its comma or the closing bracket, like `/* note */` in `[1 /* note */, 2]` and `[1, 2 /* note */]`, and a `#` comment at the end of its line. The formatter keeps them after it. It is `offset` when there are none.
	*/
	func ownedEnd(_ offset: Int) -> Int {
		var end = offset

		while let commentEnd = tree.commentEnd(startingAt: skipSpaces(from: end)) {
			end = commentEnd
		}

		return end
	}

	/**
	The removal of the text from `start` to `end`. When nothing else is on its lines, it takes the lines, including a comment at the end of the last one.
	*/
	func removal(from start: Int, to end: Int) -> Removal {
		let lineStart = tree.lineStart(at: start)

		if
			skipSpaces(from: lineStart) == start,
			let lineEnd = lineEndAfterTrivia(from: end)
		{
			return Removal(start: lineStart, end: min(lineEnd + 1, text.count), isWholeLines: true)
		}

		// The spaces after the text go too, and the spaces before it when nothing follows it on the line or in its container.
		let after = skipSpaces(from: end)

		let isLast = after == text.count
			|| text[after] == .lineFeed
			|| text[after] == .closeBrace
			|| text[after] == .closeBracket

		return Removal(start: isLast ? skipSpacesBack(from: start) : start, end: after, isWholeLines: false)
	}

	/**
	Widens a removal that starts a line by a blank line that would otherwise be left next to another blank line, or directly inside a bracket.
	*/
	func takeBlankLine(_ removal: inout Removal, in container: Container) {
		let isBlankBefore = removal.start > 0 && isBlankLine(at: tree.lineStart(at: removal.start - 1))
		let isBlankAfter = removal.end < text.count && isBlankLine(at: removal.end)

		if
			isBlankBefore,
			isBlankAfter || isAtClosing(removal.end, in: container)
		{
			removal.start = tree.lineStart(at: removal.start - 1)
		} else if
			isBlankAfter,
			isAtOpening(removal.start, in: container)
		{
			removal.end = tree.lineEnd(from: removal.end) + 1
		}
	}

	/**
	Whether only blank lines come between the line at `offset` and the line that closes `container`, or the end of the text.
	*/
	func isAtClosing(_ offset: Int, in container: Container) -> Bool {
		let end = skipBlankLines(from: offset)
		return end == text.count || (container.isBraced && skipSpaces(from: end) == container.node.range.upperBound - 1)
	}

	/**
	Whether only blank lines come between the line that opens `container`, or the start of the text, and the line at `offset`. The line that opens a container ends after the comments that follow its bracket.
	*/
	func isAtOpening(_ offset: Int, in container: Container) -> Bool {
		guard container.isBraced else {
			return skipBlankLines(from: 0) == offset
		}

		guard let lineEnd = lineEndAfterTrivia(from: container.node.range.lowerBound + 1) else {
			return false
		}

		return skipBlankLines(from: lineEnd + 1) == offset
	}

	// MARK: Renaming

	/**
	Writes `keyText` in place of the key of the member at the path.
	*/
	mutating func renameKey(to keyText: [UInt8]) throws(SOML.EditError) {
		let target = try target(verb: "rename")

		guard case .member(let member, _, _) = target.place else {
			// An item that is there has no key. An index at or past the end of its array is nothing at the path, so it gets the missing error, as `setting(_:at:)` and `settingComment(_:at:)` describe it.
			guard case .item(.some, _, _) = target.place else {
				throw missingError(verb: "rename", in: target)
			}

			throw SOML.EditError(message: "Cannot rename \(path.segments[...].described), because it is an array item, which has no key")
		}

		guard let member else {
			throw missingError(verb: "rename", in: target)
		}

		replacements.append(.init(range: member.keyRange, text: keyText))
	}

	// MARK: Comments

	/**
	Sets the `#` comment at the end of the line where the member or item at the path ends, after its comma, to `comment`, or removes it when `comment` is `nil`. Removing the comment of a member or item that is not there changes nothing.
	*/
	mutating func setComment(_ comment: [UInt8]?, verb: String) throws(SOML.EditError) {
		let target = try target(verb: verb)

		guard let range = existingNode(in: target) else {
			guard comment == nil else {
				throw missingError(verb: verb, in: target)
			}

			return
		}

		let (lineEnd, existing) = lineComment(after: range, in: target.container)

		guard let lineEnd else {
			throw SOML.EditError(message: "Cannot \(verb) \(path.segments[...].described), because something other than a comment follows it on its line")
		}

		let existingRange = existing?.range
		let commentText = comment.map { [.hash] + ($0.isEmpty ? [] : [.space] + $0) }

		switch (existingRange, commentText) {
		case (let existingRange?, let commentText?):
			replacements.append(.init(range: existingRange, text: commentText))
		case (let existingRange?, nil):
			replacements.append(.init(range: skipSpacesBack(from: existingRange.lowerBound)..<existingRange.upperBound, text: []))
		case (nil, let commentText?):
			replacements.append(.init(range: skipSpacesBack(from: lineEnd)..<lineEnd, text: [.space] + commentText))
		case (nil, nil):
			break
		}
	}

	/**
	The end of the line where the member or item at `range` ends, and the `#` comment at the end of that line after it and its comma, if any. The line end is `nil` when something other than comments follows the member or item and its comma on the line.
	*/
	func lineComment(after range: Range<Int>, in container: Container) -> (lineEnd: Int?, comment: SyntaxTree.Comment?) {
		// The comma on the same line as the end of the member or item goes before the comment.
		var end = range.upperBound
		let next = skipTrivia(from: end, crossesLines: false)

		if
			container.isBraced,
			next < text.count,
			text[next] == .comma
		{
			end = next + 1
		}

		guard let lineEnd = lineEndAfterTrivia(from: end) else {
			return (nil, nil)
		}

		// A `#` comment runs to the end of its line, so the comment that ends there, if it is after the member or item, is the one.
		let commentIndex = tree.comments.partitioningIndex { $0.range.lowerBound >= lineEnd }

		guard commentIndex > tree.comments.startIndex else {
			return (lineEnd, nil)
		}

		let comment = tree.comments[commentIndex - 1]

		guard
			!comment.isBlock,
			comment.range.upperBound == lineEnd,
			comment.range.lowerBound >= end
		else {
			return (lineEnd, nil)
		}

		return (lineEnd, comment)
	}

	// MARK: Text

	/**
	Whether the line that starts at `lineStart` has only spaces and tabs, and a line feed.
	*/
	func isBlankLine(at lineStart: Int) -> Bool {
		let end = skipSpaces(from: lineStart)
		return end < text.count && text[end] == .lineFeed
	}

	/**
	The offset after the blank lines that start at `offset`.
	*/
	func skipBlankLines(from offset: Int) -> Int {
		var position = offset

		while
			position < text.count,
			isBlankLine(at: position)
		{
			position = tree.lineEnd(from: position) + 1
		}

		return position
	}

	/**
	The offset after the spaces and tabs from `offset`.
	*/
	func skipSpaces(from offset: Int) -> Int {
		var position = offset

		while
			position < text.count,
			text[position].isSpaceOrTab
		{
			position += 1
		}

		return position
	}

	/**
	The offset before the spaces and tabs that end at `offset`.
	*/
	func skipSpacesBack(from offset: Int) -> Int {
		// A reversed prefix helped 1000-tab runs but measured 23–100% slower for ordinary 0–10-byte runs; keep the bounded backward loop.
		var position = offset

		while
			position > 0,
			text[position - 1].isSpaceOrTab
		{
			position -= 1
		}

		return position
	}

	/**
	The offset after the spaces, tabs, and comments from `offset`, and with `crossesLines`, the line feeds too.
	*/
	func skipTrivia(from offset: Int, crossesLines: Bool) -> Int {
		var position = offset

		while position < text.count {
			if
				text[position].isSpaceOrTab
					|| (crossesLines && text[position] == .lineFeed)
			{
				position += 1
			} else if let commentEnd = tree.commentEnd(startingAt: position) {
				position = commentEnd
			} else {
				break
			}
		}

		return position
	}

	/**
	The offset of the line feed that ends the line at `offset`, or the end of the text, when only spaces, tabs, and comments come before it. Otherwise `nil`.
	*/
	func lineEndAfterTrivia(from offset: Int) -> Int? {
		let end = skipTrivia(from: offset, crossesLines: false)

		guard end == text.count || text[end] == .lineFeed else {
			return nil
		}

		return end
	}

	// MARK: Result

	/**
	The document with the replacements made, after a check that it is valid and has the expected value. It is the one check of every rule, so the splicing does not need its own.
	*/
	func result(expecting expectedValue: SOML.Value) throws(SOML.EditError) -> SOML.Document {
		// Reversed replaceSubrange calls move the suffix for each edit and measured slower as edits accumulate; splice into one reserved result instead.
		var result = [UInt8]()
		let count = replacements.reduce(text.count) { $0 + ($1.text.count - $1.range.count) }

		result.reserveCapacity(count)
		var position = 0

		for replacement in replacements {
			result += text[position..<replacement.range.lowerBound]
			result += replacement.text
			position = replacement.range.upperBound
		}

		result += text[position...]

		let document: SOML.Document

		do throws(SOML.ParseError) {
			document = try SOML.Document(parsing: result)
		} catch {
			throw SOML.EditError(message: "The change would make the document invalid: \(error.message)")
		}

		guard document.value == expectedValue else {
			throw SOML.EditError(message: "The change did not give the expected value. This is a bug. Please report it")
		}

		return document
	}
}

extension SyntaxTree {
	/**
	The start of the `/* */` comment that ends at `offset`, or `nil` when no block comment ends there.
	*/
	func blockCommentStart(endingAt offset: Int) -> Int? {
		let index = comments.partitioningIndex { $0.range.upperBound >= offset }

		guard
			index < comments.endIndex,
			comments[index].isBlock,
			comments[index].range.upperBound == offset
		else {
			return nil
		}

		return comments[index].range.lowerBound
	}

	/**
	The spaces and tabs at the start of the line that holds `offset`.

	A line that a block comment from an earlier line runs into, as in `/* a\n b */ x: 1`, is indented as the line where that comment starts.
	*/
	func indentation(ofLineAt offset: Int) -> ArraySlice<UInt8> {
		var lineStart = self.lineStart(at: offset)

		while true {
			let next = comments.partitioningIndex { $0.range.lowerBound >= lineStart }

			guard
				next > comments.startIndex,
				comments[next - 1].range.upperBound > lineStart
			else {
				break
			}

			lineStart = self.lineStart(at: comments[next - 1].range.lowerBound)
		}

		return text[lineStart...].prefix(while: \.isSpaceOrTab)
	}
}

extension SOML.Difference {
	/**
	Whether it is a removed member or item.
	*/
	fileprivate var isRemoval: Bool {
		guard case .removed = self else {
			return false
		}

		return true
	}
}

extension SOML.KeyPath.Segment {
	/**
	The index, or `nil` for a key.
	*/
	fileprivate var indexValue: Int? {
		guard case .index(let index) = self else {
			return nil
		}

		return index
	}

	/**
	Whether it is a key with a carriage return, which SOML cannot represent.
	*/
	fileprivate var hasCarriageReturn: Bool {
		guard case .key(let key) = self else {
			return false
		}

		return key.hasCarriageReturn
	}
}

extension SOML.KeyPath.Segment {
	/**
	The segment as a key path of its own, as the reference implementation describes it in an error message, like `port` or `"the name"`.
	*/
	var described: String {
		[self][...].described
	}
}

extension Int {
	/**
	The number as a count of array items, like `1 item` or `3 items`.
	*/
	fileprivate var itemCountDescription: String {
		self == 1 ? "1 item" : "\(self) items"
	}
}

extension [UInt8] {
	/**
	The text with `indentation` after every line feed, so that a value written in canonical form fits the line it goes on. Canonical form escapes a line feed in a string, so every line feed is between the lines of a container.
	*/
	func indentingLines(with indentation: ArraySlice<UInt8>) -> [UInt8] {
		guard !indentation.isEmpty else {
			return self
		}

		let lineFeeds = count(where: { $0 == .lineFeed })

		guard lineFeeds > 0 else {
			return self
		}

		// `replacing([UInt8.lineFeed], with: [UInt8.lineFeed] + indentation)` measured substantially slower than this reserved byte loop in optimized Swift 6.4 builds on an M4 Pro.
		var result = [UInt8]()
		result.reserveCapacity(count + lineFeeds * indentation.count)

		for byte in self {
			result.append(byte)

			if byte == .lineFeed {
				result += indentation
			}
		}

		return result
	}
}

extension ArraySlice<SOML.KeyPath.Segment> {
	/**
	The key path as the reference implementation describes it in an error message, like `servers[0]."the name"`: each key bare when it can be and otherwise as a JSON string, each index in brackets, cut to 200 characters, with invisible characters and those that a terminal acts on written as escapes.
	*/
	var described: String {
		var description = ""

		for segment in self {
			switch segment {
			case .key(let key):
				description += (description.isEmpty ? "" : ".") + Parser.describeKey(key)
			case .index(let index):
				description += "[\(index)]"
			}

			if description.utf16.count > 200 {
				break
			}
		}

		var output = String.UnicodeScalarView()

		for scalar in description.shortened(to: 200).unicodeScalars {
			switch scalar.properties.generalCategory {
			case .control, .format, .lineSeparator, .paragraphSeparator:
				output += "\\u{\(String(scalar.value, radix: 16))}".unicodeScalars
			default:
				output.append(scalar)
			}
		}

		return String(output)
	}
}

extension SOML.Value {
	/**
	The first prefix before the last segment that cannot contain the next step of an update, or `nil` when every parent exists.
	*/
	fileprivate func firstMissingContainer(in path: SOML.KeyPath) -> SOML.KeyPath? {
		var value = self

		for index in path.segments.indices.dropLast() {
			let child: SOML.Value? = switch path.segments[index] {
			case .key(let key):
				value[key]
			case .index(let index):
				value[index]
			}

			guard
				let child,
				child.isContainer
			else {
				return SOML.KeyPath(Array(path.segments[...index]))
			}

			value = child
		}

		return nil
	}

	/**
	The value at a key path, or `nil` when the path does not lead to a value.
	*/
	func value(at path: ArraySlice<SOML.KeyPath.Segment>) -> SOML.Value? {
		var current = self

		for segment in path {
			let child: SOML.Value? = switch segment {
			case .key(let key):
				current[key]
			case .index(let index):
				current[index]
			}

			guard let child else {
				return nil
			}

			current = child
		}

		return current
	}

	/**
	The value with `newValue` at a key path, creating the objects on the way. An index that is the number of items in an array adds an item. When a value on the way is not an object or an array, or an index is past the end, the result is `newValue`, but the editor throws before it gets there.
	*/
	func setting(_ newValue: SOML.Value, at path: ArraySlice<SOML.KeyPath.Segment>) -> SOML.Value {
		switch (path.first, self) {
		case (.key(let key)?, .object(var object)):
			object[key] = (object[key] ?? .object(SOML.Object())).setting(newValue, at: path.dropFirst())
			return .object(object)
		case (.index(let index)?, .array(var array)) where index < array.count:
			array[index] = array[index].setting(newValue, at: path.dropFirst())
			return .array(array)
		case (.index(let index)?, .array(var array)) where index == array.count:
			array.append(SOML.Value.object(SOML.Object()).setting(newValue, at: path.dropFirst()))
			return .array(array)
		default:
			return newValue
		}
	}

	/**
	The value without the member or item at a key path. It is unchanged when the path does not lead to one.
	*/
	func removing(at path: ArraySlice<SOML.KeyPath.Segment>) -> SOML.Value {
		switch (path.first, self) {
		case (.key(let key)?, .object(var object)):
			guard let child = object[key] else {
				return self
			}

			if path.count == 1 {
				object.removeValue(forKey: key)
			} else {
				object[key] = child.removing(at: path.dropFirst())
			}

			return .object(object)
		case (.index(let index)?, .array(var array)) where array.indices.contains(index):
			if path.count == 1 {
				array.remove(at: index)
			} else {
				array[index] = array[index].removing(at: path.dropFirst())
			}

			return .array(array)
		default:
			return self
		}
	}

	/**
	The value with the member at a key path under a new key. It is unchanged when the path does not lead to a member.
	*/
	func renamingKey(at path: ArraySlice<SOML.KeyPath.Segment>, to newKey: String) -> SOML.Value {
		guard path.count > 1 else {
			guard
				case .key(let key)? = path.first,
				case .object(var object) = self,
				let child = object.removeValue(forKey: key)
			else {
				return self
			}

			object[newKey] = child
			return .object(object)
		}

		switch (path.first, self) {
		case (.key(let key)?, .object(var object)):
			guard let child = object[key] else {
				return self
			}

			object[key] = child.renamingKey(at: path.dropFirst(), to: newKey)
			return .object(object)
		case (.index(let index)?, .array(var array)) where array.indices.contains(index):
			array[index] = array[index].renamingKey(at: path.dropFirst(), to: newKey)
			return .array(array)
		default:
			return self
		}
	}
}
extension SOML.Document {
	/**
	Swaps two distinct members or items in the same container, preserving source spelling. Directly attached leading comments and comments immediately following a value travel with it, and so does the separator before it, like a blank line, so a group of lines stays together. The first member or item has no separator before it, so it takes the separator of the one that takes its place. Comments after a comma are part of the separator that follows. Unrelated source is unchanged.

	Throws `SOML.EditError` for missing paths, different parents, overlapping comment ownership, or a move that cannot preserve the values and valid syntax. The result is parsed and checked before it is returned.
	*/
	public func swapping(_ first: SOML.KeyPath, with second: SOML.KeyPath) throws(SOML.EditError) -> Self {
		guard
			first != second,
			first.segments.dropLast() == second.segments.dropLast(),
			value[path: first] != nil,
			value[path: second] != nil
		else {
			throw SOML.EditError(message: "Select two different members or items in the same container")
		}

		return try moving([first, second], to: [second, first])
	}

	/**
	Puts the members or items of one container in a new order, preserving source spelling. The paths are every member or item of the container, each once, in the new order. Comments and separators travel with their values as for `swapping(_:with:)`.

	It is the general form of a move: drag one or more items to another position, insert a new item after another one by adding it at the end and moving it, or sort the keys of an object without losing its comments.

	```swift
	let document = try SOML.Document(parsing: "b: 2 # Two\na: 1\n")
	let sorted = try document.reordering([["a"], ["b"]])
	//=> "a: 1\nb: 2 # Two\n"
	```

	Throws `SOML.EditError` when the paths are not every member or item of one container exactly once, or for the reasons that `swapping(_:with:)` throws.
	*/
	public func reordering(_ paths: [SOML.KeyPath]) throws(SOML.EditError) -> Self {
		let uniquePaths = Set(paths)

		guard
			let first = paths.first,
			paths.allSatisfy({ $0.segments.count == first.segments.count && $0.segments.dropLast() == first.segments.dropLast() }),
			let container = value.value(at: first.segments.dropLast()),
			uniquePaths.count == paths.count
		else {
			throw SOML.EditError(message: "Give every member or item of one container once, in the new order")
		}

		let parent = Array(first.segments.dropLast())
		let current: [SOML.KeyPath] = switch container {
		case .object(let object):
			object.keys.map { SOML.KeyPath(parent + [.key($0)]) }
		case .array(let items):
			items.indices.map { SOML.KeyPath(parent + [.index($0)]) }
		default:
			[]
		}

		guard
			current.count == uniquePaths.count,
			uniquePaths.isSuperset(of: current)
		else {
			throw SOML.EditError(message: "Give every member or item of one container once, in the new order")
		}

		return try moving(current, to: paths)
	}

	/**
	Puts the source of each path in `targets` where the source of the path at the same position in `slots` is. The paths are siblings, and `targets` is a permutation of `slots`.
	*/
	private func moving(_ slots: [SOML.KeyPath], to targets: [SOML.KeyPath]) throws(SOML.EditError) -> Self {
		guard slots != targets else {
			return self
		}

		let parent = Array(slots[0].segments.dropLast())
		let siblings: [SOML.KeyPath] = switch value.value(at: parent[...]) {
		case .object(let object):
			object.keys.map { SOML.KeyPath(parent + [.key($0)]) }
		case .array(let items):
			items.indices.map { SOML.KeyPath(parent + [.index($0)]) }
		default:
			[]
		}

		let previousSiblings = Dictionary(uniqueKeysWithValues: zip(siblings.dropFirst(), siblings))
		var ranges = [SOML.KeyPath: Range<Int>](minimumCapacity: slots.count * 2)
		for path in slots + slots.compactMap({ previousSiblings[$0] }) where ranges[path] == nil {
			ranges[path] = try Editor(tree: tree, value: self.value, path: path).movingRange()
		}

		/*
		The separator before a member or an item, like a blank line, moves with it, as its comments do, so a group of lines stays together. The first one has no separator of its own, so where it moves, it takes the separator of the one that takes its place.
		*/
		func separator(before path: SOML.KeyPath) -> Range<Int>? {
			guard
				let previous = previousSiblings[path],
				let previousRange = ranges[previous],
				let range = ranges[path]
			else {
				return nil
			}

			return previousRange.upperBound..<range.lowerBound
		}

		let newFirst = zip(slots, targets).first { $0.0 == siblings.first }?.1

		// Only the members or items that change position are rewritten, so the others keep their bytes.
		var replacements = [Editor.Replacement]()
		replacements.reserveCapacity(slots.count)
		for (slot, target) in zip(slots, targets) where slot != target {
			guard
				let slotRange = ranges[slot],
				let targetRange = ranges[target]
			else {
				continue
			}

			guard
				let slotSeparator = separator(before: slot),
				let targetSeparator = separator(before: target) ?? newFirst.flatMap(separator(before:))
			else {
				// The first place keeps the text before it.
				replacements.append(.init(range: slotRange, text: Array(tree.text[targetRange])))
				continue
			}

			replacements.append(.init(range: slotSeparator.lowerBound..<slotRange.upperBound, text: Array(tree.text[targetSeparator] + tree.text[targetRange])))
		}

		replacements.sort { $0.range.lowerBound < $1.range.lowerBound }

		for (earlier, later) in zip(replacements, replacements.dropFirst()) where earlier.range.upperBound > later.range.lowerBound {
			throw SOML.EditError(message: "These comments cannot be moved with their values")
		}

		var editor = Editor(tree: tree, value: self.value, path: slots[0])
		editor.replacements = replacements

		// The children of the container in the new order. A child that is not moved keeps its place.
		let destinations = Dictionary(uniqueKeysWithValues: zip(slots, targets))
		let expectedOrder: [SOML.KeyPath.Segment] = switch value.value(at: parent[...]) {
		case .object(let object):
			object.keys.map { key in
				let path = SOML.KeyPath(parent + [.key(key)])
				return destinations[path]?.segments.last ?? .key(key)
			}
		case .array(let items):
			items.indices.map { index in
				let path = SOML.KeyPath(parent + [.index(index)])
				return destinations[path]?.segments.last ?? .index(index)
			}
		default:
			[]
		}

		var expected = value
		if case .array(let items) = value.value(at: parent[...]) {
			let reordered = expectedOrder.compactMap { segment -> SOML.Value? in
				guard case .index(let index) = segment else {
					return nil
				}

				return items[index]
			}

			expected = value.setting(.array(reordered), at: parent[...])
		}

		let result = try editor.result(expecting: expected)

		// Object equality ignores the order of members, so check the order too.
		if
			case .object(let object) = result.value.value(at: parent[...]),
			object.keys.map({ SOML.KeyPath.Segment.key($0) }) != expectedOrder
		{
			throw SOML.EditError(message: "The change did not give the expected order. This is a bug. Please report it")
		}

		return result
	}
}

extension Editor {
	/**
	The member or item and its attached comments, excluding separators. Shares ownership rules with the document's comment and editing APIs.
	*/
	func movingRange() throws(SOML.EditError) -> Range<Int> {
		let target = try target(verb: "move")
		guard let range = existingNode(in: target) else {
			throw missingError(verb: "move", in: target)
		}

		let start = ownedStart(range.lowerBound)
		let leadingStart = tree.comments(before: start).first?.range.lowerBound ?? start
		return leadingStart..<ownedEnd(range.upperBound)
	}
}

/**
Validated application of value differences to source documents.
*/
extension SOML.Document {
	/**
	Applies a difference using the normal setting and removal rules, preserving other source bytes. The recorded old value is informational and is not checked against the document.
	*/
	public func applying(_ difference: SOML.Difference) throws(SOML.EditError) -> Self {
		switch difference {
		case .added(let value, let path), .changed(_, let value, let path):
			try setting(value, at: path)
		case .removed(_, let path):
			try removing(at: path)
		}
	}

	/**
	Applies differences in their given order. Each edit is validated before the next one, and an error leaves the original document unchanged.
	*/
	public func applying(_ differences: some Sequence<SOML.Difference>) throws(SOML.EditError) -> Self {
		var document = self

		for difference in differences {
			document = try document.applying(difference)
		}

		return document
	}
}

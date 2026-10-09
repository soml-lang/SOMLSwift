// `@testable` for the comments of a document, which the formatter must keep. The build passes `-enable-testing`, so it works in a release build.
@testable import SOML

/**
The libFuzzer entry point.

It reads the input as a document and checks that parsing never crashes, and, for a valid document, that the canonical form, the formatter, and a `setting(_:at:)` and a `removing(at:)` at a path that the input picks give the expected value. A failed check stops the process, which libFuzzer reports as a crash, with the input.
*/
@_cdecl("LLVMFuzzerTestOneInput")
public func fuzz(_ start: UnsafePointer<UInt8>?, _ count: Int) -> CInt {
	let bytes = start.map { Array(UnsafeBufferPointer(start: $0, count: count)) } ?? []
	check(bytes)
	return 0
}

/**
Runs every check on one input.
*/
private func check(_ bytes: [UInt8]) {
	let text = String(decoding: bytes, as: UTF8.self)
	checkTokens(in: text)

	// The other parsers only have to not crash.
	_ = try? SOML.Value(parsingValue: text)
	_ = try? SOML.KeyPath(parsing: text)
	_ = try? SOML.Value(parsingJSON: bytes)
	_ = try? SOML.Value(parsingJSON: bytes, format: .tagged)

	let document = try? SOML.Document(parsing: bytes)
	let value = try? SOML.Value(parsing: bytes)

	guard
		let document,
		let value
	else {
		precondition(document == nil && value == nil, "SOML.Document(parsing:) and SOML.Value(parsing:) disagree on whether the input is valid.")
		return
	}

	precondition(document.value == value, "SOML.Document(parsing:) and SOML.Value(parsing:) give different values.")

	checkCanonicalForm(of: value)
	checkFormatter(on: document)
	checkJSON(of: value)

	var choices = Choices(bytes)
	checkSetting(in: document, using: &choices)
	checkRemoving(in: document, using: &choices)
	checkRenaming(in: document, using: &choices)
	checkSettingComment(in: document, using: &choices)
	checkSettingValueText(in: document, using: &choices)
	checkSelection(in: document, using: &choices)
}

/**
Renames a member at a path that the input picks, and checks that the value moved to the new key and nothing else changed.
*/
private func checkRenaming(in document: SOML.Document, using choices: inout Choices) {
	let path = existingPath(in: document.value, using: &choices)

	guard case .key(let oldKey)? = path.last else {
		return
	}

	let keys = ["renamed", "a", "the key", "x.y", "0", "true", "é", "", "\"", "'"]
	let newKey = keys[Int.random(in: keys.indices, using: &choices)]
	let keyPath = SOML.KeyPath(path)
	let parentPath = path.dropLast()
	let isTaken = !oldKey.hasSameScalars(as: newKey) && document.value.value(at: parentPath)?.objectValue?[newKey] != nil
	let edited: SOML.Document

	do {
		edited = try document.renamingKey(at: keyPath, to: newKey)
	} catch {
		precondition(isTaken, "Renaming \(keyPath) to \(newKey) failed: \(error)")
		return
	}

	precondition(!isTaken, "Renaming \(keyPath) to \(newKey) succeeded, but the key is taken")

	guard let reparsed = try? SOML.Document(parsing: edited.text) else {
		fatalError("Renaming \(keyPath) gives a document that does not parse:\n\(edited.text)")
	}

	var expected = document.value
	expected[path: keyPath] = nil
	expected[path: SOML.KeyPath(parentPath + [.key(newKey)])] = document.value[path: keyPath]

	if !oldKey.hasSameScalars(as: newKey) {
		precondition(reparsed.value == expected, "Renaming \(keyPath) to \(newKey) gives a different value:\n\(edited.text)")
	}

	precondition(document.formatted() != document.text || reparsed.formatted() == reparsed.text, "Renaming in a formatted document gives one that is not formatted:\n\(edited.text)")
}

/**
Sets and then removes the comment of a member or item at a path that the input picks, and checks that it reads back and that the value does not change.
*/
private func checkSettingComment(in document: SOML.Document, using choices: inout Choices) {
	let path = existingPath(in: document.value, using: &choices)

	guard !path.isEmpty else {
		return
	}

	let keyPath = SOML.KeyPath(path)
	let comments = ["note", "", "with # inside", "é", "spaced  out"]
	let comment = comments[Int.random(in: comments.indices, using: &choices)]
	let edited: SOML.Document

	do {
		edited = try document.settingComment(comment, at: keyPath)
	} catch {
		// Something other than a comment follows it on its line, which is documented.
		return
	}

	guard let reparsed = try? SOML.Document(parsing: edited.text) else {
		fatalError("Setting the comment of \(keyPath) gives a document that does not parse:\n\(edited.text)")
	}

	precondition(reparsed.value == document.value, "Setting the comment of \(keyPath) changes the value:\n\(edited.text)")
	precondition(reparsed.comments(at: keyPath)?.trailing == comment, "The comment of \(keyPath) reads back as \(String(describing: reparsed.comments(at: keyPath)?.trailing)), not \(comment):\n\(edited.text)")

	guard let removed = try? reparsed.settingComment(nil, at: keyPath) else {
		fatalError("Removing the comment of \(keyPath) failed:\n\(edited.text)")
	}

	precondition(removed.value == document.value, "Removing the comment of \(keyPath) changes the value:\n\(removed.text)")
	precondition(removed.comments(at: keyPath)?.trailing == nil, "The comment of \(keyPath) is still there after removing it:\n\(removed.text)")
}

/**
Sets a value as typed at a path that the input picks, and checks that it reads back.
*/
private func checkSettingValueText(in document: SOML.Document, using choices: inout Choices) {
	let path = existingPath(in: document.value, using: &choices)

	guard !path.isEmpty else {
		return
	}

	let texts = ["0o644", "1h30m", "'x'", "[1, 2]", "{a: 1}", "[\n1,\n2\n]", "'''\nblock\n  text\n'''", "\"\"\"\n\tx\n\"\"\"", "infinity", "2026-09-19T14:00:00+02:00"]
	let valueText = texts[Int.random(in: texts.indices, using: &choices)]
	let keyPath = SOML.KeyPath(path)
	let expected = try? SOML.Value(parsingValue: valueText)
	let edited: SOML.Document

	do {
		edited = try document.setting(valueText: valueText, at: keyPath)
	} catch {
		let isTooDeep = expected.map { document.value.setting($0, at: path[...]).depth > Parser.maximumDepth } ?? true
		precondition(isTooDeep, "Setting \(keyPath) to the text \(valueText) failed: \(error)")
		return
	}

	guard let reparsed = try? SOML.Document(parsing: edited.text) else {
		fatalError("Setting \(keyPath) to the text \(valueText) gives a document that does not parse:\n\(edited.text)")
	}

	precondition(reparsed.value[path: keyPath] == expected, "Setting \(keyPath) to the text \(valueText) gives a different value:\n\(edited.text)")
}

/**
Checks that the selection of a path that the input picks holds the text of its value, and that the offset of its value leads back to it.
*/
private func checkSelection(in document: SOML.Document, using choices: inout Choices) {
	let path = existingPath(in: document.value, using: &choices)

	guard !path.isEmpty else {
		return
	}

	let keyPath = SOML.KeyPath(path)

	guard
		let range = document.range(of: keyPath),
		let valueRange = document.valueRange(of: keyPath)
	else {
		fatalError("\(keyPath) exists, but has no range")
	}

	let text = Array(document.text.utf8)
	let valueText = String(decoding: text[valueRange.lowerBound.offset..<valueRange.upperBound.offset], as: UTF8.self)

	precondition((try? SOML.Value(parsingValue: valueText)) == document.value[path: keyPath], "The value range of \(keyPath) holds \(valueText)")
	precondition(document.path(atOffset: valueRange.lowerBound.offset) == keyPath, "The path at the start of the value of \(keyPath) is \(String(describing: document.path(atOffset: valueRange.lowerBound.offset)))")
	precondition(document.location(of: keyPath) == range.lowerBound, "The range of \(keyPath) does not start at its location")

	// Any offset, in the text or not, must not crash.
	_ = document.path(atOffset: Int.random(in: -2...(text.count + 2), using: &choices))
}

/**
Checks that the canonical form of a value parses to the same value, and that the formatter does not change it.
*/
private func checkCanonicalForm(of value: SOML.Value) {
	let canonical: String

	do {
		canonical = try value.canonicalDocument()
	} catch {
		fatalError("canonicalDocument() threw for a parsed value: \(error)")
	}

	guard let canonicalDocument = try? SOML.Document(parsing: canonical) else {
		fatalError("The canonical form does not parse:\n\(canonical)")
	}

	precondition(canonicalDocument.value == value, "The canonical form parses to a different value:\n\(canonical)")
	precondition(canonicalDocument.formatted() == canonical, "Formatting the canonical form changes it:\n\(canonical)")
	precondition((try? SOML.Value(parsingValue: value.description)) == value, "The description does not parse to the same value:\n\(value.description)")
}

/**
Checks that the value reads back from tagged JSON, which holds every SOML type, and that plain JSON changes only instants and durations into their canonical strings.
*/
private func checkJSON(of value: SOML.Value) {
	guard let tagged = try? value.jsonText(format: .tagged) else {
		fatalError("jsonText(format: .tagged) threw for a parsed value")
	}

	guard let taggedValue = try? SOML.Value(parsingJSON: tagged, format: .tagged) else {
		fatalError("The tagged JSON does not read back:\n\(tagged)")
	}

	precondition(taggedValue == value, "The tagged JSON reads back as a different value:\n\(tagged)")

	// Infinity has no plain JSON number.
	guard let plain = try? value.jsonText() else {
		return
	}

	guard let plainValue = try? SOML.Value(parsingJSON: plain) else {
		fatalError("The plain JSON does not read back:\n\(plain)")
	}

	precondition(plainValue == value.plainJSONValue, "The plain JSON reads back as a different value:\n\(plain)")
}

/**
Checks both formatter modes for the same value and comments, and checks that formatting again with the same mode changes nothing.
*/
private func checkFormatter(on document: SOML.Document) {
	for expandingContainers in [false, true] {
		let formatted = document.formatted(expandingContainers: expandingContainers)

		guard let formattedDocument = try? SOML.Document(parsing: formatted) else {
			fatalError("The formatted document does not parse:\n\(formatted)")
		}

		precondition(formattedDocument.value == document.value, "The formatted document has a different value:\n\(formatted)")
		precondition(formattedDocument.commentTexts == document.commentTexts, "The formatted document has different comments:\n\(formatted)")
		precondition(formattedDocument.formatted(expandingContainers: expandingContainers) == formatted, "Formatting the formatted document changes it:\n\(formatted)")
	}
}

/**
Sets a value at a path that the input picks: an existing member or item, or a new one, which may need objects that do not exist yet.
*/
private func checkSetting(in document: SOML.Document, using choices: inout Choices) {
	var path = existingPath(in: document.value, using: &choices)

	if Bool.random(using: &choices) {
		appendMissingSegments(to: &path, in: document.value, using: &choices)
	}

	guard !path.isEmpty else {
		return
	}

	let keyPath = SOML.KeyPath(path)
	let newValue = newValue(for: document.value, using: &choices)
	let edited: SOML.Document

	do {
		edited = try document.setting(newValue, at: keyPath)
	} catch {
		// The documented case where the edit cannot be made.
		let isTooDeep = document.value.setting(newValue, at: path[...]).depth > Parser.maximumDepth

		precondition(isTooDeep, "Setting \(keyPath) to \(newValue) failed: \(error)")
		return
	}

	guard let reparsed = try? SOML.Document(parsing: edited.text) else {
		fatalError("Setting \(keyPath) gives a document that does not parse:\n\(edited.text)")
	}

	precondition(reparsed.value == edited.value, "Setting \(keyPath) gives a document whose text has a different value than its value.")
	precondition(reparsed.value[path: keyPath] == newValue, "Setting \(keyPath) to \(newValue) gives a different value there:\n\(edited.text)")

	// Undoing the change at the first segment that did not exist must give the original value, so nothing else changed.
	var restored = reparsed.value
	let existingCount = existingPrefixCount(of: path, in: document.value)
	let restoredPath = SOML.KeyPath(Array(path.prefix(existingCount + 1)))
	restored[path: restoredPath] = document.value[path: restoredPath]

	precondition(restored == document.value, "Setting \(keyPath) changes other values:\n\(edited.text)")
	checkDifferences(from: document, to: reparsed.value)
}

/**
Checks that the differences from the document's value to `newValue`, applied to the document one by one, give `newValue`.
*/
private func checkDifferences(from document: SOML.Document, to newValue: SOML.Value) {
	guard let differences = newValue.differences(from: document.value) else {
		fatalError("The differences of two documents are nil, but both are objects or both are arrays.")
	}

	var edited = document

	do {
		for difference in differences {
			switch difference {
			case .added(let value, let path), .changed(_, let value, let path):
				edited = try edited.setting(value, at: path)
			case .removed(_, let path):
				edited = try edited.removing(at: path)
			}
		}
	} catch {
		fatalError("Applying the differences failed: \(error)")
	}

	precondition(edited.value == newValue, "Applying the differences gives a different value:\n\(edited.text)")
}

/**
Removes an existing member or item at a path that the input picks.
*/
private func checkRemoving(in document: SOML.Document, using choices: inout Choices) {
	let path = existingPath(in: document.value, using: &choices)

	guard !path.isEmpty else {
		return
	}

	let keyPath = SOML.KeyPath(path)
	_ = document.comments(at: keyPath)
	_ = document.location(of: keyPath)
	let edited: SOML.Document

	do {
		edited = try document.removing(at: keyPath)
	} catch {
		fatalError("Removing \(keyPath) failed: \(error)")
	}

	guard let reparsed = try? SOML.Document(parsing: edited.text) else {
		fatalError("Removing \(keyPath) gives a document that does not parse:\n\(edited.text)")
	}

	var expected = document.value
	expected[path: keyPath] = nil

	precondition(reparsed.value == edited.value, "Removing \(keyPath) gives a document whose text has a different value than its value.")
	precondition(reparsed.value == expected, "Removing \(keyPath) gives a different value:\n\(edited.text)")
}

/**
A path to an existing member or item, picked by walking down from the top, or an empty path when the document has nothing in it.
*/
private func existingPath(in value: SOML.Value, using choices: inout Choices) -> [SOML.KeyPath.Segment] {
	var path = [SOML.KeyPath.Segment]()
	var current = value

	while true {
		let children: [(segment: SOML.KeyPath.Segment, value: SOML.Value)] = switch current {
		case .object(let object):
			object.map { (.key($0.key), $0.value) }
		case .array(let items):
			items.enumerated().map { (.index($0.offset), $0.element) }
		default:
			[]
		}

		// After the first step, it stops at each level with a chance of one in three.
		guard
			!children.isEmpty,
			path.isEmpty || Int.random(in: 0..<3, using: &choices) > 0
		else {
			return path
		}

		let child = children[Int.random(in: children.indices, using: &choices)]
		path.append(child.segment)
		current = child.value
	}
}

/**
Appends a member or an item that does not exist yet to a path to an object or an array, and sometimes a member inside it, which needs an object that does not exist yet.
*/
private func appendMissingSegments(to path: inout [SOML.KeyPath.Segment], in value: SOML.Value, using choices: inout Choices) {
	let keys = ["new", "a", "the key", "x.y", "0", "true", "é"]

	switch value.value(at: path[...]) {
	case .object?:
		path.append(.key(keys[Int.random(in: keys.indices, using: &choices)]))
	case .array(let items)?:
		path.append(.index(items.count))
	default:
		return
	}

	// A key in `keys` may already exist, and then the path goes no further.
	guard
		value.value(at: path[...]) == nil,
		Bool.random(using: &choices)
	else {
		return
	}

	path.append(.key(keys[Int.random(in: keys.indices, using: &choices)]))
}

/**
The number of segments at the start of a path that lead to an existing value.
*/
private func existingPrefixCount(of path: [SOML.KeyPath.Segment], in value: SOML.Value) -> Int {
	var count = 0

	while
		count < path.count,
		value[path: SOML.KeyPath(Array(path.prefix(count + 1)))] != nil
	{
		count += 1
	}

	return count
}

/**
A value to set: a scalar, a container that spans lines, or a part of the document, which may nest too deeply.
*/
private func newValue(for documentValue: SOML.Value, using choices: inout Choices) -> SOML.Value {
	let values: [SOML.Value] = [
		8080,
		-1,
		1.5,
		true,
		.null,
		"text",
		"",
		"it's \"quoted\"\tand\\escaped",
		"two\nlines",
		"ends with a line feed\n",
		.duration(.seconds(5400)),
		[],
		[:],
		[1, "a", [true]],
		["key": 1, "the key": ["nested": [1, 2]], "text": "line\nbreak"],
		documentValue,
		documentValue.value(at: existingPath(in: documentValue, using: &choices)[...]) ?? .null
	]

	return values[Int.random(in: values.indices, using: &choices)]
}

extension SOML.Value {
	/**
	The levels of nesting, as the parser counts them: one for every array and object.
	*/
	fileprivate var depth: Int {
		switch self {
		case .array(let items):
			1 + (items.map(\.depth).max() ?? 0)
		case .object(let object):
			1 + (object.values.map(\.depth).max() ?? 0)
		default:
			0
		}
	}
}

extension SOML.Value {
	/**
	The expected plain JSON value, replacing only instants and durations with strings while preserving every other member and item.
	*/
	fileprivate var plainJSONValue: Self {
		switch self {
		case .instant, .duration:
			.string(description)
		case .array(let items):
			.array(items.map(\.plainJSONValue))
		case .object(let object):
			.object(object.mapValues(\.plainJSONValue))
		case .string, .int, .float, .bool, .null:
			self
		}
	}
}

extension SOML.Document {
	/**
	The text of every comment, in order, as the formatter writes it: without trailing whitespace on a line, and with runs of blank lines in a block comment collapsed to one.

	The trailing whitespace is found on Unicode scalars, because a format character, like U+0600, joins the space after it into one `Character`, which would hide the space from a check on characters.
	*/
	fileprivate var commentTexts: [String] {
		tree.comments.map { comment in
			var lines = [ArraySlice<UInt8>]()

			for line in tree.text[comment.range].split(separator: .lineFeed, omittingEmptySubsequences: false) {
				let line = line[..<((line.lastIndex { !$0.isSpaceOrTab }).map { $0 + 1 } ?? line.startIndex)]

				guard !(line.isEmpty && lines.last?.isEmpty == true) else {
					continue
				}

				lines.append(line)
			}

			return lines.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
		}
	}
}

/**
The choices that the checks make, like which member to set, from the input, so that libFuzzer reaches them by changing it. It is a SplitMix64 generator seeded with the FNV-1a hash of the input.
*/
private struct Choices: RandomNumberGenerator {
	private var state: UInt64 = 0xCBF2_9CE4_8422_2325

	init(_ bytes: [UInt8]) {
		for byte in bytes {
			state = (state ^ UInt64(byte)) &* 0x100_0000_01B3
		}
	}

	mutating func next() -> UInt64 {
		state &+= 0x9E37_79B9_7F4A_7C15
		var mixed = state
		mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
		mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
		return mixed ^ (mixed >> 31)
	}
}

/**
Checks tolerant highlighting on every input, including invalid documents, for ordered nonempty tokens whose boundaries do not split UTF-8 scalars.
*/
private func checkTokens(in text: String) {
	let bytes = Array(text.utf8)
	var previousEnd = 0

	for token in SOML.Token.tokens(in: text) {
		let range = token.range
		precondition(!range.isEmpty && range.lowerBound >= previousEnd && range.upperBound <= bytes.count, "Highlight tokens must be ordered nonempty source ranges")
		precondition(!bytes[range.lowerBound].isUTF8ContinuationByte, "A highlight token starts inside a Unicode scalar")
		precondition(range.upperBound == bytes.count || !bytes[range.upperBound].isUTF8ContinuationByte, "A highlight token ends inside a Unicode scalar")
		previousEnd = range.upperBound
	}
}

# SOML for Swift

> A strict, fast encoder and decoder for [SOML](https://soml.sh), a config format for humans

> [!NOTE]
> The format is a draft.

## Highlights

- `Codable` support with `SOML.Encoder` and `SOML.Decoder`
- A value tree, `SOML.Value`, for documents of unknown shape
- A formatter that keeps comments and the spelling of every value, `SOML.Document`
- Editing of one member or array item, its key, or its end-of-line comment, or through a `Codable` model, that leaves every other byte of the file as it is
- Reading of the comments of a member, like for help text in a settings screen
- Where each member and array item is written in the text, and which one is at an offset, for an editor
- Every rule in the spec is checked: duplicate keys, int64 range, instant and duration ranges, raw control characters, invalid UTF-8, and more
- Passes the language-neutral conformance suite of the reference implementation, including the exact bytes of every canonical form
- Error messages that say what is wrong, where, and how to fix it, with a code frame, and decoding errors that say where the value is
- Optional rejection of unknown keys, so a misspelled key in a config file is reported, with a suggestion
- JSON conversion that keeps the int and float apart, merging of values for layered config, and a list of what changed between two values
- Output that keeps the member order of your types, for a file that people read, or exact canonical form, where the same value always gives the same bytes
- Faster than Foundation’s JSON coders
- No dependencies

## Requirements

Swift 6.3+, macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+, Linux

## Install

Add the following to `Package.swift`:

```swift
.package(url: "https://github.com/soml-lang/SOMLSwift", from: "0.0.0")
```

Or add `https://github.com/soml-lang/SOMLSwift` in the [“Swift Package Manager” tab in Xcode](https://developer.apple.com/documentation/xcode/adding_package_dependencies_to_your_app).

## Usage

### Decode

```swift
import Foundation
import SOML

struct Config: Codable {
	let name: String
	let replicas: Int
	let timeout: Double
	let deployedAt: Date
	let labels: [String]
	let postgres: Postgres

	struct Postgres: Codable {
		let host: String
		let port: Int
	}
}

let text = """
	# The edge service.
	name: 'api-gateway'
	replicas: 3
	timeout: 30.0
	deployed-at: 2026-09-19T14:00:00Z
	labels: ['prod', 'eu-west']
	postgres: {
		host: 'db.internal'
		port: 5432
	}
	"""

var decoder = SOML.Decoder()
decoder.keyDecodingStrategy = .convertFromKebabCase

let config = try decoder.decode(Config.self, from: text)
```

#### Defaults

Codable has no default values: a missing key is an error unless the property is optional. Pass `defaults`, and every member that the document leaves out comes from it, so a config file only needs the settings that differ:

```swift
struct Settings: Codable {
	var host = "localhost"
	var port = 80
}

let settings = try SOML.Decoder().decode(from: "port: 8080", defaults: Settings())
//=> Settings(host: "localhost", port: 8080)
```

The document is merged over the encoded defaults with `merging(_:)`, so objects merge member by member, and an array in the document replaces the default one.

### Encode

```swift
var encoder = SOML.Encoder()
encoder.keyEncodingStrategy = .convertToKebabCase

let text = try encoder.encodeToString(config)
let data = try encoder.encode(config)
```

The output follows every rule of canonical form (one entry per line, tab indentation, no commas, and no comments) except one: members keep their order, because sorted keys put `description` before `name` and are noise to a person who reads the file.

- A type writes its members in the order it encodes them, which for a synthesized `Codable` conformance is the order the properties are declared in.
- A `Dictionary` writes its members in its iteration order, as `JSONEncoder` does without `.sortedKeys`, so the order can change from one run to the next.
- A `SOML.Value` or `SOML.Object` writes its members in the order they were added, which for a parsed document is the order in the source.

Set `writesCanonicalForm` for exact canonical form, with the members of every object sorted by key, so that the same value always gives the same bytes, like for a hash, or for a stable order of a `Dictionary`. It does not sort arrays, so a `Set` is still written in its iteration order, which can change from one run to the next. Sort it into an array first if you need the same bytes:

```swift
var encoder = SOML.Encoder()
encoder.writesCanonicalForm = true
```

### Work with values

```swift
var value = try SOML.Value(parsing: text)

value["postgres"]?["port"]?.intValue
//=> 5432

value["labels"]?[0]?.stringValue
//=> "prod"
```

The subscripts also change a value in place. Setting `nil` removes a member or an item:

```swift
value["postgres"]?["port"] = 6543
value["labels"]?[1] = nil
```

`subscript(path:)` does the same with a key path, which an array literal writes:

```swift
value[path: ["postgres", "port"]]
//=> .int(6543)
```

`SOML.Value` has a case for each type in the spec: `string`, `int` (`Int64`), `float` (`Double`), `bool`, `null`, `instant`, `duration` (`Duration`), `array`, and `object`. It conforms to the literal protocols, so you can write values directly:

```swift
let value: SOML.Value = [
	"name": "api-gateway",
	"replicas": 3,
	"labels": ["prod"],
]
```

A `SOML.Value` can also be a property of a `Codable` type, for a part of a document with no fixed shape.

`SOML.Object` also has `contains(key:)`, `updateValue(_:forKey:)`, `reserveCapacity(_:)`, `removeAll(keepingCapacity:)`, `mapValues(_:)`, and `filter(_:)`. Transforming and filtering return objects that preserve member order and scalar-distinct keys. The default-value subscript supports nested mutation without making a temporary object:

```swift
var object = SOML.Object()
object["server", default: [:]]["port"] = 8080
```

### Merge

`merging(_:)` merges two values for layered config, like defaults and then a user file. Objects merge member by member, and any other value, including an array, replaces the one before it:

```swift
let defaults = try SOML.Value(parsing: "server: {host: 'localhost', port: 80}\nlabels: ['default']")
let user = try SOML.Value(parsing: "server: {port: 8080}\nlabels: ['prod']")

let config = defaults.merging(user)
//=> ["server": ["host": "localhost", "port": 8080], "labels": ["prod"]]
```

### Differences

`differences(from:)` lists what changed between two values, member by member and item by item, like to log what changed when a config file is read again:

```swift
let old = try SOML.Value(parsing: "port: 80\nhosts: ['a', 'b']\ndebug: true")
let new = try SOML.Value(parsing: "port: 8080\nhosts: ['a']\nname: 'api'")

for difference in new.differences(from: old) ?? [] {
	switch difference {
	case .added(let value, let path):
		print("Added \(path): \(value)")
	case .removed(_, let path):
		print("Removed \(path)")
	case .changed(let oldValue, let newValue, let path):
		print("Changed \(path) from \(oldValue) to \(newValue)")
	}
}
//=> Changed port from 80 to 8080
//=> Removed hosts[1]
//=> Removed debug
//=> Added name: 'api'
```

- Objects are compared by key, so the member order does not matter. Arrays are compared by index, so an item inserted at the start changes every item after it.
- It is `nil` when the two values differ and are not both objects or both arrays, because then the whole value changed, which has no key path.
- The differences are in an order in which `setting(_:at:)` and `removing(at:)` can apply them to a `SOML.Document`, one by one.

Apply differences to a document with `document.applying(differences)`. The edits follow the setting and removal rules below. A difference exposes `oldValue` and `newValue`, with `nil` for an absent member or item, and `.null` for a SOML null. To undo differences returned by `differences(from:)`, apply `differences.reversed().map(\.inverted)` to the matching edited document. This restores values; editing may change their spelling or layout.

To only check whether two configs are the same, compare the values with `==`, which ignores the member order. Their canonical forms, from `canonicalDocument()` or `writesCanonicalForm`, are also equal exactly when the values are, so a hash of the canonical form identifies a config.

### JSON

`SOML.Value(parsingJSON:)` reads JSON, and `jsonText()` writes it. Unlike `JSONSerialization`, they keep the int and float apart, so `1` is an int and `1.0` a float, an int keeps every digit, and members keep their order:

```swift
let value = try SOML.Value(parsingJSON: #"{"port": 8080, "ratio": 1.0}"#)

print(try value.jsonText())
//=> {
//=> 	"port": 8080,
//=> 	"ratio": 1.0
//=> }
```

- A string stays a string, also when it looks like an instant or a duration, because SOML never types a value by its content. An instant or a duration is written as its canonical text, like `"1h30m"`.
- What SOML cannot hold is an error with a line and column: an int outside the 64-bit range, a float that rounds to infinity or to zero, a duplicate key, a lone surrogate, a carriage return, and nesting deeper than 100 levels. Infinity and NaN cannot be written, because JSON has no number for them.
- With `format: .tagged`, both use the tagged JSON of the conformance suite, where every scalar is `{"type": …, "value": …}`, so infinity can be written, as the text `infinity`.

### Single values and key paths

`SOML.Value(parsingValue:)` reads one value with nothing around it, such as a command-line argument, and `SOML.KeyPath` reads a key path of keys joined with `.`, each written as a SOML key, with an array index in brackets where one is needed. A key that contains a `.` is quoted, like `'example.com'.port`. Both report a position in the text when it is not valid.

```swift
try SOML.Value(parsingValue: "0o644")
//=> .int(420)

let path = try SOML.KeyPath(parsing: "servers[0].'the name'")

path.segments
//=> [.key("servers"), .index(0), .key("the name")]

path.description
//=> "servers[0].'the name'"
```

A key path's `description` is its canonical spelling, so `SOML.KeyPath(["the name"]).description` is `'the name'`, quoted because the key has a space, and `SOML.KeyPath(["example.com", "port"]).description` is `'example.com'.port`, quoted because the key has a dot. An index is always in brackets, because `servers.0` is the key `0`, which SOML allows. In code, a string literal is a key and an integer literal is an index: `SOML.KeyPath(["servers", 0, "host"])`.

A key path is a random-access collection of its segments. `parent` gives the enclosing path, or `nil` when its parent is the document. `appending(_:)` accepts a segment or another path, and `hasPrefix(_:)` compares segments using SOML's exact key semantics:

```swift
let server: SOML.KeyPath = ["servers", 0]
let port = server.appending("port")
//=> servers[0].port
```

### Canonical form

`canonicalDocument()` writes a value as a document in canonical form, with the members sorted by key, the same text `SOML.Encoder` writes for it with `writesCanonicalForm`. It throws `SOML.InvalidValueError` with a plain message when SOML cannot represent the value:

```swift
let value: SOML.Value = ["limits": ["ratio": .float(.nan)]]

do {
	print(try value.canonicalDocument())
} catch {
	print(error)
	//=> NaN is not a SOML value (at limits.ratio)
}
```

### Format

`SOML.Document` keeps the text of a document, and `formatted()` normalizes its layout as the spec's formatter defines it. Comments, member order, block strings, and the spelling of every value stay as you wrote them. An object or an array whose brackets are on one line stays on one line, like `pool` below, and one with a line break anywhere inside it gets one member or item per line, like `labels`. The output is the same as `format()` in the JavaScript reference implementation, byte for byte.

```swift
let document = try SOML.Document(parsing: """
	# The edge service.
	name:   'api-gateway'   # Shown in the dashboard.
	labels: ['prod',
	    'eu-west']



	postgres: {host: 'db.internal'}
	pool: {min: 2, max: 0x10 , idle: 90m} # Connections
	""")

print(document.formatted())
```

```
# The edge service.
name: 'api-gateway' # Shown in the dashboard.
labels: [
	'prod'
	'eu-west'
]

postgres: {host: 'db.internal'}
pool: {min: 2, max: 0x10, idle: 90m} # Connections
```

`document.value` is the value of the document, the same as `SOML.Value(parsing:)` gives.

Pass `document.formatted(expandingContainers: true)` to expand every nonempty object and array onto separate lines without commas. Empty containers without comments remain compact. The default keeps the original single-line containers.

### Edit

`setting(_:at:)` and `removing(at:)` return a copy of a `SOML.Document` with one member changed, and every other byte as it was, so a tool can update a config file and keep the author's comments and layout. `text` is the source text of the result.

```swift
let document = try SOML.Document(parsing: """
	# The edge service.
	name: 'api'
	port: 0x1F90 # The default.
	""")

let edited = try document
	.setting(8080, at: SOML.KeyPath(["port"]))
	.setting(["a", "b"], at: SOML.KeyPath(parsing: "tls.hosts"))
	.removing(at: SOML.KeyPath(["name"]))

print(edited.text)
```

```
# The edge service.
port: 8080 # The default.
tls: {
	hosts: [
		'a'
		'b'
	]
}
```

- A new value is written in the spelling and layout of canonical form, without block strings, so `0x1F90` set to 8080 becomes `8080`. The members of an object keep their order. A value that spans lines is indented to fit its line. In an object or an array on one line, the value is written on one line too, so `{a: 1}` with a new member `b: [2, 3]` becomes `{a: 1, b: [2, 3]}`.
- A new member goes at the end of its object, and the objects that do not exist yet are written with braces, like `tls` above.
- It goes after the comments that the member before it owns (see below), so before a comment on a line of its own. When something follows the member before it on its line, like the `}` in `{a: 1}`, the new member goes on that line after a comma. Otherwise it goes on its own line with no comma, and the commas of the others stay, so run the formatter if you want them gone. In an object with no members, it goes on a line of its own, unless the object stays on one line: its braces are on one line with a comment between them, as in `{/* note */}`, or it is inside an object or an array on one line, so `a: [1, {}]` becomes `a: [1, {b: 2}]`.
- A removed member takes the comments that it owns, which are the ones that the formatter keeps with it: the comments after it on its line, before its comma, or after its comma when nothing else follows on that line, and the block comments before it on its line, back to the comma or bracket before it. So removing `b` from `{a: 1, /* note */ b: 2}` gives `{a: 1}`. A comment on a line of its own belongs to no member, so it stays.
- A removed member takes its comma, and its line when nothing else is on it. When the removed members are the last ones and have no comma after them, they take the comma directly before them instead, when only spaces, tabs, and the comments they own are between, so `{a: 1, b: 2}` becomes `{a: 1}`. Every other comma stays. A blank line that would be left next to another one, directly inside a bracket, or at the start or end of the document goes too. Removing the only member of a document without braces leaves `{}`, and keeps the comments that the removed member owned, so `a: 1 # note` without `a` gives `{} # note`. Removing every member of an object closes it up to `{}`, unless a comment is left inside, like one on a line of its own or one after the `{` on its line.
- Removing a value that does not exist changes nothing and is not an error: a missing member, a missing object or array on the way, or an index at or past the end of its array. So removing the same path twice is safe, and `document.removing(at: path).text == document.text` tells that nothing was removed.
- Each change reads the result back and checks its value. It throws `SOML.EditError` when the path goes through a value that is not an object or an array, when the value cannot be written, like NaN, or when the result would not be valid, like one nested too deeply.

#### Through a model

`updating(as:_:)` changes a document through a `Codable` model of it, so the compiler checks the names and the types. The difference between the model before and after the change becomes the same kind of edits, so the comments and the spelling of every value that did not change stay:

```swift
struct Service: Codable {
	var name: String
	var port: Int
}

let service = try SOML.Document(parsing: "name: 'api' # The service\nport: 0x50\n")

let updated = try service.updating(as: Service.self) {
	$0.port = 8080
}

print(updated.text)
//=> name: 'api' # The service
//=> port: 8080
```

A member the model does not read stays as it is. Pass a decoder and an encoder with the key strategies the document uses.

#### Array items, values as typed, keys, and comments

A path can name an array item, like `servers[0]`. `setting(valueText:at:)` writes a value exactly as typed, like `0o644`, for a tool that takes values from a person. `renamingKey(at:to:)` changes a member's key, and `settingComment(_:at:)` sets or removes the `#` comment at the end of a member's or an item's line.

```swift
let document = try SOML.Document(parsing: """
	servers: [
		{host: 'a'}, # Primary
		{host: 'b'},
	]
	mode: 420
	""")

let edited = try document
	.setting("c", at: SOML.KeyPath(parsing: "servers[1].host"))
	.setting(["host": "d"], at: SOML.KeyPath(parsing: "servers[2]"))
	.removing(at: SOML.KeyPath(parsing: "servers[0]"))
	.setting(valueText: "0o644", at: SOML.KeyPath(["mode"]))
	.renamingKey(at: SOML.KeyPath(["mode"]), to: "permissions")
	.settingComment("Owner can write", at: SOML.KeyPath(["permissions"]))

print(edited.text)
```

```
servers: [
	{host: 'c'},
	{
		host: 'd'
	}
]
permissions: 0o644 # Owner can write
```

- An index that is the number of items, like `servers[2]` above, adds an item at the end. Setting at an index past that is an error, and so are a key where an array is and an index where an object is. Removing at an index at or past the end changes nothing.
- A removed item takes the comments it owns, its comma, and its line when nothing else is on it, like a member, so `[1, 2]` and `[1, /* note */ 2]` without `2` become `[1]`. Removing the last item leaves `[]`, unless a comment is left inside, as for an object. A new item goes after the comments that the item before it owns, so `[1, 2 /* note */]` with a new item becomes `[1, 2 /* note */, 3]`.
- A value as typed is checked to be one SOML value, and is not indented to fit its line, so run the formatter after it if a multi-line array or object should line up. A block string is placed and indented as the formatter does it: as a member's value on the line after its key, one level deeper, and as an array item on the item's line.
- A renamed key is written in canonical form, so a key that contains a `.` is quoted. A key that already exists is an error.
- A comment goes at the end of the line where the member or item ends, after its comma if it has one, and replaces a `#` comment there. It is an error when something else follows on that line, like the next member in `{a: 1, b: 2}`, and when the comment has a line break. A comment on its own line above a member cannot be changed this way.

#### Read comments

`comments(at:)` gives the comments of a member or an array item, so a settings screen can show the comments in a config file as help text:

```swift
let document = try SOML.Document(parsing: """
	# How long to wait for the server.
	# Use 0s for no limit.
	timeout: 30s # The default
	""")

let comments = document.comments(at: ["timeout"])

comments?.leading
//=> ["How long to wait for the server.", "Use 0s for no limit."]

comments?.trailing
//=> "The default"
```

- `leading` is the comments directly above the member or item, up to a blank line or a line with something else on it, and a `/* */` comment in front of it on its line. A comment after the member before it on its line, or after an opening bracket on its line, belongs to that line, not to this member, like `/* a */` in `[1, /* a */ 2]`.
- `trailing` is the `#` comment at the end of the line where the member or item ends, which is the one that `settingComment(_:at:)` changes.
- The text is without the `#` or `/* */`, and without the one space after the `#` or `/*` and before the `*/`.
- It is `nil` when nothing is at the path.

#### Moving siblings

`document.swapping(["first"], with: ["second"])` swaps two members or array items in the same container. Their spelling, directly attached comments, and the separator before each, like a blank line, travel with them, so a group of lines stays together. The first member or item has no separator before it, so it takes the separator of the one that takes its place. Comments after a comma are part of the separator that follows. The result is parsed and checked for value preservation. Missing paths, different parents, and moves with ambiguous comment ownership or invalid resulting syntax throw `SOML.EditError`.

`document.reordering([["host"], ["name"], ["port"]])` puts every member or item of one container in a new order, like to move one or more items to another position, or to sort the keys of an object without losing its comments. The paths are all the members or items of that container, each once, in the new order. The rules for spelling, comments, and separators are those of `swapping(_:with:)`, and the members or items that stay in place keep their bytes.

#### Tolerant tokenization

`SOML.Token.tokens(in: text)` tokenizes incomplete source without throwing. Tokens expose a `kind` and a range of UTF-8 byte offsets. Whitespace is omitted; escape sequences have separate tokens. Tokenization supports editor highlighting and does not replace validation with the parser.

`SOML.lexicalContext(in: text, atUTF8Offset: offset)` classifies an insertion point as `.code`, `.comment`, or `.string(delimiter:closingDelimiterRange:)`, including quoted keys and unfinished strings. The closing delimiter range is `nil` for an unfinished string. Positions at an opening delimiter are outside the token; positions at its closing delimiter are inside. Offsets outside the source return `nil`. Like every source range in the library, these ranges use UTF-8; native text editors must translate their UTF-16 selections at the boundary.

#### Source ranges

`range(of:)` gives where a member or an array item is written, from the start of its key to the end of its value, and `valueRange(of:)` gives where its value is written. `path(atOffset:)` gives the deepest member or item at a byte offset, like the caret in an editor:

```swift
let document = try SOML.Document(parsing: """
	name: 'api'
	server: {host: 'a', port: 0x50} # Connections
	""")

document.range(of: ["server", "port"])
//=> line 2, column 21..<line 2, column 31

document.valueRange(of: ["server", "port"])
//=> line 2, column 27..<line 2, column 31

document.path(atOffset: 40)
//=> server.port
```

- A range is between `SOML.Location`s, and the end is the location after the last character of the value, so a comment or a comma after it is not in the range.
- A value range is the text a person wrote for the value, so a tool can show `0x50` as written. A block string runs from its opening delimiter to its closing one, and an object or an array from its opening bracket to its closing one.
- Both are `nil` when nothing is at the path.
- `path(atOffset:)` takes an offset in the UTF-8 bytes of the text, as `SOML.Location.offset` is. An offset at the end of a member or item belongs to it, so a caret directly after a value is on that value. An offset in a comment or white space inside an object or an array gives the member or item that holds it, and one outside the members or items of the document gives `nil`.

### Errors

A document that is not valid SOML throws `SOML.ParseError`, with a message and a `SOML.Location`: the line, the column, and the byte offset. For a document that is not valid, the message matches the `reason` of the JavaScript reference implementation, except that character names come from Swift’s Unicode properties and can differ.

```swift
do {
	_ = try SOML.Value(parsing: "a: 1\na: 2")
} catch {
	print(error)
	//=> Duplicate key a (line 2, column 1)
}
```

`codeFrame` shows where the problem is, in the same format as the JavaScript reference implementation:

```swift
print(error.codeFrame)
//=>   1 | a: 1
//=> > 2 | a: 2
//=>     | ^
```

`SOML.Decoder` wraps the parse error in `DecodingError.dataCorrupted`, with the `SOML.ParseError` as the underlying error, like `JSONDecoder` does.

### Location of a decoding error

When `SOML.Decoder` decodes text, a `DecodingError` about a value ends with where that value is, like `Expected an int for Int, but found the string 'eighty' (line 3, column 1)`.

For the location as a value, parse the text as a `SOML.Document`, decode its `value`, and ask the document where the coding path is:

```swift
let document = try SOML.Document(parsing: text)
var decoder = SOML.Decoder()
decoder.keyDecodingStrategy = .convertFromKebabCase

do {
	_ = try decoder.decode(Config.self, from: document.value)
} catch let DecodingError.typeMismatch(_, context) {
	let location = document.location(of: context.codingPath, keyDecodingStrategy: decoder.keyDecodingStrategy)
	print("The value at \(location) has the wrong type.")
}
```

The location is the start of the key of a member, or the start of an array item. For a missing key, it is the closest member that the document has. Pass the decoder's key strategy, so that the coding keys are converted to the document's spelling as the decoder converted them. `location(of:)` also takes a key path, like `["servers", 0, "host"]`.

### Errors of your own checks

A check that your app makes after it decodes, like a port that is reserved, can point at the value in the file too. `error(_:at:)` gives a `SOML.ParseError` with the location and the code frame of the member or item at a key path:

```swift
struct Config: Decodable {
	struct Server: Decodable {
		var host: String
		var port: Int
	}

	var server: Server
}

let document = try SOML.Document(parsing: """
	server: {
		host: 'localhost'
		port: 0
	}
	""")

let config = try SOML.Decoder().decode(Config.self, from: document.value)

if config.server.port == 0 {
	throw document.error("Port 0 is reserved", at: ["server", "port"])
}
// Throws: Port 0 is reserved (line 3, column 2)
```

Its `codeFrame` shows the line:

```
  1 | server: {
  2 | 	host: 'localhost'
> 3 | 	port: 0
    | 	^
```

### Unknown keys

By default, a member that the type does not read is ignored, as with `JSONDecoder`. So a misspelled key in a config file is silently lost. Set `rejectsUnknownKeys` to make it an error:

```swift
struct Options: Decodable {
	var timeout: Double?
}

var decoder = SOML.Decoder()
decoder.rejectsUnknownKeys = true

let options = try decoder.decode(Options.self, from: "timout: 30.0")
// Throws: Unknown key timout, which Options does not read. Did you mean timeout? (line 1, column 1)
```

A misspelled required key fails with or without the option, and the error names the close key that the document has: `No member with the key replicas. The document has replcas. Is it misspelled?` With a key strategy, the hint can name a key that the type reads, when that key does not convert back to its coding key, like `base-url` for `baseURL`.

A type that reads `allKeys`, like `[String: T]` or an enum with associated values, decides about the keys itself, so its own object is not checked. A `SOML.Value` property takes any members.

A type that throws does not look up the keys after the error. So when a type catches the error and goes on without the member, like a `try?` that gives `nil`, the members that the failed type did not get to are reported as unknown. Decoding the member as `SOML.Value` when the attempt fails takes any members of its object, but an object inside it that the failed type began to read is still checked.

With `defaults`, the check is of the document merged over the encoded defaults. So a member that the type encodes but does not decode, like a `let` constant with an initial value, is reported as unknown even though the document does not have it.

### File type

`UTType.soml` is the type of a SOML file, `com.sindresorhus.soml`. Use it to open and save SOML files:

```swift
import SwiftUI
import SOML

struct ContentView: View {
	@State private var isImporting = false

	var body: some View {
		Button("Open") {
			isImporting = true
		}
		.fileImporter(isPresented: $isImporting, allowedContentTypes: [.soml]) { result in
			// …
		}
	}
}
```

A package cannot declare a type, so your app must declare it in its `Info.plist`. Without the declaration, the identifier works, but the type is not linked to the `.soml` extension and does not conform to `.utf8PlainText`.

```xml
<key>UTImportedTypeDeclarations</key>
<array>
	<dict>
		<key>UTTypeIdentifier</key>
		<string>com.sindresorhus.soml</string>
		<key>UTTypeDescription</key>
		<string>SOML Document</string>
		<key>UTTypeConformsTo</key>
		<array>
			<string>public.utf8-plain-text</string>
		</array>
		<key>UTTypeTagSpecification</key>
		<dict>
			<key>public.filename-extension</key>
			<array>
				<string>soml</string>
			</array>
			<key>public.mime-type</key>
			<string>application/soml</string>
		</dict>
	</dict>
</array>
```

To show your app in the Open With menu for `.soml` files, also add a `CFBundleDocumentTypes` entry whose `LSItemContentTypes` contains `com.sindresorhus.soml`.

## Type mapping

- `String` → string. A carriage return cannot be encoded, because SOML cannot represent one.
- `Bool` → bool
- `Int`, `Int8`…`Int64`, `UInt`…`UInt64` → int, range-checked in both directions
- `Double`, `Float`, `Float16` → float. Decoding also accepts an int that converts exactly. NaN cannot be encoded.
- `Optional` → `null`
- `Date` → instant, with the fewest fractional digits that read back as the same `Date`, so `Date(timeIntervalSince1970: 0.1)` is written `.1`
- `SOML.Instant` → instant, exact, with nanosecond precision
- `Duration` → duration, exact, with nanosecond precision, so `.seconds(5400)` is written `1h30m` and `.milliseconds(1500)` is written `1.5s`. A `Duration` that SOML cannot hold cannot be encoded, and `exactNanoseconds` is `nil` for one.
- `URL` → string
- `Data` → base64 string
- `[String: T]` → object. A key strategy does not change dictionary keys, when the dictionary is a property or an element.
- `SOML.Value`, `SOML.Object` → any value, unchanged

Types are strict, as the spec intends. A float never decodes into an integer type, an int never decodes into a `String`, a string never decodes into a number, and only a duration decodes into a `Duration`.

## File format

Documents follow the [SOML specification](https://github.com/soml-lang/soml/blob/main/spec.md), v0.1.

- File extension: `.soml`
- Encoding: UTF-8 without a byte order mark, with LF line endings
- Media type: `application/soml`
- Uniform type identifier: `com.sindresorhus.soml` (`UTType.soml`)

## Performance

The shared [benchmark fixtures](https://github.com/soml-lang/soml/tree/main/benchmark), each in SOML, JSON, and TOML with the same data, against Foundation (`JSONSerialization` for a value, and `JSONDecoder` and `JSONEncoder` for a struct) and [TOMLDecoder](https://github.com/dduan/TOMLDecoder), the most used TOML package, which only reads. The table reports median total CPU time per document, using the median result from three runs on October 16, 2026, in a release build with Apple Swift 6.4 on an Apple M4 Pro with 48 GB of memory. Write timings exclude parsing or decoding the input. CPU time excludes scheduling delays from other processes. The machine was busy with other work, so the numbers are approximate. The benchmark is in [`Benchmarks`](Benchmarks).

| | SOMLSwift | Foundation | TOMLDecoder |
| --- | --- | --- | --- |
| Read `service` (3 KB) into a value | 17 µs | 19 µs | 9.5 µs¹ |
| Read `platform` (35 KB) into a value | 110 µs | 110 µs | 71 µs¹ |
| Read `earthquakes` (733 KB) into a value | 3.5 ms | 3.7 ms | 1.6 ms¹ |
| Read `earthquakes` into a `Codable` struct | 7.0 ms | 8.4 ms | 28 ms |
| Write `service` from a value | 9.7 µs | 17 µs |  |
| Write `platform` from a value | 53 µs | 88 µs |  |
| Write `earthquakes` from a value | 1.8 ms | 4.4 ms |  |
| Write `earthquakes` from a `Codable` struct | 7.0 ms | 7.4 ms |  |

¹ TOMLDecoder's value, `TOMLTable`, keeps a scalar as text until it is read, so it does less work than the others.

The struct-writing benchmark uses Foundation’s `.iso8601` date encoding, which omits fractional seconds; SOML preserves them.

To reproduce the CPU-time measurements:

```sh
cd Benchmarks
swift package benchmark --metric cpuTotal
```

## Untrusted input

Reading is safe for hostile input. Nesting is limited to 100 levels, so no document can overflow the stack. Time grows linearly with the size of the text for every input shape, and an error message shortens a long token instead of repeating it. Decoding into Swift types is the exception: Swift's own `String` hashing and comparison, which a `[String: T]` and synthesized coding keys use, take quadratic time for a key with a long run of combining marks, as with `JSONDecoder`.

Memory is what to watch. A typical document of records takes about 6 times its size while it is parsed, and twice that as a `SOML.Document`, but hostile shapes take much more: an array of a million `1`s about 45 times as a `SOML.Value`. Limit the size of untrusted text before you parse it.

## Limitations

- When you decode into Swift types, keys are compared with Swift's `String` equality, which treats canonically equivalent strings as equal. So two keys that differ only in Unicode normalization collide in a `[String: T]`. `SOML.Value` and `SOML.Object` compare keys by Unicode scalars, as the spec requires.
- `Decimal` has no special case, so it uses its own `Codable` implementation.
- `Date` stores a `Double`, so it cannot hold every nanosecond. An instant read into a `Date` can be off by a fraction of a microsecond near 2001, but by up to about 15 microseconds in the year 9999, and about 30 at the very end of the range, and a `Date` before 0001-01-01T00:00:00Z, or one that rounds past 9999-12-31T23:59:59.999999999Z, cannot be encoded. Use `SOML.Instant` for exact instants.
- A SOML duration is a count of nanoseconds in the int64 range, about 292 years either way. `Duration` holds attoseconds and a much larger range, so encoding a `Duration` with a fraction of a nanosecond, or outside that range, throws instead of rounding.
- `SOML.Value` encodes a duration for other encoders, such as `JSONEncoder`, as its canonical text, like the string `1h30m`. A `Duration` property encoded with them uses `Duration`'s own encoding, which is two integers.
- `SOML.Encoder` recognizes a `Duration` only when it is encoded through a container, with `encode(_:)`, `encode(_:forKey:)`, or `encodeIfPresent(_:forKey:)`. A type that calls `Duration.encode(to:)` directly with the encoder or a `superEncoder()` gets `Duration`'s own two integers, as with `Date`.
- With a key strategy, two coding keys that convert to the same key, like `userID` and `userId`, write one member, and the last one wins, as with `JSONEncoder`. A type that reads `allKeys`, such as an enum with associated values, sees the keys converted back to camelCase, which is lossy: `base-url` becomes `baseUrl`, so a case named `baseURL` is not found, and a document key that does not convert back to itself, like `item-1` or `Content-Type`, cannot be decoded with the key that `allKeys` gives for it. An encoding error inside a `SOML.Value` or `SOML.Object` property, like NaN or a carriage return, has the keys that the strategy writes in its coding path, rather than the coding keys of the type, because the encoder takes such a value as it is and only the writer checks it.
- `decode(_:from:defaults:)` merges objects member by member. An enum without raw values encodes as an object with one key, the case, so a document that sets another case merges with the default case, and the result does not decode. Give such an enum a `String` raw value. For the same reason, a document cannot remove an entry from a default dictionary.
- A type that encodes an object or an array for a key, and then asks for a nested container of the same kind for the same key, like a subclass and its superclass, writes into the same object or array. This also preserves the contents of a `SOML.Value` or `SOML.Object` member, or a `[String: T]` member under a key strategy. `JSONEncoder` does the same for an object, and traps for an array.
- Nesting is limited to 100 levels, as the spec requires. The top-level object counts as a level with or without its braces.
- Differences from the reference implementation, in places the spec leaves open: removing an item on the line of a bracket, in a layout that the formatter never writes, as in `a: [\n\t1\n\n\t2]`, also removes a blank line that would be left directly inside the bracket, as the Edit section says, where the reference implementation keeps it. And the code frame of invalid UTF-8 shows the rest of the line, with U+FFFD for the invalid bytes, where the reference implementation shows the line up to them. Character descriptions use Swift’s native Unicode names, so their wording can differ from the reference’s selective names.

Apart from these differences, where the spec leaves a choice open, this package does what the JavaScript reference implementation does.

## Development

```sh
swift test
```

The conformance suite in [`Tests/conformance`](Tests/conformance) is a copy of the one in the JavaScript reference implementation, [soml-javascript](https://github.com/soml-lang/soml-javascript). Some tests read the examples in the spec repository, which must be checked out next to this one, as `soml`. Without it, they are skipped, as in CI, which runs the tests on macOS and on Linux.

A differential test runs `soml-javascript` on mutated versions of every valid conformance document, through the `node` on the `PATH`, which must be Node.js 26 or later, and requires the same result from both implementations: the same acceptance, the same error line and column, the same canonical form, and the same formatted form. It needs `soml-javacript` checked out next to this repository, and is skipped without it.

### Fuzzing

[`Fuzz`](Fuzz) is a libFuzzer target in its own package, so the library gets no new target. For every input, it checks that parsing does not crash, and for a valid document, that the canonical form reads back as the same value, that the formatter keeps the value and the comments and is stable, that `setting(_:at:)`, `setting(valueText:at:)`, `removing(at:)`, `renamingKey(at:to:)`, and applying `differences(from:)` at paths that the input picks give the expected value, that a comment set with `settingComment(_:at:)` reads back through `comments(at:)` and goes again when removed, and that the text of `valueRange(of:)` reads back as the value at the path, where `path(atOffset:)` leads back to it.

Xcode's toolchain has no libFuzzer runtime, but the [swift.org toolchain](https://www.swift.org/install/macos/) for macOS has one. Install it for your user, and build from the `Fuzz` folder:

```sh
installer -pkg swift-6.4.0-RELEASE-osx.pkg -target CurrentUserHomeDirectory
cd Fuzz
TOOLCHAINS=swift swift build -c release -Xswiftc -sanitize=fuzzer,address -Xswiftc -enable-testing -Xswiftc -parse-as-library
```

Run it with the conformance suite as the seed corpus. libFuzzer reads it recursively, and writes the new inputs to the first folder:

```sh
mkdir -p /tmp/soml-fuzz/corpus /tmp/soml-fuzz/artifacts
.build/release/SOMLFuzz -fork=8 -dict=soml.dict -max_len=4096 -artifact_prefix=/tmp/soml-fuzz/artifacts/ /tmp/soml-fuzz/corpus ../Tests/conformance
```

Runs of about 40 minutes in all, with 8 processes and about 19 million inputs, found nothing.

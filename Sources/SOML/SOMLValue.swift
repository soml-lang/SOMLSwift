#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

extension SOML {
	/**
	A SOML value.

	This is the SOML data model: JSON's model, with separate int and float types, and instant and duration types.

	```swift
	let value = try SOML.Value(parsing: """
		name: 'api-gateway'
		replicas: 3
		""")

	print(value["replicas"]?.intValue)
	//=> Optional(3)
	```

	Equality follows the spec:

	- Strings are compared by their Unicode scalars, with no normalisation.
	- Object member order does not matter.
	- `0.0` and `-0.0` are the same value.
	- `.int(1)` and `.float(1.0)` are different values.

	NaN is not a SOML value. The parser never produces one and the encoder refuses one. A `.float(.nan)` you create yourself is not equal to itself, as in IEEE 754, so do not put one in a `Set` or use it as a dictionary key.
	*/
	public enum Value: Sendable {
		/**
		A string. A string with a carriage return cannot be written, because SOML cannot represent one.
		*/
		case string(String)

		/**
		An int, which SOML limits to the int64 range.
		*/
		case int(Int64)

		/**
		A float, which can be infinite. NaN is not a SOML value, so it cannot be written.
		*/
		case float(Double)

		/**
		`true` or `false`.
		*/
		case bool(Bool)

		/**
		`null`.
		*/
		case null

		/**
		An instant, with nanosecond precision.
		*/
		case instant(SOML.Instant)

		/**
		A duration. SOML holds a whole number of nanoseconds in the int64 range, so a `Duration` with a fraction of a nanosecond, or outside that range, cannot be written.
		*/
		case duration(Duration)

		/**
		An array, whose items can be of different types.
		*/
		case array([SOML.Value])

		/**
		An object.
		*/
		case object(SOML.Object)
	}
}

extension SOML.Value {
	/**
	Parses a SOML document.

	A document is an object or an array. Comments are removed.

	- Throws: `SOML.ParseError` if the text is not a valid SOML document.
	*/
	public init(parsing text: String) throws(SOML.ParseError) {
		self = try Parser.parseDocument(Array(text.utf8))
	}

	/**
	Parses a SOML document from UTF-8 bytes.

	- Throws: `SOML.ParseError` if the bytes are not a valid SOML document, including when they are not valid UTF-8.
	*/
	public init(parsing bytes: some Sequence<UInt8>) throws(SOML.ParseError) {
		self = try Parser.parseDocument(Array(bytes))
	}

	/**
	Parses one value written as it would appear after a key, like `0o644`, `'text'`, `1h30m`, or `[1, 2]`, with nothing else around it: no whitespace, no comment, and no second value.

	Unlike a document, the value can be a scalar.

	```swift
	try SOML.Value(parsingValue: "0o644")
	//=> .int(420)
	```

	- Throws: `SOML.ParseError` if the text is not one SOML value, with a position in the text.
	*/
	public init(parsingValue text: String) throws(SOML.ParseError) {
		self = try Parser.parseValue(Array(text.utf8))
	}

	/**
	The value with `other` merged into it, for layered config, like defaults and then a user file.

	- Two objects merge member by member, recursively. A member in both keeps its position and gets the merged value, and a member only in `other` is added at the end.
	- Any other pair, including two arrays, gives `other`, so a list in a user file replaces the default list instead of adding to it. A `null` in `other` is a value too, so it replaces.

	```swift
	let defaults = try SOML.Value(parsing: "server: {host: 'localhost', port: 80}\nlabels: ['default']")
	let user = try SOML.Value(parsing: "server: {port: 8080}\nlabels: ['prod']")

	defaults.merging(user)
	//=> ["server": ["host": "localhost", "port": 8080], "labels": ["prod"]]
	```
	*/
	public func merging(_ other: Self) -> Self {
		guard
			case .object(let object) = self,
			case .object(let otherObject) = other
		else {
			return other
		}

		return .object(object.merging(otherObject))
	}

	/**
	The value as a document in canonical form, the same text `SOML.Encoder` writes for it with `writesCanonicalForm`: members sorted by key, one entry per line, tab indentation, and a line feed at the end.

	`SOML.Encoder` without that option writes the same text with the members in their order.

	- Throws: `SOML.InvalidValueError` if the value is not an object or an array, or holds something SOML cannot represent, like NaN, a string with a carriage return, or nesting deeper than 100 levels.
	*/
	public func canonicalDocument() throws(SOML.InvalidValueError) -> String {
		String(decoding: try CanonicalWriter.document(self, sortsMembers: true), as: UTF8.self)
	}
}

extension SOML.Value {
	/**
	The string, if the value is a string.
	*/
	public var stringValue: String? {
		switch self {
		case .string(let value):
			value
		default:
			nil
		}
	}

	/**
	The integer, if the value is an int.
	*/
	public var intValue: Int64? {
		switch self {
		case .int(let value):
			value
		default:
			nil
		}
	}

	/**
	The number, if the value is a float.
	*/
	public var floatValue: Double? {
		switch self {
		case .float(let value):
			value
		default:
			nil
		}
	}

	/**
	The Boolean, if the value is a bool.
	*/
	public var boolValue: Bool? {
		switch self {
		case .bool(let value):
			value
		default:
			nil
		}
	}

	/**
	The instant, if the value is an instant.
	*/
	public var instantValue: SOML.Instant? {
		switch self {
		case .instant(let value):
			value
		default:
			nil
		}
	}

	/**
	The duration, if the value is a duration.
	*/
	public var durationValue: Duration? {
		switch self {
		case .duration(let value):
			value
		default:
			nil
		}
	}

	/**
	The items, if the value is an array.
	*/
	public var arrayValue: [SOML.Value]? {
		switch self {
		case .array(let value):
			value
		default:
			nil
		}
	}

	/**
	The members, if the value is an object.
	*/
	public var objectValue: SOML.Object? {
		switch self {
		case .object(let value):
			value
		default:
			nil
		}
	}

	/**
	Whether the value is `null`.
	*/
	public var isNull: Bool {
		guard case .null = self else {
			return false
		}

		return true
	}

	/**
	The member with the given key, if the value is an object that has it.

	Setting a value replaces the member in place or adds it at the end, and setting `nil` removes it, as with `SOML.Object`. Setting on a value that is not an object does nothing.

	```swift
	var value = try SOML.Value(parsing: "postgres: {port: 5432}")
	value["postgres"]?["port"] = 6543
	```
	*/
	public subscript(key: String) -> SOML.Value? {
		get {
			objectValue?[key]
		}
		_modify {
			guard case .object(var object) = self else {
				var ignored: SOML.Value?
				yield &ignored
				return
			}

			// The object moves out while it changes, so its storage is unique and the change does not copy it.
			self = .null

			defer {
				self = .object(object)
			}

			yield &object[key]
		}
	}

	/**
	The item at the given index, if the value is an array and the index is in range.

	Setting a value replaces the item, and setting `nil` removes it. Setting on a value that is not an array, or at an index out of range, does nothing.
	*/
	public subscript(index: Int) -> SOML.Value? {
		get {
			guard
				let array = arrayValue,
				array.indices.contains(index)
			else {
				return nil
			}

			return array[index]
		}
		_modify {
			guard
				case .array(var array) = self,
				array.indices.contains(index)
			else {
				var ignored: SOML.Value?
				yield &ignored
				return
			}

			// The array and the item move out while the item changes, so their storage is unique and the change does not copy them.
			self = .null
			var item: SOML.Value? = array[index]
			array[index] = .null

			defer {
				if let item {
					array[index] = item
				} else {
					array.remove(at: index)
				}

				self = .array(array)
			}

			yield &item
		}
	}

	/**
	The value at a key path, if every step of it exists: each key in an object, and each index in range in an array.

	Setting a value changes it in place, as the key and index subscripts do, and setting `nil` removes the member or the item. Setting does nothing when a step before the last does not exist.

	```swift
	var value = try SOML.Value(parsing: "servers: [{host: 'a', port: 80}]")

	value[path: ["servers", 0, "port"]]
	//=> .int(80)

	value[path: ["servers", 0, "port"]] = 8080
	```
	*/
	public subscript(path path: SOML.KeyPath) -> SOML.Value? {
		get {
			value(at: path.segments[...])
		}
		set {
			set(newValue, at: path.segments[...])
		}
	}

	/**
	Sets the value at the rest of a key path, through the key and index subscripts, so that the change is made in place.
	*/
	private mutating func set(_ newValue: SOML.Value?, at segments: ArraySlice<SOML.KeyPath.Segment>) {
		guard let segment = segments.first else {
			return
		}

		let rest = segments.dropFirst()

		switch segment {
		case .key(let key):
			if rest.isEmpty {
				self[key] = newValue
			} else {
				self[key]?.set(newValue, at: rest)
			}
		case .index(let index):
			if rest.isEmpty {
				self[index] = newValue
			} else {
				self[index]?.set(newValue, at: rest)
			}
		}
	}

	/**
	Whether the value contains members or items.
	*/
	var isContainer: Bool {
		switch self {
		case .object, .array:
			true
		default:
			false
		}
	}

	/**
	The name of the value's type, as the spec names it.
	*/
	var typeName: String {
		switch self {
		case .string:
			"string"
		case .int:
			"int"
		case .float:
			"float"
		case .bool:
			"bool"
		case .null:
			"null"
		case .instant:
			"instant"
		case .duration:
			"duration"
		case .array:
			"array"
		case .object:
			"object"
		}
	}

	/**
	A short description for error messages, like `the int 30` or `an object`.
	*/
	var briefDescription: String {
		switch self {
		case .string(let value):
			value.unicodeScalars.prefix(41).count <= 40 ? "the string \(CanonicalWriter.string(value).sanitizedForTerminal)" : "a string"
		case .int, .float, .bool, .instant, .duration:
			"the \(typeName) \(description)"
		case .null:
			"null"
		case .array:
			"an array"
		case .object:
			"an object"
		}
	}
}

extension SOML.Value: Hashable {
	public static func == (lhs: Self, rhs: Self) -> Bool {
		switch (lhs, rhs) {
		case (.string(let lhs), .string(let rhs)):
			lhs.hasSameScalars(as: rhs)
		case (.int(let lhs), .int(let rhs)):
			lhs == rhs
		case (.float(let lhs), .float(let rhs)):
			lhs == rhs
		case (.bool(let lhs), .bool(let rhs)):
			lhs == rhs
		case (.null, .null):
			true
		case (.instant(let lhs), .instant(let rhs)):
			lhs == rhs
		case (.duration(let lhs), .duration(let rhs)):
			lhs == rhs
		case (.array(let lhs), .array(let rhs)):
			lhs == rhs
		case (.object(let lhs), .object(let rhs)):
			lhs == rhs
		default:
			false
		}
	}

	public func hash(into hasher: inout Hasher) {
		switch self {
		case .string(let value):
			hasher.combine(0)
			hasher.combine(ExactKey(value))
		case .int(let value):
			hasher.combine(1)
			hasher.combine(value)
		case .float(let value):
			// `Double` hashes `0.0` and `-0.0` the same, which matches the spec.
			hasher.combine(2)
			hasher.combine(value)
		case .bool(let value):
			hasher.combine(3)
			hasher.combine(value)
		case .null:
			hasher.combine(4)
		case .instant(let value):
			hasher.combine(5)
			hasher.combine(value)
		case .array(let value):
			hasher.combine(6)
			hasher.combine(value)
		case .object(let value):
			hasher.combine(7)
			hasher.combine(value)
		case .duration(let value):
			hasher.combine(8)
			hasher.combine(value)
		}
	}
}

extension SOML.Value: CustomStringConvertible {
	/**
	The value as it would appear after a key, in the layout and spelling of canonical form, with the members of an object in their order.

	Containers span several lines, and nested lines are indented with tabs. Containers beyond the supported nesting limit of 100 levels are shown as `…`.
	*/
	public var description: String {
		CanonicalWriter.valueDescription(self)
	}
}

extension SOML.Value: ExpressibleByStringLiteral {
	public init(stringLiteral value: String) {
		self = .string(value)
	}
}

extension SOML.Value: ExpressibleByIntegerLiteral {
	public init(integerLiteral value: Int64) {
		self = .int(value)
	}
}

extension SOML.Value: ExpressibleByFloatLiteral {
	public init(floatLiteral value: Double) {
		self = .float(value)
	}
}

extension SOML.Value: ExpressibleByBooleanLiteral {
	public init(booleanLiteral value: Bool) {
		self = .bool(value)
	}
}

extension SOML.Value: ExpressibleByNilLiteral {
	public init(nilLiteral: ()) {
		self = .null
	}
}

extension SOML.Value: ExpressibleByArrayLiteral {
	public init(arrayLiteral elements: SOML.Value...) {
		self = .array(elements)
	}
}

extension SOML.Value: ExpressibleByDictionaryLiteral {
	public init(dictionaryLiteral elements: (String, SOML.Value)...) {
		self = .object(SOML.Object(elements))
	}
}

extension SOML.Value: Codable {
	/**
	Decodes any value. `SOML.Decoder` passes the value through unchanged.

	Other decoders get a best-effort mapping, which tries `Bool`, then `Int64`, then `Double`, then `String`. Most other formats do not keep int and float apart, so with `JSONDecoder`, `1.0` becomes `.int(1)`.
	*/
	public init(from decoder: any Decoder) throws {
		if let decoder = decoder as? DecoderImplementation {
			decoder.recordReadWhole(decoder.value, key: nil)
			self = decoder.value
			return
		}

		if var container = try? decoder.unkeyedContainer() {
			var items = [SOML.Value]()
			items.reserveCapacity(container.count ?? 0)

			while !container.isAtEnd {
				items.append(try container.decode(SOML.Value.self))
			}

			self = .array(items)
			return
		}

		if let container = try? decoder.container(keyedBy: SOMLCodingKey.self) {
			self = .object(try SOML.Object(decoding: container))
			return
		}

		let container = try decoder.singleValueContainer()

		if container.decodeNil() {
			self = .null
		} else if let value = try? container.decode(Bool.self) {
			self = .bool(value)
		} else if let value = try? container.decode(Int64.self) {
			self = .int(value)
		} else if let value = try? container.decode(Double.self) {
			self = .float(value)
		} else if let value = try? container.decode(String.self) {
			self = .string(value)
		} else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "The value cannot be represented as a SOML value")
		}
	}

	/**
	Encodes the value. `SOML.Encoder` writes it unchanged. Other encoders get the closest native type, and an instant or a duration becomes its canonical string, like `1h30m`, rather than `Duration`'s own encoding, which is two integers.

	- Throws: `EncodingError.invalidValue` for a duration that SOML cannot represent.
	*/
	public func encode(to encoder: any Encoder) throws {
		if let encoder = encoder as? EncoderImplementation {
			// An object adds its members to the ones already in the encoder, like with `JSONEncoder`, so a type can flatten extra members into its own. Its keys are not converted by a key strategy.
			if case .object(let object) = self {
				let storage = encoder.objectStorage()

				for (key, value) in object {
					storage.set(.value(value), forKey: key)
				}
			} else {
				encoder.result = .value(self)
			}

			return
		}

		switch self {
		case .array(let items):
			var container = encoder.unkeyedContainer()

			for item in items {
				try container.encode(item)
			}
		case .object(let object):
			var container = encoder.container(keyedBy: SOMLCodingKey.self)

			for (key, value) in object {
				try container.encode(value, forKey: SOMLCodingKey(stringValue: key))
			}
		default:
			var container = encoder.singleValueContainer()

			switch self {
			case .string(let value):
				try container.encode(value)
			case .int(let value):
				try container.encode(value)
			case .float(let value):
				try container.encode(value)
			case .bool(let value):
				try container.encode(value)
			case .null:
				try container.encodeNil()
			case .instant(let value):
				try container.encode(value.description)
			case .duration(let value):
				guard value.exactNanoseconds != nil else {
					throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: value.unrepresentableReason))
				}

				try container.encode(description)
			case .array, .object:
				preconditionFailure("Handled above.")
			}
		}
	}
}

/**
A coding key for SOML members and array items.
*/
enum SOMLCodingKey: CodingKey, Hashable {
	case key(ExactKey)
	case index(Int)

	/**
	For an array index, the string is made only when it is asked for, which is rare.
	*/
	var stringValue: String {
		switch self {
		case .key(let key):
			key.string
		case .index(let index):
			String(index)
		}
	}

	/**
	The array index, or `nil` for a member key, including a numeric member key.
	*/
	var intValue: Int? {
		switch self {
		case .key:
			nil
		case .index(let index):
			index
		}
	}

	init(stringValue: String) {
		self = .key(ExactKey(stringValue))
	}

	init(intValue: Int) {
		self = .index(intValue)
	}

	static let `super` = Self(stringValue: "super")
}

/**
A coding path as a linked list, so that extending it for a nested value does not copy the whole path. The array is built only when something asks for it, which is usually only an error.
*/
indirect enum CodingPath {
	case root
	case key(any CodingKey, parent: CodingPath)

	func appending(_ key: (any CodingKey)?) -> CodingPath {
		guard let key else {
			return self
		}

		return .key(key, parent: self)
	}

	var keys: [any CodingKey] {
		var keys = [any CodingKey]()
		var node = self

		while case .key(let key, let parent) = node {
			keys.append(key)
			node = parent
		}

		keys.reverse()
		return keys
	}
}

extension Duration {
	/**
	The units of a SOML duration and their lengths in nanoseconds, from the largest to the smallest, which is the order they are written in.
	*/
	static let somlUnits: [(symbol: String, nanoseconds: UInt64)] = [
		("h", 3_600_000_000_000),
		("m", 60_000_000_000),
		("s", 1_000_000_000),
		("ms", 1_000_000),
		("us", 1000),
		("ns", 1),
	]

	/**
	The duration as a count of nanoseconds, which is the value of a SOML duration, or `nil` if it has a fraction of a nanosecond or is outside the int64 range of nanoseconds, so that SOML cannot represent it.

	```swift
	Duration.seconds(90).exactNanoseconds
	//=> 90000000000
	```
	*/
	public var exactNanoseconds: Int64? {
		let (nanoseconds, remainder) = attoseconds.quotientAndRemainder(dividingBy: 1_000_000_000)

		guard remainder == 0 else {
			return nil
		}

		return Int64(exactly: nanoseconds)
	}

	/**
	Why SOML cannot represent the duration, for an error message.
	*/
	var unrepresentableReason: String {
		guard attoseconds.isMultiple(of: 1_000_000_000) else {
			return "The duration \(self) has a fraction of a nanosecond, which a SOML duration cannot hold"
		}

		return "The duration \(self) is outside the range of a SOML duration, which is a count of nanoseconds in the int64 range, about 292 years either way"
	}
}

#if canImport(UniformTypeIdentifiers)
extension UTType {
	/**
	The type of a SOML file: `com.sindresorhus.soml`, with the `.soml` extension.

	The type is imported, so an app that opens or saves SOML files must also declare it in its `Info.plist`, as the readme shows. Without the declaration, the identifier works, but the type is not linked to the `.soml` extension and does not conform to `.utf8PlainText`.

	```swift
	.fileImporter(isPresented: $isImporting, allowedContentTypes: [.soml]) { result in
		// …
	}
	```
	*/
	public static var soml: Self {
		.init(importedAs: "com.sindresorhus.soml", conformingTo: .utf8PlainText)
	}
}
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import struct Foundation.Date

extension SOML {
	/**
	Decodes `Decodable` values from SOML documents.

	```swift
	struct Config: Decodable {
		let name: String
		let replicas: Int
		let deployedAt: Date
	}

	var decoder = SOML.Decoder()
	decoder.keyDecodingStrategy = .convertFromKebabCase

	let config = try decoder.decode(Config.self, from: """
		name: 'api-gateway'
		replicas: 3
		deployed-at: 2026-09-19T14:00:00Z
		""")
	```

	Types are strict, as in the spec. An int never decodes as a `String`, and a float never decodes as an integer type. A float type accepts an int that converts exactly, so `timeout: 30` decodes as a `Double`.

	| Swift | SOML |
	|---|---|
	| `String` | string |
	| `Bool` | bool |
	| Integer types | int, range-checked |
	| `Double`, `Float`, `Float16` | float, or an int that converts exactly |
	| `Optional` | `null` |
	| `SOML.Date` | date |
	| `Foundation.Date`, `SOML.Instant` | instant |
	| `Duration` | duration |
	| `URL` | string |
	| `Data` | base64 string |
	| `SOML.Value`, `SOML.Object` | any value, unchanged |
	*/
	public struct Decoder: Sendable {
		/**
		How the decoder maps a coding key to a key in the document.
		*/
		public enum KeyDecodingStrategy: Sendable {
			/**
			Use the coding key as it is.
			*/
			case useDefaultKeys

			/**
			The document uses kebab-case: the coding key `deployedAt` reads the member `deployed-at`.

			The coding key is converted to the document's spelling, rather than the other way around, so a property name that `SOML.Encoder` writes with `.convertToKebabCase` reads back, including `baseURL` from `base-url`. Keys of a dictionary property or element, like a `[String: T]` or one with `CodingKeyRepresentable` keys, are not converted.

			A type that reads `allKeys`, such as an enum with associated values, sees the document's keys converted back to camelCase. That direction is lossy, as it is for `JSONDecoder`: `base-url` becomes `baseUrl`, so an enum case named `baseURL` is not found.
			*/
			case convertFromKebabCase

			/**
			The document uses snake_case: the coding key `deployedAt` reads the member `deployed_at`.

			The coding key is converted to the document's spelling, rather than the other way around, so a property name that `SOML.Encoder` writes with `.convertToSnakeCase` reads back. Keys of a dictionary property or element, like a `[String: T]` or one with `CodingKeyRepresentable` keys, are not converted.

			A type that reads `allKeys` sees the document's keys converted back to camelCase, which is lossy, as for `.convertFromKebabCase`.
			*/
			case convertFromSnakeCase

			var separator: Character? {
				switch self {
				case .useDefaultKeys:
					nil
				case .convertFromKebabCase:
					"-"
				case .convertFromSnakeCase:
					"_"
				}
			}

			/**
			The encoding strategy that writes the keys this strategy reads.
			*/
			var matchingEncodingStrategy: SOML.Encoder.KeyEncodingStrategy {
				switch self {
				case .useDefaultKeys:
					.useDefaultKeys
				case .convertFromKebabCase:
					.convertToKebabCase
				case .convertFromSnakeCase:
					.convertToSnakeCase
				}
			}
		}

		/**
		How coding keys map to the document's keys. The default is `.useDefaultKeys`.
		*/
		public var keyDecodingStrategy = KeyDecodingStrategy.useDefaultKeys

		/**
		Whether a member that the type does not read is an error. The default is `false`, which ignores such members, as `JSONDecoder` does.

		Turn it on to report a misspelled key in a config file, which would otherwise be ignored silently. The error is a `DecodingError.dataCorrupted` whose coding path ends at the unknown key, and it suggests a key the type looked for when one is close.

		A type that reads `allKeys`, like `[String: T]` or an enum with associated values, decides about the keys itself, so its object is not checked. The objects inside it are. The same holds for an object decoded whole as `SOML.Value` or `SOML.Object`, also when another type reads the same object, like a struct that keeps the members it does not know in a `[String: SOML.Value]`. So a type that only looks at the whole object, and then decodes it as a stricter type, turns off the check for that object. Look at a member through a nested container instead.

		The keys that every decoder of an object looks up count as known, so a type can peek at a member through a nested container before it decodes the member. This includes the keys of an attempt that failed, like a `try?` that falls back to another type. But a type that throws does not look up the keys after the error, so when nothing else decodes its object, like when a `try?` gives `nil` for a member, the members it did not get to are reported as unknown. Decoding the member as `SOML.Value` when the attempt fails takes any members of its object, but an object inside it that the failed type began to read is still checked.

		With `defaults`, the check is of the document merged over the encoded defaults. So a member that the type encodes but does not decode, like a `let` constant with an initial value, is reported as unknown even though the document does not have it.

		```swift
		struct Options: Decodable {
			var timeout: Double?
		}

		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true

		try decoder.decode(Options.self, from: "timout: 30.0")
		// Throws: Unknown key timout, which Options does not read. Did you mean timeout? (line 1, column 1)
		```
		*/
		public var rejectsUnknownKeys = false

		/**
		Contextual information for the types you decode, which they read from `Decoder.userInfo`.
		*/
		public var userInfo = [CodingUserInfoKey: any Sendable]()

		/**
		Creates a decoder with the default options.
		*/
		public init() {}

		/**
		Decodes a value from a SOML document.

		A `DecodingError` about a value in the document, like a type mismatch, has the line and column of that value at the end of its description, like `(line 2, column 1)`. Use `SOML.Document.location(of:keyDecodingStrategy:)` for the location as a value.

		- Throws: `DecodingError.dataCorrupted` with a `SOML.ParseError` as the underlying error if the document is not valid SOML, or another `DecodingError` if the document does not match the type.
		*/
		public func decode<T: Decodable>(_ type: T.Type = T.self, from text: String) throws -> T {
			try decode(type, parsing: Array(text.utf8), defaults: nil)
		}

		/**
		Decodes a value from the UTF-8 bytes of a SOML document, like `Data` or `[UInt8]`. See `decode(_:from:)` for a string.

		- Throws: `DecodingError.dataCorrupted` with a `SOML.ParseError` as the underlying error if the document is not valid SOML, or another `DecodingError` if the document does not match the type.
		*/
		public func decode<T: Decodable>(_ type: T.Type = T.self, from bytes: some Sequence<UInt8>) throws -> T {
			try decode(type, parsing: Array(bytes), defaults: nil)
		}

		/**
		Decodes a value from a SOML value that was already parsed.

		- Throws: `DecodingError` if the value does not match the type.
		*/
		public func decode<T: Decodable>(_ type: T.Type = T.self, from value: SOML.Value) throws -> T {
			// A value built in memory can be nested deeper than any document a reader takes, and decoding one would overflow the stack. The depth check stops at the limit before descending further, so the check itself cannot overflow the stack. Decoding from text without defaults needs no check, because the parser has already bounded the document.
			guard !value.isDeeperThan(Parser.maximumDepth) else {
				throw Self.depthError
			}

			return try decode(type, from: value, document: value)
		}

		/**
		Decodes a value from a SOML document, and takes every member that the document leaves out from `defaults`, so a config file only needs the settings that differ.

		Codable has no default values of its own: a synthesized `init(from:)` throws for a missing key, unless the property is optional. Here, `defaults` is encoded with the matching key strategy, the document is merged over it with `SOML.Value.merging(_:)`, and the result is decoded. So objects merge member by member, and an array in the document replaces the default array.

		An enum without raw values encodes as an object with one key, the case, so the case in the document merges with the default case, and the result does not decode. Give such an enum a `String` raw value. For the same reason, a document cannot remove an entry from a default dictionary.

		```swift
		struct Config: Codable {
			var host = "localhost"
			var port = 80
		}

		let config = try SOML.Decoder().decode(from: "port: 8080", defaults: Config())
		//=> Config(host: "localhost", port: 8080)
		```

		- Throws: As `decode(_:from:)`, and an `EncodingError` if `defaults` cannot be encoded.
		*/
		public func decode<T: Codable>(_ type: T.Type = T.self, from text: String, defaults: T) throws -> T {
			try decode(type, parsing: Array(text.utf8), defaults: encodedDefaults(defaults))
		}

		/**
		Decodes a value from the UTF-8 bytes of a SOML document, with defaults for what it leaves out. See `decode(_:from:defaults:)` for a string.
		*/
		public func decode<T: Codable>(_ type: T.Type = T.self, from bytes: some Sequence<UInt8>, defaults: T) throws -> T {
			try decode(type, parsing: Array(bytes), defaults: encodedDefaults(defaults))
		}

		/**
		Decodes a value from a SOML value that was already parsed, with defaults for what it leaves out. See `decode(_:from:defaults:)` for a string.
		*/
		public func decode<T: Codable>(_ type: T.Type = T.self, from value: SOML.Value, defaults: T) throws -> T {
			// Merging recurses where both values are objects, so the value is checked first, which bounds the recursion. The merged value is checked too, for deep defaults.
			guard !value.isDeeperThan(Parser.maximumDepth) else {
				throw Self.depthError
			}

			let merged = try encodedDefaults(defaults).merging(value)

			guard !merged.isDeeperThan(Parser.maximumDepth) else {
				throw Self.depthError
			}

			return try decode(type, from: merged, document: value)
		}

		/**
		Decodes `value`, which is `document`, or `document` merged over the defaults.
		*/
		private func decode<T: Decodable>(_ type: T.Type, from value: SOML.Value, document: SOML.Value) throws -> T {
			let options = options
			let result = try DecoderImplementation(value: value, options: options).unbox(value, as: type, key: nil)
			try options.readKeys?.checkUnknownKeys(rootType: type, document: document)
			return result
		}

		/**
		The error for a value nested deeper than any reader takes.
		*/
		private static var depthError: DecodingError {
			DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The value is nested more than \(Parser.maximumDepth) levels deep, \(Parser.depthLimitPhrase)"))
		}

		private func decode<T: Decodable>(_ type: T.Type, parsing bytes: [UInt8], defaults: SOML.Value?) throws -> T {
			let value: SOML.Value

			do {
				value = try Parser.parseDocument(bytes)
			} catch {
				throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "The given data was not valid SOML. \(error)", underlyingError: error))
			}

			let merged = defaults.map { $0.merging(value) } ?? value

			// The parser bounds the document, but not the defaults, which the merged value keeps where the document leaves them out.
			guard
				defaults == nil
					|| !merged.isDeeperThan(Parser.maximumDepth)
			else {
				throw Self.depthError
			}

			do {
				return try decode(type, from: merged, document: value)
			} catch let error as DecodingError {
				throw locating(error, in: bytes, value: value)
			}
		}

		/**
		The defaults as a value, encoded with the key strategy that matches this decoder's.
		*/
		private func encodedDefaults(_ defaults: some Encodable) throws -> SOML.Value {
			var encoder = SOML.Encoder()
			encoder.keyEncodingStrategy = keyDecodingStrategy.matchingEncodingStrategy
			encoder.userInfo = userInfo
			return try encoder.encodeToValue(defaults)
		}

		/**
		The error with the location of its coding path in the document at the end of its description. The syntax tree that finds it is built only here, so decoding that succeeds does not pay for it.
		*/
		private func locating(_ error: DecodingError, in bytes: [UInt8], value: SOML.Value) -> DecodingError {
			let document = SOML.Document(validDocument: bytes, value: value)

			func located(_ context: DecodingError.Context) -> DecodingError.Context {
				let location = document.location(of: context.codingPath, keyDecodingStrategy: keyDecodingStrategy)
				return DecodingError.Context(codingPath: context.codingPath, debugDescription: "\(context.debugDescription) (\(location))", underlyingError: context.underlyingError)
			}

			switch error {
			case .typeMismatch(let type, let context):
				return .typeMismatch(type, located(context))
			case .valueNotFound(let type, let context):
				return .valueNotFound(type, located(context))
			case .keyNotFound(let key, let context):
				return .keyNotFound(key, located(context))
			case .dataCorrupted(let context):
				return .dataCorrupted(located(context))
			@unknown default:
				return error
			}
		}

		private var options: DecoderImplementation.Options {
			.init(keySeparator: keyDecodingStrategy.separator, readKeys: rejectsUnknownKeys ? ReadKeys(keySeparator: keyDecodingStrategy.separator) : nil, userInfo: userInfo)
		}
	}
}

/**
An `Optional`, which decodes the type it wraps, so that an error names that type.
*/
private protocol OptionalDecodable {}

extension Optional: OptionalDecodable {}

/**
The `Decoder` for one value in the tree.

Primitive containers keep explicit witnesses for the common `Bool`, `String`, `Double`, and `Int` fast paths. The other ordinary primitives share generic boxing or unboxing. `Int128` and `UInt128` also need explicit witnesses, because their Codable protocol defaults report unsupported types instead of forwarding to the generic implementation.

The coding path is a linked list, and the array is built only when something asks for it, which is usually only an error. Copying a coding path array for every value was a large part of the decoding time.
*/
final class DecoderImplementation: Decoder {
	struct Options {
		let keySeparator: Character?
		/**
		When unknown keys are rejected: the keys that this decode looked up, shared by all its decoders.
		*/
		let readKeys: ReadKeys?
		let userInfo: [CodingUserInfoKey: Any]

		/**
		Accepts only Sendable context and erases it once for the Decoder protocol, sharing the dictionary with nested decoders and repeated userInfo reads.
		*/
		init(keySeparator: Character?, readKeys: ReadKeys?, userInfo: [CodingUserInfoKey: any Sendable]) {
			self.keySeparator = keySeparator
			self.readKeys = readKeys
			self.userInfo = userInfo.mapValues { $0 as Any }
		}
	}

	let value: SOML.Value
	let options: Options
	private let path: CodingPath

	/**
	The type that this decoder decodes, which an error names when the value is not the object or the array it reads, or `nil` when it is not known, like for a nested container.
	*/
	private let type: Any.Type?

	/**
	When unknown keys are rejected: the reads of this decoder's object, or `nil` before the first keyed container.
	*/
	private var reads: ReadKeys.Reads?

	/**
	When unknown keys are rejected: the node of this decoder's coding path in `ReadKeys`, and otherwise the root.
	*/
	private let pathNode: Int

	init(value: SOML.Value, options: Options, codingPath: CodingPath = .root, pathNode: Int = ReadKeys.rootNode, type: Any.Type? = nil) {
		self.value = value
		self.options = options
		self.path = codingPath
		self.pathNode = pathNode
		self.type = type
	}

	/**
	The node of the coding path of this decoder, followed by `key` if there is one.
	*/
	private func pathNode(appending key: (any CodingKey)?) -> Int {
		guard
			let key,
			let readKeys = options.readKeys
		else {
			return pathNode
		}

		return readKeys.node(after: pathNode, key: key)
	}

	var codingPath: [any CodingKey] {
		codingPath(appending: nil)
	}

	var userInfo: [CodingUserInfoKey: Any] {
		options.userInfo
	}

	/**
	The coding path of this decoder, followed by `key` if there is one.
	*/
	func codingPath(appending key: (any CodingKey)?) -> [any CodingKey] {
		path.appending(key).keys
	}

	func container<Key: CodingKey>(keyedBy type: Key.Type) throws(DecodingError) -> KeyedDecodingContainer<Key> {
		guard case .object(let object) = value else {
			throw mismatch(self.type, value, key: nil, expected: "an object", unknownType: [String: Any].self)
		}

		if
			reads == nil,
			let readKeys = options.readKeys
		{
			reads = readKeys.reads(of: object, at: pathNode, codingPath: path)
		}

		return KeyedDecodingContainer(KeyedContainer(decoder: self, object: object))
	}

	func unkeyedContainer() throws(DecodingError) -> any UnkeyedDecodingContainer {
		guard case .array(let items) = value else {
			throw mismatch(self.type, value, key: nil, expected: "an array", unknownType: [Any].self)
		}

		return UnkeyedContainer(decoder: self, items: items)
	}

	func singleValueContainer() -> any SingleValueDecodingContainer {
		self
	}

	func makeDecoder(for value: SOML.Value, key: (any CodingKey)?, type: Any.Type? = nil) -> DecoderImplementation {
		DecoderImplementation(value: value, options: options, codingPath: path.appending(key), pathNode: pathNode(appending: key), type: type)
	}

	func recordRead(_ documentKey: String) {
		reads?.keys.insert(ExactKey(documentKey))
	}

	func recordReadsAllKeys() {
		reads?.readsAllKeys = true
	}

	/**
	Records that a type took `value` at `key` whole, like `SOML.Value` and `[String: T]` do, so none of its keys is unknown, even when a keyed container at the same coding path looked up only some of them.
	*/
	func recordReadWhole(_ value: SOML.Value, key: (any CodingKey)?) {
		guard
			let readKeys = options.readKeys,
			case .object(let object) = value
		else {
			return
		}

		readKeys.reads(of: object, at: pathNode(appending: key), codingPath: path.appending(key)).readsAllKeys = true
	}

	// MARK: Unboxing

	/**
	Decodes a value at `key`, relative to this decoder.

	Common types are checked first by comparing metatypes, which is a pointer comparison. Without this, a generic container such as `[Int]` would create a decoder for every element.
	*/
	@inline(__always)
	func unbox<T: Decodable>(_ value: SOML.Value, as type: T.Type, key: (any CodingKey)?) throws -> T {
		if let primitive = try unboxPrimitive(value, as: type, key: key) {
			return primitive
		}

		return try unboxNonPrimitive(value, as: type, key: key)
	}

	/**
	Decodes non-primitive values separately so specialization can eliminate the primitive dispatch without inlining the recursive Codable path.
	*/
	private func unboxNonPrimitive<T: Decodable>(_ value: SOML.Value, as type: T.Type, key: (any CodingKey)?) throws -> T {
		// Only the comparisons are here, and not an optional result, which an unspecialized generic type would pay for on every value.
		if
			T.self == SOML.Value.self
				|| T.self == SOML.Object.self
				|| T.self == SOML.Date.self
				|| T.self == SOML.Instant.self
				|| T.self == Foundation.Date.self
				|| T.self == Duration.self
				|| T.self == URL.self
				|| T.self == Data.self
		{
			return try unboxSpecial(value, as: type, key: key)
		}

		// Only a key strategy needs this, and the protocol check is slow, so skip it otherwise, like `JSONDecoder` does.
		if
			options.keySeparator != nil,
			let dictionaryType = type as? any KeyedDictionaryDecodable.Type
		{
			return try unboxDictionary(value, as: dictionaryType, key: key) as! T
		}

		let decoder = makeDecoder(for: value, key: key, type: type)
		let result: T

		do {
			result = try T(from: decoder)
		} catch {
			recordThrowingType(type, of: decoder)
			throw error
		}

		recordFinishedType(type, of: decoder, value: value)
		return result
	}

	/**
	A type that throws read the members that it got to, so when another type catches the error, an unknown key in the object names it, unless a type that finished reads the object too.
	*/
	@inline(never)
	private func recordThrowingType(_ type: Any.Type, of decoder: DecoderImplementation) {
		if
			let reads = decoder.reads,
			reads.type == nil
		{
			reads.type = type
		}
	}

	/**
	Records the type that read an object, for an unknown key error.
	*/
	@inline(__always)
	private func recordFinishedType(_ type: Any.Type, of decoder: DecoderImplementation, value: SOML.Value) {
		if let reads = decoder.reads {
			// The outermost type that reads an object is the last to finish, so it is the one an unknown key error names.
			reads.type = type
		} else if
			let readKeys = options.readKeys,
			case .object(let object) = value
		{
			// A type that made no keyed container, like a struct without properties, still read the object, so its members are unknown. A wrapper that decoded the object as another type through a single value container, like `Optional`, leaves the name of that type.
			let reads = readKeys.reads(of: object, at: decoder.pathNode, codingPath: decoder.path)

			if reads.type == nil {
				reads.type = type
			}
		}
	}

	/**
	Decodes the types that SOML reads itself, like `SOML.Value` and `Date`.

	It is a frame of its own in a debug build, which does not inline it, as `unboxNonPrimitive` runs once for each level of nesting, and its frame would hold the locals of every branch here, so that a type at the nesting limit would overflow the stack of a task.
	*/
	@inline(__always)
	private func unboxSpecial<T: Decodable>(_ value: SOML.Value, as type: T.Type, key: (any CodingKey)?) throws -> T {
		if T.self == SOML.Value.self {
			recordReadWhole(value, key: key)
			return value as! T
		}

		if T.self == SOML.Object.self {
			guard case .object(let object) = value else {
				throw mismatch(type, value, key: key, expected: "an object")
			}

			recordReadWhole(value, key: key)
			return object as! T
		}

		if T.self == SOML.Date.self {
			return try unboxDate(value, key: key) as! T
		}

		if T.self == SOML.Instant.self {
			return try unboxInstant(value, key: key) as! T
		}

		if T.self == Foundation.Date.self {
			return try unboxInstant(value, as: Foundation.Date.self, key: key).date as! T
		}

		// `Duration`'s own `Decodable` conformance reads two integers, which no SOML duration is.
		if T.self == Duration.self {
			guard case .duration(let duration) = value else {
				throw mismatch(type, value, key: key, expected: "a duration")
			}

			return duration as! T
		}

		if T.self == URL.self {
			let string = try unboxString(value, as: URL.self, key: key)

			guard let url = URL(string: string) else {
				throw DecodingError.dataCorrupted(.init(codingPath: codingPath(appending: key), debugDescription: "Invalid URL string \(CanonicalWriter.string(string.abbreviated).sanitizedForTerminal)"))
			}

			return url as! T
		}

		if T.self == Data.self {
			let string = try unboxString(value, as: Data.self, key: key)

			// The String initializer already borrows contiguous UTF-8; building Data first adds a copy and measured slower across the tested base64 sizes.
			guard let data = Data(base64Encoded: string) else {
				throw DecodingError.dataCorrupted(.init(codingPath: codingPath(appending: key), debugDescription: "Expected a base64 string for Data"))
			}

			return data as! T
		}

		preconditionFailure("Only a type that SOML reads itself is decoded here.")
	}

	/**
	Decodes a dictionary whose keys a key strategy converts.
	*/
	private func unboxDictionary(_ value: SOML.Value, as type: any KeyedDictionaryDecodable.Type, key: (any CodingKey)?) throws -> any KeyedDictionaryDecodable {
		guard case .object(let object) = value else {
			// The decoder of the dictionary names it, as without a key strategy, where it decodes itself, and not the type of this decoder, like a wrapper that decodes the dictionary through a single value container.
			throw makeDecoder(for: value, key: key, type: type).mismatch(type, value, key: nil, expected: "an object")
		}

		recordReadWhole(value, key: key)
		return try type.init(object: object, decoder: makeDecoder(for: value, key: key))
	}

	/**
	Decodes primitive types before generic decoding. Keeping these typed throws in a separate frame leaves the recursive path small in debug builds.
	*/
	@inline(__always)
	private func unboxPrimitive<T: Decodable>(_ value: SOML.Value, as type: T.Type, key: (any CodingKey)?) throws(DecodingError) -> T? {
		if T.self == String.self {
			return (try unboxString(value, key: key) as! T)
		}

		if T.self == Int.self {
			return (try unboxInteger(value, as: Int.self, key: key) as! T)
		}

		if T.self == Double.self {
			return (try unboxFloat(value, as: Double.self, key: key) as! T)
		}

		if T.self == Bool.self {
			return (try unboxBool(value, key: key) as! T)
		}

		if T.self == Int64.self {
			return (try unboxInteger(value, as: Int64.self, key: key) as! T)
		}

		if T.self == Float.self {
			return (try unboxFloat(value, as: Float.self, key: key) as! T)
		}

		if T.self == UInt8.self {
			return (try unboxInteger(value, as: UInt8.self, key: key) as! T)
		}

		if T.self == Int32.self {
			return (try unboxInteger(value, as: Int32.self, key: key) as! T)
		}

		if T.self == UInt64.self {
			return (try unboxInteger(value, as: UInt64.self, key: key) as! T)
		}

		if T.self == Int8.self {
			return (try unboxInteger(value, as: Int8.self, key: key) as! T)
		}

		if T.self == Int16.self {
			return (try unboxInteger(value, as: Int16.self, key: key) as! T)
		}

		if T.self == UInt16.self {
			return (try unboxInteger(value, as: UInt16.self, key: key) as! T)
		}

		if T.self == UInt32.self {
			return (try unboxInteger(value, as: UInt32.self, key: key) as! T)
		}

		if T.self == UInt.self {
			return (try unboxInteger(value, as: UInt.self, key: key) as! T)
		}

		if T.self == Int128.self {
			return (try unboxInteger(value, as: Int128.self, key: key) as! T)
		}

		if T.self == UInt128.self {
			return (try unboxInteger(value, as: UInt128.self, key: key) as! T)
		}

		// `Float16`'s own `Decodable` conformance decodes a `Float` and rounds it, so a value that does not fit, like the int 2049, would silently change, and an error would name `Float`.
		#if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
		if T.self == Float16.self {
			return (try unboxFloat(value, as: Float16.self, key: key) as! T)
		}
		#endif

		return nil
	}

	/**
	Decodes a calendar date without accepting a string or an instant.
	*/
	func unboxDate(_ value: SOML.Value, key: (any CodingKey)?) throws(DecodingError) -> SOML.Date {
		guard case .date(let date) = value else {
			throw mismatch(SOML.Date.self, value, key: key, expected: "a date")
		}

		return date
	}

	func unboxInstant(_ value: SOML.Value, as type: Any.Type = SOML.Instant.self, key: (any CodingKey)?) throws(DecodingError) -> SOML.Instant {
		guard case .instant(let instant) = value else {
			throw mismatch(type, value, key: key, expected: "an instant")
		}

		return instant
	}

	func unboxString(_ value: SOML.Value, as type: Any.Type = String.self, key: (any CodingKey)?) throws(DecodingError) -> String {
		guard case .string(let string) = value else {
			throw mismatch(type, value, key: key, expected: "a string")
		}

		return string
	}

	func unboxBool(_ value: SOML.Value, key: (any CodingKey)?) throws(DecodingError) -> Bool {
		guard case .bool(let bool) = value else {
			throw mismatch(Bool.self, value, key: key, expected: "a bool")
		}

		return bool
	}

	func unboxInteger<T: FixedWidthInteger>(_ value: SOML.Value, as type: T.Type, key: (any CodingKey)?) throws(DecodingError) -> T {
		guard case .int(let int) = value else {
			// Only a float that an int of the type can hold gets the hint, because no int can be written for `1e300`, and the int `300` does not fit in `UInt8`.
			if
				case .float(let float) = value,
				let exact = Int64(exactly: float),
				T(exactly: exact) != nil
			{
				throw DecodingError.typeMismatch(type, .init(codingPath: codingPath(appending: key), debugDescription: "Expected an int for \(type), but found the float \(value). An int is written without a fraction, like \(exact)"))
			}

			// A quoted number, like '6,000,000', gets the int that it means, if an int of the type can hold it.
			if
				case .string(let string) = value,
				let text = Self.unquotedIntText(string),
				case .int(let int)? = try? SOML.Value(parsingValue: text),
				T(exactly: int) != nil
			{
				throw DecodingError.typeMismatch(type, .init(codingPath: codingPath(appending: key), debugDescription: "Expected an int for \(type), but found \(value.briefDescription). An int is written without quotes, like \(int)"))
			}

			throw mismatch(type, value, key: key, expected: "an int")
		}

		guard let result = T(exactly: int) else {
			throw DecodingError.dataCorrupted(.init(codingPath: codingPath(appending: key), debugDescription: "The int \(int) does not fit in \(type), whose range is \(T.min) through \(T.max)"))
		}

		return result
	}

	/**
	The text of the int that `string` means, written as SOML writes an int, with “_” between the groups of digits, like `6_000_000` for `6,000,000`, or `string` itself when it has no comma, as that is already the int's own spelling, like `42` or `1_000`. It is `nil` when a comma does not separate groups of three digits, as in `1,5`, which a decimal comma makes `1.5` in some locales, and which would become the int `15`. The caller checks that the text is an int.
	*/
	private static func unquotedIntText(_ string: String) -> String? {
		guard string.contains(",") else {
			return string
		}

		let sign = string.hasPrefix("-") ? "-" : ""
		let groups = string.dropFirst(sign.count).split(separator: ",", omittingEmptySubsequences: false)

		// The first group holds one to three digits, and every other group three, as a thousands separator writes them.
		guard
			let firstGroup = groups.first,
			groups.allSatisfy({ group in group.allSatisfy { $0.isASCII && $0.isNumber } }),
			(1...3).contains(firstGroup.count),
			groups.dropFirst().allSatisfy({ $0.count == 3 })
		else {
			return nil
		}

		return sign + groups.joined(separator: "_")
	}

	func unboxFloat<T: BinaryFloatingPoint>(_ value: SOML.Value, as type: T.Type, key: (any CodingKey)?) throws(DecodingError) -> T {
		switch value {
		case .float(let double):
			// Only a value made in code can hold NaN.
			guard !double.isNaN else {
				throw DecodingError.dataCorrupted(.init(codingPath: codingPath(appending: key), debugDescription: "NaN is not a SOML value"))
			}

			let result = T(double)

			// A float that rounds to an infinity or, when it is not zero, to zero, does not fit, as a literal that does that is an error.
			guard
				result.isFinite || double.isInfinite,
				result != 0 || double == 0
			else {
				throw DecodingError.dataCorrupted(.init(codingPath: codingPath(appending: key), debugDescription: "The float \(value) does not fit in \(type)"))
			}

			return result
		case .int(let int):
			guard let result = T(exactly: int) else {
				// The hint is the value that the float gives, because a float with the digits of the int rounds to it too.
				let closest = T(int)

				guard closest.isFinite else {
					throw DecodingError.dataCorrupted(.init(codingPath: codingPath(appending: key), debugDescription: "The int \(int) does not fit in \(type)"))
				}

				throw DecodingError.dataCorrupted(.init(codingPath: codingPath(appending: key), debugDescription: "The int \(int) cannot be represented exactly as \(type). Write the closest one as a float: \(SOML.Value.float(Double(closest)))"))
			}

			return result
		default:
			throw mismatch(type, value, key: key, expected: "a float")
		}
	}

	func mismatch(_ type: Any.Type?, _ value: SOML.Value, key: (any CodingKey)?, expected: String, unknownType: Any.Type = Any.self) -> DecodingError {
		let codingPath = codingPath(appending: key)
		let errorType = type ?? unknownType
		// The value of the decoder itself is for the decoder's type, like a UUID that decodes a string through a single value container, except for an `Optional`, which decodes the type it wraps. A nested container has no type, and the type of the error is not one that the user wrote, so then no type is named.
		let namedType = key == nil && !(self.type is any OptionalDecodable.Type) ? self.type ?? type : type
		let expectation = namedType.map { "\(expected) for \($0)" } ?? expected

		if case .null = value {
			return DecodingError.valueNotFound(errorType, .init(codingPath: codingPath, debugDescription: "Expected \(expectation), but found null"))
		}

		return DecodingError.typeMismatch(errorType, .init(codingPath: codingPath, debugDescription: "Expected \(expectation), but found \(value.briefDescription)"))
	}
}

extension DecoderImplementation: SingleValueDecodingContainer {
	func decodeNil() -> Bool {
		value.isNull
	}

	func decode(_ type: Bool.Type) throws(DecodingError) -> Bool {
		try unboxBool(value, key: nil)
	}

	func decode(_ type: String.Type) throws(DecodingError) -> String {
		try unboxString(value, key: nil)
	}

	func decode(_ type: Double.Type) throws(DecodingError) -> Double {
		try unboxFloat(value, as: type, key: nil)
	}

	func decode(_ type: Int.Type) throws(DecodingError) -> Int {
		try unboxInteger(value, as: type, key: nil)
	}

	func decode(_ type: Int128.Type) throws(DecodingError) -> Int128 {
		try unboxInteger(value, as: type, key: nil)
	}

	func decode(_ type: UInt128.Type) throws(DecodingError) -> UInt128 {
		try unboxInteger(value, as: type, key: nil)
	}

	func decode<T: Decodable>(_ type: T.Type) throws -> T {
		try unbox(value, as: type, key: nil)
	}
}

private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
	let decoder: DecoderImplementation
	let object: SOML.Object

	var codingPath: [any CodingKey] {
		decoder.codingPath
	}

	/**
	The document's keys, converted back to camelCase when there is a key strategy.

	The conversion back is lossy, as it is for `JSONDecoder`: `base-url` becomes `baseUrl`, not `baseURL`. Looking up a coding key converts the other way, which is exact, so this only matters for types that read `allKeys`, such as enums with associated values.
	*/
	var allKeys: [Key] {
		decoder.recordReadsAllKeys()

		guard let separator = decoder.options.keySeparator else {
			return object.keys.compactMap { Key(stringValue: $0) }
		}

		// Keys that convert to the same key, like `max-size` and `maxSize`, give it once, as with `JSONDecoder`, because a type that reads them all may put them in a dictionary. Its value is that of the member that the key strategy writes for it, `max-size`, and not the first.
		var seenKeys = Set<ExactKey>()

		return object.keys.compactMap { key in
			let converted = key.convertedToCamelCase(separator: separator)

			guard seenKeys.insert(ExactKey(converted)).inserted else {
				return nil
			}

			return Key(stringValue: converted)
		}
	}

	/**
	The key in the document for a coding key. Every lookup goes through here, so this is where a read is recorded when unknown keys are rejected.
	*/
	private func documentKey(for key: some CodingKey) -> String {
		let documentKey = key.documentKey(separator: decoder.options.keySeparator)

		decoder.recordRead(documentKey)

		return documentKey
	}

	private func value(forKey key: some CodingKey) throws(DecodingError) -> SOML.Value {
		let documentKey = documentKey(for: key)

		guard let value = object[documentKey] else {
			throw keyNotFound(key, documentKey: documentKey)
		}

		return value
	}

	private func keyNotFound(_ key: some CodingKey, documentKey: String) -> DecodingError {
		let conversion = documentKey.hasSameScalars(as: key.stringValue) ? "" : " (from the coding key “\(key.stringValue.forMessage)”)"
		let separator = decoder.options.keySeparator

		// A key that the type reads with another coding key is not a misspelling of this one. A coding key type that accepts any string, even one that no property name has, tells nothing about which keys the type reads.
		let acceptsAnyString = Key(stringValue: "\u{0}") != nil

		let maximumCandidateLength = documentKey.unicodeScalars.prefix(65).count
		let maximumDistance = max(1, maximumCandidateLength / 3)
		let candidates = object.keys.lazy.prefix(1000).filter { candidate in
			guard candidate.unicodeScalars.prefix(maximumCandidateLength + maximumDistance + 1).count <= maximumCandidateLength + maximumDistance else {
				return false
			}

			guard
				!acceptsAnyString,
				let codingKey = Key(stringValue: separator.map { candidate.convertedToCamelCase(separator: $0) } ?? candidate)
			else {
				return true
			}

			return !codingKey.documentKey(separator: separator).hasSameScalars(as: candidate)
		}

		// Keys are compared by their Unicode scalars, so a key in another Unicode normalization is another key, though it looks the same. Only a key short enough for a hint is compared.
		let equivalent = maximumCandidateLength > 64 ? nil : object.keys.lazy.prefix(1000).first { $0.isEquivalentKey(to: documentKey) }

		let suggestion = if let equivalent {
			". The document has \(SOML.KeyPath.Segment.key(equivalent).described), which looks the same, but is written with other Unicode scalars, so it is another key"
		} else {
			documentKey.closest(in: candidates).map { ". The document has \(SOML.KeyPath.Segment.key($0).described). Is it misspelled?" } ?? ""
		}

		return DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "No member with the key \(SOML.KeyPath.Segment.key(documentKey).described)\(conversion)\(suggestion)"))
	}

	func contains(_ key: Key) -> Bool {
		// Asking whether a member is there counts as reading its key, so a type that only checks for a member does not get it reported as unknown.
		object.contains(key: documentKey(for: key))
	}

	func decodeNil(forKey key: Key) throws(DecodingError) -> Bool {
		try value(forKey: key).isNull
	}

	func decode(_ type: Bool.Type, forKey key: Key) throws(DecodingError) -> Bool {
		try decoder.unboxBool(value(forKey: key), key: key)
	}

	func decode(_ type: String.Type, forKey key: Key) throws(DecodingError) -> String {
		try decoder.unboxString(value(forKey: key), key: key)
	}

	func decode(_ type: Double.Type, forKey key: Key) throws(DecodingError) -> Double {
		try decoder.unboxFloat(value(forKey: key), as: type, key: key)
	}

	func decode(_ type: Int.Type, forKey key: Key) throws(DecodingError) -> Int {
		try decoder.unboxInteger(value(forKey: key), as: type, key: key)
	}

	func decode(_ type: Int128.Type, forKey key: Key) throws(DecodingError) -> Int128 {
		try decoder.unboxInteger(value(forKey: key), as: type, key: key)
	}

	func decode(_ type: UInt128.Type, forKey key: Key) throws(DecodingError) -> UInt128 {
		try decoder.unboxInteger(value(forKey: key), as: type, key: key)
	}

	func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
		try decoder.unbox(value(forKey: key), as: type, key: key)
	}

	/**
	Decodes a present, non-null member with one key conversion, lookup, and read record.
	*/
	private func decodePresent<T, Failure: Error>(forKey key: Key, _ unbox: (SOML.Value) throws(Failure) -> T) throws(Failure) -> T? {
		// One lookup instead of the three the default implementation makes.
		guard
			let value = object[documentKey(for: key)],
			!value.isNull
		else {
			return nil
		}

		return try unbox(value)
	}

	/**
	Decodes an optional integer with the shared exact range check.
	*/
	private func decodePresentInteger<T: FixedWidthInteger>(_ type: T.Type, forKey key: Key) throws(DecodingError) -> T? {
		try decodePresent(forKey: key) { (value) throws(DecodingError) in
			try decoder.unboxInteger(value, as: type, key: key)
		}
	}

	/**
	Decodes an optional float with the shared representability check.
	*/
	private func decodePresentFloat<T: BinaryFloatingPoint>(_ type: T.Type, forKey key: Key) throws(DecodingError) -> T? {
		try decodePresent(forKey: key) { (value) throws(DecodingError) in
			try decoder.unboxFloat(value, as: type, key: key)
		}
	}

	func decodeIfPresent(_ type: Bool.Type, forKey key: Key) throws(DecodingError) -> Bool? {
		try decodePresent(forKey: key) { (value) throws(DecodingError) in
			try decoder.unboxBool(value, key: key)
		}
	}

	func decodeIfPresent(_ type: String.Type, forKey key: Key) throws(DecodingError) -> String? {
		try decodePresent(forKey: key) { (value) throws(DecodingError) in
			try decoder.unboxString(value, key: key)
		}
	}

	func decodeIfPresent(_ type: Double.Type, forKey key: Key) throws(DecodingError) -> Double? {
		try decodePresentFloat(type, forKey: key)
	}

	func decodeIfPresent(_ type: Float.Type, forKey key: Key) throws(DecodingError) -> Float? {
		try decodePresentFloat(type, forKey: key)
	}

	func decodeIfPresent(_ type: Int.Type, forKey key: Key) throws(DecodingError) -> Int? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: Int8.Type, forKey key: Key) throws(DecodingError) -> Int8? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: Int16.Type, forKey key: Key) throws(DecodingError) -> Int16? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: Int32.Type, forKey key: Key) throws(DecodingError) -> Int32? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: Int64.Type, forKey key: Key) throws(DecodingError) -> Int64? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: UInt.Type, forKey key: Key) throws(DecodingError) -> UInt? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: UInt8.Type, forKey key: Key) throws(DecodingError) -> UInt8? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: UInt16.Type, forKey key: Key) throws(DecodingError) -> UInt16? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: UInt32.Type, forKey key: Key) throws(DecodingError) -> UInt32? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: UInt64.Type, forKey key: Key) throws(DecodingError) -> UInt64? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: Int128.Type, forKey key: Key) throws(DecodingError) -> Int128? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent(_ type: UInt128.Type, forKey key: Key) throws(DecodingError) -> UInt128? {
		try decodePresentInteger(type, forKey: key)
	}

	func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
		try decodePresent(forKey: key) {
			try decoder.unbox($0, as: type, key: key)
		}
	}

	func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws(DecodingError) -> KeyedDecodingContainer<NestedKey> {
		try decoder.makeDecoder(for: value(forKey: key), key: key).container(keyedBy: type)
	}

	func nestedUnkeyedContainer(forKey key: Key) throws(DecodingError) -> any UnkeyedDecodingContainer {
		try decoder.makeDecoder(for: value(forKey: key), key: key).unkeyedContainer()
	}

	func superDecoder() throws(DecodingError) -> any Decoder {
		try decoder.makeDecoder(for: value(forKey: SOMLCodingKey.super), key: SOMLCodingKey.super)
	}

	func superDecoder(forKey key: Key) throws(DecodingError) -> any Decoder {
		try decoder.makeDecoder(for: value(forKey: key), key: key)
	}
}

private struct UnkeyedContainer: UnkeyedDecodingContainer {
	let decoder: DecoderImplementation
	let items: [SOML.Value]
	private(set) var currentIndex = 0

	init(decoder: DecoderImplementation, items: [SOML.Value]) {
		self.decoder = decoder
		self.items = items
	}

	var codingPath: [any CodingKey] {
		decoder.codingPath
	}

	var count: Int? {
		items.count
	}

	var isAtEnd: Bool {
		currentIndex >= items.count
	}

	private var currentKey: SOMLCodingKey {
		SOMLCodingKey(intValue: currentIndex)
	}

	private func next(_ type: Any.Type) throws(DecodingError) -> SOML.Value {
		guard !isAtEnd else {
			throw DecodingError.valueNotFound(type, .init(codingPath: decoder.codingPath(appending: currentKey), debugDescription: "The array has no more items. It has \(items.count)"))
		}

		return items[currentIndex]
	}

	private mutating func decodeNext<T>(_ type: Any.Type, _ unbox: (DecoderImplementation, SOML.Value, SOMLCodingKey) throws -> T) throws -> T {
		try consume(next(type), using: unbox)
	}

	/**
	Decodes a primitive or nested container and advances only after successful conversion.
	*/
	private mutating func decodeChecked<T>(_ type: Any.Type, _ unbox: (DecoderImplementation, SOML.Value, SOMLCodingKey) throws(DecodingError) -> T) throws(DecodingError) -> T {
		try consume(next(type), using: unbox)
	}

	/**
	Consumes null once, or decodes the current primitive without a second bounds check.
	*/
	private mutating func decodePresent<T, Failure: Error>(_ unbox: (DecoderImplementation, SOML.Value, SOMLCodingKey) throws(Failure) -> T) throws(Failure) -> T? {
		guard !isAtEnd else {
			return nil
		}

		let value = items[currentIndex]
		guard !value.isNull else {
			currentIndex += 1
			return nil
		}

		return try consume(value, using: unbox)
	}

	/**
	Advances the index only after conversion succeeds, preserving the conversion's error type.
	*/
	private mutating func consume<T, Failure: Error>(_ value: SOML.Value, using unbox: (DecoderImplementation, SOML.Value, SOMLCodingKey) throws(Failure) -> T) throws(Failure) -> T {
		let result = try unbox(decoder, value, currentKey)
		currentIndex += 1
		return result
	}

	/**
	Decodes an integer and advances only after its exact range check succeeds.
	*/
	private mutating func decodeInteger<T: FixedWidthInteger>(_ type: T.Type) throws(DecodingError) -> T {
		try decodeChecked(type) { (decoder, value, key) throws(DecodingError) in
			try decoder.unboxInteger(value, as: type, key: key)
		}
	}

	/**
	Decodes a float and advances only after its representability check succeeds.
	*/
	private mutating func decodeFloat<T: BinaryFloatingPoint>(_ type: T.Type) throws(DecodingError) -> T {
		try decodeChecked(type) { (decoder, value, key) throws(DecodingError) in
			try decoder.unboxFloat(value, as: type, key: key)
		}
	}

	/**
	Consumes an optional integer through the shared null and range checks.
	*/
	private mutating func decodePresentInteger<T: FixedWidthInteger>(_ type: T.Type) throws(DecodingError) -> T? {
		try decodePresent { (decoder, value, key) throws(DecodingError) in
			try decoder.unboxInteger(value, as: type, key: key)
		}
	}

	/**
	Consumes an optional float through the shared null and representability checks.
	*/
	private mutating func decodePresentFloat<T: BinaryFloatingPoint>(_ type: T.Type) throws(DecodingError) -> T? {
		try decodePresent { (decoder, value, key) throws(DecodingError) in
			try decoder.unboxFloat(value, as: type, key: key)
		}
	}

	mutating func decodeNil() throws(DecodingError) -> Bool {
		// The index moves on only for null, as the protocol requires, so that the caller can then decode the item that is not null.
		guard try next(Never.self).isNull else {
			return false
		}

		currentIndex += 1
		return true
	}

	mutating func decodeIfPresent(_ type: Bool.Type) throws(DecodingError) -> Bool? {
		try decodePresent { (decoder, value, key) throws(DecodingError) in
			try decoder.unboxBool(value, key: key)
		}
	}

	mutating func decodeIfPresent(_ type: String.Type) throws(DecodingError) -> String? {
		try decodePresent { (decoder, value, key) throws(DecodingError) in
			try decoder.unboxString(value, key: key)
		}
	}

	mutating func decodeIfPresent(_ type: Double.Type) throws(DecodingError) -> Double? {
		try decodePresentFloat(type)
	}

	mutating func decodeIfPresent(_ type: Float.Type) throws(DecodingError) -> Float? {
		try decodePresentFloat(type)
	}

	mutating func decodeIfPresent(_ type: Int.Type) throws(DecodingError) -> Int? {
		try decodePresentInteger(type)
	}

	mutating func decodeIfPresent(_ type: Int8.Type) throws(DecodingError) -> Int8? {
		try decodePresentInteger(type)
	}

	mutating func decodeIfPresent(_ type: Int16.Type) throws(DecodingError) -> Int16? {
		try decodePresentInteger(type)
	}

	mutating func decodeIfPresent(_ type: Int32.Type) throws(DecodingError) -> Int32? {
		try decodePresentInteger(type)
	}

	mutating func decodeIfPresent(_ type: Int64.Type) throws(DecodingError) -> Int64? {
		try decodePresentInteger(type)
	}

	mutating func decodeIfPresent(_ type: UInt.Type) throws(DecodingError) -> UInt? {
		try decodePresentInteger(type)
	}

	mutating func decodeIfPresent(_ type: UInt8.Type) throws(DecodingError) -> UInt8? {
		try decodePresentInteger(type)
	}

	mutating func decodeIfPresent(_ type: UInt16.Type) throws(DecodingError) -> UInt16? {
		try decodePresentInteger(type)
	}

	mutating func decodeIfPresent(_ type: UInt32.Type) throws(DecodingError) -> UInt32? {
		try decodePresentInteger(type)
	}

	mutating func decodeIfPresent(_ type: UInt64.Type) throws(DecodingError) -> UInt64? {
		try decodePresentInteger(type)
	}

	mutating func decode(_ type: Bool.Type) throws(DecodingError) -> Bool {
		try decodeChecked(type) { (decoder, value, key) throws(DecodingError) in
			try decoder.unboxBool(value, key: key)
		}
	}

	mutating func decode(_ type: String.Type) throws(DecodingError) -> String {
		try decodeChecked(type) { (decoder, value, key) throws(DecodingError) in
			try decoder.unboxString(value, key: key)
		}
	}

	mutating func decode(_ type: Double.Type) throws(DecodingError) -> Double {
		try decodeFloat(type)
	}

	mutating func decode(_ type: Int.Type) throws(DecodingError) -> Int {
		try decodeInteger(type)
	}

	mutating func decode(_ type: Int128.Type) throws(DecodingError) -> Int128 {
		try decodeInteger(type)
	}

	mutating func decodeIfPresent(_ type: Int128.Type) throws(DecodingError) -> Int128? {
		try decodePresentInteger(type)
	}

	mutating func decode(_ type: UInt128.Type) throws(DecodingError) -> UInt128 {
		try decodeInteger(type)
	}

	mutating func decodeIfPresent(_ type: UInt128.Type) throws(DecodingError) -> UInt128? {
		try decodePresentInteger(type)
	}

	mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
		try decodeNext(type) { try $0.unbox($1, as: type, key: $2) }
	}

	mutating func decodeIfPresent<T: Decodable>(_ type: T.Type) throws -> T? {
		try decodePresent { decoder, value, key in
			try decoder.unbox(value, as: type, key: key)
		}
	}

	mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws(DecodingError) -> KeyedDecodingContainer<NestedKey> {
		try decodeChecked(KeyedDecodingContainer<NestedKey>.self) { (decoder, value, key) throws(DecodingError) in
			try decoder.makeDecoder(for: value, key: key).container(keyedBy: type)
		}
	}

	mutating func nestedUnkeyedContainer() throws(DecodingError) -> any UnkeyedDecodingContainer {
		try decodeChecked([Any].self) { (decoder, value, key) throws(DecodingError) in
			try decoder.makeDecoder(for: value, key: key).unkeyedContainer()
		}
	}

	mutating func superDecoder() throws(DecodingError) -> any Decoder {
		try decodeChecked((any Decoder).self) { decoder, value, key in
			decoder.makeDecoder(for: value, key: key)
		}
	}
}

/**
When unknown keys are rejected: the keys that the keyed containers of one decode looked up, for each object.

All decoders of one object share its reads, so a type can read an object through more than one decoder, like a nested container that peeks at a member before the member is decoded as a type, or a `singleValueContainer()` that decodes the same object as another type. The check runs once, after the whole decode.
*/
final class ReadKeys {
	final class Reads {
		let object: SOML.Object
		let node: Int

		/**
		The coding path of the object, as a linked list that shares its keys with the paths of the objects around it. An array for each object would hold up to a hundred keys per object in a document nested to the limit.
		*/
		let codingPath: CodingPath

		var keys = Set<ExactKey>()

		/**
		Whether a keyed container gave its `allKeys`, which means the type handles the keys itself.
		*/
		var readsAllKeys = false

		/**
		The type that read the object, for the error message, or `nil` if only nested containers read it.
		*/
		var type: Any.Type?

		init(object: SOML.Object, node: Int, codingPath: CodingPath) {
			self.object = object
			self.node = node
			self.codingPath = codingPath
		}
	}

	/**
	The separator of the key strategy, which turns a coding path into the keys of the document.
	*/
	private let keySeparator: Character?

	/**
	The node of the empty coding path, which every decode starts at.
	*/
	static let rootNode = 0

	/**
	A node and the document key of one of its children.
	*/
	private struct Edge: Hashable {
		let parent: Int
		let key: ExactKey
	}

	/**
	The tree of the document keys of coding paths, where each coding path is a node, from the root node. Two decoders of one object can have different coding keys for it, like a property `mainServer` and the key `main-server` of a `[String: T]` under a key strategy, but the document keys, and so the node, are the same.

	Each decoder finds its node from the node of its parent and its own key, so a long key is not hashed again for every object inside it, which made hostile input take quadratic time.
	*/
	private var nodes = [Edge: Int]()

	/**
	The parent of each node, which is `nil` for the root node.
	*/
	private var parents: [Int?] = [nil]

	/**
	The reads of each object, by the node of its coding path, and in the order the objects were first read.
	*/
	private var readsByNode: [Reads?] = [nil]
	private var orderedReads = [Reads]()

	init(keySeparator: Character?) {
		self.keySeparator = keySeparator
	}

	/**
	The node of the coding path of the node `parent` followed by `key`.
	*/
	func node(after parent: Int, key: any CodingKey) -> Int {
		let edge = Edge(parent: parent, key: ExactKey(key.documentKey(separator: keySeparator)))

		// Dictionary's default-value getter does not insert its result; explicit insertion ensures repeated visits share the same node.
		if let node = nodes[edge] {
			return node
		}

		let node = parents.count
		parents.append(parent)
		readsByNode.append(nil)
		nodes[edge] = node
		return node
	}

	func reads(of object: SOML.Object, at node: Int, codingPath: CodingPath) -> Reads {
		if let reads = readsByNode[node] {
			return reads
		}

		let reads = Reads(object: object, node: node, codingPath: codingPath)
		readsByNode[node] = reads
		orderedReads.append(reads)
		return reads
	}

	/**
	Throws for the first member of an object that no keyed container looked up.
	*/
	func checkUnknownKeys(rootType: Any.Type, document: SOML.Value) throws(DecodingError) {
		for reads in orderedReads where !reads.readsAllKeys {
			let object = reads.object

			// Building a Set and subtracting read keys measured 1.6–4.1 times slower and still needs a source-order scan to select the first unknown key.
			guard let unknownKey = object.keys.first(where: { !reads.keys.contains(ExactKey($0)) }) else {
				continue
			}

			// An object that only nested containers read belongs to the closest type that read an object around it.
			// UnfoldSequence is not a Collection, so .lazy.compactMap(...).first selects the eager Array-producing overload; first(where:) stops at the nearest typed ancestor.
			let type = reads.type ?? sequence(first: reads.node) { self.parents[$0] }.first(where: { self.readsByNode[$0]?.type != nil }).flatMap { self.readsByNode[$0]?.type } ?? rootType

			let codingPath = reads.codingPath.keys

			// A misspelling is likely one of the keys the type looked for that the document does not have. With defaults, the decoded object has every key, so look in the document.
			let suggestion: String
			if unknownKey.unicodeScalars.prefix(65).count <= 64 {
				let documentObject = document.value(at: codingPath, keySeparator: keySeparator)?.objectValue ?? object
				// The suggestion is not shortened, as it is what to write, and `closest(in:)` only suggests a key for a short one.
				let candidates = reads.keys.lazy.prefix(1000).map(\.string).filter { !documentObject.contains(key: $0) }

				// Keys are compared by their Unicode scalars, so a key in another Unicode normalization is another key, though it looks the same, as for a missing key.
				if let equivalent = candidates.first(where: { $0.isEquivalentKey(to: unknownKey) }) {
					suggestion = ". \(type) reads \(SOML.KeyPath.Segment.key(equivalent).described), which looks the same, but is written with other Unicode scalars, so it is another key"
				} else {
					suggestion = unknownKey.closest(in: candidates).map { ". Did you mean \(CanonicalWriter.key($0).sanitizedForTerminal)?" } ?? ""
				}
			} else {
				suggestion = ""
			}
			throw DecodingError.dataCorrupted(.init(codingPath: codingPath + [SOMLCodingKey(stringValue: unknownKey)], debugDescription: "Unknown key \(SOML.KeyPath.Segment.key(unknownKey).described), which \(type) does not read\(suggestion)"))
		}
	}
}

extension String {
	/**
	Whether the key is canonically equivalent to `key`, a key of at most 64 scalars, so that it looks the same. `String` equality normalizes, which takes quadratic time for a long run of combining marks, so a key longer than any that can be equivalent to such a short one is not compared, as a scalar decomposes to at most 4.
	*/
	fileprivate func isEquivalentKey(to key: String) -> Bool {
		unicodeScalars.prefix(4 * 64 + 1).count <= 4 * 64 && self == key
	}
}

extension SOML.Value {
	/**
	Whether the value is nested more than `limit` levels, where every array and object is one level, as a reader counts. It stops at the limit before descending further, so that a deep value cannot overflow the stack and a wide value needs no traversal array.
	*/
	func isDeeperThan(_ limit: Int) -> Bool {
		switch self {
		case .array(let items):
			limit < 1 || items.contains { $0.isDeeperThan(limit - 1) }
		case .object(let object):
			limit < 1 || object.values.contains { $0.isDeeperThan(limit - 1) }
		default:
			false
		}
	}

	/**
	The value at a coding path of the decoder, or `nil` if there is none.
	*/
	fileprivate func value(at codingPath: [any CodingKey], keySeparator: Character?) -> SOML.Value? {
		var value = self

		for key in codingPath {
			switch value {
			case .object(let object):
				guard let member = object[key.documentKey(separator: keySeparator)] else {
					return nil
				}

				value = member
			case .array(let items):
				guard
					let index = key.intValue,
					items.indices.contains(index)
				else {
					return nil
				}

				value = items[index]
			default:
				return nil
			}
		}

		return value
	}
}

/**
Lets the decoder read a dictionary with keys like `String` or a `CodingKeyRepresentable` enum directly, so that a key strategy does not change the dictionary's keys, which a type that reads `allKeys` would get converted back to camelCase, and then not find.
*/
protocol KeyedDictionaryDecodable {
	init(object: SOML.Object, decoder: DecoderImplementation) throws
}

extension Dictionary: KeyedDictionaryDecodable where Key: CodingKeyRepresentable, Value: Decodable {
	init(object: SOML.Object, decoder: DecoderImplementation) throws {
		// An `Int` key is digits, which a key strategy does not change, and `Dictionary` reads it with its int value in the coding path.
		if Key.self == Int.self {
			// `Dictionary` reads the keys through `allKeys`, which a key strategy converts, so a key that is not an int is refused here, as the document writes it, and with its own location.
			if let key = object.keys.first(where: { Int($0) == nil }) {
				throw DecodingError.typeMismatch(Int.self, .init(codingPath: decoder.codingPath(appending: SOMLCodingKey(stringValue: key)), debugDescription: "Expected Int key but found String key instead."))
			}

			self = try [Int: Value](from: decoder) as! Self
			return
		}

		self.init(minimumCapacity: object.count)

		for (key, value) in object {
			let codingKey = SOMLCodingKey(stringValue: key)

			// A key type with an `Int` raw value makes its key only from a coding key with an int value, which `Dictionary` gives it for a key of digits.
			guard let dictionaryKey = Key(codingKey: codingKey) else {
				guard
					let int = Int(key),
					let intKey = Key(codingKey: SOMLCodingKey.key(ExactKey(key), intValue: int))
				else {
					throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath(appending: codingKey), debugDescription: "Could not convert key to type \(Key.self)"))
				}

				// A key that only the int makes keeps its int value, as for `[Int: T]` above, and its spelling in the document, so keys like `01` and `1` have separate reads.
				self[intKey] = try decoder.unbox(value, as: Value.self, key: SOMLCodingKey.key(ExactKey(key), intValue: int))
				continue
			}

			self[dictionaryKey] = try decoder.unbox(value, as: Value.self, key: codingKey)
		}
	}
}

extension String {
	/**
	The candidate closest to the string, if it is close enough to be a likely misspelling: at most one edit for a short key, and at most one edit per three scalars for a longer one. A tie goes to the candidate first in scalar order, so the result does not depend on the order of the candidates.

	A string longer than 64 scalars gets no suggestion, because a hint is no help for such a key, and only the first 1000 source candidates are examined, before filtering, so that hostile input cannot make an error slow to build, even for a type that catches it and goes on.
	*/
	fileprivate func closest(in candidates: some Sequence<String>) -> String? {
		let scalars = Array(unicodeScalars.prefix(65))

		guard scalars.count <= 64 else {
			return nil
		}

		let maximumDistance = Swift.max(1, scalars.count / 3)
		// A difference only in case, like `docs-URL` for `docs-url`, is the likeliest misspelling, so the distance ignores case, however many letters differ.
		let lowercaseScalars = scalars.map(\.lowercaseScalar)
		// A lazy filter/min(by:) pipeline measured slower for populated candidate lists; retain the single-pass selection and its explicit work limits.
		var closest: (distance: Int, key: String)?

		for candidate in candidates.prefix(1000) {
			let candidateScalars = Array(candidate.unicodeScalars.prefix(scalars.count + maximumDistance + 1))

			guard
				abs(candidateScalars.count - scalars.count) <= maximumDistance,
				candidateScalars != scalars
			else {
				continue
			}

			let distance = lowercaseScalars.editDistance(to: candidateScalars.map(\.lowercaseScalar))

			guard distance <= maximumDistance else {
				continue
			}

			if let closest {
				guard distance < closest.distance || (distance == closest.distance && candidate.scalarOrderPrecedes(closest.key)) else {
					continue
				}
			}

			closest = (distance, candidate)
		}

		return closest?.key
	}
}

extension Unicode.Scalar {
	/**
	The scalar in lowercase, or the scalar itself when its lowercase is not one scalar.
	*/
	fileprivate var lowercaseScalar: Self {
		guard !isASCII else {
			return (0x41...0x5A).contains(value) ? Self(UInt8(value) + 0x20) : self
		}

		let lowercase = properties.lowercaseMapping.unicodeScalars
		return lowercase.count == 1 ? lowercase.first ?? self : self
	}
}

extension [Unicode.Scalar] {
	/**
	The optimal string alignment distance to another string: the fewest insertions, deletions, substitutions, and swaps of two neighbors that turn one into the other. A swap counts as one edit, because it is a common typo, like `hots` for `host`.
	*/
	fileprivate func editDistance(to other: Self) -> Int {
		guard !isEmpty else {
			return other.count
		}

		guard !other.isEmpty else {
			return count
		}

		// TODO: Remove the ContiguousArray fallback once Swift 6.4 is the minimum requirement.
		#if compiler(>=6.4)
		return withTemporaryAllocation(of: Int.self, capacity: other.count + 1) { beforePrevious in
			beforePrevious.append(repeating: 0, count: other.count + 1)

			return withTemporaryAllocation(of: Int.self, capacity: other.count + 1) { previous in
				for index in 0...other.count {
					previous.append(index)
				}

				return withTemporaryAllocation(of: Int.self, capacity: other.count + 1) { scratch in
					scratch.append(repeating: 0, count: other.count + 1)
					return editDistance(to: other, beforePrevious: beforePrevious.mutableSpan, previous: previous.mutableSpan, scratch: scratch.mutableSpan)
				}
			}
		}
		#else
		var beforePrevious = ContiguousArray<Int>(repeating: 0, count: other.count + 1)
		var previous = ContiguousArray<Int>(0...other.count)
		var scratch = beforePrevious
		return editDistance(to: other, beforePrevious: beforePrevious.mutableSpan, previous: previous.mutableSpan, scratch: scratch.mutableSpan)
		#endif
	}

	/**
	Calculates the distance using three borrowed scratch rows, sharing the algorithm across storage types.
	*/
	private func editDistance(to other: Self, beforePrevious: consuming MutableSpan<Int>, previous: consuming MutableSpan<Int>, scratch: consuming MutableSpan<Int>) -> Int {
		// A single temporary OutputSpan with row offsets measured 24% slower for two 64-scalar keys; separate temporary rows avoid that indexing overhead and heap allocations for common short keys.
		var rowBeforePrevious = consume beforePrevious
		var previousRow = consume previous
		var row = consume scratch

		for index in indices {
			row[0] = index + 1

			for otherIndex in other.indices {
				var distance = Swift.min(previousRow[otherIndex + 1] + 1, row[otherIndex] + 1, previousRow[otherIndex] + (self[index] == other[otherIndex] ? 0 : 1))

				if
					index > 0,
					otherIndex > 0,
					self[index] == other[otherIndex - 1],
					self[index - 1] == other[otherIndex]
				{
					distance = Swift.min(distance, rowBeforePrevious[otherIndex - 1] + 1)
				}

				row[otherIndex + 1] = distance
			}

			let oldest = consume rowBeforePrevious
			rowBeforePrevious = consume previousRow
			previousRow = consume row
			row = consume oldest
		}

		return previousRow[other.count]
	}
}

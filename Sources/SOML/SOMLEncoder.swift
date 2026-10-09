#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension SOML {
	/**
	Encodes `Encodable` values as SOML documents.

	```swift
	struct Config: Encodable {
		let name: String
		let replicas: Int
		let labels: [String]
	}

	var encoder = SOML.Encoder()
	encoder.keyEncodingStrategy = .convertToKebabCase

	let text = try encoder.encodeToString(Config(name: "api-gateway", replicas: 3, labels: ["prod"]))
	//=> """
	//	name: 'api-gateway'
	//	replicas: 3
	//	labels: [
	//		'prod'
	//	]
	//
	//	"""
	```

	The output follows every rule of canonical form, as the spec defines it, except that members keep their order, because sorted keys are noise to a person who reads the file. Nesting uses braces, and there are no comments.

	- A type writes its members in the order it encodes them, which for a synthesized `Encodable` conformance is the order the properties are declared in.
	- A `Dictionary` writes its members in its iteration order, as `JSONEncoder` does without `.sortedKeys`, so the order can change from one run to the next.
	- A `SOML.Value` or `SOML.Object` writes its members in the order they were added, which for a parsed document is the order in the source.

	Set `writesCanonicalForm` to sort the members by key, so that the output is exactly canonical form and the same value always gives the same bytes, like for a hash, or for a stable order of a `Dictionary`. It does not sort arrays, so a `Set` is still written in its iteration order, which can change from one run to the next. Sort it into an array first if you need the same bytes.

	A document must be an object or an array, so encoding a single scalar throws.

	| Swift | SOML |
	|---|---|
	| `String` | string. A carriage return throws, because SOML cannot represent one. |
	| `Bool` | bool |
	| Integer types | int. A value outside the int64 range throws. |
	| `Double`, `Float`, `Float16` | float. NaN throws. |
	| `nil` | `null`. Synthesized `Encodable` conformances leave out `nil` properties. |
	| `Date` | instant, with the fewest fractional digits that read back as the same `Date` |
	| `SOML.Instant` | instant |
	| `Duration` | duration. A fraction of a nanosecond, or a value outside the int64 range of nanoseconds, throws. |
	| `URL` | string |
	| `Data` | base64 string |
	| `SOML.Value`, `SOML.Object` | unchanged |
	*/
	public struct Encoder: Sendable {
		/**
		How the encoder writes coding keys as keys in the document.
		*/
		public enum KeyEncodingStrategy: Sendable {
			/**
			Use the coding key as it is.
			*/
			case useDefaultKeys

			/**
			Write keys in kebab-case: the coding key `deployedAt` becomes `deployed-at`, and `baseURL` becomes `base-url`.

			Keys of a `[String: T]` property or element are not converted. If two coding keys convert to the same key, the last value wins.
			*/
			case convertToKebabCase

			/**
			Write keys in snake_case: the coding key `deployedAt` becomes `deployed_at`, and `baseURL` becomes `base_url`.

			Keys of a `[String: T]` property or element are not converted. If two coding keys convert to the same key, the last value wins.
			*/
			case convertToSnakeCase

			var separator: Character? {
				switch self {
				case .useDefaultKeys:
					nil
				case .convertToKebabCase:
					"-"
				case .convertToSnakeCase:
					"_"
				}
			}
		}

		/**
		How coding keys are written. The default is `.useDefaultKeys`.
		*/
		public var keyEncodingStrategy = KeyEncodingStrategy.useDefaultKeys

		/**
		Whether to write exactly canonical form, with the members of every object sorted by the Unicode scalars of their keys, so that the same value always gives the same bytes. The default is `false`, which keeps the order of the members.

		```swift
		var encoder = SOML.Encoder()
		encoder.writesCanonicalForm = true

		let text = try encoder.encodeToString(Config(name: "api-gateway", replicas: 3, labels: ["prod"]))
		//=> """
		//	labels: [
		//		'prod'
		//	]
		//	name: 'api-gateway'
		//	replicas: 3
		//
		//	"""
		```

		`SOML.Value.canonicalDocument()` writes the same text for a value.
		*/
		public var writesCanonicalForm = false

		/**
		Contextual information for the types you encode, which they read from `Encoder.userInfo`.
		*/
		public var userInfo = [CodingUserInfoKey: any Sendable]()

		/**
		Creates an encoder with the default options.
		*/
		public init() {}

		/**
		Encodes a value as a SOML document in UTF-8.

		- Throws: `EncodingError.invalidValue` if the value is not an object or an array, or if it contains something SOML cannot represent.
		*/
		public func encode(_ value: some Encodable) throws -> Data {
			Data(try encodeToBytes(value))
		}

		/**
		Encodes a value as the text of a SOML document.

		- Throws: `EncodingError.invalidValue` if the value is not an object or an array, or if it contains something SOML cannot represent.
		*/
		public func encodeToString(_ value: some Encodable) throws -> String {
			String(decoding: try encodeToBytes(value), as: UTF8.self)
		}

		/**
		Encodes a value as a `SOML.Value` tree, without writing it out.

		Unlike `encode(_:)`, this accepts a single scalar.
		*/
		public func encodeToValue(_ value: some Encodable) throws -> SOML.Value {
			let encoder = EncoderImplementation(options: options, codingPath: .root)
			return try encoder.box(value, key: nil).finalized()
		}

		private func encodeToBytes(_ value: some Encodable) throws -> [UInt8] {
			let tree = try encodeToValue(value)

			do {
				return try CanonicalWriter.document(tree, sortsMembers: writesCanonicalForm)
			} catch {
				throw EncodingError.invalidValue(value, .init(codingPath: error.codingPath, debugDescription: error.message))
			}
		}

		private var options: EncoderImplementation.Options {
			.init(keySeparator: keyEncodingStrategy.separator, userInfo: userInfo)
		}
	}
}

/**
A value while it is being encoded. Containers are references, so that a container can be filled after it is handed out.
*/
enum EncodedValue {
	case value(SOML.Value)
	case object(ObjectStorage)
	case array(ArrayStorage)
	case invalid(EncodingError)

	/**
	A value encoded by an encoder that is still in use, such as one from `superEncoder()`.
	*/
	case pending(EncoderImplementation)

	/**
	Attaches a nested encoder only within the depth limit, so manual container creation cannot build a tree that overflows the stack during finalization or destruction.
	*/
	init(pending encoder: EncoderImplementation) {
		guard encoder.depth <= Parser.maximumDepth else {
			self = .invalid(.tooDeep(codingPath: encoder.codingPath))
			return
		}

		self = .pending(encoder)
	}

	func finalized() throws(EncodingError) -> SOML.Value {
		switch self {
		case .value(let value):
			value
		case .object(let storage):
			.object(SOML.Object(try storage.members.mapValues { (value) throws(EncodingError) in
				try value.finalized()
			}))
		case .array(let storage):
			.array(try storage.items.map { (value) throws(EncodingError) in
				try value.finalized()
			})
		case .invalid(let error):
			throw error
		case .pending(let encoder):
			// An encoder that encoded nothing gives an empty object, like `JSONEncoder`.
			try encoder.result?.finalized() ?? .object([:])
		}
	}

	/**
	Whether the two values take different storage on an encoder, so that one cannot replace the other without losing the first's members. A container that a single value container encodes, like a struct, has storage of its own, so it is different from the container already there, even when both are objects.
	*/
	func hasOtherStorage(as other: EncodedValue) -> Bool {
		switch (self, other) {
		case (.value, .value):
			false
		case (.object(let storage), .object(let otherStorage)):
			storage !== otherStorage
		case (.array(let storage), .array(let otherStorage)):
			storage !== otherStorage
		default:
			true
		}
	}

	/**
	What the storage is called, for the error of `EncoderImplementation.result`.
	*/
	var storageName: String {
		switch self {
		case .value:
			"a single value"
		case .object, .pending:
			"an object"
		case .array:
			"an array"
		case .invalid:
			"an invalid value"
		}
	}
}

final class ObjectStorage {
	private(set) var members = OrderedMembers<EncodedValue>()

	/**
	Sets a member. Encoding the same key twice replaces the earlier value.
	*/
	func set(_ value: EncodedValue, forKey key: String) {
		members.set(value, forKey: key)
	}

	/**
	The value of a member, or `nil` if there is none.
	*/
	func member(forKey key: String) -> EncodedValue? {
		members.value(forKey: key)
	}
}

final class ArrayStorage {
	var items = [EncodedValue]()
}

/**
The `Encoder` for one value in the tree.

Primitive containers keep explicit witnesses for the common `Bool`, `String`, `Double`, and `Int` fast paths. The other ordinary primitives share generic boxing or unboxing. `Int128` and `UInt128` also need explicit witnesses, because their Codable protocol defaults report unsupported types instead of forwarding to the generic implementation.
*/
final class EncoderImplementation: Encoder {
	struct Options {
		let keySeparator: Character?
		let userInfo: [CodingUserInfoKey: Any]

		/**
		Accepts only Sendable context and erases it once for the Encoder protocol, sharing the dictionary with nested encoders and repeated userInfo reads.
		*/
		init(keySeparator: Character?, userInfo: [CodingUserInfoKey: any Sendable]) {
			self.keySeparator = keySeparator
			self.userInfo = userInfo.mapValues { $0 as Any }
		}
	}

	let options: Options
	private let path: CodingPath
	private var storedResult: EncodedValue?

	/**
	The value that this encoder holds.

	Setting a value whose storage differs from the one already there records an error instead of replacing it, because the first value's members would be silently lost, which `JSONEncoder` refuses with a precondition. The error surfaces when the tree is finalized, and the encoder keeps working, so the rest of the type's encoding can go on. A single value replaces a single value, as when a single value container encodes a scalar twice.
	*/
	var result: EncodedValue? {
		get { storedResult }
		set {
			guard let new = newValue else {
				return
			}

			if case .invalid = storedResult {
				// The first conflict is the one the encode reports.
				return
			}

			guard
				let old = storedResult,
				old.hasOtherStorage(as: new)
			else {
				storedResult = new
				return
			}

			storedResult = .invalid(EncodingError.invalidValue(new, .init(codingPath: codingPath, debugDescription: "The type wrote \(old.storageName) and then \(new.storageName) with the same encoder, which would lose what it wrote first")))
		}
	}

	var codingPath: [any CodingKey] {
		path.keys
	}

	var userInfo: [CodingUserInfoKey: Any] {
		options.userInfo
	}

	/**
	The nesting level of the value. Coding paths stop growing once this exceeds the limit.
	*/
	let depth: Int

	init(options: Options, codingPath: CodingPath, depth: Int = 0) {
		self.options = options
		self.path = codingPath
		self.depth = depth
	}

	/**
	An encoder for a nested value at `key`, relative to this one. Beyond the depth limit, the path stays at the invalid prefix so detached encoders cannot create an arbitrarily deep path.
	*/
	func makeEncoder(key: (any CodingKey)?) -> EncoderImplementation {
		EncoderImplementation(options: options, codingPath: depth > Parser.maximumDepth ? path : path.appending(key), depth: key == nil ? depth : depth + 1)
	}

	/**
	The coding path of this encoder, followed by `key` if there is one. It is only built for errors.
	*/
	func codingPath(appending key: (any CodingKey)?) -> [any CodingKey] {
		path.appending(key).keys
	}

	/**
	The members of the object this encoder writes. A type and its superclass can both ask for a keyed container, and a type can flatten a `SOML.Object` into its own encoder, so they all share one storage.
	*/
	func objectStorage() -> ObjectStorage {
		if case .object(let storage) = result {
			return storage
		}

		let storage = ObjectStorage()
		result = newContainer(.object(storage))
		return storage
	}

	/**
	The result for a new container, or an error when it would be nested past the limit, which a container of this encoder is at `depth + 1`. The writer refuses it too, but only after the key strategy has converted the keys of its coding path, so the error is made here, with the coding keys of the type. The storage that the container writes to is kept apart, so that the type can finish encoding.
	*/
	private func newContainer(_ container: EncodedValue) -> EncodedValue {
		guard depth < Parser.maximumDepth else {
			return .invalid(.tooDeep(codingPath: codingPath))
		}

		return container
	}

	func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
		KeyedEncodingContainer(KeyedContainer(encoder: self, storage: objectStorage()))
	}

	func unkeyedContainer() -> any UnkeyedEncodingContainer {
		if case .array(let storage) = result {
			return UnkeyedContainer(encoder: self, storage: storage)
		}

		let storage = ArrayStorage()
		result = newContainer(.array(storage))
		return UnkeyedContainer(encoder: self, storage: storage)
	}

	func singleValueContainer() -> any SingleValueEncodingContainer {
		self
	}

	func convertedKey(_ key: some CodingKey) -> String {
		key.documentKey(separator: options.keySeparator)
	}

	// MARK: Boxing

	func box<T: Encodable>(_ value: T, key: (any CodingKey)?) throws -> EncodedValue {
		// Comparing metatypes is a pointer comparison, while a failed `as?` cast is a runtime type search, and this runs for every value. Common primitives come first, because a generic container such as `[String]` encodes each element through here, and would otherwise create an encoder for each one.
		if T.self == String.self {
			return try boxString(value as! String, key: key)
		}

		if T.self == Int.self {
			return try boxInteger(value as! Int, key: key)
		}

		if T.self == Double.self {
			return try boxFloat(value as! Double, key: key)
		}

		if T.self == Bool.self {
			return .value(.bool(value as! Bool))
		}

		if T.self == Int64.self {
			return .value(.int(value as! Int64))
		}

		if T.self == Float.self {
			return try boxFloat(value as! Float, key: key)
		}

		#if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
		if T.self == Float16.self {
			return try boxFloat(value as! Float16, key: key)
		}
		#endif

		if T.self == UInt8.self {
			return .value(.int(Int64(value as! UInt8)))
		}

		if T.self == Int32.self {
			return .value(.int(Int64(value as! Int32)))
		}

		if T.self == UInt64.self {
			return try boxInteger(value as! UInt64, key: key)
		}

		if T.self == Int8.self {
			return .value(.int(Int64(value as! Int8)))
		}

		if T.self == Int16.self {
			return .value(.int(Int64(value as! Int16)))
		}

		if T.self == UInt16.self {
			return .value(.int(Int64(value as! UInt16)))
		}

		if T.self == UInt32.self {
			return .value(.int(Int64(value as! UInt32)))
		}

		if T.self == UInt.self {
			return try boxInteger(value as! UInt, key: key)
		}

		if T.self == Int128.self {
			return try boxInteger(value as! Int128, key: key)
		}

		if T.self == UInt128.self {
			return try boxInteger(value as! UInt128, key: key)
		}

		if T.self == SOML.Value.self {
			return .value(value as! SOML.Value)
		}

		if T.self == SOML.Object.self {
			return .value(.object(value as! SOML.Object))
		}

		if T.self == SOML.Instant.self {
			return .value(.instant(value as! SOML.Instant))
		}

		if T.self == Date.self {
			let date = value as! Date

			guard let instant = SOML.Instant(date) else {
				// The message does not show the date, because `Date.description` uses the Julian calendar before 1582, so `Date.distantPast` would read as 0001-01-01, and it is empty for a date far in the future.
				let end = date < SOML.Instant.minimum.date ? "before \(SOML.Instant.minimum), the earliest" : "after \(SOML.Instant.maximum), the latest"
				throw EncodingError.invalidValue(date, .init(codingPath: codingPath(appending: key), debugDescription: "The date is \(end) SOML instant"))
			}

			return .value(.instant(instant))
		}

		// `Duration`'s own `Encodable` conformance writes two integers, which would silently become an array.
		if T.self == Duration.self {
			let duration = value as! Duration

			guard duration.exactNanoseconds != nil else {
				throw EncodingError.invalidValue(duration, .init(codingPath: codingPath(appending: key), debugDescription: duration.unrepresentableReason))
			}

			return .value(.duration(duration))
		}

		if T.self == URL.self {
			return .value(.string((value as! URL).absoluteString))
		}

		if T.self == Data.self {
			return .value(.string((value as! Data).base64EncodedString()))
		}

		let encoder = makeEncoder(key: key)

		// Only a key strategy needs this, and the protocol check is slow, so skip it otherwise, like `JSONEncoder` does.
		if
			options.keySeparator != nil,
			let dictionary = value as? any StringKeyedDictionaryEncodable
		{
			// The dictionary is an object, so it is refused past the limit here, like a keyed container, with the coding keys of the type rather than the converted keys the writer would report.
			guard encoder.depth < Parser.maximumDepth else {
				throw EncodingError.tooDeep(codingPath: encoder.codingPath)
			}

			return .value(.object(try dictionary.encodeMembers(with: encoder)))
		}

		// Stop a value that nests too deeply, such as a cycle of class references, before it overflows the stack. The writer would refuse it anyway.
		guard encoder.depth <= Parser.maximumDepth else {
			throw EncodingError.tooDeep(codingPath: codingPath(appending: key))
		}

		try value.encode(to: encoder)
		return encoder.result ?? .value(.object([:]))
	}

	/**
	A string, checked for a carriage return here rather than when the document is written, so that the error has the coding keys of the type, and not the keys that a key strategy writes.
	*/
	func boxString(_ value: String, key: (any CodingKey)?) throws(EncodingError) -> EncodedValue {
		guard !value.hasCarriageReturn else {
			throw EncodingError.invalidValue(value, .init(codingPath: codingPath(appending: key), debugDescription: "A string cannot contain a carriage return, because SOML cannot represent one"))
		}

		return .value(.string(value))
	}

	func boxInteger(_ value: some FixedWidthInteger, key: (any CodingKey)?) throws(EncodingError) -> EncodedValue {
		guard let int = Int64(exactly: value) else {
			throw EncodingError.invalidValue(value, .init(codingPath: codingPath(appending: key), debugDescription: "The integer \(value) is outside the int64 range, which is the range of a SOML int"))
		}

		return .value(.int(int))
	}

	func boxFloat<T: BinaryFloatingPoint & LosslessStringConvertible>(_ value: T, key: (any CodingKey)?) throws(EncodingError) -> EncodedValue {
		guard !value.isNaN else {
			throw EncodingError.invalidValue(value, .init(codingPath: codingPath(appending: key), debugDescription: "NaN is not a SOML value"))
		}

		if let double = value as? Double {
			return .value(.float(double))
		}

		// Use the shortest decimal for the narrower type, so that `Float(0.1)` is written as 0.1, which decodes back to the same `Float`. Rounding that decimal to a `Double` and then to the narrower type rarely gives the next value, like for the `Float` 7.038531e-26, so then the exact value is written instead.
		if
			let shortest = Double(value.description),
			T(shortest) == value
		{
			return .value(.float(shortest))
		}

		return .value(.float(Double(value)))
	}
}

extension EncoderImplementation: SingleValueEncodingContainer {
	func encodeNil() {
		result = .value(.null)
	}

	func encode(_ value: Bool) {
		result = .value(.bool(value))
	}

	func encode(_ value: String) throws(EncodingError) {
		result = try boxString(value, key: nil)
	}

	func encode(_ value: Double) throws(EncodingError) {
		result = try boxFloat(value, key: nil)
	}

	func encode(_ value: Int) throws(EncodingError) {
		result = try boxInteger(value, key: nil)
	}

	func encode(_ value: Int128) throws(EncodingError) {
		result = try boxInteger(value, key: nil)
	}

	func encode(_ value: UInt128) throws(EncodingError) {
		result = try boxInteger(value, key: nil)
	}

	func encode<T: Encodable>(_ value: T) throws {
		result = try box(value, key: nil)
	}
}

private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
	let encoder: EncoderImplementation
	let storage: ObjectStorage

	var codingPath: [any CodingKey] {
		encoder.codingPath
	}

	private func set(_ value: EncodedValue, forKey key: Key) {
		storage.set(value, forKey: encoder.convertedKey(key))
	}

	mutating func encodeNil(forKey key: Key) {
		set(.value(.null), forKey: key)
	}

	mutating func encode(_ value: Bool, forKey key: Key) {
		set(.value(.bool(value)), forKey: key)
	}

	mutating func encode(_ value: String, forKey key: Key) throws(EncodingError) {
		set(try encoder.boxString(value, key: key), forKey: key)
	}

	mutating func encode(_ value: Double, forKey key: Key) throws(EncodingError) {
		set(try encoder.boxFloat(value, key: key), forKey: key)
	}

	mutating func encode(_ value: Int, forKey key: Key) throws(EncodingError) {
		set(try encoder.boxInteger(value, key: key), forKey: key)
	}

	mutating func encode(_ value: Int128, forKey key: Key) throws(EncodingError) {
		set(try encoder.boxInteger(value, key: key), forKey: key)
	}

	mutating func encode(_ value: UInt128, forKey key: Key) throws(EncodingError) {
		set(try encoder.boxInteger(value, key: key), forKey: key)
	}

	mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
		set(try encoder.box(value, key: key), forKey: key)
	}

	/**
	The encoder for a nested value at `key`. A type and its superclass can both ask for one, and they share it, as with `JSONEncoder`, so neither replaces what the other wrote.
	*/
	private func sharedEncoder(forKey key: some CodingKey, documentKey: String, member: EncodedValue?) -> EncoderImplementation {
		if case .pending(let nested) = member {
			return nested
		}

		let nested = encoder.makeEncoder(key: key)
		storage.set(.init(pending: nested), forKey: documentKey)
		return nested
	}

	/**
	Looks up an existing encoder once using the document's spelling of the key.
	*/
	private func sharedEncoder(forKey key: some CodingKey) -> EncoderImplementation {
		let documentKey = encoder.convertedKey(key)
		return sharedEncoder(forKey: key, documentKey: documentKey, member: storage.member(forKey: documentKey))
	}

	/**
	The encoder for a nested container at `key`, which also goes on filling an object or array that `encode(_:forKey:)` wrote, like a struct, as with `JSONEncoder`. A container of the other kind, like an unkeyed one after a struct, is an error, where `JSONEncoder` traps.
	*/
	private func nestedEncoder(forKey key: Key) -> EncoderImplementation {
		let documentKey = encoder.convertedKey(key)
		let member = storage.member(forKey: documentKey)
		let nested = sharedEncoder(forKey: key, documentKey: documentKey, member: member)

		switch member {
		case .object, .array:
			nested.result = member
		case .value(.object(let object)):
			let storage = ObjectStorage()

			for (key, value) in object {
				storage.set(.value(value), forKey: key)
			}

			nested.result = .object(storage)
		case .value(.array(let items)):
			let storage = ArrayStorage()
			storage.items = items.map(EncodedValue.value)
			nested.result = .array(storage)
		default:
			break
		}

		return nested
	}

	mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
		nestedEncoder(forKey: key).container(keyedBy: keyType)
	}

	mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
		nestedEncoder(forKey: key).unkeyedContainer()
	}

	mutating func superEncoder() -> any Encoder {
		sharedEncoder(forKey: SOMLCodingKey.super)
	}

	mutating func superEncoder(forKey key: Key) -> any Encoder {
		sharedEncoder(forKey: key)
	}
}

private struct UnkeyedContainer: UnkeyedEncodingContainer {
	let encoder: EncoderImplementation
	let storage: ArrayStorage

	var codingPath: [any CodingKey] {
		encoder.codingPath
	}

	var count: Int {
		storage.items.count
	}

	private var nextKey: SOMLCodingKey {
		SOMLCodingKey(intValue: count)
	}

	mutating func encodeNil() {
		storage.items.append(.value(.null))
	}

	mutating func encode(_ value: Bool) {
		storage.items.append(.value(.bool(value)))
	}

	mutating func encode(_ value: String) throws(EncodingError) {
		storage.items.append(try encoder.boxString(value, key: nextKey))
	}

	mutating func encode(_ value: Double) throws(EncodingError) {
		storage.items.append(try encoder.boxFloat(value, key: nextKey))
	}

	mutating func encode(_ value: Int) throws(EncodingError) {
		storage.items.append(try encoder.boxInteger(value, key: nextKey))
	}

	mutating func encode(_ value: Int128) throws(EncodingError) {
		storage.items.append(try encoder.boxInteger(value, key: nextKey))
	}

	mutating func encode(_ value: UInt128) throws(EncodingError) {
		storage.items.append(try encoder.boxInteger(value, key: nextKey))
	}

	mutating func encode<T: Encodable>(_ value: T) throws {
		storage.items.append(try encoder.box(value, key: nextKey))
	}

	mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
		appendEncoder().container(keyedBy: keyType)
	}

	mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
		appendEncoder().unkeyedContainer()
	}

	mutating func superEncoder() -> any Encoder {
		appendEncoder()
	}

	/**
	Appends one pending value and returns its encoder, sharing index and depth handling for every nested container.
	*/
	private func appendEncoder() -> EncoderImplementation {
		let nested = encoder.makeEncoder(key: nextKey)
		storage.items.append(.init(pending: nested))
		return nested
	}
}

/**
Lets the encoder write a `[String: T]` directly, so that a key strategy does not change the dictionary's keys.
*/
protocol StringKeyedDictionaryEncodable {
	func encodeMembers(with encoder: EncoderImplementation) throws -> SOML.Object
}

extension Dictionary: StringKeyedDictionaryEncodable where Key == String, Value: Encodable {
	func encodeMembers(with encoder: EncoderImplementation) throws -> SOML.Object {
		var members = OrderedMembers<SOML.Value>()
		members.reserveCapacity(count)

		for (key, value) in self {
			let codingKey = SOMLCodingKey(stringValue: key)

			// Checked here, with the coding keys, rather than when the document is written, after the key strategy has converted the keys of the path to the dictionary.
			guard !key.hasCarriageReturn else {
				throw EncodingError.invalidValue(key, .init(codingPath: encoder.codingPath(appending: codingKey), debugDescription: "A key cannot contain a carriage return, because SOML cannot represent one"))
			}

			members.append(try encoder.box(value, key: codingKey).finalized(), forKey: key)
		}

		return SOML.Object(members)
	}
}

extension EncodingError {
	/**
	The error for a value nested more deeply than a SOML reader accepts.
	*/
	static func tooDeep(codingPath: [any CodingKey]) -> Self {
		.invalidValue(codingPath.count, .init(codingPath: codingPath, debugDescription: "The value is nested more than \(Parser.maximumDepth) levels deep, which is the most a SOML reader accepts"))
	}
}

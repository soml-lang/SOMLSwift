extension SOML {
	/**
	A SOML object: a collection of members with unique keys.

	Keys are compared by their Unicode scalars, as the spec requires, and never by canonical equivalence the way Swift's `String ==` compares. So `"\u{E9}"` and `"e\u{301}"` are two different keys here.

	The object keeps the order in which members were added, which for a parsed document is the source order, and iterating it gives that order. The order is not part of the value: two objects with the same members are equal in any order, and canonical form sorts the members. `SOML.Encoder` keeps the order, unless `writesCanonicalForm` is on.

	```swift
	var object: SOML.Object = ["name": "api-gateway", "replicas": 3]
	object["timeout"] = 30.0

	for (key, value) in object {
		print(key, value)
	}
	```
	*/
	public struct Object: Sendable {
		/**
		A member: its key and its value.
		*/
		public typealias Element = (key: String, value: SOML.Value)

		private var members: OrderedMembers<SOML.Value>

		/**
		Creates an empty object.
		*/
		public init() {
			self.members = OrderedMembers()
		}

		/**
		Creates an object from key and value pairs.

		If a key appears more than once, the last value wins and the position of the first one is kept.
		*/
		public init(_ members: some Sequence<(String, SOML.Value)>) {
			self.init()
			self.members.reserveCapacity(members.underestimatedCount)

			for (key, value) in members {
				self.members.set(value, forKey: key)
			}
		}

		/**
		Creates an object from labeled key and value pairs, like a dictionary or the result of filtering another object.

		If a key appears more than once, the last value wins and the position of the first one is kept.

		```swift
		let dictionary: [String: SOML.Value] = ["name": "api-gateway", "replicas": 3]
		let object = SOML.Object(dictionary)
		let small = SOML.Object(object.filter { $0.key != "replicas" })
		```
		*/
		public init(_ members: some Sequence<Element>) {
			self.init(members.lazy.map { ($0.key, $0.value) })
		}

		init(_ members: OrderedMembers<SOML.Value>) {
			self.members = members
		}

		/**
		The value for a key, or `nil` if the object has no member with that key.

		Setting a value replaces the member in place or adds it at the end. Setting `nil` removes the member.
		*/
		public subscript(key: String) -> SOML.Value? {
			get {
				members.value(forKey: key)
			}
			set {
				if let newValue {
					members.set(newValue, forKey: key)
				} else {
					removeValue(forKey: key)
				}
			}
			_modify {
				guard let position = members.position(of: key) else {
					var value: SOML.Value?

					defer {
						if let value {
							members.append(value, forKey: key)
						}
					}

					yield &value
					return
				}

				// The value moves out while it changes, so its storage is unique and a nested change, like `object["a"]?["b"] = 1`, does not copy it.
				var value: SOML.Value? = members.values[position]
				members.setValue(.null, at: position)

				defer {
					if let value {
						members.setValue(value, at: position)
					} else {
						members.remove(at: position)
					}
				}

				yield &value
			}
		}

		/**
		Removes the member with the given key and returns its value, or returns `nil` if there is no such member.

		This takes linear time, because the members after it move up.
		*/
		@discardableResult
		public mutating func removeValue(forKey key: String) -> SOML.Value? {
			guard let position = members.position(of: key) else {
				return nil
			}

			return members.remove(at: position)
		}

		/**
		Whether an exact key is present, without loading its value.
		*/
		public func contains(key: String) -> Bool {
			members.position(of: key) != nil
		}

		/**
		Replaces a member in place or appends it, returning its previous value when present.
		*/
		@discardableResult
		public mutating func updateValue(_ value: SOML.Value, forKey key: String) -> SOML.Value? {
			guard let position = members.position(of: key) else {
				members.append(value, forKey: key)
				return nil
			}

			let previous = members.values[position]
			members.setValue(value, at: position)
			return previous
		}

		/**
		Reserves storage for at least `minimumCapacity` members when building an object incrementally.
		*/
		public mutating func reserveCapacity(_ minimumCapacity: Int) {
			members.reserveCapacity(minimumCapacity)
		}

		/**
		Removes all members, optionally retaining the member arrays for reuse.
		*/
		public mutating func removeAll(keepingCapacity: Bool = false) {
			members.removeAll(keepingCapacity: keepingCapacity)
		}

		/**
		Reads a member or the lazily evaluated default. Mutating through this subscript inserts the default only when the member is absent, then changes its value in place.

		```swift
		var object = SOML.Object()
		object["server", default: [:]]["port"] = 8080
		```
		*/
		public subscript(key: String, default defaultValue: @autoclosure () -> SOML.Value) -> SOML.Value {
			get {
				members.value(forKey: key) ?? defaultValue()
			}
			_modify {
				let position: Int

				if let existing = members.position(of: key) {
					position = existing
				} else {
					position = members.count
					members.append(defaultValue(), forKey: key)
				}

				yield &members[valueAt: position]
			}
		}

		/**
		Transforms values while keeping exact keys, insertion order, and the existing lookup index. If the transform throws, the original object is unchanged.
		*/
		public func mapValues<Failure: Error>(_ transform: (SOML.Value) throws(Failure) -> SOML.Value) throws(Failure) -> Self {
			Self(try members.mapValues(transform))
		}

		/**
		Keeps the selected members as an object, preserving insertion order and scalar-distinct keys.
		*/
		public func filter<Failure: Error>(_ isIncluded: (Element) throws(Failure) -> Bool) throws(Failure) -> Self {
			var result = Self()
			result.reserveCapacity(count)

			for member in self where try isIncluded(member) {
				result.members.append(member.value, forKey: member.key)
			}

			return result
		}

		/**
		The keys, in insertion order.
		*/
		public var keys: [String] {
			members.keys
		}

		/**
		The values, in insertion order.
		*/
		public var values: [SOML.Value] {
			members.values
		}

		/**
		The position of a key in source order, using the object's existing lookup index.
		*/
		func index(forKey key: String) -> Int? {
			members.position(of: key)
		}

		/**
		The positions of the members in canonical key order, or `nil` when insertion order is already canonical.
		*/
		var canonicalOrder: [Int]? {
			members.canonicalOrder
		}
	}
}

extension SOML.Object: RandomAccessCollection {
	public var startIndex: Int { 0 }
	public var endIndex: Int { members.count }

	public subscript(position: Int) -> Element {
		(members.keys[position], members.values[position])
	}
}

extension SOML.Object: Hashable {
	/**
	Two objects are equal when they have the same members, in any order.
	*/
	public static func == (lhs: Self, rhs: Self) -> Bool {
		guard lhs.count == rhs.count else {
			return false
		}

		for (key, value) in lhs {
			guard rhs[key] == value else {
				return false
			}
		}

		return true
	}

	public func hash(into hasher: inout Hasher) {
		// Order is not part of the value, so combine the members with an operation that ignores order.
		var combined = 0

		for (key, value) in self {
			var memberHasher = Hasher()
			memberHasher.combine(ExactKey(key))
			memberHasher.combine(value)
			combined ^= memberHasher.finalize()
		}

		hasher.combine(count)
		hasher.combine(combined)
	}
}

extension SOML.Object: ExpressibleByDictionaryLiteral {
	public init(dictionaryLiteral elements: (String, SOML.Value)...) {
		self.init(elements)
	}
}

extension SOML.Object: CustomStringConvertible {
	/**
	The object in the layout and spelling of canonical form, with the members in their order.
	*/
	public var description: String {
		SOML.Value.object(self).description
	}
}

extension SOML.Object {
	/**
	The object with `other` merged into it, for layered config, like defaults and then a user file. See `SOML.Value.merging(_:)` for the rules.
	*/
	public func merging(_ other: Self) -> Self {
		guard !other.isEmpty else {
			return self
		}

		guard !isEmpty else {
			return other
		}

		var result = self

		result.merge(other)
		return result
	}
	/**
	Merges another object into this one in place, using the recursive rules of `merging(_:)`.
	*/
	public mutating func merge(_ other: Self) {
		for (key, value) in other {
			merge(value, forKey: key)
		}
	}

	/**
	Merges an existing member or appends a new one using one key lookup.
	*/
	private mutating func merge(_ value: SOML.Value, forKey key: String) {
		guard let position = members.position(of: key) else {
			members.append(value, forKey: key)
			return
		}

		members.setValue(members.values[position].merging(value), at: position)
	}

}

extension SOML.Object: Codable {
	/**
	Decodes an object, as `SOML.Value` decodes one, and throws if the value is not an object. Null is `DecodingError.valueNotFound`, as for any other type.
	*/
	public init(from decoder: any Decoder) throws {
		if let decoder = decoder as? DecoderImplementation {
			switch decoder.value {
			case .object(let object):
				decoder.recordReadWhole(decoder.value, key: nil)
				self = object
			case .null:
				throw DecodingError.valueNotFound(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected an object, but found null"))
			default:
				throw DecodingError.typeMismatch(Self.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected an object"))
			}

			return
		}

		let container: KeyedDecodingContainer<SOMLCodingKey>
		do {
			container = try decoder.container(keyedBy: SOMLCodingKey.self)
		} catch DecodingError.valueNotFound(_, let context) {
			throw DecodingError.valueNotFound(Self.self, context)
		} catch DecodingError.typeMismatch(_, let context) {
			throw DecodingError.typeMismatch(Self.self, context)
		}

		try self.init(decoding: container)
	}

	/**
	Decodes ordered object members from a foreign keyed container, without first attempting to decode arrays or scalars.
	*/
	init(decoding container: KeyedDecodingContainer<SOMLCodingKey>) throws {
		let keys = container.allKeys
		var members = OrderedMembers<SOML.Value>()
		members.reserveCapacity(keys.count)

		for key in keys {
			members.set(try container.decode(SOML.Value.self, forKey: key), forKey: key.stringValue)
		}

		self.init(members)
	}

	/**
	Encodes the object, as `SOML.Value` encodes an object.
	*/
	public func encode(to encoder: any Encoder) throws {
		try SOML.Value.object(self).encode(to: encoder)
	}
}

/**
Members with unique keys, in insertion order, where keys are compared by their UTF-8 bytes.

Most objects have a handful of members, and for those a linear search is faster than hashing and needs no dictionary. A hash index is built only once there are more than `indexThreshold` members.

The parser, `SOML.Object`, and the encoder all store members this way, so a finished object takes over the storage, and its keys are never hashed again.
*/
struct OrderedMembers<Value> {
	private static var indexThreshold: Int { 32 }

	private(set) var keys = [String]()
	private(set) var values = [Value]()
	private var index: [ExactKey: Int]?

	/**
	The `fingerprint` of each key, so that a linear search compares integers, and compares strings only for a key with the same length and start. Reaching the bytes of a string costs more than comparing a few of them.
	*/
	private var fingerprints = [UInt64]()

	var count: Int {
		keys.count
	}

	/**
	Reserves storage for at least this many members, including the lookup index when one exists.
	*/
	mutating func reserveCapacity(_ capacity: Int) {
		keys.reserveCapacity(capacity)
		values.reserveCapacity(capacity)
		fingerprints.reserveCapacity(capacity)
		index?.reserveCapacity(capacity)
	}

	/**
	Removes all members together, keeping their parallel arrays aligned.
	*/
	mutating func removeAll(keepingCapacity: Bool) {
		keys.removeAll(keepingCapacity: keepingCapacity)
		values.removeAll(keepingCapacity: keepingCapacity)
		fingerprints.removeAll(keepingCapacity: keepingCapacity)
		index = nil
	}

	/**
	Accesses a stored value in place without copying nested containers during mutation.
	*/
	subscript(valueAt position: Int) -> Value {
		get {
			values[position]
		}
		_modify {
			yield &values[position]
		}
	}

	func position(of key: String) -> Int? {
		if let index {
			return index[ExactKey(key)]
		}

		let fingerprint = key.fingerprint
		return fingerprints.indices.first { fingerprints[$0] == fingerprint && keys[$0].hasSameScalars(as: key) }
	}

	/**
	The value for an exact key, using the existing index when present.
	*/
	func value(forKey key: String) -> Value? {
		position(of: key).map { values[$0] }
	}

	/**
	Adds a member at the end. The key must not be in the members already.
	*/
	mutating func append(_ value: Value, forKey key: String) {
		// Most objects are small. Room for a few members up front saves the arrays from growing one step at a time.
		if keys.isEmpty {
			reserveCapacity(4)
		}

		keys.append(key)
		values.append(value)
		fingerprints.append(key.fingerprint)

		if index != nil {
			index?[ExactKey(key)] = keys.count - 1
		} else if keys.count > Self.indexThreshold {
			buildIndex()
		}
	}

	/**
	Replaces the value of a member, or adds a member at the end.
	*/
	mutating func set(_ value: Value, forKey key: String) {
		if let position = position(of: key) {
			values[position] = value
		} else {
			append(value, forKey: key)
		}
	}

	mutating func setValue(_ value: Value, at position: Int) {
		values[position] = value
	}

	@discardableResult
	mutating func remove(at position: Int) -> Value {
		let key = keys.remove(at: position)
		fingerprints.remove(at: position)
		let value = values.remove(at: position)

		if index != nil {
			if keys.count > Self.indexThreshold {
				// Only the members after the removed one move up a position, so only their keys are hashed again, and removing the last member takes constant time.
				index?.removeValue(forKey: ExactKey(key))

				for position in position..<keys.count {
					index?[ExactKey(keys[position])] = position
				}
			} else {
				index = nil
			}
		}

		return value
	}

	/**
	The same keys with transformed values. The index is kept, so no key is hashed again.
	*/
	func mapValues<NewValue, Failure: Error>(_ transform: (Value) throws(Failure) -> NewValue) throws(Failure) -> OrderedMembers<NewValue> {
		var result = OrderedMembers<NewValue>()
		result.keys = keys
		result.values = try values.map(transform)
		result.index = index
		result.fingerprints = fingerprints
		return result
	}

	/**
	The positions of the members sorted by the UTF-8 bytes of their keys, which is the same as sorting by Unicode scalars, or `nil` when no sorting is needed.
	*/
	var canonicalOrder: [Int]? {
		guard keys.count > 1 else {
			return nil
		}

		// Documents are often written sorted already, and canonical documents always are.
		if zip(keys, keys.dropFirst()).allSatisfy({ $0.scalarOrderPrecedes($1) }) {
			return nil
		}

		// Not `sorted(using:)` with a `SortComparator`: Foundation's implementation is not inlinable, so it sorts through generic dispatch, which made writing several times slower.
		var positions = Array(keys.indices)
		positions.sort { keys[$0].scalarOrderPrecedes(keys[$1]) }
		return positions
	}

	private mutating func buildIndex() {
		// `Dictionary(uniqueKeysWithValues:)` showed no consistent integrated performance benefit in optimized Swift 6.4 builds on an M4 Pro. This loop reserves capacity explicitly without relying on the input sequence's `underestimatedCount`.
		var index = [ExactKey: Int](minimumCapacity: keys.count)

		for (position, key) in keys.enumerated() {
			index[ExactKey(key)] = position
		}

		self.index = index
	}
}

extension OrderedMembers: Sendable where Value: Sendable {}

/**
A string that compares and hashes by its UTF-8 bytes, which is the same as comparing its Unicode scalars.
*/
struct ExactKey: Hashable {
	let string: String

	init(_ string: String) {
		self.string = string
	}

	static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.string.hasSameScalars(as: rhs.string)
	}

	func hash(into hasher: inout Hasher) {
		string.withUTF8Buffer { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }

		// A terminator, as `String` hashes, so the end of a string cannot move into the bytes of what follows it, which made unequal values collide for every seed. 0xFF never occurs in UTF-8.
		hasher.combine(0xFF as UInt8)
	}
}

extension String {
	/**
	Calls `body` with the UTF-8 bytes of the string, without copying them when the string is stored contiguously, which native Swift strings are.
	*/
	@inline(always)
	func withUTF8Buffer<Result>(_ body: (UnsafeBufferPointer<UInt8>) throws -> Result) rethrows -> Result {
		// Keep this fast path inlined even though the bridged fallback needs availability checks.
		if let result = try utf8.withContiguousStorageIfAvailable(body) {
			return result
		}

		// The span caches transcoded UTF-8 for bridged UTF-16 strings, so repeated reads do not convert a fresh copy each time. Native strings have already returned above.
		// `String.utf8Span` is unavailable on 32-bit watchOS.
		#if !(os(watchOS) && (arch(arm) || arch(arm64_32)))
		if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
			return try utf8Span.span.withUnsafeBufferPointer(body)
		}
		#endif

		var copy = self
		return try copy.withUTF8(body)
	}

	/**
	Whether two strings have the same Unicode scalars. Swift's `==` instead compares by canonical equivalence, so it calls `"\u{E9}"` and `"e\u{301}"` equal.
	*/
	func hasSameScalars(as other: String) -> Bool {
		// Compare bytes directly, because Swift's normalization-aware `==` can take quadratic time for long combining sequences from untrusted input.
		guard utf8.count == other.utf8.count else {
			return false
		}

		// Applying `elementsEqual` directly to the UTF-8 views measured slower than comparing contiguous buffers in optimized Swift 6.4 builds on an M4 Pro.
		return withUTF8Buffer { lhs in
			other.withUTF8Buffer { rhs in
				lhs.elementsEqual(rhs)
			}
		}
	}

	/**
	The length and the first seven UTF-8 bytes of the string, in one integer. Two strings with the same Unicode scalars have the same fingerprint.
	*/
	fileprivate var fingerprint: UInt64 {
		withUTF8Buffer { bytes in
			var fingerprint = UInt64(min(bytes.count, 0xFF)) << 56

			#if compiler(>=6.4)
			if bytes.count >= MemoryLayout<UInt64>.size {
				// Read one checked word, retain its first seven bytes in source order, and leave the top byte for the capped length.
				return fingerprint | (bytes.span.bytes.load(fromByteOffset: 0, as: UInt64.self).littleEndian & 0x00FF_FFFF_FFFF_FFFF)
			}
			#endif

			for (offset, byte) in bytes.prefix(7).enumerated() {
				fingerprint |= UInt64(byte) << (offset * 8)
			}

			return fingerprint
		}
	}

	/**
	Whether the string comes before `other` when both are compared by their Unicode scalars, which is the same as comparing their UTF-8 bytes.
	*/
	func scalarOrderPrecedes(_ other: String) -> Bool {
		// Applying `lexicographicallyPrecedes` directly to the UTF-8 views also measured slower than comparing contiguous buffers.
		withUTF8Buffer { lhs in
			other.withUTF8Buffer { rhs in
				lhs.lexicographicallyPrecedes(rhs)
			}
		}
	}

	/**
	Whether the string contains the carriage return that SOML cannot represent.
	*/
	var hasCarriageReturn: Bool {
		withUTF8Buffer { $0.contains(.carriageReturn) }
	}

	/**
	Whether the string can be written as an unquoted SOML key.
	*/
	var isBareSOMLKey: Bool {
		withUTF8Buffer { !$0.isEmpty && $0.allSatisfy(\.isBareKeyByte) }
	}
}

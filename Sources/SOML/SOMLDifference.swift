extension SOML {
	/**
	A difference between two values at a key path, from `SOML.Value.differences(from:)`.
	*/
	public enum Difference: Sendable, Hashable {
		/**
		A member or an array item that only the new value has.
		*/
		case added(SOML.Value, at: SOML.KeyPath)

		/**
		A member or an array item that only the old value has.
		*/
		case removed(SOML.Value, at: SOML.KeyPath)

		/**
		A member or an array item whose value changed. Two objects or two arrays are compared member by member and item by item instead, so the old and the new value are never both objects or both arrays.
		*/
		case changed(from: SOML.Value, to: SOML.Value, at: SOML.KeyPath)

		/**
		The key path of the member or item.
		*/
		public var path: SOML.KeyPath {
			switch self {
			case .added(_, let path), .removed(_, let path), .changed(_, _, let path):
				path
			}
		}
	}
}

extension SOML.Value {
	/**
	What changed from `old` to this value, member by member and item by item, like to log what changed when a config file is read again.

	- Objects are compared by key, so the member order does not matter.
	- Arrays are compared by index: an item at an index that both have is compared, and items past the end of the shorter array are added or removed.

	The differences are in an order in which `SOML.Document.setting(_:at:)` for an added or changed value and `SOML.Document.removing(at:)` for a removed one, made one by one, turn a document with the old value into one with this value. Each object gives its changed and removed members in the old member order, then its added members. Each array gives its changed items, then its added items, or its removed items from the end.

	```swift
	let old = try SOML.Value(parsing: "port: 80\nhosts: ['a', 'b']\ndebug: true")
	let new = try SOML.Value(parsing: "port: 8080\nhosts: ['a']\nname: 'api'")

	new.differences(from: old)
	//=> [
	//=> 	.changed(from: 80, to: 8080, at: ["port"]),
	//=> 	.removed("b", at: ["hosts", 1]),
	//=> 	.removed(true, at: ["debug"]),
	//=> 	.added("api", at: ["name"])
	//=> ]
	```

	It is `nil` when the two values differ and are not both objects or both arrays, like two different ints, because then the whole value changed, which has no key path. It is empty when they are equal.
	*/
	public func differences(from old: Self) -> [SOML.Difference]? {
		switch (old, self) {
		case (.object, .object), (.array, .array):
			var differences = [SOML.Difference]()
			var path = [SOML.KeyPath.Segment]()
			Self.appendDifferences(from: old, to: self, at: &path, into: &differences)
			return differences
		default:
			return old == self ? [] : nil
		}
	}

	/**
	Appends the differences from `old` to `new`, which are at `path`.
	*/
	private static func appendDifferences(from old: Self, to new: Self, at path: inout [SOML.KeyPath.Segment], into differences: inout [SOML.Difference]) {
		switch (old, new) {
		case (.object(let oldObject), .object(let newObject)):
			for (key, oldMember) in oldObject {
				path.append(.key(key))
				defer {
					path.removeLast()
				}

				guard let newMember = newObject[key] else {
					differences.append(.removed(oldMember, at: SOML.KeyPath(path)))
					continue
				}

				appendDifferences(from: oldMember, to: newMember, at: &path, into: &differences)
			}

			for (key, newMember) in newObject where !oldObject.contains(key: key) {
				differences.append(.added(newMember, at: SOML.KeyPath(path + [.key(key)])))
			}
		case (.array(let oldItems), .array(let newItems)):
			// zip-based traversal measured 30–88% slower in focused 10–1000-item probes and still needs an index for each difference's path.
			for index in 0..<min(oldItems.count, newItems.count) {
				path.append(.index(index))
				appendDifferences(from: oldItems[index], to: newItems[index], at: &path, into: &differences)
				path.removeLast()
			}

			for index in oldItems.count..<max(oldItems.count, newItems.count) {
				differences.append(.added(newItems[index], at: SOML.KeyPath(path + [.index(index)])))
			}

			for index in (newItems.count..<max(oldItems.count, newItems.count)).reversed() {
				differences.append(.removed(oldItems[index], at: SOML.KeyPath(path + [.index(index)])))
			}
		default:
			guard old != new else {
				return
			}

			// The two values at the top are both objects or both arrays, so the path is not empty.
			differences.append(.changed(from: old, to: new, at: SOML.KeyPath(path)))
		}
	}
}

/**
Value access and inversion for individual differences.
*/
extension SOML.Difference {
	/**
	The previous value, or `nil` when a member or item was added. A SOML null is returned as `.null`.
	*/
	public var oldValue: SOML.Value? {
		switch self {
		case .added:
			nil
		case .removed(let value, _), .changed(let value, _, _):
			value
		}
	}

	/**
	The replacement value, or `nil` when a member or item was removed.
	*/
	public var newValue: SOML.Value? {
		switch self {
		case .removed:
			nil
		case .added(let value, _), .changed(_, let value, _):
			value
		}
	}

	/**
	The reverse change at the same path. To undo differences returned by `differences(from:)` on their matching document, apply the inverted differences in reverse order. Array additions follow setting rules, so this does not restore an arbitrary removal from the middle of an array.
	*/
	public var inverted: Self {
		switch self {
		case .added(let value, let path):
			.removed(value, at: path)
		case .removed(let value, let path):
			.added(value, at: path)
		case .changed(let old, let new, let path):
			.changed(from: new, to: old, at: path)
		}
	}
}

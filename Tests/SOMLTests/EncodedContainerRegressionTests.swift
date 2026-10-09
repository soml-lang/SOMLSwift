import Testing
@testable import SOML

@Suite
struct EncodedContainerRegressionTests {
	enum CodingKeys: String, CodingKey {
		case value
		case first
		case second
		case `super`
	}

	struct ExtendsObject<Value: Encodable>: Encodable {
		let value: Value

		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(value, forKey: .value)
			var first = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .value)
			try first.encode(2, forKey: .second)
			var second = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .value)
			try second.encode(3, forKey: .first)
		}
	}

	@Test(arguments: [SOML.Encoder.KeyEncodingStrategy.useDefaultKeys, .convertToKebabCase, .convertToSnakeCase])
	func `extending a SOML object or object value preserves raw keys and reuses storage`(_ strategy: SOML.Encoder.KeyEncodingStrategy) throws {
		let object: SOML.Object = ["rawKey": ["nestedKey": 1], "first": 1]
		let expected: SOML.Value = ["value": ["rawKey": ["nestedKey": 1], "first": 3, "second": 2]]
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = strategy
		let encodedObject = try encoder.encodeToValue(ExtendsObject(value: object))
		#expect(encodedObject == expected)
		#expect(encodedObject["value"]?.objectValue?.keys == ["rawKey", "first", "second"])
		#expect(try encoder.encodeToValue(ExtendsObject(value: SOML.Value.object(object))) == expected)
	}

	struct ExtendsArray: Encodable {
		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(SOML.Value.array([1, ["rawKey": 2]]), forKey: .value)
			var first = container.nestedUnkeyedContainer(forKey: .value)
			try first.encode(3)
			var second = container.nestedUnkeyedContainer(forKey: .value)
			try second.encode(4)
		}
	}

	@Test
	func `extending an encoded array value preserves items and reuses storage`() throws {
		#expect(try SOML.Encoder().encodeToValue(ExtendsArray()) == ["value": [1, ["rawKey": 2], 3, 4]])
	}

	struct ChangesContainerKind: Encodable {
		let value: SOML.Value

		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(value, forKey: .value)

			if case .object = value {
				var nested = container.nestedUnkeyedContainer(forKey: .value)
				try nested.encode(2)
			} else {
				var nested = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .value)
				try nested.encode(2, forKey: .second)
			}
		}
	}

	@Test(arguments: [SOML.Value.object(["first": 1]), .array([1])])
	func `an encoded container cannot silently change its kind`(_ value: SOML.Value) throws {
		let error = try #require(throws: EncodingError.self) {
			try SOML.Encoder().encodeToValue(ChangesContainerKind(value: value))
		}

		guard case .invalidValue(_, let context) = error else {
			Issue.record("Expected an invalid value error")
			return
		}

		#expect(context.codingPath.map(\.stringValue) == ["value"])
		#expect(context.debugDescription.contains("would lose what it wrote first"))
	}

	@Test
	func `the error for a container of the other kind has the value that the type wrote, not an internal type`() throws {
		let error = try #require(throws: EncodingError.self) {
			try SOML.Encoder().encodeToValue(ChangesContainerKind(value: ["first": 1]))
		}

		guard case .invalidValue(let value, _) = error else {
			Issue.record("Expected an invalid value error")
			return
		}

		// The array is empty when the type asks for it, before it writes to it.
		#expect(value as? SOML.Value == [])
	}

	struct SingleObjectThenKeyed: Encodable {
		let object: SOML.Value

		func encode(to encoder: any Encoder) throws {
			var single = encoder.singleValueContainer()
			try single.encode(object)
			var keyed = encoder.container(keyedBy: CodingKeys.self)
			try keyed.encode(2, forKey: .second)
		}
	}

	struct SingleDictionaryThenKeyed: Encodable {
		func encode(to encoder: any Encoder) throws {
			var single = encoder.singleValueContainer()
			try single.encode(["first": 1])
			var keyed = encoder.container(keyedBy: CodingKeys.self)
			try keyed.encode(2, forKey: .second)
		}
	}

	@Test(arguments: [SOML.Encoder.KeyEncodingStrategy.useDefaultKeys, .convertToKebabCase, .convertToSnakeCase])
	func `a keyed container goes on filling an object that a single value container wrote`(_ strategy: SOML.Encoder.KeyEncodingStrategy) throws {
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = strategy
		#expect(try encoder.encodeToValue(SingleDictionaryThenKeyed()) == ["first": 1, "second": 2])
		#expect(try encoder.encodeToValue(SingleObjectThenKeyed(object: ["first": 1])) == ["first": 1, "second": 2])
		#expect(try encoder.encodeToString(SingleObjectThenKeyed(object: ["first": 1])) == "first: 1\nsecond: 2\n")
	}

	struct SingleArrayThenUnkeyed: Encodable {
		let array: SOML.Value

		func encode(to encoder: any Encoder) throws {
			try array.encode(to: encoder)
			var unkeyed = encoder.unkeyedContainer()
			try unkeyed.encode(2)
		}
	}

	@Test
	func `an unkeyed container goes on filling an array that a single value container wrote`() throws {
		#expect(try SOML.Encoder().encodeToValue(SingleArrayThenUnkeyed(array: [1])) == [1, 2])
		#expect(try SOML.Encoder().encodeToValue(SingleArrayThenUnkeyed(array: [])) == [2])
	}

	struct TwoObjects: Encodable {
		func encode(to encoder: any Encoder) throws {
			var single = encoder.singleValueContainer()
			try single.encode(["first": 1])
			try single.encode(["second": 2])
		}
	}

	struct ObjectThenScalar: Encodable {
		func encode(to encoder: any Encoder) throws {
			var single = encoder.singleValueContainer()
			try single.encode(SOML.Value.object(["first": 1]))
			try single.encode(3)
		}
	}

	@Test(arguments: [SOML.Encoder.KeyEncodingStrategy.useDefaultKeys, .convertToKebabCase, .convertToSnakeCase])
	func `writing a second object or a scalar over an object is an error with every key strategy`(_ strategy: SOML.Encoder.KeyEncodingStrategy) throws {
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = strategy

		for (value, message) in [(TwoObjects() as any Encodable, "The type wrote an object and then an object with the same encoder, which would lose what it wrote first"), (ObjectThenScalar(), "The type wrote an object and then a single value with the same encoder, which would lose what it wrote first")] {
			let error = try #require(throws: EncodingError.self) {
				try encoder.encodeToValue(value)
			}

			guard case .invalidValue(_, let context) = error else {
				Issue.record("Expected an invalid value error")
				continue
			}

			#expect(context.debugDescription == message)
		}
	}

	@Test
	func `a single value replaces a single value`() throws {
		struct TwoScalars: Encodable {
			func encode(to encoder: any Encoder) throws {
				var single = encoder.singleValueContainer()
				try single.encode(1)
				try single.encode("two")
			}
		}

		#expect(try SOML.Encoder().encodeToValue([TwoScalars()]) == ["two"])
	}

	struct Inner: Encodable {
		var x = 1
	}

	struct SuperAfterValue: Encodable {
		let first: any Encodable
		let usesKey: Bool

		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)

			if usesKey {
				try container.encode(first, forKey: .value)
				var nested = container.superEncoder(forKey: .value).container(keyedBy: CodingKeys.self)
				try nested.encode(2, forKey: .second)
			} else {
				try container.encode(first, forKey: .super)
				var nested = container.superEncoder().container(keyedBy: CodingKeys.self)
				try nested.encode(2, forKey: .second)
			}
		}
	}

	@Test(arguments: [false, true])
	func `a super encoder goes on filling what was encoded for its key, like a nested container`(_ usesKey: Bool) throws {
		let key = usesKey ? "value" : "super"

		for first in [Inner() as any Encodable, SOML.Object(["x": 1]), SOML.Value.object(["x": 1])] {
			#expect(try SOML.Encoder().encodeToValue(SuperAfterValue(first: first, usesKey: usesKey)) == [key: ["x": 1, "second": 2]])
		}
	}
}

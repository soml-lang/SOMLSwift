import Testing
@testable import SOML

@Suite
struct EncodedContainerRegressionTests {
	enum CodingKeys: String, CodingKey {
		case value
		case first
		case second
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
}

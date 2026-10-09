import Foundation
import Testing
@testable import SOML

/**
The finer points of the coders: coding paths, `decodeIfPresent`, dictionaries under a key strategy, dates, and every primitive type in containers.
*/
@Suite
struct CodingPathTests {
	/**
	Records the coding paths that containers report while a document is decoded or encoded.
	*/
	final class PathLog: @unchecked Sendable {
		var paths = [String: String]()
	}

	static func describe(_ path: [any CodingKey]) -> String {
		path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
	}

	struct Probe: Decodable {
		static let log = PathLog()

		enum Keys: String, CodingKey {
			case list
			case k
		}

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: Keys.self)
			Self.log.paths["keyed"] = CodingPathTests.describe(container.codingPath)
			var list = try container.nestedUnkeyedContainer(forKey: .list)
			Self.log.paths["unkeyed"] = CodingPathTests.describe(list.codingPath)
			_ = try list.decode(Int.self)
			let nested = try list.nestedContainer(keyedBy: Keys.self)
			Self.log.paths["nested in unkeyed"] = CodingPathTests.describe(nested.codingPath)
			Self.log.paths["super for key"] = CodingPathTests.describe(try nested.superDecoder(forKey: .k).codingPath)
			Self.log.paths["super"] = CodingPathTests.describe(try nested.superDecoder().codingPath)
			Self.log.paths["unkeyed super"] = CodingPathTests.describe(try list.superDecoder().codingPath)

			do {
				_ = try list.decode(Int.self)
			} catch DecodingError.valueNotFound(_, let context) {
				Self.log.paths["past the end"] = CodingPathTests.describe(context.codingPath)
			}
		}
	}

	@Test
	func `containers report their coding paths`() throws {
		_ = try SOML.Decoder().decode(Probe.self, from: "list: [1, {k: 2, super: null}, 3]")
		#expect(Probe.log.paths == [
			"keyed": "",
			"unkeyed": "list",
			"nested in unkeyed": "list.[1]",
			"super for key": "list.[1].k",
			"super": "list.[1].super",
			"unkeyed super": "list.[2]",
			"past the end": "list.[3]",
		])
	}

	struct EncodingProbe: Encodable {
		static let log = PathLog()

		enum Keys: String, CodingKey {
			case list
			case k
		}

		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: Keys.self)
			Self.log.paths["keyed"] = CodingPathTests.describe(container.codingPath)
			var list = container.nestedUnkeyedContainer(forKey: .list)
			Self.log.paths["unkeyed"] = CodingPathTests.describe(list.codingPath)
			try list.encode(1)
			let nested = list.nestedContainer(keyedBy: Keys.self)
			Self.log.paths["nested in unkeyed"] = CodingPathTests.describe(nested.codingPath)
			var mutableNested = nested
			Self.log.paths["super for key"] = CodingPathTests.describe(mutableNested.superEncoder(forKey: .k).codingPath)
			Self.log.paths["super"] = CodingPathTests.describe(mutableNested.superEncoder().codingPath)
			Self.log.paths["unkeyed super"] = CodingPathTests.describe(list.superEncoder().codingPath)
		}
	}

	@Test
	func `encoding containers report their coding paths`() throws {
		_ = try SOML.Encoder().encodeToString(EncodingProbe())
		#expect(EncodingProbe.log.paths == [
			"keyed": "",
			"unkeyed": "list",
			"nested in unkeyed": "list.[1]",
			"super for key": "list.[1].k",
			"super": "list.[1].super",
			"unkeyed super": "list.[2]",
		])
	}

	@Test
	func `a missing dynamic key with combining sequences is rejected quickly`() throws {
		struct Lookup: Decodable {
			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: SOMLCodingKey.self)
				let key = try container.decode(String.self, forKey: SOMLCodingKey(stringValue: "lookup"))
				_ = try container.decode(Int.self, forKey: SOMLCodingKey(stringValue: key))
			}
		}

		let key = "X" + String(repeating: "\u{315}", count: 64_000) + String(repeating: "\u{300}", count: 64_000)
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		let source = "lookup: '\(key)'"
		let clock = ContinuousClock()
		let start = clock.now

		do {
			_ = try decoder.decode(Lookup.self, from: source)
			Issue.record("Expected a missing-key error")
		} catch DecodingError.keyNotFound(let codingKey, let context) {
			#expect(codingKey.stringValue.utf8.elementsEqual(key.utf8))
			#expect(context.codingPath.isEmpty)
		}

		// It takes about half a second in a debug build, and quadratic time would take minutes, so the limit leaves room for a busy machine.
		#expect(start.duration(to: clock.now) < .seconds(5))
	}

	@Test
	func `a key with combining sequences converts quickly`() {
		let combining = String(repeating: "\u{315}", count: 32_000) + String(repeating: "\u{300}", count: 32_000)
		let key = "X" + combining + "-suffix"
		let clock = ContinuousClock()
		let start = clock.now
		let converted = key.convertedToCamelCase(separator: "-")
		#expect(converted.utf8.elementsEqual(("x" + combining + "Suffix").utf8))
		#expect(start.duration(to: clock.now) < .seconds(1))
	}

	private func decodingPath(_ type: any Decodable.Type, _ source: String, strategy: SOML.Decoder.KeyDecodingStrategy = .useDefaultKeys) -> String? {
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = strategy

		do {
			_ = try decoder.decode(type, from: source)
			Issue.record("Expected an error for \(source)")
			return nil
		} catch let error as DecodingError {
			switch error {
			case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context), .dataCorrupted(let context):
				return Self.describe(context.codingPath)
			@unknown default:
				return nil
			}
		} catch {
			Issue.record("Unexpected \(error)")
			return nil
		}
	}

	struct Inner: Decodable {
		var count: Int
	}

	struct Outer: Decodable {
		var items: [Inner]
		var map: [String: [Int]]
		var maybe: Int?
	}

	@Test
	func `error paths`() {
		#expect(decodingPath(Outer.self, "items: [{count: 'x'}]\nmap: {}") == "items.[0].count")
		#expect(decodingPath(Outer.self, "items: [{}]\nmap: {}") == "items.[0]")
		#expect(decodingPath(Outer.self, "items: []\nmap: {a: [1, 'x']}") == "map.a.[1]")
		#expect(decodingPath(Outer.self, "items: []\nmap: {a: [1, 'x']}", strategy: .convertFromKebabCase) == "map.a.[1]")
		#expect(decodingPath(Outer.self, "items: []\nmap: {a: 1}", strategy: .convertFromKebabCase) == "map.a")
		#expect(decodingPath(Outer.self, "items: []\nmap: [1]", strategy: .convertFromKebabCase) == "map")
		#expect(decodingPath(Outer.self, "items: []\nmap: {}\nmaybe: 'x'") == "maybe")
		#expect(decodingPath([Int].self, "[1, null]") == "[1]")
		#expect(decodingPath([[Int]].self, "[[1], [2, 2.5]]") == "[1].[1]")
		#expect(decodingPath([Int8].self, "[1, 200]") == "[1]")
	}

	struct Settings: Encodable {
		var innerThing: Inner
		var allNames: [String] = []
		var labelsByName: [String: String] = [:]

		struct Inner: Encodable {
			var myText = "ok"
			var myRatio = 1.0
		}
	}

	/**
	The coding path of an encoding error, under `strategy`.
	*/
	private func encodingPath(_ value: some Encodable, strategy: SOML.Encoder.KeyEncodingStrategy) -> String? {
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = strategy

		do {
			_ = try encoder.encodeToString(value)
			Issue.record("Expected an error for \(value)")
			return nil
		} catch let EncodingError.invalidValue(_, context) {
			return Self.describe(context.codingPath)
		} catch {
			Issue.record("Unexpected \(error)")
			return nil
		}
	}

	@Test(arguments: [SOML.Encoder.KeyEncodingStrategy.useDefaultKeys, .convertToKebabCase, .convertToSnakeCase])
	func `an encoding error has the coding keys of the type, also under a key strategy`(_ strategy: SOML.Encoder.KeyEncodingStrategy) {
		// A carriage return has the same path as NaN, which is the path of coding keys, not the keys the document gets.
		#expect(encodingPath(Settings(innerThing: .init(myText: "a\rb")), strategy: strategy) == "innerThing.myText")
		#expect(encodingPath(Settings(innerThing: .init(myRatio: .nan)), strategy: strategy) == "innerThing.myRatio")
		#expect(encodingPath(Settings(innerThing: .init(), allNames: ["a", "b\r"]), strategy: strategy) == "allNames.[1]")
		#expect(encodingPath(Settings(innerThing: .init(), labelsByName: ["someName": "x\ry"]), strategy: strategy) == "labelsByName.someName")
		#expect(encodingPath(["a\rb"], strategy: strategy) == "[0]")
		#expect(encodingPath(Settings(innerThing: .init(), labelsByName: ["bad\rKey": "x"]), strategy: strategy) == "labelsByName.bad\rKey")
	}

	struct ValueSettings: Encodable {
		var someValue: SOML.Value = [:]
		var someObject: SOML.Object = [:]
	}

	@Test
	func `an encoding error inside a SOML value or object property has the keys that the strategy writes`() {
		#expect(encodingPath(ValueSettings(someValue: ["innerKey": .float(.nan)]), strategy: .convertToKebabCase) == "some-value.innerKey")
		#expect(encodingPath(ValueSettings(someObject: ["innerKey": "a\rb"]), strategy: .convertToSnakeCase) == "some_object.innerKey")
		#expect(encodingPath(ValueSettings(someValue: ["innerKey": .float(.nan)]), strategy: .useDefaultKeys) == "someValue.innerKey")
	}

	final class Chain: Encodable {
		let nextNode: Chain?
		let kind: Kind?

		enum Kind: String, Encodable {
			case leaf
		}

		init(nextNode: Chain? = nil, kind: Kind?) {
			self.nextNode = nextNode
			self.kind = kind
		}

		/**
		A chain whose objects nest `depth` levels deep, with the top-level object as the first. With `hasKind`, each object also holds a scalar that is not one of the encoder's fast paths.
		*/
		static func nested(_ depth: Int, hasKind: Bool) -> Chain {
			let kind: Kind? = hasKind ? .leaf : nil
			var chain = Chain(kind: kind)

			for _ in 0..<(depth - 1) {
				chain = Chain(nextNode: chain, kind: kind)
			}

			return chain
		}
	}

	@Test(arguments: [SOML.Encoder.KeyEncodingStrategy.useDefaultKeys, .convertToKebabCase, .convertToSnakeCase])
	func `a value nested past the limit is refused with the coding keys of the type, at every depth past it`(_ strategy: SOML.Encoder.KeyEncodingStrategy) {
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = strategy

		for hasKind in [false, true] {
			// The deepest object at the limit can hold a scalar that is not one of the encoder's fast paths, which must still be accepted.
			#expect(throws: Never.self) {
				try encoder.encodeToString(Chain.nested(Parser.maximumDepth, hasKind: hasKind))
			}

			for depth in (Parser.maximumDepth + 1)...(Parser.maximumDepth + 3) {
				do {
					_ = try encoder.encodeToString(Chain.nested(depth, hasKind: hasKind))
					Issue.record("Expected an error at depth \(depth)")
				} catch let EncodingError.invalidValue(_, context) {
					let keys = Set(context.codingPath.map(\.stringValue))
					#expect(keys.isSubset(of: ["nextNode", "kind"]), "Depth \(depth), kind \(hasKind): \(keys)")
					#expect(context.debugDescription.contains("nested more than"))
				} catch {
					Issue.record("Unexpected \(error)")
				}
			}
		}
	}

	/**
	A chain of objects that ends in a `[String: Int]`, which a key strategy writes without converting its keys.
	*/
	final class MapChain: Encodable {
		let nextNode: MapChain?
		let lastMap: [String: Int]?

		init(nextNode: MapChain? = nil, lastMap: [String: Int]? = nil) {
			self.nextNode = nextNode
			self.lastMap = lastMap
		}

		/**
		A chain whose objects nest `depth` levels deep, with the top-level object as the first and the dictionary as the last.
		*/
		static func nested(_ depth: Int) -> MapChain {
			var chain = MapChain(lastMap: ["someKey": 1])

			for _ in 0..<(depth - 2) {
				chain = MapChain(nextNode: chain)
			}

			return chain
		}
	}

	@Test(arguments: [SOML.Encoder.KeyEncodingStrategy.useDefaultKeys, .convertToKebabCase, .convertToSnakeCase])
	func `a dictionary nested past the limit is refused with the coding keys of the type, also under a key strategy`(_ strategy: SOML.Encoder.KeyEncodingStrategy) {
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = strategy

		#expect(throws: Never.self) {
			try encoder.encodeToString(MapChain.nested(Parser.maximumDepth))
		}

		do {
			_ = try encoder.encodeToValue(MapChain.nested(Parser.maximumDepth + 1))
			Issue.record("Expected an error")
		} catch let EncodingError.invalidValue(_, context) {
			let keys = Set(context.codingPath.map(\.stringValue))
			#expect(keys == ["nextNode", "lastMap"])
			#expect(context.debugDescription.contains("nested more than"))
		} catch {
			Issue.record("Unexpected \(error)")
		}
	}
}

@Suite
struct SuperEncoderTests {
	/**
	A type that writes a keyed container through each of two super encoders for the same member.
	*/
	private struct TwoSupers: Encodable {
		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: Keys.self)
			try container.encode(1, forKey: .a)

			let first = container.superEncoder()
			var firstContainer = first.container(keyedBy: Keys.self)
			try firstContainer.encode("Rex", forKey: .b)

			let second = container.superEncoder()
			var secondContainer = second.container(keyedBy: Keys.self)
			try secondContainer.encode("Second", forKey: .c)
		}

		enum Keys: String, CodingKey {
			case a
			case b
			case c
		}
	}

	@Test
	func `a second super encoder keeps the first one's content`() throws {
		// The two super encoders share one storage, as with `JSONEncoder`, so that neither writer's content is lost.
		let text = try SOML.Encoder().encodeToString(TwoSupers())
		#expect(text == """
			a: 1
			super: {
				b: 'Rex'
				c: 'Second'
			}

			""")
	}
}

@Suite
struct SuperDecoderTests {
	struct Probe: Decodable {
		var paths = [String: [String]]()

		enum Keys: String, CodingKey {
			case nested
		}

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: Keys.self)

			if let decoder = try? container.superDecoder() {
				paths["super"] = decoder.codingPath.map(\.stringValue)
			}

			if let decoder = try? container.superDecoder(forKey: .nested) {
				paths["nested"] = decoder.codingPath.map(\.stringValue)
			}
		}
	}

	@Test
	func `missing super decoders can be detected`() throws {
		#expect(try SOML.Decoder().decode(Probe.self, from: "{}").paths.isEmpty)
	}

	@Test(arguments: ["super: null\nnested: null", "super: {}\nnested: {}"])
	func `present super decoders keep their coding paths`(_ source: String) throws {
		#expect(try SOML.Decoder().decode(Probe.self, from: source).paths == ["super": ["super"], "nested": ["nested"]])
	}
}

@Suite
struct DeepDecodeTests {
	/**
	A type that decodes itself recursively through an unkeyed container, like a tree.
	*/
	private struct Nest: Decodable {
		var items: [Nest]?
		var leaf: Int?

		init(from decoder: any Decoder) throws {
			let container = try decoder.singleValueContainer()

			if let int = try? container.decode(Int.self) {
				leaf = int
				items = nil
			} else {
				leaf = nil
				items = try decoder.singleValueContainer().decode([Nest].self)
			}
		}
	}

	private static func deepValue(_ depth: Int) -> SOML.Value {
		var value = SOML.Value.int(7)

		for _ in 0..<depth {
			value = .array([value])
		}

		return value
	}

	@Test
	func `a value nested deeper than a reader accepts is a decoding error, not a crash`() throws {
		// A value built in memory can be deeper than any document the parser takes.
		let error = try #require(#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(Nest.self, from: Self.deepValue(Parser.maximumDepth + 20))
		})

		guard case .dataCorrupted(let context) = error else {
			Issue.record("Expected data corrupted, got \(error)")
			return
		}

		#expect(context.debugDescription.contains("nested more than"))
	}

	@Test
	func `a value decodes up to the nesting limit of a reader and not one level past it`() throws {
		for isObject in [false, true] {
			func nested(_ depth: Int) -> SOML.Value {
				var value = SOML.Value.int(7)

				for _ in 0..<depth {
					value = isObject ? .object(["a": value]) : .array([value])
				}

				return value
			}

			#expect(try SOML.Decoder().decode(SOML.Value.self, from: nested(Parser.maximumDepth)) == nested(Parser.maximumDepth))
			#expect(throws: DecodingError.self) {
				try SOML.Decoder().decode(SOML.Value.self, from: nested(Parser.maximumDepth + 1))
			}
			#expect(throws: DecodingError.self) {
				try SOML.Decoder().decode(SOML.Value.self, from: nested(Parser.maximumDepth + 1), defaults: .object([:]))
			}
		}
	}

	@Test
	func `defaults nested deeper than a reader accepts are an error when decoding from text`() throws {
		// The parser bounds the document, but not the defaults, which the merged value keeps where the document leaves them out.
		var defaults = SOML.Value.int(7)

		for _ in 0..<(Parser.maximumDepth + 1) {
			defaults = .object(["a": defaults])
		}

		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(SOML.Value.self, from: "{}", defaults: defaults)
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(SOML.Value.self, from: Array("{}".utf8), defaults: defaults)
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(SOML.Value.self, from: SOML.Value.object([:]), defaults: defaults)
		}
	}

	@Test
	func `defaults nested exactly as deep as a reader accepts decode from text, also merged with a document as deep`() throws {
		var defaults = SOML.Value.int(7)

		for _ in 0..<Parser.maximumDepth {
			defaults = .object(["a": defaults])
		}

		#expect(try SOML.Decoder().decode(SOML.Value.self, from: "{}", defaults: defaults) == defaults)

		// The document is 100 levels deep in another member, so the merged value is as deep as either, not deeper.
		let document = "b: " + String(repeating: "[", count: Parser.maximumDepth - 1) + String(repeating: "]", count: Parser.maximumDepth - 1)
		let merged = try SOML.Decoder().decode(SOML.Value.self, from: document, defaults: defaults)
		#expect(merged.objectValue?["a"] == defaults.objectValue?["a"])
		#expect(merged.objectValue?["b"] != nil)
	}

	struct Holder: Codable {
		var extra: SOML.Value
	}

	@Test
	func `a value far deeper than a reader accepts is a decoding error with defaults as deep, not a crash`() throws {
		func chain() -> SOML.Value {
			var value = SOML.Value.int(7)

			// Deep enough that merging before the depth check overflows the stack, and shallow enough that tearing the value down on the small stack of a test thread does not.
			for _ in 0..<1500 {
				value = .object(["a": value])
			}

			return value
		}

		// Merging recurses where both sides are objects, so it must not run before the document's depth is checked.
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(Holder.self, from: SOML.Value.object(["extra": chain()]), defaults: Holder(extra: chain()))
		}
	}

	@Test
	func `a value deeper than the depth limit of a document still decodes`() throws {
		// Decoding one level of a recursive type costs more stack than parsing one, so this stays well under the limit, which leaves room for the small stack of a test thread even in a debug build.
		let decoded = try SOML.Decoder().decode(Nest.self, from: Self.deepValue(50))
		#expect(decoded.items?.count == 1)
	}
}

@Suite
struct DecodeIfPresentTests {
	struct Optionals: Decodable {
		var value: Int?
		var nested: [String: Int]?
	}

	@Test
	func `missing, null, and present`() throws {
		#expect(try SOML.Decoder().decode(Optionals.self, from: "{}").value == nil)
		#expect(try SOML.Decoder().decode(Optionals.self, from: "value: null").value == nil)
		#expect(try SOML.Decoder().decode(Optionals.self, from: "value: 3").value == 3)
		#expect(try SOML.Decoder().decode(Optionals.self, from: "nested: {a: 1}").nested == ["a": 1])
		#expect(try SOML.Decoder().decode(Optionals.self, from: "nested: null").nested == nil)
	}

	@Test
	func `a present value of the wrong type is still an error`() {
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(Optionals.self, from: "value: 'three'")
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(Optionals.self, from: "value: 3.5")
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(Optionals.self, from: "nested: [1]")
		}
	}

	@Test
	func `with a key strategy`() throws {
		struct Keys: Decodable {
			var maxRetries: Int?
		}

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		#expect(try decoder.decode(Keys.self, from: "max-retries: 3").maxRetries == 3)
		#expect(try decoder.decode(Keys.self, from: "max-retries: null").maxRetries == nil)
		#expect(try decoder.decode(Keys.self, from: "maxRetries: 3").maxRetries == nil)
	}
}

@Suite
struct DictionaryStrategyTests {
	struct Wrapper: Codable, Equatable {
		var someMap: [String: [String: Int]]
		var optionalValues: [String: Int?]
		var maybeMap: [String: Int]?
	}

	@Test
	func `nested and optional dictionaries keep their keys under a key strategy`() throws {
		let value = Wrapper(someMap: ["camelKey": ["innerKey": 1]], optionalValues: ["someKey": nil, "otherKey": 2], maybeMap: ["mapKey": 3])
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		// Canonical form, because a dictionary's order changes from one run to the next.
		encoder.writesCanonicalForm = true
		let text = try encoder.encodeToString(value)
		#expect(text == """
			maybe-map: {
				mapKey: 3
			}
			optional-values: {
				otherKey: 2
				someKey: null
			}
			some-map: {
				camelKey: {
					innerKey: 1
				}
			}

			""")

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		#expect(try decoder.decode(Wrapper.self, from: text) == value)
	}

	struct Holder: Codable, Equatable {
		var someMap: [String: Int]
		var mapList: [[String: Int]]
		var someValue: SOML.Value
		var someObject: SOML.Object
	}

	@Test(arguments: [
		(SOML.Encoder.KeyEncodingStrategy.convertToKebabCase, SOML.Decoder.KeyDecodingStrategy.convertFromKebabCase),
		(.convertToSnakeCase, .convertFromSnakeCase),
	])
	func `a key strategy changes no key of a dictionary, a SOML value, or a SOML object, as a property, an element, or the document`(_ encoding: SOML.Encoder.KeyEncodingStrategy, _ decoding: SOML.Decoder.KeyDecodingStrategy) throws {
		let holder = Holder(
			someMap: ["camelKey": 1, "kebab-key": 2, "snake_key": 3],
			mapList: [["innerKey": 1]],
			someValue: ["valueKey": ["deepKey": 1]],
			someObject: ["objectKey": 1]
		)

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = decoding
		let separator = encoding == .convertToKebabCase ? "-" : "_"

		for writesCanonicalForm in [false, true] {
			var encoder = SOML.Encoder()
			encoder.keyEncodingStrategy = encoding
			encoder.writesCanonicalForm = writesCanonicalForm

			let text = try encoder.encodeToString(holder)
			let value = try SOML.Value(parsing: text)
			#expect(value["some\(separator)map"]?.objectValue.map { Set($0.keys) } == ["camelKey", "kebab-key", "snake_key"])
			#expect(value["map\(separator)list"]?[0]?.objectValue?.keys == ["innerKey"])
			#expect(value["some\(separator)value"] == ["valueKey": ["deepKey": 1]])
			#expect(value["some\(separator)object"] == ["objectKey": 1])
			#expect(try decoder.decode(Holder.self, from: text) == holder)
			#expect(try encoder.encodeToString(["camelKey": 1]) == "camelKey: 1\n")
		}

		#expect(try decoder.decode([String: Int].self, from: "camelKey: 1\nkebab-key: 2\nsnake_key: 3") == ["camelKey": 1, "kebab-key": 2, "snake_key": 3])
	}
}

@Suite
struct DateTests {
	@Test(arguments: [0.1, 0.001, 0.000_001, 0.000_000_001, -0.1, -0.001])
	func `a Date near the reference date round-trips without losing precision`(_ interval: Double) throws {
		let date = Date(timeIntervalSinceReferenceDate: interval)
		let instant = try #require(SOML.Instant(date))
		#expect(instant.date == date)

		let text = try SOML.Encoder().encodeToString([date])
		#expect(try SOML.Decoder().decode([Date].self, from: text) == [date])
	}

	@Test
	func `a Date is written with the fewest digits that read back as the same Date`() throws {
		let cases: [(Double, String)] = [
			(1_789_826_400, "2026-09-19T14:00:00Z"),
			(1_789_826_400.1, "2026-09-19T14:00:00.0999999Z"),
			(1_789_826_400.123, "2026-09-19T14:00:00.1229999Z"),
			(1_789_826_400.5, "2026-09-19T14:00:00.5Z"),
			(-0.25, "1969-12-31T23:59:59.75Z"),
		]

		for (interval, expected) in cases {
			let date = Date(timeIntervalSince1970: interval)
			#expect(try SOML.Encoder().encodeToString([date]) == "[\n\t\(expected)\n]\n")
			#expect(try SOML.Decoder().decode([Date].self, from: "[\(expected)]") == [date])
		}
	}

	@Test
	func `random dates round-trip exactly through text`() throws {
		var generator = SeededGenerator(seed: 21)

		for _ in 0..<5000 {
			let date = Date(timeIntervalSinceReferenceDate: Double.random(in: -60_000_000_000...250_000_000_000, using: &generator))
			let text = try SOML.Encoder().encodeToString([date])
			let decoded = try SOML.Decoder().decode([Date].self, from: text)
			#expect(decoded == [date], "\(text)")
			// Text is stable after one round through `Date`.
			#expect(try SOML.Encoder().encodeToString(decoded) == text)
		}
	}

	@Test
	func `an exact instant read into a Date is stable after one round`() throws {
		let first = try SOML.Decoder().decode([Date].self, from: "[2026-09-19T14:00:00.123456789Z]")
		let text = try SOML.Encoder().encodeToString(first)
		#expect(try SOML.Encoder().encodeToString(SOML.Decoder().decode([Date].self, from: text)) == text)
	}

	@Test
	func `a type mismatch for a Date names Date`() {
		do {
			_ = try SOML.Decoder().decode([Date].self, from: "['2026-09-19']")
			Issue.record("Expected an error")
		} catch DecodingError.typeMismatch(let type, _) {
			#expect(ObjectIdentifier(type) == ObjectIdentifier(Date.self))
		} catch {
			Issue.record("Unexpected \(error)")
		}
	}

	@Test
	func `a Date before 0001-01-01T00:00:00Z or past 9999-12-31T23:59:59.999999999Z cannot be encoded`() throws {
		let first = SOML.Instant.minimum.date
		#expect(try SOML.Encoder().encodeToString([first]) == "[\n\t0001-01-01T00:00:00Z\n]\n")
		#expect(try SOML.Encoder().encodeToString([SOML.Instant.maximum.date]).hasPrefix("[\n\t9999-12-31T23:59:59.99"))

		for date in [first.addingTimeInterval(-0.001), SOML.Instant.maximum.date.addingTimeInterval(0.001), Date.distantFuture.addingTimeInterval(1e12)] {
			#expect(throws: EncodingError.self) {
				try SOML.Encoder().encodeToString([date])
			}
		}
	}

	@Test
	func `an instant read into a Date near 2001 is off by less than a microsecond`() throws {
		let dates = try SOML.Decoder().decode([Date].self, from: "[2001-01-01T00:00:00.123456789Z, 2000-12-31T23:59:59.987654321Z]")
		#expect(abs(dates[0].timeIntervalSinceReferenceDate - 0.123_456_789) < 0.000_001)
		#expect(abs(dates[1].timeIntervalSinceReferenceDate - -0.012_345_679) < 0.000_001)
	}
}

@Suite
struct MixedContainerTests {
	struct ObjectThenArray: Encodable {
		enum Keys: String, CodingKey {
			case a
		}

		func encode(to encoder: any Encoder) throws {
			var keyed = encoder.container(keyedBy: Keys.self)
			try keyed.encode(1, forKey: .a)
			var unkeyed = encoder.unkeyedContainer()
			try unkeyed.encode(2)
		}
	}

	struct ArrayThenObject: Encodable {
		enum Keys: String, CodingKey {
			case a
		}

		func encode(to encoder: any Encoder) throws {
			var unkeyed = encoder.unkeyedContainer()
			try unkeyed.encode(2)
			var keyed = encoder.container(keyedBy: Keys.self)
			try keyed.encode(1, forKey: .a)
		}
	}

	struct ValueAfterObject: Encodable {
		enum Keys: String, CodingKey {
			case a
		}

		func encode(to encoder: any Encoder) throws {
			var keyed = encoder.container(keyedBy: Keys.self)
			try keyed.encode(1, forKey: .a)
			try SOML.Value.array([3]).encode(to: encoder)
		}
	}

	/**
	A type that writes a member with a keyed container, and then an object or an array through a single value container of the same encoder.
	*/
	struct ContainerThenSingleValue: Encodable {
		var isArray = false

		enum Keys: String, CodingKey {
			case a
		}

		struct Other: Encodable {
			var b = 2
		}

		func encode(to encoder: any Encoder) throws {
			if isArray {
				var unkeyed = encoder.unkeyedContainer()
				try unkeyed.encode(1)
				var single = encoder.singleValueContainer()
				try single.encode([2])
			} else {
				var keyed = encoder.container(keyedBy: Keys.self)
				try keyed.encode(1, forKey: .a)
				var single = encoder.singleValueContainer()
				try single.encode(Other())
			}
		}
	}

	@Test
	func `a container and then an object or array through a single value container with one encoder is an error, not silent loss`() {
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encodeToString(ContainerThenSingleValue())
		}
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encodeToString(ContainerThenSingleValue(isArray: true))
		}
	}

	@Test
	func `writing an object and an array with one encoder is an error, not silent loss`() {
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode(ObjectThenArray())
		}
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode(ArrayThenObject())
		}
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode(ValueAfterObject())
		}
	}

	@Test
	func `a conflict names both kinds at the encoder's path`() {
		do {
			_ = try SOML.Encoder().encodeToString(ObjectThenArray())
			Issue.record("Expected an error")
		} catch let error as EncodingError {
			guard case .invalidValue(_, let context) = error else {
				Issue.record("Unexpected \(error)")
				return
			}

			#expect(context.debugDescription == "The type wrote an object and then an array with the same encoder, which would lose what it wrote first")
			#expect(context.codingPath.isEmpty)
		} catch {
			Issue.record("Unexpected \(error)")
		}
	}
}

@Suite
struct PrimitiveContainerTests {
	@Test
	func `every integer type in arrays and dictionaries`() throws {
		#expect(try roundTrip([Int8.min, 0, .max]) == [Int8.min, 0, .max])
		#expect(try roundTrip([Int16.min, .max]) == [Int16.min, .max])
		#expect(try roundTrip([Int32.min, .max]) == [Int32.min, .max])
		#expect(try roundTrip([Int64.min, .max]) == [Int64.min, .max])
		#expect(try roundTrip([UInt8.min, .max]) == [UInt8.min, .max])
		#expect(try roundTrip([UInt16.max]) == [UInt16.max])
		#expect(try roundTrip([UInt32.max]) == [UInt32.max])
		#expect(try roundTrip([UInt64(Int64.max)]) == [UInt64(Int64.max)])
		#expect(try roundTrip([UInt(Int64.max)]) == [UInt(Int64.max)])
		#expect(try roundTrip([Int128(Int64.min), Int128(Int64.max)]) == [Int128(Int64.min), Int128(Int64.max)])
		#expect(try roundTrip([UInt128(Int64.max)]) == [UInt128(Int64.max)])
		#expect(try roundTrip(["a": UInt8(7)]) == ["a": UInt8(7)])
		#expect(try roundTrip(["a": Int64.min]) == ["a": Int64.min])
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode([UInt64.max])
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode([UInt8].self, from: "[256]")
		}
	}

	@Test
	func `every integer type in an array is range-checked when it decodes`() throws {
		let decoder = SOML.Decoder()
		#expect(try decoder.decode([Int8].self, from: "[-128, 127]") == [-128, 127])
		#expect(try decoder.decode([Int16].self, from: "[-32768, 32767]") == [-32768, 32767])
		#expect(try decoder.decode([UInt16].self, from: "[0, 65535]") == [0, 65535])
		#expect(try decoder.decode([UInt32].self, from: "[0, 4294967295]") == [0, 4294967295])
		#expect(try decoder.decode([UInt].self, from: "[0, 9223372036854775807]") == [0, UInt(Int64.max)])
		#expect(try decoder.decode([Int128].self, from: "[-9223372036854775808]") == [Int128(Int64.min)])
		#expect(try decoder.decode([UInt128].self, from: "[9223372036854775807]") == [UInt128(Int64.max)])

		for (type, source) in [(Int8.self, "[128]"), (Int8.self, "[-129]"), (Int16.self, "[32768]"), (UInt16.self, "[-1]"), (UInt16.self, "[65536]"), (UInt32.self, "[4294967296]"), (UInt.self, "[-1]"), (UInt128.self, "[-1]")] as [(any Decodable.Type, String)] {
			#expect(throws: DecodingError.self, "\(type) \(source)") {
				try Self.decodeArray(of: type, from: source)
			}
		}

		// A float never decodes into an integer type, also with the faster path.
		#expect(throws: DecodingError.self) {
			try decoder.decode([Int8].self, from: "[1.0]")
		}
	}

	private static func decodeArray<T: Decodable>(of type: T.Type, from source: String) throws {
		_ = try SOML.Decoder().decode([T].self, from: source)
	}

	@Test
	func `floats in arrays and dictionaries`() throws {
		#expect(try roundTrip([Float(0.1), -1.5, .infinity, -.infinity, .greatestFiniteMagnitude, .leastNonzeroMagnitude]) == [Float(0.1), -1.5, .infinity, -.infinity, .greatestFiniteMagnitude, .leastNonzeroMagnitude])
		#expect(try roundTrip(["a": Float(2.5)]) == ["a": Float(2.5)])
		#expect(try SOML.Encoder().encodeToString([Float(-0.0)]) == "[\n\t0.0\n]\n")
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode([Float].self, from: "[1e39]")
		}
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode([Float.nan])
		}
	}

	private func roundTrip<T: Codable>(_ value: T) throws -> T {
		try SOML.Decoder().decode(T.self, from: SOML.Encoder().encode(value))
	}
}

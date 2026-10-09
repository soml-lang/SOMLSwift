import Foundation
import Testing
@testable import SOML

@Suite
struct DecoderTests {
	struct Service: Codable, Equatable {
		var name: String
		var version: String
		var replicas: Int
		var timeout: Duration
		var drained: Bool
		var owner: String?
		var deployedAt: Date
		var labels: [String]
		var postgres: Postgres

		struct Postgres: Codable, Equatable {
			var host: String
			var port: UInt16
			var ssl: Bool
		}
	}

	@Test(.enabled(if: isSpecAvailable))
	func `decodes the edge service file with kebab-case keys`() throws {
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		let service = try decoder.decode(Service.self, from: exampleBlock(startingWith: "# The edge service"))
		#expect(service.name == "api-gateway")
		#expect(service.version == "2.1.0")
		#expect(service.replicas == 3)
		#expect(service.timeout == .seconds(30))
		#expect(service.drained == false)
		#expect(service.owner == nil)
		#expect(service.deployedAt == Date(timeIntervalSince1970: 1_789_826_400))
		#expect(service.labels == ["prod", "eu-west", "canary"])
		#expect(service.postgres == .init(host: "db.internal", port: 5432, ssl: true))
	}

	struct Primitives: Codable, Equatable {
		var bool: Bool
		var string: String
		var double: Double
		var float: Float
		var int: Int
		var int8: Int8
		var int16: Int16
		var int32: Int32
		var int64: Int64
		var uint: UInt
		var uint8: UInt8
		var uint16: UInt16
		var uint32: UInt32
		var uint64: UInt64
	}

	@Test
	func `decodes every primitive type`() throws {
		let source = """
			bool: true
			string: 'text'
			double: 1.5
			float: 0.1
			int: -1
			int8: -128
			int16: 32767
			int32: -2147483648
			int64: 9223372036854775807
			uint: 1
			uint8: 255
			uint16: 65535
			uint32: 4294967295
			uint64: 9223372036854775807
			"""
		let value = try SOML.Decoder().decode(Primitives.self, from: source)
		#expect(value == Primitives(bool: true, string: "text", double: 1.5, float: 0.1, int: -1, int8: -128, int16: 32767, int32: -2_147_483_648, int64: .max, uint: 1, uint8: 255, uint16: 65535, uint32: 4_294_967_295, uint64: 9_223_372_036_854_775_807))
	}

	@Test
	func `decodes primitives in arrays and as single values`() throws {
		let decoder = SOML.Decoder()
		#expect(try decoder.decode([Bool].self, from: "[true, false]") == [true, false])
		#expect(try decoder.decode([String].self, from: "['a', \"b\"]") == ["a", "b"])
		#expect(try decoder.decode([Int].self, from: "[1, -2, 0xFF]") == [1, -2, 255])
		#expect(try decoder.decode([Int8].self, from: "[127]") == [127])
		#expect(try decoder.decode([UInt8].self, from: "[255]") == [255])
		#expect(try decoder.decode([UInt64].self, from: "[0]") == [0])
		#expect(try decoder.decode([Double].self, from: "[1.5, 2, infinity]") == [1.5, 2, .infinity])
		#expect(try decoder.decode([Float].self, from: "[1.5, 2]") == [1.5, 2])
		#expect(try decoder.decode([Int?].self, from: "[1, null, 3]") == [1, nil, 3])
		#expect(try decoder.decode([[Int]].self, from: "[[1], [], [2, 3]]") == [[1], [], [2, 3]])
		#expect(try decoder.decode([String: Int].self, from: "a: 1\nb: 2") == ["a": 1, "b": 2])
		#expect(try decoder.decode([String: [String: Bool]].self, from: "a: {b: true}") == ["a": ["b": true]])
	}

	@Test
	func `128-bit integers encode and decode in the int64 range`() throws {
		struct Big: Codable, Equatable {
			var signed: Int128
			var unsigned: UInt128
			var items: [Int128]
		}

		let value = Big(signed: -5, unsigned: 6, items: [Int128(Int64.min)])
		let text = try SOML.Encoder().encodeToString(value)
		#expect(text == "signed: -5\nunsigned: 6\nitems: [\n\t-9223372036854775808\n]\n")
		#expect(try SOML.Decoder().decode(Big.self, from: text) == value)
		#expect(decodingError([UInt128].self, from: "[-1]") != nil)
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode([Int128(Int64.max) + 1])
		}
	}

	@Test
	func `an int decodes as a float when it converts exactly`() throws {
		let decoder = SOML.Decoder()
		#expect(try decoder.decode([Double].self, from: "[30, -1, 9007199254740992]") == [30, -1, 9_007_199_254_740_992])
		#expect(try decoder.decode([Float].self, from: "[16777216]") == [16_777_216])
		#expect(throws: DecodingError.self) {
			try decoder.decode([Double].self, from: "[9007199254740993]")
		}
		#expect(throws: DecodingError.self) {
			try decoder.decode([Float].self, from: "[16777217]")
		}
	}

	@Test
	func `an int at either end of the int64 range decodes as a Double only when it converts exactly`() throws {
		let decoder = SOML.Decoder()
		#expect(try decoder.decode([Double].self, from: "[-9223372036854775808]") == [-9_223_372_036_854_775_808])
		#expect(throws: DecodingError.self) {
			try decoder.decode([Double].self, from: "[9223372036854775807]")
		}
	}

	@Test
	func `a float never decodes as an int`() throws {
		let error = try #require(decodingError([Int].self, from: "[4.0]"))
		guard case .typeMismatch(_, let context) = error else {
			Issue.record("Expected a type mismatch, got \(error)")
			return
		}

		#expect(context.debugDescription.contains("An int is written without a fraction, like 4"))
		#expect(context.codingPath.map(\.intValue) == [0])
	}

	struct Endpoint: Decodable {
		var host: String
	}

	struct Deployment: Decodable {
		var endpoint: Endpoint
		var ports: [Int]
		var backup: Endpoint?
	}

	@Test(arguments: [
		("endpoint: 'db'\nports: [1]", "Expected an object for Endpoint, but found the string 'db' (line 1, column 1)", ["endpoint"]),
		("endpoint: {host: 'a'}\nports: {http: 80}", "Expected an array for Array<Int>, but found an object (line 2, column 1)", ["ports"]),
		("endpoint: {host: 'a'}\nports: []\nbackup: 5", "Expected an object for Endpoint, but found the int 5 (line 3, column 1)", ["backup"]),
		("[1]", "Expected an object for Deployment, but found an array (line 1, column 1)", []),
	])
	func `a mismatch for an object or an array names the type that reads it`(source: String, message: String, path: [String]) throws {
		let error = try #require(decodingError(Deployment.self, from: source))
		guard case .typeMismatch(_, let context) = error else {
			Issue.record("Expected a type mismatch, got \(error)")
			return
		}

		#expect(context.debugDescription == message)
		#expect(context.codingPath.map(\.stringValue) == path)
	}

	@Test
	func `reading past the end of an array says how many items it has, at the array`() throws {
		struct Pair: Decodable {
			var first: Int
			var second: Int

			init(from decoder: any Decoder) throws {
				var container = try decoder.unkeyedContainer()
				first = try container.decode(Int.self)
				second = try container.decode(Int.self)
			}
		}

		struct Holder: Decodable {
			var pair: Pair
		}

		let error = try #require(decodingError(Holder.self, from: "name: 'a'\npair: [1]"))
		guard case .valueNotFound(_, let context) = error else {
			Issue.record("Expected a missing value, got \(error)")
			return
		}

		#expect(context.debugDescription == "The array has no more items. It has 1 (line 2, column 1)")
		#expect(context.codingPath.map(\.stringValue) == ["pair", "1"])
	}

	@Test(arguments: ["1e300", "9.3e18", "-9.3e18", "9223372036854775808.0", "1.5", "-0.5"])
	func `a float that no int has the value of gets no hint to drop the fraction`(source: String) throws {
		let error = try #require(decodingError([Int].self, from: "[\(source)]"))
		guard case .typeMismatch(_, let context) = error else {
			Issue.record("Expected a type mismatch, got \(error)")
			return
		}

		#expect(context.debugDescription.hasPrefix("Expected an int for Int, but found the float "))
		#expect(!context.debugDescription.contains("without a fraction"), "Message was: \(context.debugDescription)")
	}

	@Test(arguments: [("-0.0", "0"), ("1e3", "1000"), ("-9.2e18", "-9200000000000000000"), ("-9223372036854775808.0", "-9223372036854775808")])
	func `an integral float gets a hint with the int of its value`(source: String, int: String) throws {
		let error = try #require(decodingError([Int64].self, from: "[\(source)]"))
		guard case .typeMismatch(_, let context) = error else {
			Issue.record("Expected a type mismatch, got \(error)")
			return
		}

		#expect(context.debugDescription.contains(". An int is written without a fraction, like \(int) (line 1, column 2)"), "Message was: \(context.debugDescription)")
	}

	@Test
	func `a hint to drop the fraction is only given when the int fits the type`() throws {
		func message<T: Decodable>(_ type: T.Type, _ source: String) throws -> String {
			let error = try #require(throws: DecodingError.self) {
				try SOML.Decoder().decode([T].self, from: "[\(source)]")
			}

			guard case .typeMismatch(_, let context) = error else {
				Issue.record("Expected a type mismatch, got \(error)")
				return ""
			}

			return context.debugDescription
		}

		#expect(try message(UInt8.self, "300.0") == "Expected an int for UInt8, but found the float 300.0 (line 1, column 2)")
		#expect(try message(UInt.self, "-1.0") == "Expected an int for UInt, but found the float -1.0 (line 1, column 2)")
		#expect(try message(Int8.self, "-129.0") == "Expected an int for Int8, but found the float -129.0 (line 1, column 2)")

		// At the ends of the range, the int of the hint decodes.
		#expect(try message(UInt8.self, "255.0") == "Expected an int for UInt8, but found the float 255.0. An int is written without a fraction, like 255 (line 1, column 2)")
		#expect(try message(Int8.self, "-128.0") == "Expected an int for Int8, but found the float -128.0. An int is written without a fraction, like -128 (line 1, column 2)")
		#expect(try SOML.Decoder().decode([UInt8].self, from: "[255]") == [255])
		#expect(try SOML.Decoder().decode([Int8].self, from: "[-128]") == [-128])
	}

	@Test
	func `an int that a float type cannot hold exactly gets a hint with the closest value, which decodes`() throws {
		func message<T: Decodable>(_ type: T.Type, _ int: Int64) throws -> String {
			let error = try #require(throws: DecodingError.self) {
				try SOML.Decoder().decode([T].self, from: "[\(int)]")
			}

			guard case .dataCorrupted(let context) = error else {
				Issue.record("Expected data corrupted, got \(error)")
				return ""
			}

			return context.debugDescription
		}

		#expect(try message(Float.self, 16_777_217) == "The int 16777217 cannot be represented exactly as Float. Write the closest one as a float: 16777216.0 (line 1, column 2)")
		#expect(try SOML.Decoder().decode([Float].self, from: "[16777216.0]") == [16_777_216])

		#expect(try message(Double.self, 9_007_199_254_740_993) == "The int 9007199254740993 cannot be represented exactly as Double. Write the closest one as a float: 9007199254740992.0 (line 1, column 2)")
		#expect(try SOML.Decoder().decode([Double].self, from: "[9007199254740992.0]") == [9_007_199_254_740_992])

		#expect(try message(Double.self, Int64.max) == "The int 9223372036854775807 cannot be represented exactly as Double. Write the closest one as a float: 9223372036854776000.0 (line 1, column 2)")
		#expect(try SOML.Decoder().decode([Double].self, from: "[9223372036854776000.0]") == [Double(Int64.max)])

		#expect(try message(Float.self, Int64.max) == "The int 9223372036854775807 cannot be represented exactly as Float. Write the closest one as a float: 9223372036854776000.0 (line 1, column 2)")
		#expect(try SOML.Decoder().decode([Float].self, from: "[9223372036854776000.0]") == [Float(Int64.max)])
	}

	#if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
	@Test
	func `Float16 is decoded as strictly as Float, and an error names it`() throws {
		let decoder = SOML.Decoder()
		#expect(try decoder.decode([Float16].self, from: "[2048, 0.5, -0.0, infinity]") == [2048, 0.5, 0, .infinity])

		for (source, message) in [
			("2049", "The int 2049 cannot be represented exactly as Float16. Write the closest one as a float: 2048.0 (line 1, column 2)"),
			("70000", "The int 70000 does not fit in Float16 (line 1, column 2)"),
			("70000.0", "The float 70000.0 does not fit in Float16 (line 1, column 2)"),
			("1e-10", "The float 1e-10 does not fit in Float16 (line 1, column 2)"),
		] {
			let error = try #require(throws: DecodingError.self) {
				try decoder.decode([Float16].self, from: "[\(source)]")
			}

			guard case .dataCorrupted(let context) = error else {
				Issue.record("Expected data corrupted, got \(error)")
				continue
			}

			#expect(context.debugDescription == message)
		}

		#expect(try decoder.decode([Float16].self, from: "[2048.0]") == [2048])
	}

	@Test
	func `Float16 round trips, including the ends of its range`() throws {
		let values: [Float16] = [0, -0.0, 0.1, -65504, 65504, .leastNonzeroMagnitude, .infinity, -.infinity]
		let text = try SOML.Encoder().encodeToString(values)
		let decoded = try SOML.Decoder().decode([Float16].self, from: text)
		// The sign of a zero is not part of the format, so `-0.0` is written `0.0`.
		#expect(decoded == values)
		#expect(text.contains("-0.0") == false)

		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode([Float16.nan])
		}
	}
	#endif

	@Test
	func `the hint to drop the fraction works for the widest int types`() throws {
		for (type, source, hint) in [
			([UInt64].self as any Decodable.Type, "[-1.0]", false),
			([UInt128].self, "[5.0]", true),
			([Int128].self, "[-5.0]", true),
			([UInt128].self, "[-5.0]", false),
		] {
			let error = try #require(throws: DecodingError.self) {
				_ = try SOML.Decoder().decode(type, from: source)
			}

			guard case .typeMismatch(_, let context) = error else {
				Issue.record("Expected a type mismatch, got \(error)")
				continue
			}

			#expect(context.debugDescription.contains("An int is written without a fraction") == hint, "Message was: \(context.debugDescription)")
		}
	}

	@Test
	func `strict types`() throws {
		let cases: [(any Decodable.Type, String)] = [
			([String].self, "[1]"),
			([String].self, "[true]"),
			([String].self, "[2026-09-19T14:00:00Z]"),
			([Int].self, "['1']"),
			([Int].self, "[1.5]"),
			([Int].self, "[true]"),
			([Bool].self, "[1]"),
			([Bool].self, "['true']"),
			([Double].self, "['1.5']"),
			([Date].self, "['2026-09-19T14:00:00Z']"),
			([Date].self, "[0]"),
			([SOML.Instant].self, "['2026-09-19T14:00:00Z']"),
			([URL].self, "[1]"),
			([Data].self, "[[1, 2]]"),
			([[Int]].self, "[{}]"),
			([[String: Int]].self, "[[]]"),
			([SOML.Object].self, "[[]]"),
		]

		for (type, source) in cases {
			#expect(throws: DecodingError.self, "\(type) from \(source)") {
				_ = try SOML.Decoder().decode(type, from: source)
			}
		}
	}

	@Test
	func `an integer out of range is an error`() throws {
		let cases: [(any Decodable.Type, String)] = [
			([Int8].self, "[128]"),
			([Int8].self, "[-129]"),
			([UInt8].self, "[256]"),
			([UInt8].self, "[-1]"),
			([UInt].self, "[-1]"),
			([UInt64].self, "[-1]"),
			([Int16].self, "[40000]"),
			([UInt32].self, "[4294967296]"),
			([Int32].self, "[2147483648]"),
		]

		for (type, source) in cases {
			let error = try #require(decodingError(type, from: source), "\(type) from \(source)")
			guard case .dataCorrupted(let context) = error else {
				Issue.record("Expected data corrupted, got \(error)")
				continue
			}

			#expect(context.debugDescription.contains("does not fit"))
		}
	}

	@Test
	func `a float out of range for Float is an error`() throws {
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode([Float].self, from: "[1e300]")
		}
		#expect(try SOML.Decoder().decode([Float].self, from: "[infinity]") == [.infinity])
	}

	@Test
	func `a float too small for Float is an error, not a silent zero`() throws {
		// As the spec makes a literal that rounds to zero an error, because `0.0` is the spelling of zero.
		for text in ["1e-50", "-1e-50", "5e-324", "7e-46"] {
			let error = try #require(#expect(throws: DecodingError.self) {
				try SOML.Decoder().decode([String: Float].self, from: "ratio: \(text)")
			})

			guard case .dataCorrupted(let context) = error else {
				Issue.record("Expected dataCorrupted, got \(error)")
				continue
			}

			#expect(context.debugDescription.hasPrefix("The float \(text) does not fit in Float"))
			#expect(context.codingPath.map(\.stringValue) == ["ratio"])
		}

		// A subnormal `Float` is not zero, and zero itself is fine.
		#expect(try SOML.Decoder().decode([Float].self, from: "[1e-45, 1e-40, 0.0, -0.0, 1.0e-38]") == [.leastNonzeroMagnitude, Float(1e-40 as Double), 0, 0, 1e-38])
		#expect(try SOML.Decoder().decode([Double].self, from: "[5e-324]") == [.leastNonzeroMagnitude])
	}

	struct Optionals: Codable, Equatable {
		var present: Int?
		var null: Int?
		var missing: Int?
	}

	@Test
	func `optionals`() throws {
		let value = try SOML.Decoder().decode(Optionals.self, from: "present: 1\nnull: null")
		#expect(value == Optionals(present: 1, null: nil, missing: nil))
	}

	@Test
	func `null for a non-optional is value not found`() throws {
		struct Required: Decodable {
			var value: Int
		}

		let error = try #require(decodingError(Required.self, from: "value: null"))
		guard case .valueNotFound(_, let context) = error else {
			Issue.record("Expected value not found, got \(error)")
			return
		}

		#expect(context.codingPath.map(\.stringValue) == ["value"])
		#expect(context.debugDescription.contains("found null"))
	}

	@Test
	func `null for a SOML object that decodes itself is value not found, as through a container`() throws {
		/**
		A type that calls `SOML.Object(from:)` directly, as a property wrapper or a superclass does, rather than through a container.
		*/
		struct Holder: Decodable {
			enum Keys: CodingKey {
				case object
			}

			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: Keys.self)
				_ = try SOML.Object(from: container.superDecoder(forKey: .object))
			}
		}

		let error = try #require(decodingError(Holder.self, from: "object: null"))
		guard case .valueNotFound(let type, let context) = error else {
			Issue.record("Expected value not found, got \(error)")
			return
		}

		#expect(type is SOML.Object.Type)
		#expect(context.codingPath.map(\.stringValue) == ["object"])

		#expect {
			try JSONDecoder().decode(SOML.Object.self, from: Data("null".utf8))
		} throws: { error in
			guard case DecodingError.valueNotFound(let type, _) = error else {
				return false
			}

			return type is SOML.Object.Type
		}
	}

	@Test
	func `a missing key is key not found`() throws {
		struct Required: Decodable {
			var value: Int
		}

		let error = try #require(decodingError(Required.self, from: "other: 1"))
		guard case .keyNotFound(let key, _) = error else {
			Issue.record("Expected key not found, got \(error)")
			return
		}

		#expect(key.stringValue == "value")
	}

	@Test
	func `the coding path of a nested error`() throws {
		struct Outer: Decodable {
			var items: [Inner]
		}

		struct Inner: Decodable {
			var count: Int
		}

		let error = try #require(decodingError(Outer.self, from: "items: [{count: 1}, {count: 'two'}]"))
		guard case .typeMismatch(_, let context) = error else {
			Issue.record("Expected a type mismatch, got \(error)")
			return
		}

		#expect(context.codingPath.map(\.stringValue) == ["items", "1", "count"])
		#expect(context.debugDescription.contains("the string 'two'"))
	}

	@Test
	func `a syntax error is data corrupted with the parse error underneath`() throws {
		let error = try #require(decodingError([Int].self, from: "[1, 2"))
		guard case .dataCorrupted(let context) = error else {
			Issue.record("Expected data corrupted, got \(error)")
			return
		}

		let parseError = try #require(context.underlyingError as? SOML.ParseError)
		#expect(parseError.location.line == 1)
		#expect(context.debugDescription.contains("Unterminated array: expected “]”"))
	}

	@Test
	func `decodes from bytes, a string, and a parsed value`() throws {
		let decoder = SOML.Decoder()
		#expect(try decoder.decode([Int].self, from: Data("[1]".utf8)) == [1])
		#expect(try decoder.decode([Int].self, from: Array("[1]".utf8)) == [1])
		#expect(try decoder.decode([Int].self, from: "[1]") == [1])
		#expect(try decoder.decode([Int].self, from: SOML.Value.array([1])) == [1])
		// A parsed value can be a scalar, which a document cannot.
		#expect(try decoder.decode(Int.self, from: SOML.Value.int(5)) == 5)
		#expect(try decoder.decode(String?.self, from: SOML.Value.null) == nil)
	}

	@Test
	func `infers the type`() throws {
		let numbers: [Int] = try SOML.Decoder().decode(from: "[1, 2]")
		#expect(numbers == [1, 2])
	}

	@Test
	func `special types`() throws {
		struct Special: Decodable {
			var date: Date
			var instant: SOML.Instant
			var url: URL
			var data: Data
			var value: SOML.Value
			var object: SOML.Object
			var values: [SOML.Value]
		}

		let source = """
			date: 2026-09-19T14:00:00.5Z
			instant: 2026-09-19T14:00:00.123456789Z
			url: 'https://example.com/path?query=1'
			data: 'AAEC/w=='
			value: {nested: [1, 'x']}
			object: {a: 1}
			values: [1, 1.0, 'one', null]
			"""
		let special = try SOML.Decoder().decode(Special.self, from: source)
		#expect(special.date == Date(timeIntervalSince1970: 1_789_826_400.5))
		#expect(special.instant.nanoseconds == 123_456_789)
		#expect(special.url == URL(string: "https://example.com/path?query=1"))
		#expect(special.data == Data([0, 1, 2, 255]))
		#expect(special.value == ["nested": [1, "x"]])
		#expect(special.object == ["a": 1])
		#expect(special.values == [1, 1.0, "one", nil])
	}

	@Test
	func `invalid base64 and an invalid URL`() {
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode([Data].self, from: "['not base64!']")
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode([URL].self, from: "['']")
		}
	}

	enum Level: String, Codable {
		case debug
		case info
	}

	enum Priority: Int, Codable {
		case low = 1
		case high = 2
	}

	enum Shape: Codable, Equatable {
		case circle(radius: Double)
		case rectangle(width: Double, height: Double)
		case point
	}

	@Test
	func `enums`() throws {
		let decoder = SOML.Decoder()
		#expect(try decoder.decode([Level].self, from: "['info', 'debug']") == [.info, .debug])
		#expect(try decoder.decode([Priority].self, from: "[2, 1]") == [.high, .low])
		#expect(throws: DecodingError.self) {
			try decoder.decode([Level].self, from: "['trace']")
		}
		#expect(try decoder.decode([Shape].self, from: "[{circle: {radius: 1.5}}, {rectangle: {width: 1, height: 2.5}}, {point: {}}]") == [.circle(radius: 1.5), .rectangle(width: 1, height: 2.5), .point])
	}

	@Test
	func `int keys in a dictionary`() throws {
		#expect(try SOML.Decoder().decode([Int: String].self, from: "404: 'not found'\n500: 'error'") == [404: "not found", 500: "error"])
	}

	@Test
	func `kebab-case and snake_case keys`() throws {
		struct Keys: Decodable, Equatable {
			var deployedAt: Int
			var baseURL: String
			var isHTTP2Enabled: Bool
			var plain: Int
		}

		var kebab = SOML.Decoder()
		kebab.keyDecodingStrategy = .convertFromKebabCase
		#expect(try kebab.decode(Keys.self, from: "deployed-at: 1\nbase-url: 'x'\nis-http2-enabled: true\nplain: 2") == Keys(deployedAt: 1, baseURL: "x", isHTTP2Enabled: true, plain: 2))

		var snake = SOML.Decoder()
		snake.keyDecodingStrategy = .convertFromSnakeCase
		#expect(try snake.decode(Keys.self, from: "deployed_at: 1\nbase_url: 'x'\nis_http2_enabled: true\nplain: 2") == Keys(deployedAt: 1, baseURL: "x", isHTTP2Enabled: true, plain: 2))

		// The default reads keys as they are.
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(Keys.self, from: "deployed-at: 1\nbase-url: 'x'\nis-http2-enabled: true\nplain: 2")
		}
	}

	@Test
	func `a key strategy does not change dictionary keys`() throws {
		struct Wrapper: Decodable {
			var someMap: [String: Int]
		}

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		let value = try decoder.decode(Wrapper.self, from: "some-map: {'kebab-key': 1, camelKey: 2, snake_key: 3}")
		#expect(value.someMap == ["kebab-key": 1, "camelKey": 2, "snake_key": 3])
	}

	@Test
	func `the missing key error names the converted key`() throws {
		struct Keys: Decodable {
			var deployedAt: Int
		}

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase

		do {
			_ = try decoder.decode(Keys.self, from: "other: 1")
			Issue.record("Expected an error")
		} catch DecodingError.keyNotFound(_, let context) {
			#expect(context.debugDescription.contains("deployed-at"))
			#expect(context.debugDescription.contains("deployedAt"))
		}
	}

	@Test
	func `all keys with a key strategy`() throws {
		struct AnyKeys: Decodable {
			var keys: [String]
			var values: [Int]

			struct Key: CodingKey {
				var stringValue: String
				var intValue: Int? { nil }

				init(stringValue: String) {
					self.stringValue = stringValue
				}

				init?(intValue: Int) {
					nil
				}
			}

			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: Key.self)
				keys = container.allKeys.map(\.stringValue)
				values = try container.allKeys.map { try container.decode(Int.self, forKey: $0) }
			}
		}

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		let value = try decoder.decode(AnyKeys.self, from: "first-key: 1\nsecond: 2\nhttp2-port: 3")
		#expect(value.keys == ["firstKey", "second", "http2Port"])
		#expect(value.values == [1, 2, 3])
	}

	@Test
	func `all keys under a key strategy are converted back to camelCase, which loses what does not convert back`() throws {
		struct AnyKeys: Decodable {
			var keys: [String]
			var values: [String: Int]

			struct Key: CodingKey {
				var stringValue: String
				var intValue: Int? { nil }

				init(stringValue: String) {
					self.stringValue = stringValue
				}

				init?(intValue: Int) {
					nil
				}
			}

			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: Key.self)
				keys = container.allKeys.map(\.stringValue)
				values = [:]

				for key in container.allKeys {
					values[key.stringValue] = try? container.decode(Int.self, forKey: key)
				}
			}
		}

		enum Endpoint: Decodable {
			case baseURL(String)
		}

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		let value = try decoder.decode(AnyKeys.self, from: "base-url: 1\nitem-1: 2\nContent-Type: 3")
		#expect(value.keys == ["baseUrl", "item1", "contentType"])
		#expect(value.values == ["baseUrl": 1])

		#expect {
			try decoder.decode(Endpoint.self, from: "base-url: {_0: 'a'}")
		} throws: { error in
			// The synthesized conformance finds no case among the keys, because `allKeys` gives `baseUrl`.
			guard case DecodingError.typeMismatch(_, let context) = error else {
				return false
			}

			return context.debugDescription == "Invalid number of keys found, expected one. (line 1, column 1)"
		}
	}

	@Test
	func `keys that differ only in Unicode normalization collide in a dictionary, but not in a SOML value`() throws {
		let text = "\"\\u{e9}\": 1\n\"e\\u{301}\": 2\n"
		#expect(try SOML.Value(parsing: text).objectValue?.count == 2)
		#expect(try SOML.Decoder().decode([String: Int].self, from: text) == ["\u{E9}": 2])
	}

	@Test
	func `custom containers`() throws {
		struct Custom: Decodable, Equatable {
			var first: Int
			var rest: [Int]
			var flag: Bool?
			var nested: String

			enum Keys: String, CodingKey {
				case pair
				case info
			}

			enum InfoKeys: String, CodingKey {
				case name
				case flag
			}

			init(first: Int, rest: [Int], flag: Bool?, nested: String) {
				self.first = first
				self.rest = rest
				self.flag = flag
				self.nested = nested
			}

			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: Keys.self)
				var pair = try container.nestedUnkeyedContainer(forKey: .pair)
				#expect(pair.count == 4)
				first = try pair.decode(Int.self)
				var rest = [Int]()

				while !pair.isAtEnd {
					if try pair.decodeNil() {
						continue
					}

					rest.append(try pair.decode(Int.self))
				}

				self.rest = rest
				#expect(throws: DecodingError.self) {
					try pair.decode(Int.self)
				}

				let info = try container.nestedContainer(keyedBy: InfoKeys.self, forKey: .info)
				nested = try info.decode(String.self, forKey: .name)
				flag = try info.decodeIfPresent(Bool.self, forKey: .flag)
				#expect(!info.contains(.flag))
				#expect(info.contains(.name))
			}
		}

		let value = try SOML.Decoder().decode(Custom.self, from: "pair: [1, 2, null, 3]\ninfo: {name: 'n'}")
		#expect(value == Custom(first: 1, rest: [2, 3], flag: nil, nested: "n"))
	}

	@Test
	func `nested containers in an unkeyed container`() throws {
		struct Rows: Decodable {
			var values: [Int]

			init(from decoder: any Decoder) throws {
				var container = try decoder.unkeyedContainer()
				var row = try container.nestedUnkeyedContainer()
				let object = try container.nestedContainer(keyedBy: SOMLCodingKey.self)
				values = [try row.decode(Int.self), try object.decode(Int.self, forKey: SOMLCodingKey(stringValue: "a"))]
				#expect(container.isAtEnd)
			}
		}

		#expect(try SOML.Decoder().decode(Rows.self, from: "[[1], {a: 2}]").values == [1, 2])
	}

	@Test
	func `an unkeyed container stays at an item that fails to decode, as with JSONDecoder`() throws {
		/**
		A type that tries the wrong types and containers on each item before it decodes the item, and records the index it decodes the item at.
		*/
		struct Retries: Decodable, Equatable {
			var values = [String]()
			var indices = [Int]()

			init(from decoder: any Decoder) throws {
				var container = try decoder.unkeyedContainer()

				while !container.isAtEnd {
					_ = try? container.decode(Bool.self)
					_ = try? container.decode([Int].self)
					_ = try? container.nestedContainer(keyedBy: SOMLCodingKey.self)
					_ = try? container.nestedUnkeyedContainer()

					if try container.decodeNil() {
						values.append("null")
						continue
					}

					indices.append(container.currentIndex)
					values.append(try container.decode(String.self))
				}

				#expect(try container.decodeIfPresent(String.self) == nil)
			}
		}

		let json = try JSONDecoder().decode(Retries.self, from: Data(#"["a", null, "b"]"#.utf8))
		let soml = try SOML.Decoder().decode(Retries.self, from: "['a', null, 'b']")
		#expect(soml == json)
		#expect(soml.values == ["a", "null", "b"])
		#expect(soml.indices == [0, 2])
	}

	class Animal: Codable {
		var name: String

		init(name: String) {
			self.name = name
		}
	}

	final class Dog: Animal {
		var breed: String

		enum CodingKeys: String, CodingKey {
			case breed
		}

		init(name: String, breed: String) {
			self.breed = breed
			super.init(name: name)
		}

		required init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			breed = try container.decode(String.self, forKey: .breed)
			try super.init(from: container.superDecoder())
		}

		override func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(breed, forKey: .breed)
			try super.encode(to: container.superEncoder())
		}
	}

	@Test
	func `class inheritance with a super decoder and encoder`() throws {
		let text = try SOML.Encoder().encodeToString(Dog(name: "Rex", breed: "corgi"))
		#expect(text == "breed: 'corgi'\nsuper: {\n\tname: 'Rex'\n}\n")
		let dog = try SOML.Decoder().decode(Dog.self, from: text)
		#expect(dog.name == "Rex")
		#expect(dog.breed == "corgi")
	}

	class Labeled: Encodable {
		enum CodingKeys: CodingKey {
			case labels
			case meta
			case name
		}

		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			var meta = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .meta)
			try meta.encode("base", forKey: .name)
			var labels = container.nestedUnkeyedContainer(forKey: .labels)
			try labels.encode("a")
		}
	}

	final class MoreLabeled: Labeled {
		enum MoreCodingKeys: CodingKey {
			case labels
			case meta
			case version
		}

		override func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: MoreCodingKeys.self)
			var meta = container.nestedContainer(keyedBy: MoreCodingKeys.self, forKey: .meta)
			try meta.encode(2, forKey: .version)
			var labels = container.nestedUnkeyedContainer(forKey: .labels)
			try labels.encode("b")
			try super.encode(to: encoder)
		}
	}

	@Test
	func `a type and its superclass share a nested container for the same key, as with JSONEncoder`() throws {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		#expect(String(decoding: try encoder.encode(MoreLabeled()), as: UTF8.self) == #"{"labels":["b","a"],"meta":{"name":"base","version":2}}"#)
		#expect(try SOML.Encoder().encodeToString(MoreLabeled()) == "meta: {\n\tversion: 2\n\tname: 'base'\n}\nlabels: [\n\t'b'\n\t'a'\n]\n")
	}

	/**
	A subclass that writes `meta` as a struct with `encode(_:forKey:)`, and `labels` as an array when `encodesLabels`, before its superclass fills both through nested containers.
	*/
	final class EncodedLabeled: Labeled {
		struct Meta: Encodable {
			var version = 2
		}

		var encodesLabels = false

		override func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(Meta(), forKey: .meta)

			if encodesLabels {
				try container.encode(["b"], forKey: .labels)
			}

			try super.encode(to: encoder)
		}
	}

	@Test
	func `a nested container fills a container that was encoded for the same key, as with JSONEncoder`() throws {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		#expect(String(decoding: try encoder.encode(EncodedLabeled()), as: UTF8.self) == #"{"labels":["a"],"meta":{"name":"base","version":2}}"#)
		#expect(try SOML.Encoder().encodeToString(EncodedLabeled()) == "meta: {\n\tversion: 2\n\tname: 'base'\n}\nlabels: [\n\t'a'\n]\n")

		// `JSONEncoder` traps for an array, so keeping its items is the alternative to losing them.
		let withLabels = EncodedLabeled()
		withLabels.encodesLabels = true
		#expect(try SOML.Encoder().encodeToString(withLabels) == "meta: {\n\tversion: 2\n\tname: 'base'\n}\nlabels: [\n\t'b'\n\t'a'\n]\n")
	}

	/**
	Writes a struct or an array of structs with `encode(_:forKey:)`, and then asks for nested containers for the same key.
	*/
	struct NestedAfterEncode: Encodable {
		enum CodingKeys: CodingKey {
			case meta
			case list
			case name
		}

		enum Mode {
			case twice
			case array
			case otherKind
		}

		var mode: Mode

		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)

			switch mode {
			case .twice:
				try container.encode(EncodedLabeled.Meta(), forKey: .meta)
				var first = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .meta)
				try first.encode("one", forKey: .name)
				var second = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .meta)
				try second.encode("two", forKey: .list)
			case .array:
				try container.encode([EncodedLabeled.Meta()], forKey: .list)
				var list = container.nestedUnkeyedContainer(forKey: .list)
				var item = list.nestedContainer(keyedBy: CodingKeys.self)
				try item.encode("n", forKey: .name)
			case .otherKind:
				try container.encode(EncodedLabeled.Meta(), forKey: .meta)
				var list = container.nestedUnkeyedContainer(forKey: .meta)
				try list.encode(1)
			}
		}
	}

	@Test
	func `nested containers for a key that has a struct or an array keep filling it, and one of the other kind is an error`() throws {
		#expect(try SOML.Encoder().encodeToString(NestedAfterEncode(mode: .twice)) == "meta: {\n\tversion: 2\n\tname: 'one'\n\tlist: 'two'\n}\n")
		#expect(try SOML.Encoder().encodeToString(NestedAfterEncode(mode: .array)) == "list: [\n\t{\n\t\tversion: 2\n\t}\n\t{\n\t\tname: 'n'\n\t}\n]\n")

		// `JSONEncoder` traps here, and losing the struct silently would be worse.
		do {
			_ = try SOML.Encoder().encodeToString(NestedAfterEncode(mode: .otherKind))
			Issue.record("Expected an error")
		} catch EncodingError.invalidValue(_, let context) {
			#expect(context.codingPath.map(\.stringValue) == ["meta"])
			#expect(context.debugDescription == "The type wrote an object and then an array with the same encoder, which would lose what it wrote first")
		}
	}

	@Test
	func `user info reaches the decoder`() throws {
		struct ReadsUserInfo: Decodable {
			var multiplier: Int

			init(from decoder: any Decoder) throws {
				let factor = decoder.userInfo[.factor] as? Int ?? 1
				multiplier = try decoder.singleValueContainer().decode(Int.self) * factor
			}
		}

		var decoder = SOML.Decoder()
		decoder.userInfo[.factor] = 10
		#expect(try decoder.decode([ReadsUserInfo].self, from: "[2]").map(\.multiplier) == [20])
	}

	@Test
	func `a large config decodes`() throws {
		struct Item: Decodable {
			var id: Int
			var name: String
			var tags: [String]
		}

		let source = "[" + (0..<2000).map { "{id: \($0), name: 'item \($0)', tags: ['a', 'b']}" }.joined(separator: ",\n") + "]"
		let items = try SOML.Decoder().decode([Item].self, from: source)
		#expect(items.count == 2000)
		#expect(items[1999].name == "item 1999")
	}

	private func decodingError(_ type: any Decodable.Type, from source: String) -> DecodingError? {
		do {
			_ = try SOML.Decoder().decode(type, from: source)
			Issue.record("Expected a decoding error")
			return nil
		} catch let error as DecodingError {
			return error
		} catch {
			Issue.record("Expected a DecodingError, got \(error)")
			return nil
		}
	}
}

@Suite
struct EncoderTests {
	struct Config: Codable, Equatable {
		var name: String
		var replicas: Int
		var timeout: Double
		var labels: [String]
		var owner: String?
		var pool: Pool
		var deployedAt: Date

		struct Pool: Codable, Equatable {
			var min: Int
			var max: Int
		}
	}

	let config = Config(name: "api-gateway", replicas: 3, timeout: 30, labels: ["prod", "eu-west"], owner: nil, pool: .init(min: 2, max: 16), deployedAt: Date(timeIntervalSince1970: 1_789_826_400))

	@Test
	func `encodes a config with the members in the order the properties are declared`() throws {
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		let expected = """
			name: 'api-gateway'
			replicas: 3
			timeout: 30.0
			labels: [
				'prod'
				'eu-west'
			]
			pool: {
				min: 2
				max: 16
			}
			deployed-at: 2026-09-19T14:00:00Z

			"""
		#expect(try encoder.encodeToString(config) == expected)
		#expect(try encoder.encode(config) == Data(expected.utf8))
	}

	@Test
	func `encodes a config in canonical form`() throws {
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		encoder.writesCanonicalForm = true
		let expected = """
			deployed-at: 2026-09-19T14:00:00Z
			labels: [
				'prod'
				'eu-west'
			]
			name: 'api-gateway'
			pool: {
				max: 16
				min: 2
			}
			replicas: 3
			timeout: 30.0

			"""
		#expect(try encoder.encodeToString(config) == expected)
		#expect(try encoder.encode(config) == Data(expected.utf8))
	}

	@Test
	func `round-trips a config`() throws {
		for (keyEncoding, keyDecoding) in [(SOML.Encoder.KeyEncodingStrategy.useDefaultKeys, SOML.Decoder.KeyDecodingStrategy.useDefaultKeys), (.convertToKebabCase, .convertFromKebabCase), (.convertToSnakeCase, .convertFromSnakeCase)] {
			var encoder = SOML.Encoder()
			encoder.keyEncodingStrategy = keyEncoding
			var decoder = SOML.Decoder()
			decoder.keyDecodingStrategy = keyDecoding
			#expect(try decoder.decode(Config.self, from: encoder.encode(config)) == config)
		}
	}

	@Test
	func `encodes every primitive type`() throws {
		let value = DecoderTests.Primitives(bool: true, string: "text", double: 1.5, float: 0.1, int: -1, int8: -128, int16: 32767, int32: -2_147_483_648, int64: .max, uint: 1, uint8: 255, uint16: 65535, uint32: 4_294_967_295, uint64: 9_223_372_036_854_775_807)
		let text = try SOML.Encoder().encodeToString(value)
		#expect(text.contains("float: 0.1\n"))
		#expect(text.contains("uint64: 9223372036854775807\n"))
		#expect(try SOML.Decoder().decode(DecoderTests.Primitives.self, from: text) == value)
	}

	@Test
	func `a Float is written with its own shortest digits`() throws {
		#expect(try SOML.Encoder().encodeToString([Float(0.1), 1.5, 16_777_216, .greatestFiniteMagnitude]) == "[\n\t0.1\n\t1.5\n\t16777216.0\n\t3.4028235e38\n]\n")
		#expect(try SOML.Decoder().decode([Float].self, from: SOML.Encoder().encode([Float(0.1)])) == [0.1])
	}

	@Test
	func `a Float whose shortest digits round to another Float through a Double still round-trips`() throws {
		struct Box: Codable, Equatable {
			var value: Float
			var values: [Float]
			var dictionary: [String: Float]
		}

		// 7.038531e-26, from its bits, because a literal is rounded through `Double`. Its shortest digits, read as a `Double` and then rounded to a `Float`, give the next `Float`, so they are not written.
		for float in [Float(bitPattern: 0x15AE_43FD), Float(bitPattern: 0x95AE_43FD)] {
			let box = Box(value: float, values: [float], dictionary: ["a": float])
			let decoded = try SOML.Decoder().decode(Box.self, from: SOML.Encoder().encode(box))
			#expect(decoded.value.bitPattern == float.bitPattern)
			#expect(decoded.values.map(\.bitPattern) == [float.bitPattern])
			#expect(decoded.dictionary["a"]?.bitPattern == float.bitPattern)
			#expect(try SOML.Encoder().encodeToValue(float) == .float(Double(float)))
		}
	}

	@Test
	func `random Floats round-trip`() throws {
		var generator = SeededGenerator(seed: 3)
		let floats = (0..<20_000).map { _ in Float(bitPattern: UInt32.random(in: 0...UInt32.max, using: &generator)) }.filter { !$0.isNaN }
		let decoded = try SOML.Decoder().decode([Float].self, from: SOML.Encoder().encode(floats))
		#expect(decoded.map(\.bitPattern) == floats.map { $0 == 0 ? 0 : $0.bitPattern })
	}

	@Test
	func `nil is left out by synthesized conformances, and written as null when encoded`() throws {
		struct Explicit: Encodable {
			var value: Int?

			enum CodingKeys: CodingKey {
				case value
			}

			func encode(to encoder: any Encoder) throws {
				var container = encoder.container(keyedBy: CodingKeys.self)
				try container.encode(value, forKey: .value)
			}
		}

		#expect(try SOML.Encoder().encodeToString(DecoderTests.Optionals(present: 1, null: nil, missing: nil)) == "present: 1\n")
		#expect(try SOML.Encoder().encodeToString(Explicit(value: nil)) == "value: null\n")
		#expect(try SOML.Encoder().encodeToString([Int?.none, 1]) == "[\n\tnull\n\t1\n]\n")
	}

	@Test
	func `a document must be an object or an array`() throws {
		for value: any Encodable in [1, "text", true, 1.5, Date(timeIntervalSince1970: 0), SOML.Instant.minimum, URL(string: "https://example.com")!] {
			#expect(throws: EncodingError.self) {
				_ = try SOML.Encoder().encode(value)
			}
		}

		#expect(try SOML.Encoder().encodeToValue(1) == 1)
	}

	@Test
	func `an empty object is written with braces`() throws {
		struct Empty: Codable, Equatable {}
		#expect(try SOML.Encoder().encodeToString(Empty()) == "{}\n")
		#expect(try SOML.Encoder().encodeToString([String: Int]()) == "{}\n")
		#expect(try SOML.Decoder().decode(Empty.self, from: "{}") == Empty())
	}

	@Test
	func `a key with a line break is written escaped and reads back`() throws {
		let value = ["line\nbreak": 1]
		let text = try SOML.Encoder().encodeToString(value)
		#expect(text == "\"line\\nbreak\": 1\n")
		#expect(try SOML.Decoder().decode([String: Int].self, from: text) == value)
	}

	@Test
	func `values SOML cannot hold are errors`() throws {
		let cases: [(any Encodable, String)] = [
			([UInt64.max], "outside the int64 range"),
			([UInt(Int64.max) + 1], "outside the int64 range"),
			([Double.nan], "NaN"),
			([Float.nan], "NaN"),
			(["a": "carriage\rreturn"], "carriage return"),
			(["key\r": 1], "carriage return"),
			([Date(timeIntervalSince1970: -70_000_000_000)], "before 0001-01-01T00:00:00Z"),
			([Date(timeIntervalSince1970: 300_000_000_000)], "after 9999-12-31T23:59:59.999999999Z"),
		]

		for (value, fragment) in cases {
			do {
				_ = try SOML.Encoder().encode(value)
				Issue.record("Expected an error for \(value)")
			} catch EncodingError.invalidValue(_, let context) {
				#expect(context.debugDescription.contains(fragment), "\(context.debugDescription)")
			}
		}
	}

	@Test
	func `a date just outside either end of the range of an instant says which end it is past`() throws {
		let minimum = SOML.Instant.minimum.date
		let maximum = SOML.Instant.maximum.date
		#expect(SOML.Instant(minimum) != nil)
		#expect(SOML.Instant(maximum) != nil)

		// The closest dates outside the range. The latest instant's date is the last one before 10000-01-01T00:00:00Z.
		let beforeMinimum = Date(timeIntervalSinceReferenceDate: minimum.timeIntervalSinceReferenceDate.nextDown)
		let pastMaximum = Date(timeIntervalSinceReferenceDate: maximum.timeIntervalSinceReferenceDate.nextUp)

		for (date, end) in [(beforeMinimum, "before 0001-01-01T00:00:00Z, the earliest"), (pastMaximum, "after 9999-12-31T23:59:59.999999999Z, the latest")] {
			do {
				_ = try SOML.Encoder().encode([date])
				Issue.record("Expected an error for \(date.timeIntervalSinceReferenceDate)")
			} catch EncodingError.invalidValue(_, let context) {
				#expect(context.debugDescription == "The date is \(end) SOML instant")
			}
		}
	}

	@Test(arguments: [
		(Date.distantPast, "The date is before 0001-01-01T00:00:00Z, the earliest SOML instant"),
		(Date(timeIntervalSince1970: -70_000_000_000), "The date is before 0001-01-01T00:00:00Z, the earliest SOML instant"),
		(Date(timeIntervalSince1970: 300_000_000_000), "The date is after 9999-12-31T23:59:59.999999999Z, the latest SOML instant"),
		(Date(timeIntervalSince1970: 1e15), "The date is after 9999-12-31T23:59:59.999999999Z, the latest SOML instant"),
	])
	func `a date outside the range of an instant is an error that says which end it is past`(date: Date, message: String) {
		do {
			_ = try SOML.Encoder().encode(["created": date])
			Issue.record("Expected an error for \(date)")
		} catch EncodingError.invalidValue(_, let context) {
			#expect(context.debugDescription == message)
			#expect(context.codingPath.map(\.stringValue) == ["created"])
		} catch {
			Issue.record("Unexpected \(error)")
		}
	}

	@Test
	func `a value nested deeper than a reader accepts is an error`() throws {
		var value = SOML.Value.array([])

		for _ in 0..<Parser.maximumDepth {
			value = .array([value])
		}

		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode(value)
		}

		// One level less fits, and reads back.
		guard case .array(let items) = value else {
			return
		}

		let fits = try SOML.Encoder().encodeToString(items[0])
		#expect(try SOML.Value(parsing: fits) == items[0])
	}

	@Test
	func `a brace-less top-level object counts toward the nesting limit when writing`() throws {
		var array = SOML.Value.array([])

		for _ in 1..<(Parser.maximumDepth - 1) {
			array = .array([array])
		}

		// The top-level object and the arrays make the limit, which fits.
		let fits: SOML.Value = ["a": array]
		#expect(try SOML.Value(parsing: SOML.Encoder().encodeToString(fits)) == fits)

		let tooDeep: SOML.Value = ["a": .array([array])]
		#expect(throws: EncodingError.self) {
			try SOML.Encoder().encode(tooDeep)
		}
	}

	@Test
	func `the coding path of an encoding error`() throws {
		struct Outer: Encodable {
			var items: [Inner]
		}

		struct Inner: Encodable {
			var count: UInt64
		}

		do {
			_ = try SOML.Encoder().encode(Outer(items: [.init(count: 1), .init(count: .max)]))
			Issue.record("Expected an error")
		} catch EncodingError.invalidValue(_, let context) {
			#expect(context.codingPath.map(\.stringValue) == ["items", "1", "count"])
		}
	}

	@Test
	func `special types`() throws {
		struct Special: Encodable {
			var date = Date(timeIntervalSince1970: 1_789_826_400.25)
			var instant = SOML.Instant("2026-09-19T14:00:00.123456789Z")!
			var url = URL(string: "https://example.com/a?b=c")!
			var data = Data([0, 1, 2, 255])
			var value: SOML.Value = ["nested": [1, "x"]]
			var object: SOML.Object = ["a": 1]
		}

		let expected = """
			date: 2026-09-19T14:00:00.25Z
			instant: 2026-09-19T14:00:00.123456789Z
			url: 'https://example.com/a?b=c'
			data: 'AAEC/w=='
			value: {
				nested: [
					1
					'x'
				]
			}
			object: {
				a: 1
			}

			"""
		#expect(try SOML.Encoder().encodeToString(Special()) == expected)
	}

	@Test
	func `enums`() throws {
		let shapes: [DecoderTests.Shape] = [.circle(radius: 1.5), .rectangle(width: 1, height: 2.5), .point]
		let text = try SOML.Encoder().encodeToString(shapes)
		#expect(try SOML.Decoder().decode([DecoderTests.Shape].self, from: text) == shapes)
		#expect(try SOML.Encoder().encodeToString([DecoderTests.Level.info]) == "[\n\t'info'\n]\n")
		#expect(try SOML.Encoder().encodeToString([DecoderTests.Priority.high]) == "[\n\t2\n]\n")
	}

	@Test
	func `key strategies`() throws {
		struct Keys: Encodable {
			var deployedAt = 1
			var baseURL = 2
			var myURLProperty = 3
			var isHTTP2Enabled = 4
			var plain = 5
			var a = 6
			var _private = 7
		}

		var kebab = SOML.Encoder()
		kebab.keyEncodingStrategy = .convertToKebabCase
		#expect(try kebab.encodeToString(Keys()) == "deployed-at: 1\nbase-url: 2\nmy-url-property: 3\nis-http2-enabled: 4\nplain: 5\na: 6\n_private: 7\n")

		var snake = SOML.Encoder()
		snake.keyEncodingStrategy = .convertToSnakeCase
		#expect(try snake.encodeToString(Keys()) == "deployed_at: 1\nbase_url: 2\nmy_url_property: 3\nis_http2_enabled: 4\nplain: 5\na: 6\n_private: 7\n")
	}

	@Test
	func `ASCII keys convert as the general Unicode path converts them`() {
		// A trailing “•” is neither a letter nor ASCII, so it moves a key to the `Character` path without changing how the rest converts.
		let alphabet = Array("aAbBzZ09_-".unicodeScalars)
		var generator = SeededGenerator(seed: 13)

		for _ in 0..<20_000 {
			let length = Int.random(in: 0...8, using: &generator)
			let key = String(String.UnicodeScalarView((0..<length).map { _ in alphabet.randomElement(using: &generator)! }))

			for separator in ["-", "_"] as [Character] {
				#expect(key.convertedFromCamelCase(separator: separator) + "•" == (key + "•").convertedFromCamelCase(separator: separator), "\(key)")
			}
		}

		#expect("éA".convertedFromCamelCase(separator: "-") == "é-a")
		#expect("ÅngströmUnit".convertedFromCamelCase(separator: "-") == "ångström-unit")
	}

	@Test
	func `a key with a long run of combining marks converts in linear time`() throws {
		struct Keys: Encodable {
			struct Key: CodingKey {
				var stringValue: String
				var intValue: Int? { nil }

				init(stringValue: String) {
					self.stringValue = stringValue
				}

				init?(intValue: Int) {
					nil
				}
			}

			var key: String

			func encode(to encoder: any Encoder) throws {
				var container = encoder.container(keyedBy: Key.self)
				try container.encode(1, forKey: Key(stringValue: key))
			}
		}

		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase

		// One character that holds every mark, out of canonical order, so that comparing it with `==` normalizes it, and an uppercase letter after it, so that the case of the character before is asked for.
		func word(size: Int) -> String {
			"x" + String(repeating: "\u{315}", count: size) + String(repeating: "\u{300}", count: size)
		}

		let small = Keys(key: word(size: 1000) + "A")
		let large = Keys(key: word(size: 16_000) + "A")
		#expect(try encoder.encodeToValue(large).objectValue?.keys == [word(size: 16_000) + "-a"])

		try expectLinearTime {
			_ = try encoder.encodeToValue(small)
		} large: {
			_ = try encoder.encodeToValue(large)
		}
	}

	@Test
	func `a key that is not ASCII splits before an uppercase letter, also one with combining marks, and round trips`() throws {
		// A letter with no uppercase form, like `ĸ` or `º`, is not uppercase, as the Unicode Uppercase property says.
		let cases = [("größeWert", "größe-wert"), ("naïveÉtat", "naïve-état"), ("fooE\u{301}t", "foo-e\u{301}t"), ("τιμήΑξία", "τιμή-αξία"), ("имяФайла", "имя-файла"), ("ÜBERGröße", "über-größe"), ("aĸb", "aĸb"), ("ĸA", "ĸ-a"), ("nºPedido", "nº-pedido"), ("անունՖայլ", "անուն-ֆայլ"), ("სახელიᲤაილი", "სახელი-ფაილი"), ("\u{10428}\u{10429}\u{10400}\u{10428}", "\u{10428}\u{10429}-\u{10428}\u{10428}")]

		for (key, expected) in cases {
			#expect(key.convertedFromCamelCase(separator: "-") == expected, "\(key)")
			#expect(expected.convertedToCamelCase(separator: "-").convertedFromCamelCase(separator: "-") == expected, "\(expected)")
		}
	}

	@Test
	func `a key that starts with capitals keeps them in its first word, unlike JSONEncoder`() throws {
		// `JSONEncoder` splits off the first character, as in `u_rl` and `h_ttp_server`.
		let cases = [("URL", "url"), ("ID", "id"), ("URLString", "url-string"), ("HTTPServer", "http-server"), ("A", "a"), ("AB", "ab"), ("Foo", "foo"), ("myURL", "my-url"), ("ABc", "a-bc")]

		for (key, expected) in cases {
			#expect(key.convertedFromCamelCase(separator: "-") == expected, "\(key)")
		}

		// The decoder converts the coding key the same way, so such a key reads back.
		struct Keys: Codable, Equatable {
			var URL: Int
			var HTTPServer: Int
		}

		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		let text = try encoder.encodeToString(Keys(URL: 1, HTTPServer: 2))
		#expect(text == "url: 1\nhttp-server: 2\n")
		#expect(try decoder.decode(Keys.self, from: text) == Keys(URL: 1, HTTPServer: 2))
	}

	@Test
	func `a key strategy does not change dictionary keys`() throws {
		struct Wrapper: Encodable {
			var someMap: [String: Int]
		}

		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		#expect(try encoder.encodeToString(Wrapper(someMap: ["camelKey": 1])) == "some-map: {\n\tcamelKey: 1\n}\n")
	}

	@Test
	func `int keys in a dictionary`() throws {
		var encoder = SOML.Encoder()
		encoder.writesCanonicalForm = true
		#expect(try encoder.encodeToString([404: "not found", 200: "ok"]) == "200: 'ok'\n404: 'not found'\n")
	}

	@Test
	func `encoding the same key twice keeps the last value`() throws {
		struct Twice: Encodable {
			enum CodingKeys: CodingKey {
				case a
			}

			func encode(to encoder: any Encoder) throws {
				var container = encoder.container(keyedBy: CodingKeys.self)
				try container.encode(1, forKey: .a)
				try container.encode(2, forKey: .a)
			}
		}

		#expect(try SOML.Encoder().encodeToString(Twice()) == "a: 2\n")
	}

	@Test
	func `custom containers`() throws {
		struct Custom: Encodable {
			enum Keys: CodingKey {
				case pair
				case info
				case later
			}

			func encode(to encoder: any Encoder) throws {
				var container = encoder.container(keyedBy: Keys.self)
				var pair = container.nestedUnkeyedContainer(forKey: .pair)
				try pair.encode(1)
				try pair.encodeNil()
				var inner = pair.nestedContainer(keyedBy: Keys.self)
				try inner.encode(true, forKey: .info)
				var innerArray = pair.nestedUnkeyedContainer()
				try innerArray.encode("x")
				#expect(pair.count == 4)
				var info = container.nestedContainer(keyedBy: Keys.self, forKey: .info)
				try info.encode("n", forKey: .pair)
				// A container that is filled after it is created still ends up in the output.
				let later = container.superEncoder(forKey: .later)
				var single = later.singleValueContainer()
				try single.encode(3)
			}
		}

		let expected = """
			pair: [
				1
				null
				{
					info: true
				}
				[
					'x'
				]
			]
			info: {
				pair: 'n'
			}
			later: 3

			"""
		#expect(try SOML.Encoder().encodeToString(Custom()) == expected)
	}

	@Test
	func `an encoder that encodes nothing gives an empty object`() throws {
		struct Nothing: Encodable {
			func encode(to encoder: any Encoder) throws {}
		}

		#expect(try SOML.Encoder().encodeToString([Nothing()]) == "[\n\t{}\n]\n")
	}

	@Test
	func `nil in every kind of container, as with JSONEncoder`() throws {
		struct Nils: Encodable {
			enum Keys: CodingKey {
				case null
				case absent
				case optional
				case nested
				case list
			}

			func encode(to encoder: any Encoder) throws {
				var container = encoder.container(keyedBy: Keys.self)
				try container.encodeNil(forKey: .null)
				try container.encodeIfPresent(Int?.none, forKey: .absent)
				try container.encode(Int?.none, forKey: .optional)
				var nested = container.nestedContainer(keyedBy: Keys.self, forKey: .nested)
				try nested.encodeNil(forKey: .null)
				var list = container.nestedUnkeyedContainer(forKey: .list)
				try list.encodeNil()
				try list.encode(Int?.none)
				var single = list.superEncoder().singleValueContainer()
				try single.encodeNil()
			}
		}

		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		#expect(String(decoding: try encoder.encode(Nils()), as: UTF8.self) == #"{"list":[null,null,null],"nested":{"null":null},"null":null,"optional":null}"#)
		#expect(try SOML.Encoder().encodeToString(Nils()) == "null: null\noptional: null\nnested: {\n\tnull: null\n}\nlist: [\n\tnull\n\tnull\n\tnull\n]\n")
	}

	/**
	A type that writes its own members and then the members of `extra` into the same encoder, or `extra` first when `isExtraFirst`.
	*/
	struct Flattened: Encodable {
		var name = "api"
		var extra: SOML.Object = ["port": 80]
		var isExtraFirst = false

		enum CodingKeys: CodingKey {
			case name
			case serviceName
		}

		func encode(to encoder: any Encoder) throws {
			if isExtraFirst {
				try extra.encode(to: encoder)
			}

			var container = encoder.container(keyedBy: CodingKeys.self)
			try container.encode(name, forKey: .name)
			try container.encode(name, forKey: .serviceName)

			if !isExtraFirst {
				try extra.encode(to: encoder)
			}
		}
	}

	@Test
	func `a SOML object flattened into an encoder keeps the members already there, as with JSONEncoder`() throws {
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		#expect(String(decoding: try encoder.encode(Flattened()), as: UTF8.self) == #"{"name":"api","port":80,"serviceName":"api"}"#)
		#expect(try SOML.Encoder().encodeToString(Flattened()) == "name: 'api'\nserviceName: 'api'\nport: 80\n")
	}

	@Test
	func `a SOML object flattened into an encoder before its keyed container keeps its members`() throws {
		#expect(try SOML.Encoder().encodeToString(Flattened(isExtraFirst: true)) == "port: 80\nname: 'api'\nserviceName: 'api'\n")
	}

	@Test
	func `a SOML object flattened into an encoder keeps its keys as they are with a key strategy`() throws {
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		let flattened = Flattened(extra: ["maxConnections": 10, "port": 80])
		#expect(try encoder.encodeToString(flattened) == "name: 'api'\nservice-name: 'api'\nmaxConnections: 10\nport: 80\n")
		#expect(try encoder.encodeToString(Flattened(extra: flattened.extra, isExtraFirst: true)) == "maxConnections: 10\nport: 80\nname: 'api'\nservice-name: 'api'\n")
	}

	@Test
	func `a member of a flattened SOML object replaces a member with the same key written before it`() throws {
		#expect(try SOML.Encoder().encodeToString(Flattened(extra: ["name": "other"])) == "name: 'other'\nserviceName: 'api'\n")
		#expect(try SOML.Encoder().encodeToString(Flattened(extra: ["name": "other"], isExtraFirst: true)) == "name: 'api'\nserviceName: 'api'\n")
	}

	@Test
	func `a SOML value that is not an object, encoded into an encoder, is the value`() throws {
		struct Wrapper: Encodable {
			var value: SOML.Value

			func encode(to encoder: any Encoder) throws {
				try value.encode(to: encoder)
			}
		}

		#expect(try SOML.Encoder().encodeToString(Wrapper(value: [1, 2])) == "[\n\t1\n\t2\n]\n")
		#expect(try SOML.Encoder().encodeToString(Wrapper(value: ["a": ["b": 1]])) == "a: {\n\tb: 1\n}\n")
		#expect(try SOML.Encoder().encodeToValue(Wrapper(value: "x")) == "x")
		#expect(try SOML.Encoder().encodeToString([Wrapper(value: [:])]) == "[\n\t{}\n]\n")
	}

	@Test
	func `user info reaches the encoder`() throws {
		struct WritesUserInfo: Encodable {
			func encode(to encoder: any Encoder) throws {
				var container = encoder.singleValueContainer()
				try container.encode(encoder.userInfo[.factor] as? Int ?? 0)
			}
		}

		var encoder = SOML.Encoder()
		encoder.userInfo[.factor] = 7
		#expect(try encoder.encodeToString([WritesUserInfo()]) == "[\n\t7\n]\n")
	}

	@Test
	func `canonical output is sorted and the same for any dictionary order`() throws {
		var encoder = SOML.Encoder()
		encoder.writesCanonicalForm = true
		let dictionary = Dictionary(uniqueKeysWithValues: (0..<200).map { ("key\($0)", $0) })
		// The keys are ASCII, where `String` order is the same as the scalar order canonical form uses.
		let expected = dictionary.keys.sorted().map { "\($0): \(dictionary[$0]!)\n" }.joined()
		#expect(try encoder.encodeToString(dictionary) == expected)

		for seed in 0..<10 {
			var generator = SeededGenerator(seed: UInt64(seed))
			let shuffled = Dictionary(uniqueKeysWithValues: dictionary.shuffled(using: &generator))
			#expect(try encoder.encodeToString(shuffled) == expected)
		}
	}

	struct AlreadySorted: Encodable {
		struct Item: Encodable {
			var key = "x"
		}

		var array: [Int] = []
		var block = "line 1\nit's"
		var date = Date(timeIntervalSince1970: 0.5)
		var items = [Item()]
		var object = [String: Int]()
		var ratio = 1.0
		var timeout = Duration.seconds(90)
	}

	@Test
	func `the output is exactly canonical form when the members are already in order`() throws {
		var canonicalEncoder = SOML.Encoder()
		canonicalEncoder.writesCanonicalForm = true

		let text = try SOML.Encoder().encodeToString(AlreadySorted())
		#expect(text == "array: []\nblock: \"line 1\\nit's\"\ndate: 1970-01-01T00:00:00.5Z\nitems: [\n\t{\n\t\tkey: 'x'\n\t}\n]\nobject: {}\nratio: 1.0\ntimeout: 1m30s\n")
		#expect(try canonicalEncoder.encodeToString(AlreadySorted()) == text)
		#expect(try SOML.Encoder().encodeToString([AlreadySorted.Item(), AlreadySorted.Item()]) == canonicalEncoder.encodeToString([AlreadySorted.Item(), AlreadySorted.Item()]))
	}

	@Test
	func `a dictionary writes its members in its iteration order, also under a key strategy`() throws {
		let dictionary = Dictionary(uniqueKeysWithValues: (0..<50).map { ("someKey\($0)", $0) })
		var kebabEncoder = SOML.Encoder()
		kebabEncoder.keyEncodingStrategy = .convertToKebabCase

		for encoder in [SOML.Encoder(), kebabEncoder] {
			#expect(try SOML.Value(parsing: encoder.encodeToString(dictionary)).objectValue?.keys == Array(dictionary.keys))
			#expect(try SOML.Value(parsing: encoder.encodeToString(["map": dictionary]))["map"]?.objectValue?.keys == Array(dictionary.keys))
		}
	}

	@Test
	func `a SOML object writes its members in the order they were added`() throws {
		var object = SOML.Object()
		object["z"] = 1
		object["a"] = 2
		object["m"] = 3
		#expect(try SOML.Encoder().encodeToString(object) == "z: 1\na: 2\nm: 3\n")
		#expect(try SOML.Encoder().encodeToString(SOML.Value.object(object)) == "z: 1\na: 2\nm: 3\n")
	}

	@Test
	func `two coding keys that a key strategy converts to the same key write one member, and the last one wins`() throws {
		struct Colliding: Encodable {
			var userID = 1
			var userId = 2
		}

		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		#expect(try encoder.encodeToString(Colliding()) == "user-id: 2\n")
		encoder.keyEncodingStrategy = .convertToSnakeCase
		#expect(try encoder.encodeToString(Colliding()) == "user_id: 2\n")
	}

	/**
	Writes a SOML value, a SOML object, and a dictionary for a key, each followed by a nested container for the same key.
	*/
	struct NestedForWrittenKey: Encodable {
		enum CodingKeys: String, CodingKey {
			case value
			case object
			case dictionary
		}

		enum InnerKeys: String, CodingKey {
			case added
		}

		func encode(to encoder: any Encoder) throws {
			var container = encoder.container(keyedBy: CodingKeys.self)
			let kept: SOML.Value = ["kept": 1]
			try container.encode(kept, forKey: .value)
			var value = container.nestedContainer(keyedBy: InnerKeys.self, forKey: .value)
			try value.encode(1, forKey: .added)
			let keptObject: SOML.Object = ["kept": 1]
			try container.encode(keptObject, forKey: .object)
			var object = container.nestedContainer(keyedBy: InnerKeys.self, forKey: .object)
			try object.encode(1, forKey: .added)
			try container.encode(["kept": 1], forKey: .dictionary)
			var dictionary = container.nestedContainer(keyedBy: InnerKeys.self, forKey: .dictionary)
			try dictionary.encode(1, forKey: .added)
		}
	}

	@Test
	func `a nested container extends encoded values objects and dictionaries consistently`() throws {
		#expect(try SOML.Encoder().encodeToString(NestedForWrittenKey()) == "value: {\n\tkept: 1\n\tadded: 1\n}\nobject: {\n\tkept: 1\n\tadded: 1\n}\ndictionary: {\n\tkept: 1\n\tadded: 1\n}\n")

		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		#expect(try encoder.encodeToString(NestedForWrittenKey()) == "value: {\n\tkept: 1\n\tadded: 1\n}\nobject: {\n\tkept: 1\n\tadded: 1\n}\ndictionary: {\n\tkept: 1\n\tadded: 1\n}\n")
	}
}

@Suite
struct InteroperabilityTests {
	@Test
	func `a SOML value round-trips through JSON where JSON can hold it`() throws {
		let value: SOML.Value = ["string": "x", "int": 1, "bool": true, "null": nil, "array": [1, "two"], "object": ["nested": false]]
		let json = try JSONEncoder().encode(value)
		#expect(try JSONDecoder().decode(SOML.Value.self, from: json) == value)
	}

	@Test
	func `JSON output of a SOML value`() throws {
		let value: SOML.Value = ["b": 1.5, "a": .instant(SOML.Instant("2026-09-19T14:00:00Z")!)]
		let encoder = JSONEncoder()
		encoder.outputFormatting = .sortedKeys
		#expect(String(decoding: try encoder.encode(value), as: UTF8.self) == #"{"a":"2026-09-19T14:00:00Z","b":1.5}"#)
	}

	@Test
	func `a SOML object round-trips through JSON`() throws {
		let object: SOML.Object = ["a": [1, 2], "b": ["c": "d"]]
		#expect(try JSONDecoder().decode(SOML.Object.self, from: JSONEncoder().encode(object)) == object)
		#expect(throws: DecodingError.self) {
			try JSONDecoder().decode(SOML.Object.self, from: Data("[1]".utf8))
		}
	}

	@Test
	func `a property list round trip`() throws {
		let value: SOML.Value = ["a": [1, "two"], "b": ["c": true]]
		let data = try PropertyListEncoder().encode(value)
		#expect(try PropertyListDecoder().decode(SOML.Value.self, from: data) == value)
	}

	@Test
	func `a type decodes the same from SOML and from JSON`() throws {
		struct Model: Codable, Equatable {
			var name: String
			var count: Int
			var ratio: Double
			var tags: [String]
			var nested: [String: Bool]
		}

		let fromJSON = try JSONDecoder().decode(Model.self, from: Data(#"{"name": "x", "count": 2, "ratio": 0.5, "tags": ["a"], "nested": {"k": true}}"#.utf8))
		let fromSOML = try SOML.Decoder().decode(Model.self, from: "name: 'x'\ncount: 2\nratio: 0.5\ntags: ['a']\nnested: {k: true}")
		#expect(fromJSON == fromSOML)
	}
}

extension CodingUserInfoKey {
	static let factor = CodingUserInfoKey(rawValue: "factor")!
}

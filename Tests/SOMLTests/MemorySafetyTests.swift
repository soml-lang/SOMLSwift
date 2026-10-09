import Foundation
import Testing
@testable import SOML

@Suite
struct MemorySafetyTests {
	@Test
	func `word scans preserve encoding errors at every chunk boundary`() {
		for padding in 0..<17 {
			for byte in UInt8.min...UInt8.max {
				let bytes = Array(repeating: UInt8.space, count: padding) + [byte] + Array(repeating: .space, count: 17)
				let scan = Parser.scanEncoding(bytes)
				let expectedInvalid = String(validating: bytes, as: UTF8.self) == nil ? padding : nil
				#expect(scan.invalidUTF8Index == expectedInvalid)
				let expectedControl = byte < 0x20 && byte != .tab && byte != .lineFeed || byte == 0x7F
				#expect(scan.controlIndex == (expectedControl ? padding : nil))
			}
		}
	}

	#if canImport(ObjectiveC)
	@Test(arguments: [1, 1000])
	func `borrowed UTF8 buffers preserve bridged text nil results and thrown errors`(repetitions: Int) throws {
		enum Failure: Error {
			case requested
		}

		let original = "abcdefgé😀\u{0}" + String(repeating: "字😀e\u{301}", count: repetitions)
		let units = Array(original.utf16)
		let bridged = NSString(characters: units, length: units.count) as String
		try #require(bridged.utf8.withContiguousStorageIfAvailable { _ in true } == nil)
		let expected = Array(original.utf8)

		for _ in 0..<3 {
			var calls = 0
			let result: Int? = bridged.withUTF8Buffer { bytes in
				calls += 1
				#expect(Array(bytes) == expected)
				return nil
			}
			#expect(result == nil)
			#expect(calls == 1)
		}

		#expect(throws: Failure.requested) {
			try bridged.withUTF8Buffer { bytes in
				#expect(Array(bytes) == expected)
				throw Failure.requested
			}
		}
		#expect(bridged.withUTF8Buffer { Array($0) } == expected)
		#expect(Array(bridged.utf16) == units)
	}
	#endif

	@Test
	func `canonical floats round trip at all binary exponents`() throws {
		for exponent in UInt64(0)...2046 {
			for fraction in [UInt64(1), 0xF_FFFF_FFFF_FFFF] {
				let number = Double(bitPattern: exponent << 52 | fraction)
				for value in [number, -number] {
					let text = SOML.Value.float(value).description
					#expect(Double(text) == value)
					#expect(try SOML.Value(parsingValue: text) == .float(value))
				}
			}
		}
	}

	@Test
	func `canonical floats round trip across decimal notation boundaries`() {
		for exponent in -323...308 {
			guard let number = Double("1.2345678901234567e\(exponent)") else {
				Issue.record("A decimal exponent in range must parse")
				continue
			}

			for value in [number.nextDown, number, number.nextUp] {
				#expect(Double(SOML.Value.float(value).description) == value)
				#expect(Double(SOML.Value.float(-value).description) == -value)
			}
		}
	}

	@Test(arguments: ["\rplain", "plain\rmiddle", "quote'\r", "control\t\r", "é😀\r"])
	func `string validation retains the full error path`(_ string: String) throws {
		let value: SOML.Value = ["outer": .array([.object(["leaf": .string(string)])])]
		let error = try #require(throws: SOML.InvalidValueError.self) {
			try value.canonicalDocument()
		}
		#expect(error.codingPath.map(\.stringValue) == ["outer", "0", "leaf"])
		#expect(error.message.contains("A string cannot contain a carriage return"))
		#expect(!value.description.utf8.contains(.carriageReturn))
	}

	@Test(arguments: ["bare\rkey", "quoted key\r", "é😀\rkey", "'\rkey"])
	func `key validation preserves exact key diagnostics`(_ key: String) throws {
		let value: SOML.Value = ["outer": .object(SOML.Object([(key, .int(1))]))]
		let error = try #require(throws: SOML.InvalidValueError.self) {
			try value.canonicalDocument()
		}
		#expect(error.codingPath.map(\.stringValue).map { Array($0.utf8) } == ["outer", key].map { Array($0.utf8) })
		#expect(error.message.contains("A key cannot contain a carriage return"))
		#expect(!value.description.utf8.contains(.carriageReturn))
	}

	struct Context: Sendable, Equatable {
		let value: Int
	}

	struct ContextualValue: Codable, Equatable {
		static let contextKey = CodingUserInfoKey(rawValue: "context")!
		let value: Int

		init(value: Int) {
			self.value = value
		}

		init(from decoder: any Decoder) throws {
			let context = try #require(decoder.userInfo[Self.contextKey] as? Context)
			var local = decoder.userInfo
			local[Self.contextKey] = "replaced"
			#expect(decoder.userInfo[Self.contextKey] as? Context == context)
			value = try decoder.singleValueContainer().decode(Int.self) + context.value
		}

		func encode(to encoder: any Encoder) throws {
			let context = try #require(encoder.userInfo[Self.contextKey] as? Context)
			var local = encoder.userInfo
			local[Self.contextKey] = "replaced"
			#expect(encoder.userInfo[Self.contextKey] as? Context == context)
			var container = encoder.singleValueContainer()
			try container.encode(value - context.value)
		}
	}

	@Test
	func `typed coder context survives protocol erasure and local dictionary mutations`() throws {
		let values = (0..<10).map { ContextualValue(value: $0) }
		var encoder = SOML.Encoder()
		encoder.userInfo[ContextualValue.contextKey] = Context(value: 10)
		var decoder = SOML.Decoder()
		decoder.userInfo[ContextualValue.contextKey] = Context(value: 10)
		#expect(try decoder.decode([ContextualValue].self, from: encoder.encodeToString(values)) == values)
	}
}

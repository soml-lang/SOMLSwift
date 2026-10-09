import Foundation
import Testing
@testable import SOML

@Suite
/**
Foundation types with their own `Codable` implementations, which write keyed containers, arrays, or strings of their own, round-trip under every key strategy with unknown keys rejected, so the strategies convert their keys the same way in both directions.
*/
struct FoundationTypeTests {
	func roundTrip<T: Codable & Equatable>(_ value: T, _ label: String) {
		for (encodingStrategy, decodingStrategy) in [(SOML.Encoder.KeyEncodingStrategy.convertToKebabCase, SOML.Decoder.KeyDecodingStrategy.convertFromKebabCase), (.convertToSnakeCase, .convertFromSnakeCase)] {
			var encoder = SOML.Encoder()
			encoder.keyEncodingStrategy = encodingStrategy
			var decoder = SOML.Decoder()
			decoder.keyDecodingStrategy = decodingStrategy
			decoder.rejectsUnknownKeys = true

			do {
				let text = try encoder.encodeToString(["v": value])
				let back = try decoder.decode([String: T].self, from: text)
				#expect(back["v"] == value, "\(label) under \(encodingStrategy): \(text)")
			} catch {
				Issue.record("\(label) under \(encodingStrategy) threw \(error)")
			}
		}
	}

	@Test
	func `Foundation types round-trip under every key strategy`() {
		roundTrip(Decimal(string: "3.14159")!, "Decimal")
		roundTrip(Decimal(string: "-12345678901234567890.5")!, "Decimal big")
		roundTrip(UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!, "UUID")
		roundTrip(TimeZone(identifier: "Europe/Oslo")!, "TimeZone")
		roundTrip(Locale(identifier: "nb_NO"), "Locale")
		roundTrip(DateComponents(year: 2026, month: 9, day: 19), "DateComponents")
		roundTrip(Measurement(value: 3, unit: UnitLength.meters), "Measurement")
		roundTrip(Set(["a", "b"]), "Set")
		roundTrip(1.0...2.0, "ClosedRange")
		roundTrip(IndexSet([1, 2, 5]), "IndexSet")
		roundTrip(URLComponents(string: "https://a.b/c?d=e")!, "URLComponents")
		roundTrip(PersonNameComponents(givenName: "A", familyName: "B"), "PersonNameComponents")
		// Only Apple platforms make `AttributedString` `Codable`.
		#if canImport(Darwin)
		roundTrip(AttributedString("hi"), "AttributedString")
		#endif
		roundTrip([1: "a", 2: "b"], "Int-keyed dictionary")
		roundTrip(Optional<Int>.none, "nil Optional")
		roundTrip([Optional(1), nil, 3], "array with nil")
		roundTrip(Duration.seconds(1.5), "Duration")
		roundTrip(Date(timeIntervalSince1970: 1.25), "Date")
	}

	@Test
	func `Decimal has no special case, so it writes the object of its own implementation`() throws {
		let value = try SOML.Encoder().encodeToValue(try #require(Decimal(string: "1.5")))
		#expect(value["exponent"] == -1)
		#expect(value["mantissa"]?[0] == 15)
	}
}

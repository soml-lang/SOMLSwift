import Foundation
import Testing
@testable import SOML

@Suite
struct CalendarDateTests {
	@Test(arguments: ["0001-01-01", "0099-01-01", "1582-10-10", "2011-12-30", "2000-02-29", "2024-02-29", "2026-11-01", "9999-12-31"])
	func `calendar dates preserve their exact components`(_ text: String) throws {
		let date = try #require(SOML.Date(text))
		let value = try parse("a: \(text)")
		#expect(date.description == text)
		#expect(SOML.Date(year: date.year, month: date.month, day: date.day) == date)
		#expect(value == ["a": .date(date)])
		#expect(value["a"]?.dateValue == date)
		#expect(try SOML.Encoder().encodeToString([date]) == "[\n\t\(text)\n]\n")
		#expect(try SOML.Decoder().decode([SOML.Date].self, from: "[\(text)]") == [date])
	}

	@Test(arguments: ["0000-01-01", "10000-01-01", "1900-02-29", "2100-02-29", "2026-02-30", "2026-00-01", "2026-13-01", "2026-01-00", "2026-04-31", "2026-1-01", "2026-11-1", "+2026-11-01", "２０２６-11-01", "2026-11-01T", "2026-11-01Z", "2026-11-01foo", "2026-11-01T12:00:00", "2026-11-01[u-ca=iso8601]"])
	func `calendar dates reject invalid dates and partial tokens`(_ text: String) {
		#expect(SOML.Date(text) == nil)
		#expect(parseError("[\(text)]") != nil)
	}

	@Test
	func `calendar component construction rejects extreme integers without overflow`() {
		for component in [Int.min, -1, 0, 10_000, Int.max] {
			#expect(SOML.Date(year: component, month: 1, day: 1) == nil)
			#expect(SOML.Date(year: 2026, month: component, day: 1) == nil)
			#expect(SOML.Date(year: 2026, month: 1, day: component) == nil)
		}
	}

	@Test
	func `calendar dates remain distinct from strings and instants`() throws {
		let date = try #require(SOML.Date("2026-11-01"))
		#expect(SOML.Value.date(date) != .string(date.description))
		#expect(SOML.Value.date(date) != .instant(try #require(SOML.Instant("2026-11-01T00:00:00Z"))))
		#expect(Set([SOML.Value.date(date), .string(date.description)]).count == 2)
		#expect(date < (try #require(SOML.Date("2026-11-02"))))

		for text in ["['2026-11-01']", "[2026-11-01T00:00:00Z]"] {
			#expect(throws: DecodingError.self) {
				try SOML.Decoder().decode([SOML.Date].self, from: text)
			}
		}

		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode([Foundation.Date].self, from: "[2026-11-01]")
		}
		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode([String].self, from: "[2026-11-01]")
		}
	}

	@Test
	func `calendar dates work in documents editing highlighting and JSON`() throws {
		let date = try #require(SOML.Date("1582-10-10"))
		let document = try SOML.Document(parsing: "birthday: 2000-02-29# birthday\nnext: [2011-12-30,2026-11-01]\n")
		#expect(document.formatted() == "birthday: 2000-02-29 # birthday\nnext: [2011-12-30, 2026-11-01]\n")
		#expect(try document.setting(.date(date), at: ["birthday"]).text.hasPrefix("birthday: 1582-10-10# birthday"))
		#expect(SOML.Token.tokens(in: "a: 2026-11-01").map(\.kind) == [.key, .punctuation, .date])
		#expect(SOML.Token.tokens(in: "a: 2026-11-01foo").last?.kind == .invalid)
		let value: SOML.Value = ["date": .date(date)]
		#expect(try SOML.Value(parsingJSON: value.jsonText(format: .tagged), format: .tagged) == value)
		#expect(try SOML.Value(parsingJSON: value.jsonText()) == ["date": .string("1582-10-10")])
		#expect(try JSONDecoder().decode([SOML.Date].self, from: JSONEncoder().encode([date])) == [date])
	}

	@Test
	func `calendar dates survive typed keyed optional array and dictionary coding`() throws {
		struct Configuration: Codable, Equatable {
			var launchDate: SOML.Date
			var optionalDate: SOML.Date?
			var dates: [SOML.Date]
			var milestones: [String: SOML.Date]
		}

		let date = try #require(SOML.Date("1582-10-10"))
		let configuration = Configuration(launchDate: date, optionalDate: date, dates: [date], milestones: ["first": date])
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		decoder.rejectsUnknownKeys = true
		let text = try encoder.encodeToString(configuration)
		#expect(text.contains("launch-date: 1582-10-10"))
		#expect(try decoder.decode(Configuration.self, from: text) == configuration)

		let document = try SOML.Document(parsing: text + "# retained\n")
		let changedDate = try #require(SOML.Date("2011-12-30"))
		let changed = try document.updating(as: Configuration.self, decoder: decoder, encoder: encoder) {
			$0.launchDate = changedDate
		}
		#expect(changed.value["launch-date"] == .date(changedDate))
		#expect(changed.text.hasSuffix("# retained\n"))
	}

	@Test(arguments: ["", " 2026-11-01", "2026-11-01 ", "2026-11-01\n", "2026-11-01T12:00:00+02:00", "2026-11-01[u-ca=gregory]"])
	func `foreign date decoding rejects invalid syntax instead of discarding context`(_ text: String) throws {
		#expect(SOML.Date(text) == nil)
		let bytes = try JSONEncoder().encode([text])
		#expect(throws: DecodingError.self) {
			try JSONDecoder().decode([SOML.Date].self, from: bytes)
		}
	}

	@Test
	func `calendar dates retain all boundaries and month lengths without timezone arithmetic`() throws {
		for text in ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31", "2026-06-30", "2026-07-31", "2026-08-31", "2026-09-30", "2026-10-31", "2026-11-30", "2026-12-31"] {
			let date = try #require(SOML.Date(text))
			#expect(SOML.Date(year: date.year, month: date.month, day: date.day + 1) == nil)
			#expect(try parse("[\(text)]").arrayValue?.first?.dateValue == date)
		}
	}

	@Test
	func `calendar token boundaries preserve containers comments adjacent lines and EOF`() throws {
		let date = try #require(SOML.Date("2026-11-01"))
		for source in ["a: 2026-11-01", "a: 2026-11-01# comment", "a: 2026-11-01/* comment */", "{a:2026-11-01}", "a:2026-11-01\nb:2026-11-02", "a:\n2026-11-01"] {
			#expect(try parse(source)["a"] == .date(date))
		}
		for source in ["[2026-11-01]", "[2026-11-01,]", "[2026-11-01# comment\n]", "[2026-11-01/* comment */]"] {
			#expect(try parse(source) == [.date(date)])
		}
	}

	@Test
	func `untrusted date-shaped input has bounded diagnostics and never normalizes`() throws {
		let source = "[2026-11-01" + String(repeating: "0", count: 100_000) + "]"
		let error = try #require(parseError(source))
		#expect(error.message.count < 300)
		#expect(error.location.column == 2)
		#expect(SOML.Date(String(repeating: "0", count: 100_000)) == nil)
		let date = try #require(SOML.Date("2026-11-01"))
		#expect(SOML.Date(year: date.year, month: 2, day: 30) == nil)
	}
}

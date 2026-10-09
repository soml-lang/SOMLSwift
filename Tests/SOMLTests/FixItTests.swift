import Foundation
import Testing
@testable import SOML

/**
A parse error has a fix-it when the problem is a spelling with exactly one fix that keeps the meaning.
*/
@Suite
struct FixItTests {
	@Test(arguments: [
		("a: 0xff", "a: 0xFF"),
		("a: 0xFf_00", "a: 0xFF_00"),
		// The spelling is fixed even when the value is out of range, which the next parse reports.
		("a: 0xfffffffffffffffffff", "a: 0xFFFFFFFFFFFFFFFFFFF"),
		("a: 0Xff", "a: 0xff"),
		("a: 0B101", "a: 0b101"),
		("a: 0O17", "a: 0o17"),
		("a: -0Xff", "a: -0xff"),
		("a: 1E10", "a: 1e10"),
		("a: 1_000E3", "a: 1_000e3"),
		("a: -1.5E-3", "a: -1.5e-3"),
		// The digits of the exponent are missing, which the next parse reports.
		("a: 1E", "a: 1e"),
		("a: True", "a: true"),
		("a: FALSE", "a: false"),
		("a: Null", "a: null"),
		("a: Infinity", "a: infinity"),
		("a: INFINITY", "a: infinity"),
		("a: -Infinity", "a: -infinity"),
		("a: [True, 1]", "a: [true, 1]"),
		("a: {b: True}", "a: {b: true}"),
		("a: True # comment", "a: true # comment"),
		("a: 2026-09-19t14:00:00Z", "a: 2026-09-19T14:00:00Z"),
		("a: 2026-09-19t14:00:00+07:00", "a: 2026-09-19T14:00:00+07:00"),
		("a: 2026-09-19T14:00:00z", "a: 2026-09-19T14:00:00Z"),
		("a: 2026-09-19T14:00:00.5z", "a: 2026-09-19T14:00:00.5Z"),
		("a: 1H", "a: 1h"),
		("a: 1h30S", "a: 1h30s"),
		("a: 100MS", "a: 100ms"),
		("a: 1US", "a: 1us"),
		("a: \"caf\\u{E9}\"", "a: \"caf\\u{e9}\""),
		("\"\\u{C0}x\": 1", "\"\\u{c0}x\": 1"),
		("a: \"\\u{00e9}\"", "a: \"\\u{e9}\""),
		("a: \"\\u{00}\"", "a: \"\\u{0}\""),
		("a: \"\"\"\n\t\\u{E9}\n\t\"\"\"", "a: \"\"\"\n\t\\u{e9}\n\t\"\"\""),
		// The digits of an escape without its `}` are fixed too, and the next parse reports the `}`.
		("a: \"\\u{E9\"", "a: \"\\u{e9\""),
		// Multibyte text before the problem, so a byte offset differs from a character offset.
		("a: 'é😀'\nb: 0xff", "a: 'é😀'\nb: 0xFF")
	])
	func `a fix-it gives the one allowed spelling`(_ text: String, _ expected: String) throws {
		let error = try #require(parseError(text))
		let fixIt = try #require(error.fixIt, "No fix-it for: \(error)")
		#expect(fixIt.applied(to: text) == expected)
	}

	@Test(arguments: [
		// Another word for a keyword may be meant as a string.
		"a: yes",
		"a: Off",
		"a: nil",
		"a: None",
		"a: inf",
		"a: -inf",
		"a: NaN",
		// A keyword hint is only for the word on its own.
		"a: True story",
		// `M` is more often a size than minutes.
		"a: 512M",
		"a: 1Hz",
		"a: 0xG1",
		// A prefix that no digits of its radix follow is most likely part of a word.
		"a: 0B",
		"a: 0Bad",
		"a: 0O8",
		"a: 0Xyz",
		// A “t” or “z” that is not where an instant has it is part of a word.
		"a: 2026-09-19that",
		"a: 2026-09-19tz",
		"a: 2026-09-19z",
		"a: 2026-09-19fizz",
		"a: 2026-09-19T14:00:00buzz",
		"a: -Infinity war",
		// More than six digits are wrong in any case.
		"a: \"\\u{ABCDEF1}\"",
		"a: \"\\u{ABCDEF1\"",
		// The value of an escape is checked before its spelling.
		"a: \"\\u{D80F}\"",
		"a: \"\\u{00D}\"",
		"a: \"\\U{e9}\"",
		"a: 2026-09-19T14:00:00",
		"a: [1,"
	])
	func `an error that is not a spelling with one fix has no fix-it`(_ text: String) throws {
		let error = try #require(parseError(text))
		#expect(error.fixIt == nil, "\(error)")
	}

	@Test
	func `a fix-it of a value text is in the bytes of the value text`() throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.Value(parsingValue: "0xff")
		}
		let fixIt = try #require(error.fixIt)
		#expect(fixIt.range == 2..<4)
		#expect(fixIt.applied(to: "0xff") == "0xFF")
	}

	@Test(arguments: [
		("\"\\u{E9}\"", "\"\\u{e9}\""),
		("a[0].\"\\u{E9}\"", "a[0].\"\\u{e9}\"")
	])
	func `a fix-it of a key path is in the bytes of the whole key path`(_ text: String, _ expected: String) throws {
		let error = try #require(throws: SOML.ParseError.self) {
			try SOML.KeyPath(parsing: text)
		}
		let fixIt = try #require(error.fixIt, "No fix-it for: \(error)")
		#expect(fixIt.applied(to: text) == expected)
	}

	/**
	The doc comment example of `range(in:)`, with multibyte text before the problem, so a byte offset differs from a character offset.
	*/
	@Test
	func `the range in the text is the text that the fix-it replaces`() throws {
		let text = "a: 'é😀'\nb: True"
		let error = try #require(parseError(text))
		let fixIt = try #require(error.fixIt)
		#expect(text[fixIt.range(in: text)] == "True")
		#expect(Array(text.utf8)[fixIt.range].elementsEqual("True".utf8))
		#expect(fixIt.replacement == "true")
	}

	@Test
	func `an edit error for a value text has its parse error`() throws {
		let document = try SOML.Document(parsing: "mask: 0\n")

		let editError = try #require(throws: SOML.EditError.self) {
			try document.setting(valueText: "0Xff00", at: SOML.KeyPath(["mask"]))
		}
		let parseError = try #require(editError.underlyingError)
		#expect(parseError.location.offset == 0)
		#expect(parseError.fixIt?.applied(to: "0Xff00") == "0xff00")

		// An edit error that is not about the value text has none.
		let otherEditError = try #require(throws: SOML.EditError.self) {
			try document.setting(.float(.nan), at: SOML.KeyPath(["mask"]))
		}
		#expect(otherEditError.underlyingError == nil)
	}

	@Test
	func `a decoding error keeps the fix-it of its parse error`() throws {
		struct Config: Decodable {
			let a: Int
		}

		do {
			_ = try SOML.Decoder().decode(Config.self, from: "a: 0xff")
			Issue.record("Expected a decoding error")
		} catch DecodingError.dataCorrupted(let context) {
			let error = try #require(context.underlyingError as? SOML.ParseError)
			#expect(error.fixIt?.applied(to: "a: 0xff") == "a: 0xFF")
		}
	}

	@Test
	func `applying fix-its until the text parses fixes every spelling`() throws {
		var text = "a: [0Xff, True, 1E3, 2026-09-19t14:00:00z, 1H30m, \"\\u{00E9}\"]"
		var appliedCount = 0

		while true {
			do {
				_ = try SOML.Document(parsing: text)
				break
			} catch {
				let fixIt = try #require(error.fixIt, "No fix-it for: \(error)")
				text = fixIt.applied(to: text)
				appliedCount += 1
				try #require(appliedCount < 20)
			}
		}

		#expect(text == "a: [0xFF, true, 1e3, 2026-09-19T14:00:00Z, 1h30m, \"\\u{e9}\"]")
	}

	/**
	Each fix-it in the invalid conformance cases is progress: the fixed text parses, or fails with another problem or at another place, so applying fix-its until the text parses comes to a stop.
	*/
	@Test
	func `every fix-it in the invalid conformance cases is progress`() throws {
		var fixItCount = 0

		for name in ConformanceTests.invalidCases {
			let url = ConformanceTests.root.appending(path: "invalid/\(name).soml")
			var text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
			var stepCount = 0

			while
				stepCount < 10,
				case .failure(let error) = Result(catching: { () throws(SOML.ParseError) in try SOML.Document(parsing: text) }),
				let fixIt = error.fixIt
			{
				stepCount += 1
				fixItCount += 1
				#expect(fixIt.range.lowerBound >= 0, "\(name)")
				#expect(fixIt.range.upperBound <= text.utf8.count, "\(name)")

				let fixed = fixIt.applied(to: text)
				#expect(fixed != text, "\(name)")

				do {
					_ = try SOML.Document(parsing: fixed)
				} catch let next {
					#expect(next.message != error.message || next.location != error.location, "\(name): \(next)")
				}

				text = fixed
			}

			#expect(stepCount < 10, "\(name) needs too many fix-its")
		}

		#expect(fixItCount > 5)
	}

	/**
	Flipping the case of one letter in a valid conformance case gives no error, an error that has no fix-it, or fix-its that lead back to the value of the original case, so a fix-it never changes the meaning of a document.
	*/
	@Test
	func `a fix-it for a letter in the wrong case leads back to the value of the original case`() throws {
		var fixItCount = 0

		for name in ConformanceTests.validCases {
			let text = try String(contentsOf: ConformanceTests.root.appending(path: "valid/\(name).soml"), encoding: .utf8)
			let value = try parse(text)
			let bytes = Array(text.utf8)

			for index in bytes.indices where bytes[index].isASCIILetter {
				let flipped = bytes[index].isASCIILowercase ? bytes[index].asciiUppercased : bytes[index].asciiLowercased
				var mutated = bytes
				mutated[index] = flipped
				var fixedText = String(decoding: mutated, as: UTF8.self)
				var hasFixIt = false

				for _ in 0..<10 {
					guard
						case .failure(let error) = Result(catching: { () throws(SOML.ParseError) in try SOML.Document(parsing: fixedText) }),
						let fixIt = error.fixIt
					else {
						break
					}

					hasFixIt = true
					fixedText = fixIt.applied(to: fixedText)
				}

				guard hasFixIt else {
					continue
				}

				fixItCount += 1
				#expect(try parse(fixedText) == value, "\(name) at byte \(index): \(fixedText.debugDescription)")
			}
		}

		// The flips reach the fix-its, so the test checks something.
		#expect(fixItCount > 300, "Only \(fixItCount) fix-its were checked")
	}
}

import Testing
@testable import SOML

@Suite
struct DiagnosticMetadataTests {
	@Test(arguments: [
		("2026-02-30", SOML.ParseError.Kind.invalidDate),
		("2026-09-19T25:00:00Z", .invalidInstant),
		("1m1m", .invalidDuration),
		("0xff", .invalidNumber)
	])
	func `scalar diagnostics retain exact UTF8 token ranges after Unicode`(token: String, kind: SOML.ParseError.Kind) throws {
		let prefix = "'🎉é': 'é'\nvalue: "
		let source = prefix + token + " # Keep\nother: 1\n"
		do {
			_ = try SOML.Value(parsing: source)
			Issue.record("Expected invalid scalar")
		} catch {
			#expect(error.kind == kind)
			#expect(error.sourceRange == prefix.utf8.count..<(prefix.utf8.count + token.utf8.count))
			#expect(error.location.offset == prefix.utf8.count)
			#expect(error.location.line == 2)
			#expect(error.location.column == 8)
		}
	}

	@Test
	func `adding scalar metadata preserves spelling fixes`() throws {
		let source = "value: 0xff\n"
		do {
			_ = try SOML.Value(parsing: source)
			Issue.record("Expected invalid hexadecimal spelling")
		} catch {
			let fix = try #require(error.fixIt)
			#expect(fix.applied(to: source) == "value: 0xFF\n")
			#expect(try SOML.Value(parsing: fix.applied(to: source)) == SOML.Value(parsing: "value: 255\n"))
			#expect(error.kind == .invalidNumber)
			#expect(error.sourceRange == 7..<11)
		}
	}

	@Test
	func `unterminated string metadata stops before the next member`() throws {
		let source = "value: 'unterminated\nother: 1\n"
		do {
			_ = try SOML.Value(parsing: source)
			Issue.record("Expected unterminated string")
		} catch {
			#expect(error.kind == .invalidString)
			let range = try #require(error.sourceRange)
			#expect(String(decoding: Array(source.utf8)[range], as: UTF8.self) == "'unterminated")
			#expect(error.location.offset == 7)
		}
	}

	@Test
	func `missing value at EOF has an empty range without losing its kind`() throws {
		let source = "value: "
		do {
			_ = try SOML.Value(parsing: source)
			Issue.record("Expected missing value")
		} catch {
			#expect(error.kind == .expectedValue)
			#expect(error.sourceRange == source.utf8.count..<source.utf8.count)
		}
	}

	@Test(arguments: ["value 1\n", "value: mystery\n"])
	func `other syntax errors retain generic diagnostics`(source: String) throws {
		do {
			_ = try SOML.Value(parsing: source)
			Issue.record("Expected missing colon")
		} catch {
			#expect(error.kind == .other)
			#expect(error.sourceRange == nil)
		}
	}

	@Test
	func `malformed string prefixes end at a UTF8 scalar boundary`() throws {
		let source = "value: \"a\\é\" # Keep\nother: 1\n"
		do {
			_ = try SOML.Value(parsing: source)
			Issue.record("Expected invalid escape")
		} catch {
			#expect(error.kind == .invalidString)
			let range = try #require(error.sourceRange)
			#expect(range == 7..<(7 + "\"a\\é".utf8.count))
			#expect(String(validating: Array(source.utf8)[range], as: UTF8.self) != nil)
		}
	}

	@Test
	func `duplicate key ranges preserve exact escaped spelling and original location`() throws {
		let prefix = "outer: {'🎉é': 1, "
		let key = #""\u{1f389}é""#
		let source = prefix + key + ": 2}\n"
		do {
			_ = try SOML.Value(parsing: source)
			Issue.record("Expected a duplicate key")
		} catch {
			#expect(error.kind == .duplicateKey("🎉é"))
			#expect(error.location.offset == prefix.utf8.count)
			let range = try #require(error.sourceRange)
			#expect(range == prefix.utf8.count..<(prefix.utf8.count + key.utf8.count))
			#expect(String(decoding: Array(source.utf8)[range], as: UTF8.self).utf8.elementsEqual(key.utf8))
		}
	}
}

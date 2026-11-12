import Testing
@testable import SOML

@Suite
struct JSONEscapeFixTests {
	@Test(arguments: [
		(#"\u0041"#, #"\u{41}"#, "A"),
		(#"\u00E9"#, #"\u{e9}"#, "é"),
		(#"\u0000"#, #"\u{0}"#, "\u{0}"),
		(#"\uD83D\uDE00"#, #"\u{1f600}"#, "😀"),
		(#"\udbff\udfff"#, #"\u{10ffff}"#, "\u{10ffff}")
	])
	func `JSON escapes expose exact native replacements after a Unicode prefix`(escape: String, replacement: String, expected: String) throws {
		let prefix = "'🎉é': 1\nvalue: \"before "
		let source = prefix + escape + " after\" # Keep\n"
		do {
			_ = try SOML.Value(parsing: source)
			Issue.record("JSON escapes must still be rejected before applying the fix")
		} catch {
			let fix = try #require(error.fixIt)
			#expect(fix.range == prefix.utf8.count..<(prefix.utf8.count + escape.utf8.count))
			#expect(fix.replacement == replacement)
			#expect(error.kind == .invalidString)
			#expect(error.location.offset == prefix.utf8.count)
			let corrected = fix.applied(to: source)
			#expect(corrected.utf8.elementsEqual((prefix + replacement + " after\" # Keep\n").utf8))
			let value = try #require(SOML.Value(parsing: corrected)[path: ["value"]]?.stringValue)
			#expect(value.utf8.elementsEqual(("before " + expected + " after").utf8))
		}
	}

	@Test(arguments: [
		(#""\u0061": 1"#, "a"),
		("value:\n\t\"\"\"\n\t\\u0061\n\t\"\"\"\n", "value")
	])
	func `JSON escape fixes use original ranges in quoted keys and escaped block strings`(source: String, key: String) throws {
		do {
			_ = try SOML.Value(parsing: source)
			Issue.record("Expected a foreign escape error")
		} catch {
			let fix = try #require(error.fixIt)
			#expect(String(source[fix.range(in: source)]) == #"\u0061"#)
			#expect(fix.replacement == #"\u{61}"#)
			let parsed = try SOML.Value(parsing: fix.applied(to: source))
			#expect(parsed[path: SOML.KeyPath([key])] != nil)
			if key == "value" {
				#expect(parsed[path: ["value"]]?.stringValue == "a")
			}
		}
	}

	@Test(arguments: [#"\u000D"#, #"\uD800"#, #"\uDC00"#, #"\uD83D\u0041"#, #"\uDE00\uD83D"#, #"\uD83D\uDE"#, #"\u12"#, #"\u12XZ"#])
	func `unrepresentable and incomplete JSON escapes never offer a fix`(escape: String) {
		do {
			_ = try SOML.Value(parsing: "value: \"" + escape + "\"\n")
			Issue.record("Expected an invalid escape")
		} catch {
			#expect(error.fixIt == nil)
		}
	}

	@Test(arguments: [
		#"value: "\\u00e9""#,
		#"value: '\u00e9'"#,
		"value:\n\t'''\n\t\\u00e9\n\t'''\n"
	])
	func `literal backslashes and literal strings remain unchanged`(source: String) throws {
		let value = try #require(SOML.Value(parsing: source)[path: ["value"]]?.stringValue)
		#expect(value.utf8.elementsEqual(#"\u00e9"#.utf8))
	}

	@Test
	func `one JSON escape fix leaves a later independent error`() throws {
		let source = #"value: "\u0041\q""#
		do {
			_ = try SOML.Value(parsing: source)
			Issue.record("Expected first escape error")
		} catch {
			let fix = try #require(error.fixIt)
			let corrected = fix.applied(to: source)
			#expect(corrected == #"value: "\u{41}\q""#)
			do {
				_ = try SOML.Value(parsing: corrected)
				Issue.record("The later invalid escape must still fail")
			} catch {
				#expect(error.fixIt == nil)
				#expect(error.kind == .invalidString)
			}
		}
	}
}

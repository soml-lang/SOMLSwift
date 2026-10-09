import Foundation
import Testing
@testable import SOML

/**
The language-neutral conformance suite in `Tests/conformance`, a copy of the one in the JavaScript reference implementation, `soml-javascript`.

- `valid/**/name.soml` must parse to the tagged value in `name.json`, serialize to exactly `name.canonical.soml` with `writesCanonicalForm`, and format to exactly `name.formatted.soml`.
- `invalid/**/name.soml` must be rejected.
- `edit/name.json` holds a formatted `document`, a `path`, a tagged `value`, which is left out for a removal, and the `expected` document after the change, or `error: true` when the change must fail because its path does not fit the document.
*/
@Suite
struct ConformanceTests {
	static let root = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appending(path: "conformance")

	static func cases(in directory: String) -> [String] {
		let base = root.appending(path: directory)

		guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else {
			return []
		}

		return enumerator
			.compactMap { $0 as? URL }
			.map { String($0.path(percentEncoded: false).dropFirst(base.path(percentEncoded: false).count)).trimmingPrefix("/") }
			.filter { $0.hasSuffix(".soml") && !$0.hasSuffix(".canonical.soml") && !$0.hasSuffix(".formatted.soml") }
			.map { String($0.dropLast(".soml".count)) }
			.sorted()
	}

	static let validCases = cases(in: "valid")
	static let invalidCases = cases(in: "invalid")

	@Test
	func `the suite is there`() {
		#expect(Self.validCases.count > 300)
		#expect(Self.invalidCases.count > 300)
	}

	@Test(arguments: validCases)
	func `a valid case parses to its value, serializes to its canonical form, and formats to its formatted form`(_ name: String) throws {
		let base = Self.root.appending(path: "valid/\(name)")
		let bytes = try Data(contentsOf: base.appendingPathExtension("soml"))
		let expected = try SOML.Value(parsingJSON: try Data(contentsOf: base.appendingPathExtension("json")), format: .tagged)
		let canonicalForm = try String(contentsOf: URL(filePath: base.path(percentEncoded: false) + ".canonical.soml"), encoding: .utf8)
		let formattedForm = try String(contentsOf: URL(filePath: base.path(percentEncoded: false) + ".formatted.soml"), encoding: .utf8)

		let value = try SOML.Value(parsing: bytes)
		#expect(value == expected)
		#expect(try SOML.Value(parsing: String(decoding: bytes, as: UTF8.self)) == expected)

		var encoder = SOML.Encoder()
		encoder.writesCanonicalForm = true
		let written = try encoder.encodeToString(value)
		#expect(written == canonicalForm)

		// Canonical form is a valid document with the same value, and a fixed point.
		let reparsed = try SOML.Value(parsing: canonicalForm)
		#expect(reparsed == expected)
		#expect(try encoder.encodeToString(reparsed) == canonicalForm)

		// The default output reads back as the same value, with the members in their order.
		let defaultOutput = try SOML.Value(parsing: SOML.Encoder().encodeToString(value))
		#expect(defaultOutput == expected)
		#expect(defaultOutput.objectValue?.keys == value.objectValue?.keys)

		#expect(try SOML.Document(parsing: bytes).formatted() == formattedForm)

		// The formatted form is a valid document with the same value, and a fixed point.
		let formattedDocument = try SOML.Document(parsing: formattedForm)
		#expect(formattedDocument.value == expected)
		#expect(formattedDocument.formatted() == formattedForm)
	}

	/**
	The reason, line, and column with which the JavaScript reference implementation rejects each invalid case. The spec does not fix them. Positions and reasons match the reference, except for minor differences from native Unicode names.
	*/
	static let invalidReasons: [String: (reason: String, line: Int, column: Int)] = {
		guard
			let data = try? Data(contentsOf: root.appending(path: "invalid-reasons.json")),
			let reasons = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
		else {
			return [:]
		}

		return reasons.compactMapValues { reason in
			guard
				let text = reason["reason"] as? String,
				let line = reason["line"] as? Int,
				let column = reason["column"] as? Int
			else {
				return nil
			}

			return (text, line, column)
		}
	}()

	@Test(arguments: invalidCases)
	func `an invalid case is rejected with the reason and at the position the reference reports`(_ name: String) throws {
		let bytes = try Data(contentsOf: Self.root.appending(path: "invalid/\(name).soml"))
		let expected = try #require(Self.invalidReasons[name], "No reason for \(name) in invalid-reasons.json")

		do {
			let value = try SOML.Value(parsing: bytes)
			Issue.record("Expected an error, got \(value)")
		} catch {
			#expect(error.location.line == expected.line && error.location.column == expected.column, "\(name): reported at \(error.location.line):\(error.location.column), the reference at \(expected.line):\(expected.column): \(error.message)")
			// Swift has no name or alias for U+0085; keep the code point and whitespace guidance.
			let expectedReason = name == "whitespace/next-line" ? "Unexpected U+0085 (only space, tab, and line feed are whitespace) after a value" : expected.reason
			#expect(error.message == expectedReason, "\(name)")
		}
	}

	static let editCases = (try? FileManager.default.contentsOfDirectory(atPath: root.appending(path: "edit").path(percentEncoded: false)))?
		.filter { $0.hasSuffix(".json") }
		.map { String($0.dropLast(".json".count)) }
		.sorted() ?? []

	@Test
	func `the edit cases are there`() {
		#expect(Self.editCases.count > 40)
	}

	@Test(arguments: editCases)
	func `an edit case gives exactly its expected document`(_ name: String) throws {
		let data = try Data(contentsOf: Self.root.appending(path: "edit/\(name).json"))
		let editCase = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
		let text = try #require(editCase["document"] as? String)
		let segments = try #require(editCase["path"] as? [Any])

		let path = SOML.KeyPath(try segments.map { segment throws -> SOML.KeyPath.Segment in
			if let key = segment as? String {
				return .key(key)
			}

			return .index(try #require(segment as? Int))
		})

		let document = try SOML.Document(parsing: text)
		#expect(document.formatted() == text, "The document is not formatted.")

		// Read the value with the order-preserving JSON reader, as `JSONSerialization` does not keep the order of the members.
		let value = try SOML.Value(parsingJSON: data)["value"].map { try SOML.Value(parsingJSON: $0.jsonText(), format: .tagged) }

		func change() throws(SOML.EditError) -> SOML.Document {
			if let value {
				try document.setting(value, at: path)
			} else {
				try document.removing(at: path)
			}
		}

		if editCase["error"] as? Bool == true {
			#expect(throws: SOML.EditError.self) {
				try change()
			}

			return
		}

		let expected = try #require(editCase["expected"] as? String)
		let edited = try change()
		#expect(edited.text == expected)
		#expect(edited.formatted() == expected, "The result is not formatted.")
	}
}

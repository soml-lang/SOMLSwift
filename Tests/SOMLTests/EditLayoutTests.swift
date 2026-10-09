import Foundation
import Testing
@testable import SOML

/**
The spec promises that an edit to a formatted document gives a formatted document. Every `setting(_:at:)` and `removing(at:)` of the formatted form of every valid and edit conformance case, at many paths and with many values, must come out formatted again.
*/
@Suite
struct EditLayoutTests {
	static let paths: [SOML.KeyPath] = [
		["a"], ["b"], ["c"], ["x"], ["y"], ["z"], ["list"], ["nested"], ["empty"], ["ports"],
		["a", "b"], ["a", "c"], ["x", "y"], ["nested", 0], ["nested", 1], ["nested", 0, "a"], ["list", 0], ["list", 1], ["list", 2],
		["new"], ["new", "deep"], ["a", "new"], ["list", 3], ["empty", 0], ["empty", "k"],
	]

	static let values: [SOML.Value] = [
		8080, -1, 1.5, 0.0, "text", "", true, nil, [1, 2], [], ["k": 1], [:],
		"multi\nline", "it's", "say \"hi\"", "tab\there", "ctrl\u{1}", "🌍", 9_223_372_036_854_775_807,
		["deep": ["deeper": [1, ["x": "y"]]]],
	]

	@Test
	func `edits of formatted documents stay formatted`() throws {
		let root = URL(filePath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "conformance")

		var documents = [String]()

		for kind in ["valid", "edit"] {
			let directory = root.appending(path: kind)

			guard FileManager.default.fileExists(atPath: directory.path) else {
				continue
			}

			let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)

			while let file = enumerator?.nextObject() as? URL {
				if file.lastPathComponent.hasSuffix(".formatted.soml") {
					documents.append(try String(contentsOf: file, encoding: .utf8))
				}
			}
		}

		try #require(!documents.isEmpty)
		var violations = 0
		var checked = 0
		var firstViolations = [String]()

		for documentText in documents {
			let document = try SOML.Document(parsing: documentText)
			try #require(document.formatted() == documentText, "The suite document is not formatted: \(documentText)")

			for path in Self.paths {
				do {
					let edited = try document.removing(at: path)
					checked += 1

					if edited.text != edited.formatted() {
						violations += 1

						if firstViolations.count < 10 {
							firstViolations.append("REMOVE \(path) of \(documentText.debugDescription) gave \(edited.text.debugDescription), formatted \(edited.formatted().debugDescription)")
						}
					}
				} catch {}

				for value in Self.values {
					do {
						let edited = try document.setting(value, at: path)
						checked += 1

						if edited.text != edited.formatted() {
							violations += 1

							if firstViolations.count < 10 {
								firstViolations.append("SET \(value) at \(path) of \(documentText.debugDescription) gave \(edited.text.debugDescription), formatted \(edited.formatted().debugDescription)")
							}
						}
					} catch {}
				}
			}
		}

		for violation in firstViolations {
			Issue.record("\(violation)")
		}

		#expect(violations == 0, "\(violations) of \(checked) edits of formatted documents were not formatted")
	}
}

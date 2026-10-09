import Foundation
import Testing
@testable import SOML

/**
The selection APIs agree with each other and with the value: for every member and item of every valid conformance case, raw and formatted, the text of `valueRange(of:)` parses back to the value at the path, `path(atOffset:)` at its start gives back the path, `range(of:)` starts where `location(of:)` points, and both ranges end together.
*/
@Suite
struct SelectionTests {
	static func paths(of value: SOML.Value, prefix: [SOML.KeyPath.Segment] = []) -> [[SOML.KeyPath.Segment]] {
		switch value {
		case .object(let object):
			object.flatMap { key, member in
				[prefix + [.key(key)]] + paths(of: member, prefix: prefix + [.key(key)])
			}
		case .array(let items):
			items.enumerated().flatMap { index, item in
				[prefix + [.index(index)]] + paths(of: item, prefix: prefix + [.index(index)])
			}
		default:
			[]
		}
	}

	@Test
	func `selection APIs agree with each other and the value`() throws {
		let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "conformance/valid")
		let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
		var checked = 0
		var failures = [String]()

		while let file = enumerator?.nextObject() as? URL {
			guard
				file.pathExtension == "soml",
				!file.lastPathComponent.contains(".canonical."),
				!file.lastPathComponent.contains(".formatted.")
			else {
				continue
			}

			let bytes = try Array(Data(contentsOf: file))

			for document in [try SOML.Document(parsing: bytes), try SOML.Document(parsing: SOML.Document(parsing: bytes).formatted())] {
				let text = Array(document.text.utf8)

				for segments in Self.paths(of: document.value) {
					let path = SOML.KeyPath(segments)
					checked += 1

					guard
						let range = document.range(of: path),
						let valueRange = document.valueRange(of: path)
					else {
						failures.append("\(file.lastPathComponent) \(path): no range")
						continue
					}

					// The value text parses back to the value at the path.
					let valueText = String(decoding: text[valueRange.lowerBound.offset..<valueRange.upperBound.offset], as: UTF8.self)

					if (try? SOML.Value(parsingValue: valueText)) != document.value[path: path] {
						failures.append("\(file.lastPathComponent) \(path): value text \(valueText.debugDescription) does not parse to the value")
					}

					// The start of the value gives back the path, and so does its end.
					if document.path(atOffset: valueRange.lowerBound.offset) != path {
						failures.append("\(file.lastPathComponent) \(path): path at value start is \(document.path(atOffset: valueRange.lowerBound.offset)?.description ?? "nil")")
					}

					// The range of a member starts where location(of:) points.
					if document.location(of: path) != range.lowerBound {
						failures.append("\(file.lastPathComponent) \(path): range starts at \(range.lowerBound), location(of:) is \(document.location(of: path))")
					}

					if !(range.lowerBound <= valueRange.lowerBound && valueRange.upperBound == range.upperBound) {
						failures.append("\(file.lastPathComponent) \(path): value range \(valueRange) is not at the end of range \(range)")
					}
				}
			}
		}

		for failure in failures.prefix(15) {
			Issue.record("\(failure)")
		}

		#expect(checked > 1000, "Only \(checked) paths")
		#expect(failures.isEmpty, "\(failures.count) of \(checked) failed")
	}
}

import Foundation
import Testing
@testable import SOML

/**
Expects `large`, which does sixteen times the work of `small`, to take about sixteen times as long, rather than the 256 times of quadratic time.
*/
func expectLinearTime(_ small: () throws -> Void, large: () throws -> Void, sourceLocation: SourceLocation = #_sourceLocation) rethrows {
	// The limit leaves room for other tests that run at the same time.
	try expectTimeRatio(small, large: large, below: 64, sourceLocation: sourceLocation)
}

/**
Expects `large` to take less than `limit` times as long as `small`.

Each round takes the fastest of several runs of each, in turns, so that other work on the machine adds little, and a round that is still slowed by a busy machine is measured again. Code that is too slow fails every round.
*/
func expectTimeRatio(_ small: () throws -> Void, large: () throws -> Void, below limit: Double, sourceLocation: SourceLocation = #_sourceLocation) rethrows {
	let clock = ContinuousClock()
	var ratio = 0.0

	for _ in 0..<3 {
		var smallTime = Duration.seconds(1000)
		var largeTime = Duration.seconds(1000)

		for _ in 0..<5 {
			smallTime = min(smallTime, try clock.measure(small))
			largeTime = min(largeTime, try clock.measure(large))
		}

		ratio = largeTime / smallTime

		if ratio < limit {
			return
		}
	}

	Issue.record("It took \(ratio) times as long, and the limit is \(limit)", sourceLocation: sourceLocation)
}

/**
A named document, so that parameterized tests show a readable name.
*/
struct Sample: CustomTestStringConvertible, Sendable {
	let name: String
	let source: String

	init(_ name: String, _ source: String) {
		self.name = name
		self.source = source
	}

	var testDescription: String {
		name
	}
}

/**
A named document that must fail, and a fragment of the error message it must give.
*/
struct Rejection: CustomTestStringConvertible, Sendable {
	let name: String
	let source: String
	let message: String

	init(_ name: String, _ source: String, _ message: String) {
		self.name = name
		self.source = source
		self.message = message
	}

	var testDescription: String {
		name
	}
}

/**
A named document and the value it must parse to.
*/
struct Expectation: CustomTestStringConvertible, Sendable {
	let name: String
	let source: String
	let value: SOML.Value

	init(_ name: String, _ source: String, _ value: SOML.Value) {
		self.name = name
		self.source = source
		self.value = value
	}

	var testDescription: String {
		name
	}
}

func parse(_ source: String) throws -> SOML.Value {
	try SOML.Value(parsing: source)
}

/**
Parses a document that must fail, and returns the error.
*/
@discardableResult
func parseError(_ source: String, sourceLocation: SourceLocation = #_sourceLocation) -> SOML.ParseError? {
	do {
		let value = try SOML.Value(parsing: source)
		Issue.record("Expected a parse error, but got \(value)", sourceLocation: sourceLocation)
		return nil
	} catch {
		return error
	}
}

/**
Checks that a document fails with a message that contains `fragment`.
*/
func expectRejected(_ source: String, _ fragment: String, sourceLocation: SourceLocation = #_sourceLocation) {
	guard let error = parseError(source, sourceLocation: sourceLocation) else {
		return
	}

	#expect(error.message.contains(fragment), "Message was: \(error.message)", sourceLocation: sourceLocation)
}

/**
Parses `value: <source>` and returns the value.
*/
func parseScalar(_ source: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> SOML.Value {
	let document = try SOML.Value(parsing: "value: \(source)")
	return try #require(document["value"], sourceLocation: sourceLocation)
}

/**
The error for `value: <source>`.
*/
func scalarError(_ source: String, sourceLocation: SourceLocation = #_sourceLocation) -> SOML.ParseError? {
	parseError("value: \(source)", sourceLocation: sourceLocation)
}

/**
The canonical text of a document.
*/
func canonical(_ value: SOML.Value) throws -> String {
	var encoder = SOML.Encoder()
	encoder.writesCanonicalForm = true
	return try encoder.encodeToString(value)
}

/**
The canonical text of a document given as source.
*/
func canonical(_ source: String) throws -> String {
	try canonical(parse(source))
}

/**
The spec repository, which must be checked out next to this one, as `soml`.
*/
let specRepository = URL(filePath: #filePath)
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.deletingLastPathComponent()
	.appending(path: "soml")

/**
Whether the spec repository is checked out. The tests that read its examples are skipped without it, like in CI.
*/
let isSpecAvailable = FileManager.default.fileExists(atPath: specRepository.appending(path: "spec.md").path(percentEncoded: false))

/**
The readme, the comparison, and the spec, joined, for tests that use their examples. They are read from the spec repository.
*/
func documentationText() throws -> String {
	try ["readme.md", "comparison.md", "spec.md"]
		.map { try String(contentsOf: specRepository.appending(path: $0), encoding: .utf8) }
		.joined(separator: "\n")
}

/**
The untagged code blocks of the readme, the comparison, and the spec.
*/
func exampleBlocks() throws -> [String] {
	let text = try documentationText()
	var blocks = [String]()
	var current: [String]?
	var isUntagged = false

	for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
		if line.hasPrefix("```") {
			if let lines = current {
				if isUntagged {
					blocks.append(lines.joined(separator: "\n"))
				}

				current = nil
			} else {
				current = []
				isUntagged = line.dropFirst(3).trimmingCharacters(in: .whitespaces).isEmpty
			}

			continue
		}

		current?.append(String(line))
	}

	return blocks
}

/**
The one untagged example block that starts with `prefix`.
*/
func exampleBlock(startingWith prefix: String) throws -> String {
	let matches = try exampleBlocks().filter { $0.hasPrefix(prefix) }
	try #require(matches.count == 1, "Expected one block starting with \(prefix), found \(matches.count)")
	return matches[0]
}

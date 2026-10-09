import Foundation
import Testing
@testable import SOML

/**
Differential testing against the JavaScript reference implementation, which must be checked out next to this repository as `soml-javascript`, with a Node.js on the `PATH` that has `Temporal` (Node.js 26 or later, or an older one with a polyfill loaded through `NODE_OPTIONS`). Without them, the test is skipped.

Every valid document of the conformance suite is mutated in seeded random ways, and for each result both implementations must agree: both accept it or both reject it, a rejection has the same reason and is at the same line and column, and an accepted document has the same canonical form and the same formatted form, byte for byte.
*/
@Suite
struct DifferentialTests {
	static let referenceSource = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.deletingLastPathComponent()
		.appending(path: "soml-javascript/source/index.ts")

	static let isReferenceAvailable = FileManager.default.fileExists(atPath: referenceSource.path(percentEncoded: false)) && (try? runNode(["--eval", "if (typeof Temporal === 'undefined') { process.exit(1); }"])) != nil

	/**
	The result of one document in one implementation, as the reference script writes it.
	*/
	struct Outcome: Codable, Equatable {
		var reason: String?
		var line: Int?
		var column: Int?
		var canonical: String?
		var formatted: String?
	}

	/**
	Reads a JSON array of documents from the file in its first argument, and writes the outcome of each to the file in its second argument.
	*/
	static let referenceScript = """
		import fs from 'node:fs';
		const {parse, stringify, format, ParseError} = await import(process.argv[4]);
		const documents = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
		const outcomes = documents.map(text => {
			try {
				return {canonical: stringify(parse(text), {canonical: true}), formatted: format(text)};
			} catch (error) {
				if (error instanceof ParseError) {
					return {reason: error.reason, line: error.line, column: error.column};
				}

				return {canonical: `unexpected error: ${error}`};
			}
		});
		fs.writeFileSync(process.argv[3], JSON.stringify(outcomes));
		"""

	@discardableResult
	static func runNode(_ arguments: [String]) throws -> String {
		let process = Process()
		process.executableURL = URL(filePath: "/usr/bin/env")
		process.arguments = ["node"] + arguments
		let output = Pipe()
		process.standardOutput = output
		process.standardError = Pipe()
		try process.run()
		let data = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()

		guard process.terminationStatus == 0 else {
			throw CocoaError(.executableLoad)
		}

		return String(decoding: data, as: UTF8.self)
	}

	/**
	A document changed in one random place: a character removed, repeated, or replaced with a token that SOML gives meaning to, or two lines joined.
	*/
	static func mutated(_ text: String, using generator: inout SeededGenerator) -> String {
		let tokens = ["", " ", "\t", "\n", ",", ":", ".", "{", "}", "[", "]", "'", "\"", "'''", "#", "/*", "*/", "-", "_", "0", "1e5", "0x1F", "1h", "1.5s", "2026-09-19T14:00:00Z", "true", "null", "a", "é", "\\"]
		var scalars = Array(text.unicodeScalars)
		let index = scalars.isEmpty ? 0 : Int.random(in: scalars.indices, using: &generator)

		switch Int.random(in: 0..<4, using: &generator) {
		case 0 where !scalars.isEmpty:
			scalars.remove(at: index)
		case 1 where !scalars.isEmpty:
			scalars.insert(scalars[index], at: index)
		case 2:
			scalars.insert(contentsOf: tokens.randomElement(using: &generator)!.unicodeScalars, at: index)
		default:
			if let lineFeed = scalars[index...].firstIndex(of: "\n") {
				scalars[lineFeed] = " "
			}
		}

		return String(String.UnicodeScalarView(scalars))
	}

	/**
	The outcome of a document in this implementation, in the shape the reference script writes.
	*/
	static func outcome(of text: String) -> Outcome {
		do {
			let document = try SOML.Document(parsing: text)
			let canonical = (try? document.value.canonicalDocument()) ?? "not representable"
			return Outcome(canonical: canonical, formatted: document.formatted())
		} catch {
			return Outcome(reason: error.message, line: error.location.line, column: error.location.column)
		}
	}

	@Test(.enabled(if: isReferenceAvailable))
	func `agrees with the reference implementation on mutated documents`() throws {
		var generator = SeededGenerator(seed: 17)
		var documents = [String]()

		for name in ConformanceTests.validCases {
			let text = try String(contentsOf: ConformanceTests.root.appending(path: "valid/\(name).soml"), encoding: .utf8)
			documents.append(text)

			for _ in 0..<6 {
				var document = text

				for _ in 0..<Int.random(in: 1...3, using: &generator) {
					document = Self.mutated(document, using: &generator)
				}

				documents.append(document)
			}
		}

		let directory = URL.temporaryDirectory.appending(path: "soml-differential-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

		defer {
			try? FileManager.default.removeItem(at: directory)
		}

		let input = directory.appending(path: "input.json")
		let output = directory.appending(path: "output.json")
		let script = directory.appending(path: "reference.mjs")
		try JSONEncoder().encode(documents).write(to: input)
		try Self.referenceScript.write(to: script, atomically: true, encoding: .utf8)
		try Self.runNode([script, input, output, Self.referenceSource].map { $0.path(percentEncoded: false) })

		let expected = try JSONDecoder().decode([Outcome].self, from: Data(contentsOf: output))
		try #require(expected.count == documents.count)
		var differences = [String]()

		for (document, expectedOutcome) in zip(documents, expected) {
			let outcome = Self.outcome(of: document)

			if outcome != expectedOutcome {
				differences.append("\(document.debugDescription)\nSwift: \(outcome)\nJS: \(expectedOutcome)")
			}
		}

		#expect(differences.isEmpty, "\(differences.count) of \(documents.count) documents differ. The first ones:\n\n\(differences.prefix(5).joined(separator: "\n\n"))")
	}
}

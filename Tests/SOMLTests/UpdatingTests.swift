import Foundation
import Testing
@testable import SOML

/**
The readme promises that `updating(as:_:)` turns the difference between the model before and after the change into edits, so that a member the model does not read stays, arrays are appended or shrunk from the end, and every other byte stays.
*/
@Suite
struct UpdatingTests {
	struct Config: Codable, Equatable {
		var name = "api"
		var port = 80
		var replicas = 3
		var labels: [String] = []
		var flags: [String: Bool] = [:]
		var limit: Int?
	}

	@Test
	func `updating cases`() throws {
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase

		func update(_ text: String, _ change: (inout Config) -> Void) throws -> (String, Config) {
			let document = try SOML.Document(parsing: text)
			let updated = try document.updating(as: Config.self, decoder: decoder, encoder: encoder, change)
			let model = try decoder.decode(Config.self, from: updated.value)
			return (updated.text, model)
		}

		// A plain change keeps the comment and the spelling of the other members.
		let (first, firstModel) = try update("name: 'web' # kept\nport: 0x50\nreplicas: 3\nlabels: []\nflags: {}\n") {
			$0.port = 8080
		}
		#expect(first == "name: 'web' # kept\nport: 8080\nreplicas: 3\nlabels: []\nflags: {}\n")
		#expect(firstModel.port == 8080)

		// A member the model does not read stays.
		let (second, _) = try update("name: 'web'\nport: 80\nreplicas: 3\nlabels: []\nflags: {}\nextra: true\n") {
			$0.port = 90
		}
		#expect(second == "name: 'web'\nport: 90\nreplicas: 3\nlabels: []\nflags: {}\nextra: true\n")

		// An optional set from nil to a value is added after the members that are there.
		let (third, thirdModel) = try update("name: 'web'\nport: 80\nreplicas: 3\nlabels: []\nflags: {}\n") {
			$0.limit = 5
		}
		#expect(third == "name: 'web'\nport: 80\nreplicas: 3\nlabels: []\nflags: {}\nlimit: 5\n")
		#expect(thirdModel.limit == 5)

		// An optional set from a value to nil is removed.
		let (fourth, fourthModel) = try update("name: 'web'\nport: 80\nreplicas: 3\nlabels: []\nflags: {}\nlimit: 5 # kept?\n") {
			$0.limit = nil
		}
		#expect(fourth == "name: 'web'\nport: 80\nreplicas: 3\nlabels: []\nflags: {}\n")
		#expect(fourthModel.limit == nil)

		// An array that gets longer gets items appended.
		let (fifth, fifthModel) = try update("name: 'web'\nport: 80\nreplicas: 3\nlabels: ['a', 'b']\nflags: {}\n") {
			$0.labels = ["a", "b", "c"]
		}
		#expect(fifth == "name: 'web'\nport: 80\nreplicas: 3\nlabels: ['a', 'b', 'c']\nflags: {}\n")
		#expect(fifthModel.labels == ["a", "b", "c"])

		// An array that gets shorter loses items from the end.
		let (sixth, sixthModel) = try update("name: 'web'\nport: 80\nreplicas: 3\nlabels: ['a', 'b', 'c']\nflags: {}\n") {
			$0.labels = ["a"]
		}
		#expect(sixth == "name: 'web'\nport: 80\nreplicas: 3\nlabels: ['a']\nflags: {}\n")
		#expect(sixthModel.labels == ["a"])

		// A dictionary entry is added and another one removed.
		let (seventh, seventhModel) = try update("name: 'web'\nport: 80\nreplicas: 3\nlabels: []\nflags: {a: true, b: false}\n") {
			$0.flags = ["a": true, "c": true]
		}
		#expect(seventh == "name: 'web'\nport: 80\nreplicas: 3\nlabels: []\nflags: {a: true, c: true}\n")
		#expect(seventhModel.flags == ["a": true, "c": true])

		// Two members change in one update, and the order of the members stays.
		let (eighth, eighthModel) = try update("name: 'x'\nport: 80\nreplicas: 3\nlabels: []\nflags: {}\n") {
			$0.port = 8080
			$0.replicas = 4
		}
		#expect(eighth == "name: 'x'\nport: 8080\nreplicas: 4\nlabels: []\nflags: {}\n")
		#expect(eighthModel.port == 8080 && eighthModel.replicas == 4)

		// A changed member is replaced in place.
		let (ninth, ninthModel) = try update("name: 'x'\nport: 80\nreplicas: 3\nlabels: []\nflags: {}\n") {
			$0.port = 1
		}
		#expect(ninth == "name: 'x'\nport: 1\nreplicas: 3\nlabels: []\nflags: {}\n")
		#expect(ninthModel.port == 1)
	}

	struct Flags: Codable {
		var flags: [String: Bool]
	}

	enum Mode: Codable {
		case fast(level: Int)
		case slow
	}

	struct Settings: Codable {
		var mode: Mode
	}

	@Test
	func `replacing every member of an object keeps its layout`() throws {
		// The object is never empty in between, which would put the new member on a line of its own, or wrap a document without braces in braces.
		let flags = try SOML.Document(parsing: "flags: {a: true} # Flags\n").updating(as: Flags.self) {
			$0.flags = ["b": true]
		}
		#expect(flags.text == "flags: {b: true} # Flags\n")

		let settings = try SOML.Document(parsing: "mode: {fast: {level: 1}} # Mode\n").updating(as: Settings.self) {
			$0.mode = .slow
		}
		#expect(settings.text == "mode: {slow: {}} # Mode\n")

		let document = try SOML.Document(parsing: "# Ports\na: 1\n").updating(as: [String: Int].self) {
			$0 = ["b": 2]
		}
		#expect(document.text == "# Ports\nb: 2\n")
	}

	@Test
	func `removals after the other changes still give the new value when an array shrinks and changes, and a nested object loses its members and gains a deeper one`() throws {
		let document = try SOML.Document(parsing: "a: [{x: 1}, 2, 3] # A\nb: {c: 1, d: {e: 1}}\nf: 1\n")
		let edited = try document.updating(as: SOML.Value.self) {
			$0 = ["a": [["x": 2, "y": 3]], "b": ["d": ["g": ["h": 1]]]]
		}
		#expect(edited.text == "a: [{x: 2, y: 3}] # A\nb: {d: {g: {h: 1}}}\n")
		#expect(edited.value == ["a": [["x": 2, "y": 3]], "b": ["d": ["g": ["h": 1]]]])
	}

	struct NestedConfig: Codable, Equatable {
		var serviceName: String
		var maxConnections: Int?
		var servers: [Server]
		var labelsByName: [String: String]
		var timeoutSeconds: Double
		var retry: Retry?

		struct Server: Codable, Equatable {
			var hostName: String
			var portNumber: Int?
			var tags: [String]
		}

		struct Retry: Codable, Equatable {
			var attemptCount: Int
			var backoff: Duration
		}
	}

	static func randomConfig(_ generator: inout SeededGenerator) -> NestedConfig {
		NestedConfig(
			serviceName: ["api", "web", "it's", "a\nb"][Int.random(in: 0..<4, using: &generator)],
			maxConnections: Bool.random(using: &generator) ? Int.random(in: 0...500, using: &generator) : nil,
			servers: (0..<Int.random(in: 0...3, using: &generator)).map { index in
				NestedConfig.Server(hostName: "h\(index)\(Int.random(in: 0...2, using: &generator))", portNumber: Bool.random(using: &generator) ? Int.random(in: 1...3, using: &generator) : nil, tags: (0..<Int.random(in: 0...2, using: &generator)).map { "t\($0)" })
			},
			labelsByName: Dictionary(uniqueKeysWithValues: (0..<Int.random(in: 0...2, using: &generator)).map { ("someKey\($0)", "v\(Int.random(in: 0...1, using: &generator))") }),
			timeoutSeconds: [1.0, 2.5, 30][Int.random(in: 0..<3, using: &generator)],
			retry: Bool.random(using: &generator) ? NestedConfig.Retry(attemptCount: Int.random(in: 1...3, using: &generator), backoff: .seconds(Int.random(in: 1...90, using: &generator))) : nil
		)
	}

	@Test
	func `updating through a nested typed model with optionals, arrays, and a dictionary gives the new model`() throws {
		// Random pairs of models under a key strategy, from a document as the encoder writes it, and from one with a comment on every line.
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase
		var generator = SeededGenerator(seed: 404)
		var failures = [String]()

		for index in 0..<3000 {
			let old = Self.randomConfig(&generator)
			let new = Self.randomConfig(&generator)
			let text = try encoder.encodeToString(old)

			// Layouts a person writes: as encoded, and formatted after commas and comments were added.
			let document = try SOML.Document(parsing: index % 2 == 0 ? text : text.replacingOccurrences(of: "\n", with: " # c\n"))

			do {
				let updated = try document.updating(as: NestedConfig.self, decoder: decoder, encoder: encoder) { $0 = new }
				let reread = try decoder.decode(NestedConfig.self, from: updated.text)

				if reread != new {
					failures.append("Got \(reread) for \(new) from\n\(document.text)\nto\n\(updated.text)")
				}

				if document.formatted() == document.text, updated.formatted() != updated.text {
					failures.append("Not formatted:\n\(updated.text)")
				}
			} catch {
				failures.append("Threw \(error) for\n\(document.text)\nto \(new)")
			}
		}

		for failure in failures.prefix(5) {
			Issue.record("\(failure)")
		}

		#expect(failures.isEmpty, "\(failures.count) failed")
	}
}

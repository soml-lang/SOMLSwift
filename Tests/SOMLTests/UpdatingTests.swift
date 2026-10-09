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

	/**
	Reads its ports sorted, so it encodes them in another order than the document has them.
	*/
	struct SortedPorts: Codable {
		var ports: [Int]

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			ports = try container.decode([Int].self, forKey: .ports).sorted()
		}
	}

	@Test
	func `a model that sorts the strings of a document that is an array cannot change one of them`() throws {
		struct Sorted: Codable {
			var items: [String]

			init(from decoder: any Decoder) throws {
				items = try [String](from: decoder).sorted()
			}

			func encode(to encoder: any Encoder) throws {
				try items.encode(to: encoder)
			}
		}

		let document = try SOML.Document(parsing: "['b', 'a']\n")

		let error = try #require(throws: SOML.EditError.self) {
			try document.updating(as: Sorted.self) { $0.items[1] = "z" }
		}

		#expect(error.message.hasPrefix("The changed document does not read back as the changed model"), "\(error.message)")
	}

	@Test
	func `array items are matched by position, so what the model does not read stays at its position`() throws {
		struct Host: Codable {
			var host: String
		}

		struct Root: Codable {
			var servers: [Host]
		}

		let document = try SOML.Document(parsing: "servers: [\n\t{host: 'a', weight: 5} # Primary\n\t{host: 'b'} # Backup\n]\n")

		// As documented: the first item gets the second's host, and the last item goes.
		let updated = try document.updating(as: Root.self) { $0.servers.remove(at: 0) }
		#expect(updated.text == "servers: [\n\t{host: 'b', weight: 5} # Primary\n]\n")

		// `removing(at:)` takes the item with everything it holds.
		#expect(try document.removing(at: ["servers", 0]).text == "servers: [\n\t{host: 'b'} # Backup\n]\n")
	}

	@Test
	func `a model that does not encode the document as it is written cannot change it in place`() throws {
		let document = try SOML.Document(parsing: "ports: [443, 80, 8080]\n")

		let error = try #require(throws: SOML.EditError.self) {
			try document.updating(as: SortedPorts.self) {
				$0.ports.removeAll { $0 == 443 }
			}
		}

		#expect(error.message == "The changed document does not read back as the changed model, so the model does not read the document as it is written, like an array that it sorts or a Set, or the decoder and the encoder have different key strategies, and it cannot be changed in place")

		// A change where the model and the document agree is made.
		let sorted = try SOML.Document(parsing: "ports: [80, 443] # Sorted\n")
		#expect(try sorted.updating(as: SortedPorts.self) { $0.ports.append(8080) }.text == "ports: [80, 443, 8080] # Sorted\n")
		#expect(try sorted.updating(as: SortedPorts.self) { $0.ports[1] = 444 }.text == "ports: [80, 444] # Sorted\n")
	}

	/**
	Reads its servers sorted by name.
	*/
	struct SortedServers: Codable {
		struct Server: Codable {
			var name: String
			var port: Int?
		}

		var servers: [Server]

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			servers = try container.decode([Server].self, forKey: .servers).sorted(using: KeyPathComparator(\.name))
		}
	}

	@Test
	func `a model that reorders an array cannot add to an item or the array, or change an item whose old value happens to agree`() throws {
		let unchanged = try SOML.Document(parsing: "servers: [\n\t{name: 'b'}\n\t{name: 'a'}\n]\n")

		let added = try #require(throws: SOML.EditError.self) {
			try unchanged.updating(as: SortedServers.self) {
				$0.servers[0].port = 80
			}
		}

		#expect(added.message == "The changed document does not read back as the changed model, so the model does not read the document as it is written, like an array that it sorts or a Set, or the decoder and the encoder have different key strategies, and it cannot be changed in place")

		let agreeing = try SOML.Document(parsing: "servers: [\n\t{name: 'b', port: 1}\n\t{name: 'a', port: 1}\n]\n")

		#expect(throws: SOML.EditError.self) {
			try agreeing.updating(as: SortedServers.self) {
				$0.servers[0].port = 2
			}
		}

		// An item added at the end reads back where the model has it, so it is added.
		let ports = try SOML.Document(parsing: "ports: [443, 80]\n")
		#expect(try ports.updating(as: SortedPorts.self) { $0.ports.append(8080) }.text == "ports: [443, 80, 8080]\n")

		// The order of the document does not matter for a change outside the array.
		struct Tagged: Codable {
			var tags: Set<String>
			var name: String
		}

		let tagged = try SOML.Document(parsing: "tags: ['b', 'a', 'c']\nname: 'x'\n")
		#expect(try tagged.updating(as: Tagged.self) { $0.name = "y" }.text == "tags: ['b', 'a', 'c']\nname: 'y'\n")

		// A model that keeps the order changes the array in place.
		struct Plain: Codable {
			var servers: [SortedServers.Server]
		}

		#expect(try unchanged.updating(as: Plain.self) { $0.servers[1].port = 80 }.text == "servers: [\n\t{name: 'b'}\n\t{name: 'a', port: 80}\n]\n")
	}

	/**
	Reads its name lowercased, so it encodes another value than the document has.
	*/
	struct LowercasedName: Codable {
		var name: String
		var port: Int

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			name = try container.decode(String.self, forKey: .name).lowercased()
			port = try container.decode(Int.self, forKey: .port)
		}
	}

	@Test
	func `a model that changes a value that it reads sets the value that it has`() throws {
		let document = try SOML.Document(parsing: "name: 'API'\nport: 80\n")

		// The document reads back as the changed model, which is what the change asks for.
		#expect(try document.updating(as: LowercasedName.self) { $0.name += "-v2" }.text == "name: 'api-v2'\nport: 80\n")

		// Another member changes, and the one that the model reads in another way stays as it is.
		#expect(try document.updating(as: LowercasedName.self) { $0.port = 8080 }.text == "name: 'API'\nport: 8080\n")
	}

	/**
	Reads its items sorted by name, and each item's values in the order written.
	*/
	struct SortedNamed: Codable {
		struct Named: Codable {
			var name: String
			var values: [Int]
			var tags: [String]

			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				name = try container.decode(String.self, forKey: .name)
				values = try container.decodeIfPresent([Int].self, forKey: .values) ?? []
				tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
			}
		}

		var items: [Named]

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			items = try container.decode([Named].self, forKey: .items).sorted(using: KeyPathComparator(\.name))
		}
	}

	@Test
	func `a model that sorts an array around the changed one cannot change it in place`() throws {
		let document = try SOML.Document(parsing: "items: [{name: 'b', values: [1]}, {name: 'a', values: [1]}]\n")

		#expect(throws: SOML.EditError.self) {
			try document.updating(as: SortedNamed.self) {
				$0.items[0].values[0] = 7
			}
		}

		// Also when the changed member is missing from the document, and is set whole.
		#expect(throws: SOML.EditError.self) {
			try document.updating(as: SortedNamed.self) {
				$0.items[0].tags.append("x")
			}
		}
	}

	/**
	A document that is an array, which the model reads sorted.
	*/
	struct SortedTop: Codable {
		struct Entry: Codable {
			var name: String
			var port: Int
		}

		var entries: [Entry]

		init(from decoder: any Decoder) throws {
			entries = try decoder.singleValueContainer().decode([Entry].self).sorted(using: KeyPathComparator(\.name))
		}

		func encode(to encoder: any Encoder) throws {
			var container = encoder.singleValueContainer()
			try container.encode(entries)
		}
	}

	@Test
	func `a model that sorts a document that is an array cannot change it in place`() throws {
		let document = try SOML.Document(parsing: "[\n\t{name: 'b', port: 1}\n\t{name: 'a', port: 1}\n]\n")

		#expect(throws: SOML.EditError.self) {
			try document.updating(as: SortedTop.self) {
				$0.entries[0].port = 5
			}
		}
	}

	@Test
	func `a change that changes nothing gives the document as it is`() throws {
		// A `Set` can encode in another order each time, which the check of the result must not see when nothing changed.
		let document = try SOML.Document(parsing: "['b', 'a', 'c', 'd', 'e', 'f', 'g', 'h'] # Tags\n")

		for _ in 0..<20 {
			#expect(try document.updating(as: Set<String>.self) { _ in }.text == document.text)
		}
	}

	@Test
	func `a decoder and an encoder with different key strategies cannot change the document`() throws {
		struct Limits: Codable {
			var maxCount: Int
			var other: Int
		}

		var kebab = SOML.Decoder()
		kebab.keyDecodingStrategy = .convertFromKebabCase

		#expect(throws: SOML.EditError.self) {
			try SOML.Document(parsing: "max-count: 1\nother: 2\n").updating(as: Limits.self, decoder: kebab) {
				$0.maxCount = 5
			}
		}

		var kebabEncoder = SOML.Encoder()
		kebabEncoder.keyEncodingStrategy = .convertToKebabCase

		#expect(throws: SOML.EditError.self) {
			try SOML.Document(parsing: "maxCount: 1\nother: 2\n").updating(as: Limits.self, encoder: kebabEncoder) {
				$0.maxCount = 5
			}
		}

		#expect(try SOML.Document(parsing: "max-count: 1\nother: 2\n").updating(as: Limits.self, decoder: kebab, encoder: kebabEncoder) { $0.maxCount = 5 }.text == "max-count: 5\nother: 2\n")
	}

	@Test
	func `a member that the document writes as null and the model gives a default, and a float that the document writes as an int, can be changed`() throws {
		struct Settings: Codable {
			var port: Int
			var name: String
			var timeout: Double
			var ratios: [Double]

			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 80
				name = try container.decode(String.self, forKey: .name)
				timeout = try container.decode(Double.self, forKey: .timeout)
				ratios = try container.decode([Double].self, forKey: .ratios)
			}
		}

		let document = try SOML.Document(parsing: "port: null # x\nname: 'a'\ntimeout: 30\nratios: [1, 2.5]\n")
		#expect(try document.updating(as: Settings.self) { $0.port = 8080 }.text == "port: 8080 # x\nname: 'a'\ntimeout: 30\nratios: [1, 2.5]\n")
		#expect(try document.updating(as: Settings.self) { $0.name = "b" }.text == "port: null # x\nname: 'b'\ntimeout: 30\nratios: [1, 2.5]\n")
		#expect(try document.updating(as: Settings.self) { $0.timeout = 45.5 }.text == "port: null # x\nname: 'a'\ntimeout: 45.5\nratios: [1, 2.5]\n")
		#expect(try document.updating(as: Settings.self) { $0.ratios[1] = 3.5 }.text == "port: null # x\nname: 'a'\ntimeout: 30\nratios: [1, 3.5]\n")
	}

	@Test
	func `a member the model does not read does not make the document disagree with the model`() throws {
		struct Server: Codable {
			var host: String
		}

		struct Servers: Codable {
			var servers: [Server]
		}

		let document = try SOML.Document(parsing: "servers: [{host: 'a', note: 'primary'}, {host: 'b'}]\n")
		let edited = try document.updating(as: Servers.self) {
			$0.servers[0].host = "c"
			$0.servers.removeLast()
		}

		#expect(edited.text == "servers: [{host: 'c', note: 'primary'}]\n")
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

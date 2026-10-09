import Foundation
import Testing
@testable import SOML

/**
The examples in `readme.md`, `comparison.md`, and `spec.md`, read from the files so that the tests follow the documentation when it changes.
*/
@Suite(.enabled(if: isSpecAvailable))
struct ExampleTests {
	@Test
	func `every untagged block is a valid document, an error example, or not SOML`() throws {
		let blocks = try exampleBlocks()
		#expect(blocks.count >= 10)

		for block in blocks {
			if block.contains("# error") {
				#expect(throws: SOML.ParseError.self, "The error example must fail: \(block)") {
					try parse(block)
				}

				continue
			}

			// These blocks are a .gitattributes line, an escape listing, and the grammar.
			let isNotSOML = block.hasPrefix("* text") || block.hasPrefix("\\u{") || block.hasPrefix(";") || block.hasPrefix("document    =")

			if isNotSOML {
				continue
			}

			#expect(throws: Never.self, "The example must parse: \(block)") {
				try parse(block)
			}
		}
	}

	@Test
	func `the edge service file`() throws {
		let value = try parse(exampleBlock(startingWith: "# The edge service"))
		#expect(value["name"] == "api-gateway")
		#expect(value["version"] == "2.1.0")
		#expect(value["pattern"] == #"^\d{4}-\d{2}-\d{2}$"#)
		#expect(value["windows-path"] == #"C:\Users\sindre\dev"#)
		#expect(value["content-security-policy"] == "default-src 'self'; script-src https://cdn.example.com")
		#expect(value["replicas"] == 3)
		#expect(value["timeout"] == .duration(.seconds(30)))
		#expect(value["drained"] == false)
		#expect(value["owner"] == .null)
		#expect(value["deployed-at"] == .instant(SOML.Instant(year: 2026, month: 9, day: 19, hour: 14)!))
		#expect(value["labels"] == ["prod", "eu-west", "canary"])
		#expect(value["description"] == "The API gateway terminates TLS.\nIt routes requests to internal services.\nIt has no external dependencies.")
		#expect(value["postgres"] == ["host": "db.internal", "port": 5432, "ssl": true])
	}

	@Test
	func `each JSON example holds the same data as the SOML example before it, apart from types JSON lacks`() throws {
		let pairs = try documentationText().jsonExamplePairs
		#expect(pairs.count >= 2)

		for (soml, json) in pairs {
			#expect(try parse(soml).asJSONData == SOML.Value(parsingJSON: json).asJSONData, "\(soml)")
		}
	}

	@Test
	func `the every-feature file`() throws {
		let value = try parse(exampleBlock(startingWith: "/*\nEverything SOML can express"))
		#expect(value["name"] == "soml")
		#expect(value["release-date"] == .instant(SOML.Instant("2026-09-19T14:00:00Z")!))
		#expect(value["the name"] == "quotes are the escape hatch, when a key needs spaces")
		#expect(value["404"] == "and a key may begin with a digit")
		#expect(value["regex"] == #"^\d{4}-\d{2}-\d{2}$"#)
		#expect(value["shell"] == #"echo "$HOME" | tr -d "\n""#)
		#expect(value["escaped"] == "line one\nline two\t\"quoted\"\u{1F600}")
		#expect(value["description"] == "A block string keeps its line breaks.\nThe leading tab of each line is stripped,\nbecause the closing delimiter sits at one tab.")
		#expect(value["replicas"] == 3)
		#expect(value["ratio"] == 0.75)
		#expect(value["budget"] == 1_000_000)
		#expect(value["mask"] == 0b1010_1100)
		#expect(value["permissions"] == 0o644)
		#expect(value["color"] == 0xFF8800)
		#expect(value["flags"] == 0x00FF)
		#expect(value["limit"] == .float(.infinity))
		#expect(value["floor"] == .float(-.infinity))
		#expect(value["drained"] == false)
		#expect(value["owner"] == .null)
		#expect(value["labels"] == ["prod", "eu-west", "canary"])
		#expect(value["matrix"] == [[1, 2], [3, 4]])
		#expect(value["mixed"] == [1, "two", true, nil])
		#expect(value["pool"] == ["min": 2, "max": 16])
		#expect(value["maintainers"] == [
			["name": "Sindre Sorhus", "email": "sindresorhus@gmail.com"],
			["name": "Random Person", "email": "person@example.com"],
		])
		#expect(value["retry-after"] == .duration(.seconds(90)))
		#expect(value["healthcheck"] == ["path": "/health", "interval": .duration(.seconds(10)), "grace": .duration(.milliseconds(1500))])
	}

	@Test
	func `member order is not significant`() throws {
		#expect(try parse("{a: 1, b: 2}") == parse("{b: 2, a: 1}"))
	}

	@Test
	func `the three document forms`() throws {
		#expect(try parse(exampleBlock(startingWith: "key: 'value'")) == ["key": "value"])
		#expect(try parse("{a: 1, b: 2}") == ["a": 1, "b": 2])
		#expect(try parse(exampleBlock(startingWith: "[1, 2, 3]")) == [1, 2, 3])
	}

	@Test
	func `the escape listing decodes`() throws {
		let listing = try exampleBlock(startingWith: "\\u{")
		let escapes = listing.split(separator: " ", omittingEmptySubsequences: true)
		let decoded = try escapes.map { try parseScalar("\"\($0)\"") }
		#expect(decoded == ["\u{0}", "\u{E9}", "\u{1F600}"])
	}

	@Test
	func `the canonical form of the every-feature file reads back as the same value`() throws {
		let value = try parse(exampleBlock(startingWith: "/*\nEverything SOML can express"))
		let text = try canonical(value)
		#expect(try parse(text) == value)
		#expect(try canonical(parse(text)) == text)
	}
}

/**
The Swift examples in this package's `readme.md` and in the doc comments of the sources, each run as written, with the output that the documentation shows.
*/
@Suite
struct CodeExampleTests {
	@Test
	func `the readme decode example`() throws {
		struct Config: Codable {
			let name: String
			let replicas: Int
			let timeout: Double
			let deployedAt: Date
			let labels: [String]
			let postgres: Postgres

			struct Postgres: Codable {
				let host: String
				let port: Int
			}
		}

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase

		let config = try decoder.decode(Config.self, from: readmeText)
		#expect(config.name == "api-gateway")
		#expect(config.replicas == 3)
		#expect(config.timeout == 30)
		#expect(config.deployedAt == Date(timeIntervalSince1970: 1_789_826_400))
		#expect(config.labels == ["prod", "eu-west"])
		#expect(config.postgres.host == "db.internal")
		#expect(config.postgres.port == 5432)
	}

	@Test
	func `the readme defaults example`() throws {
		struct Settings: Codable, Equatable {
			var host = "localhost"
			var port = 80
		}

		let settings = try SOML.Decoder().decode(from: "port: 8080", defaults: Settings())
		#expect(settings == Settings(host: "localhost", port: 8080))
	}

	@Test
	func `the readme value examples`() throws {
		var value = try SOML.Value(parsing: readmeText)
		#expect(value["postgres"]?["port"]?.intValue == 5432)
		#expect(value["labels"]?[0]?.stringValue == "prod")

		value["postgres"]?["port"] = 6543
		value["labels"]?[1] = nil
		#expect(value[path: ["postgres", "port"]] == .int(6543))
		#expect(value["labels"] == ["prod"])
	}

	@Test
	func `the merge example`() throws {
		let defaults = try SOML.Value(parsing: "server: {host: 'localhost', port: 80}\nlabels: ['default']")
		let user = try SOML.Value(parsing: "server: {port: 8080}\nlabels: ['prod']")

		let config = defaults.merging(user)
		#expect(config == ["server": ["host": "localhost", "port": 8080], "labels": ["prod"]])
	}

	@Test
	func `the differences examples`() throws {
		let old = try SOML.Value(parsing: "port: 80\nhosts: ['a', 'b']\ndebug: true")
		let new = try SOML.Value(parsing: "port: 8080\nhosts: ['a']\nname: 'api'")

		#expect(new.differences(from: old) == [
			.changed(from: 80, to: 8080, at: ["port"]),
			.removed("b", at: ["hosts", 1]),
			.removed(true, at: ["debug"]),
			.added("api", at: ["name"]),
		])

		var lines = [String]()

		for difference in new.differences(from: old) ?? [] {
			switch difference {
			case .added(let value, let path):
				lines.append("Added \(path): \(value)")
			case .removed(_, let path):
				lines.append("Removed \(path)")
			case .changed(let oldValue, let newValue, let path):
				lines.append("Changed \(path) from \(oldValue) to \(newValue)")
			}
		}

		#expect(lines == [
			"Changed port from 80 to 8080",
			"Removed hosts[1]",
			"Removed debug",
			"Added name: 'api'",
		])
	}

	@Test
	func `the JSON examples`() throws {
		let value = try SOML.Value(parsingJSON: #"{"port": 8080, "ratio": 1.0}"#)
		#expect(value == ["port": .int(8080), "ratio": .float(1.0)])
		#expect(try value.jsonText() == "{\n\t\"port\": 8080,\n\t\"ratio\": 1.0\n}\n")

		let durationValue: SOML.Value = ["timeout": .duration(.seconds(90)), "ports": [80, 443]]
		#expect(try durationValue.jsonText() == "{\n\t\"timeout\": \"1m30s\",\n\t\"ports\": [\n\t\t80,\n\t\t443\n\t]\n}\n")
	}

	@Test
	func `the single value and key path examples`() throws {
		#expect(try SOML.Value(parsingValue: "0o644") == .int(420))

		let path = try SOML.KeyPath(parsing: "servers[0].'the name'")
		#expect(path.segments == [.key("servers"), .index(0), .key("the name")])
		#expect(path.description == "servers[0].'the name'")

		#expect(SOML.KeyPath(["the name"]).description == "'the name'")
		#expect(SOML.KeyPath(["example.com", "port"]).description == "'example.com'.port")
		#expect(SOML.KeyPath(["server", "port"]).description == "server.port")
	}

	@Test
	func `the canonical form error example`() {
		let value: SOML.Value = ["limits": ["ratio": .float(.nan)]]

		#expect {
			try value.canonicalDocument()
		} throws: { error in
			"\(error)" == "NaN is not a SOML value (at limits.ratio)"
		}
	}

	@Test
	func `the readme format example`() throws {
		let document = try SOML.Document(parsing: """
			# The edge service.
			name:   'api-gateway'   # Shown in the dashboard.
			labels: ['prod',
			    'eu-west']



			postgres: {host: 'db.internal'}
			pool: {min: 2, max: 0x10 , idle: 90m} # Connections
			""")

		#expect(document.formatted() == """
			# The edge service.
			name: 'api-gateway' # Shown in the dashboard.
			labels: [
				'prod'
				'eu-west'
			]

			postgres: {host: 'db.internal'}
			pool: {min: 2, max: 0x10, idle: 90m} # Connections

			""")
	}

	@Test
	func `the document format example`() throws {
		let document = try SOML.Document(parsing: "pool: {\nmin: 2, max: 16} # Connections")
		#expect(document.formatted() == "pool: {\n\tmin: 2\n\tmax: 16\n} # Connections\n")
	}

	@Test
	func `the readme edit example`() throws {
		let document = try SOML.Document(parsing: """
			# The edge service.
			name: 'api'
			port: 0x1F90 # The default.
			""")

		let edited = try document
			.setting(8080, at: SOML.KeyPath(["port"]))
			.setting(["a", "b"], at: SOML.KeyPath(parsing: "tls.hosts"))
			.removing(at: SOML.KeyPath(["name"]))

		#expect(edited.text == """
			# The edge service.
			port: 8080 # The default.
			tls: {
				hosts: [
					'a'
					'b'
				]
			}
			""")
	}

	@Test
	func `the readme edit rules`() throws {
		#expect(try SOML.Document(parsing: "{a: 1}").setting([2, 3], at: ["b"]).text == "{a: 1, b: [2, 3]}")
		#expect(try SOML.Document(parsing: "a: [1, {}]").setting(2, at: ["a", 1, "b"]).text == "a: [1, {b: 2}]")
		#expect(try SOML.Document(parsing: "{a: 1, /* note */ b: 2}").removing(at: ["b"]).text == "{a: 1}")
		#expect(try SOML.Document(parsing: "{a: 1, b: 2}").removing(at: ["b"]).text == "{a: 1}")
		#expect(try SOML.Document(parsing: "a: 1 # note").removing(at: ["a"]).text == "{} # note")
		#expect(try SOML.Document(parsing: "a: [1, 2]").removing(at: ["a", 1]).text == "a: [1]")
		#expect(try SOML.Document(parsing: "a: [1, /* note */ 2]").removing(at: ["a", 1]).text == "a: [1]")
		#expect(try SOML.Document(parsing: "a: [1]").removing(at: ["a", 0]).text == "a: []")
		#expect(try SOML.Document(parsing: "a: [1, 2 /* note */]").setting(3, at: ["a", 2]).text == "a: [1, 2 /* note */, 3]")
	}

	@Test
	func `the updating examples`() throws {
		struct Service: Codable {
			var name: String
			var port: Int
		}

		let service = try SOML.Document(parsing: "name: 'api' # The service\nport: 0x50\n")
		let updated = try service.updating(as: Service.self) {
			$0.port = 8080
		}
		#expect(updated.text == "name: 'api' # The service\nport: 8080\n")

		let document = try SOML.Document(parsing: "name: 'api' # The service\nport: 80\n")
		let edited = try document.updating(as: Service.self) {
			$0.port = 8080
		}
		#expect(edited.text == "name: 'api' # The service\nport: 8080\n")
	}

	@Test
	func `the readme array item, value text, key, and comment example`() throws {
		let document = try SOML.Document(parsing: """
			servers: [
				{host: 'a'}, # Primary
				{host: 'b'},
			]
			mode: 420
			""")

		let edited = try document
			.setting("c", at: SOML.KeyPath(parsing: "servers[1].host"))
			.setting(["host": "d"], at: SOML.KeyPath(parsing: "servers[2]"))
			.removing(at: SOML.KeyPath(parsing: "servers[0]"))
			.setting(valueText: "0o644", at: SOML.KeyPath(["mode"]))
			.renamingKey(at: SOML.KeyPath(["mode"]), to: "permissions")
			.settingComment("Owner can write", at: SOML.KeyPath(["permissions"]))

		#expect(edited.text == """
			servers: [
				{host: 'c'},
				{
					host: 'd'
				}
			]
			permissions: 0o644 # Owner can write
			""")
	}

	@Test
	func `the editing doc comment examples`() throws {
		let port = try SOML.Document(parsing: "port: 80 # The default\n")
		#expect(try port.setting(8080, at: SOML.KeyPath(["port"])).text == "port: 8080 # The default\n")

		let mode = try SOML.Document(parsing: "mode: 420 # Permissions\n")
		#expect(try mode.setting(valueText: "0o644", at: SOML.KeyPath(["mode"])).text == "mode: 0o644 # Permissions\n")

		let missing = try SOML.Document(parsing: "port: 80\n")
		#expect(try missing.removing(at: SOML.KeyPath(["host"])).text == missing.text)

		let server = try SOML.Document(parsing: "server: {host: 'a'} # Primary\n")
		#expect(try server.renamingKey(at: SOML.KeyPath(["server", "host"]), to: "hostname").text == "server: {hostname: 'a'} # Primary\n")

		let comment = try SOML.Document(parsing: "port: 8080 # The default\n")
		#expect(try comment.settingComment("Set by the deploy script", at: SOML.KeyPath(["port"])).text == "port: 8080 # Set by the deploy script\n")
	}

	@Test
	func `the read comments examples`() throws {
		let document = try SOML.Document(parsing: """
			# How long to wait for the server.
			# Use 0s for no limit.
			timeout: 30s # The default
			""")

		let comments = document.comments(at: ["timeout"])
		#expect(comments?.leading == ["How long to wait for the server.", "Use 0s for no limit."])
		#expect(comments?.trailing == "The default")

		let port = try SOML.Document(parsing: "# The port to listen on.\n# Ports below 1024 need root.\nport: 8080 # The default\n")
		#expect(port.comments(at: ["port"])?.leading == ["The port to listen on.", "Ports below 1024 need root."])
		#expect(port.comments(at: ["port"])?.trailing == "The default")

		let array = try SOML.Document(parsing: "a: [1, /* a */ 2]")
		#expect(array.comments(at: ["a", 1])?.leading == [])
	}

	@Test
	func `the source range examples`() throws {
		let document = try SOML.Document(parsing: """
			name: 'api'
			server: {host: 'a', port: 0x50} # Connections
			""")

		#expect(document.range(of: ["server", "port"]).map { "\($0)" } == "line 2, column 21..<line 2, column 31")
		#expect(document.valueRange(of: ["server", "port"]).map { "\($0)" } == "line 2, column 27..<line 2, column 31")
		#expect(document.path(atOffset: 40)?.description == "server.port")

		let ports = try SOML.Document(parsing: "name: 'api'\nports: [80, 443]")
		#expect(ports.range(of: ["ports"]).map { "\($0)" } == "line 2, column 1..<line 2, column 17")
		#expect(ports.location(of: ["ports", 1]).description == "line 2, column 13")

		let port = try SOML.Document(parsing: "port: 0x1F90 # The default")
		#expect(port.valueRange(of: ["port"]).map { "\($0)" } == "line 1, column 7..<line 1, column 13")
		#expect(port.valueText(at: ["port"]) == "0x1F90")

		let server = try SOML.Document(parsing: "server: {host: 'a', port: 80}")
		#expect(server.path(atOffset: 27)?.description == "server.port")
	}

	@Test
	func `the parse error examples`() {
		#expect {
			_ = try SOML.Value(parsing: "a: 1\na: 2")
		} throws: { error in
			guard let error = error as? SOML.ParseError else {
				return false
			}

			return "\(error)" == "Duplicate key a (line 2, column 1)"
				&& error.location.description == "line 2, column 1"
				&& error.codeFrame == "  1 | a: 1\n> 2 | a: 2\n    | ^"
		}

		#expect {
			_ = try SOML.Value(parsing: "name: 'api'\nport: eighty")
		} throws: { error in
			(error as? SOML.ParseError)?.codeFrame == "  1 | name: 'api'\n> 2 | port: eighty\n    |       ^"
		}
	}

	@Test
	func `the decoding error location examples`() throws {
		struct Config: Decodable {
			let name: String
			let ports: [Int]
		}

		let document = try SOML.Document(parsing: "name: 'api'\nports: [80, 'eighty']")

		#expect {
			_ = try SOML.Decoder().decode(Config.self, from: document.value)
		} throws: { error in
			guard case DecodingError.typeMismatch(_, let context) = error else {
				return false
			}

			return document.location(of: context.codingPath).description == "line 2, column 13"
		}

		struct Deployment: Decodable {
			let name: String
			let deployedAt: Date
		}

		// The readme example, with a value that does not decode, so that the key strategy finds `deployed-at`.
		let deployment = try SOML.Document(parsing: "name: 'api'\ndeployed-at: 'soon'")
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase

		#expect {
			_ = try decoder.decode(Deployment.self, from: deployment.value)
		} throws: { error in
			guard case DecodingError.typeMismatch(_, let context) = error else {
				return false
			}

			let location = deployment.location(of: context.codingPath, keyDecodingStrategy: decoder.keyDecodingStrategy)
			return "The value at \(location) has the wrong type." == "The value at line 2, column 1 has the wrong type."
		}

		struct Service: Decodable {
			let name: String
			let replicas: Int
			let port: Int
		}

		#expect {
			_ = try SOML.Decoder().decode(Service.self, from: "name: 'api'\nreplicas: 3\nport: 'eighty'")
		} throws: { error in
			guard case DecodingError.typeMismatch(_, let context) = error else {
				return false
			}

			return context.debugDescription == "Expected an int for Int, but found the string 'eighty' (line 3, column 1)"
		}

		#expect {
			_ = try SOML.Decoder().decode(Service.self, from: "name: 'api'\nreplcas: 3\nport: 80")
		} throws: { error in
			guard case DecodingError.keyNotFound(_, let context) = error else {
				return false
			}

			return context.debugDescription == "No member with the key replicas. The document has replcas. Is it misspelled? (line 1, column 1)"
		}
	}

	@Test
	func `the error at a key path examples`() throws {
		let document = try SOML.Document(parsing: """
			server: {
				host: 'localhost'
				port: 0
			}
			""")

		let error = document.error("Port 0 is reserved", at: ["server", "port"])
		#expect("\(error)" == "Port 0 is reserved (line 3, column 2)")
		#expect(error.codeFrame == "  1 | server: {\n  2 | \thost: 'localhost'\n> 3 | \tport: 0\n    | \t^")

		let short = try SOML.Document(parsing: "server: {\n\thost: 'a'\n\tport: 0\n}")
		#expect("\(short.error("Port 0 is reserved", at: ["server", "port"]))" == "Port 0 is reserved (line 3, column 2)")
	}

	@Test
	func `the unknown key example`() {
		struct Options: Decodable {
			var timeout: Double?
		}

		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true

		#expect {
			try decoder.decode(Options.self, from: "timout: 30.0")
		} throws: { error in
			guard case DecodingError.dataCorrupted(let context) = error else {
				return false
			}

			return context.debugDescription == "Unknown key timout, which Options does not read. Did you mean timeout? (line 1, column 1)"
		}
	}

	@Test
	func `the type mapping examples`() throws {
		#expect(try SOML.Encoder().encodeToString(["date": Date(timeIntervalSince1970: 0.1)]) == "date: 1970-01-01T00:00:00.1Z\n")
		#expect(try SOML.Encoder().encodeToString(["duration": Duration.seconds(5400)]) == "duration: 1h30m\n")
		#expect(try SOML.Encoder().encodeToString(["duration": Duration.milliseconds(1500)]) == "duration: 1.5s\n")
		#expect(Duration.seconds(90).exactNanoseconds == 90_000_000_000)
	}

	@Test
	func `the tagged JSON infinity example`() throws {
		let value: SOML.Value = ["limit": .float(.infinity)]
		#expect(try value.jsonText(format: .tagged) == "{\n\t\"limit\": {\n\t\t\"type\": \"float\",\n\t\t\"value\": \"infinity\"\n\t}\n}\n")
	}

	@Test
	func `the encoder examples`() throws {
		struct Config: Encodable {
			let name: String
			let replicas: Int
			let labels: [String]
		}

		var encoder = SOML.Encoder()
		encoder.keyEncodingStrategy = .convertToKebabCase

		let text = try encoder.encodeToString(Config(name: "api-gateway", replicas: 3, labels: ["prod"]))
		#expect(text == """
			name: 'api-gateway'
			replicas: 3
			labels: [
				'prod'
			]

			""")

		var canonicalEncoder = SOML.Encoder()
		canonicalEncoder.writesCanonicalForm = true

		let canonicalText = try canonicalEncoder.encodeToString(Config(name: "api-gateway", replicas: 3, labels: ["prod"]))
		#expect(canonicalText == """
			labels: [
				'prod'
			]
			name: 'api-gateway'
			replicas: 3

			""")
	}

	@Test
	func `the decoder example`() throws {
		struct Config: Decodable {
			let name: String
			let replicas: Int
			let deployedAt: Date
		}

		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase

		let config = try decoder.decode(Config.self, from: """
			name: 'api-gateway'
			replicas: 3
			deployed-at: 2026-09-19T14:00:00Z
			""")

		#expect(config.name == "api-gateway")
		#expect(config.replicas == 3)
		#expect(config.deployedAt == Date(timeIntervalSince1970: 1_789_826_400))
	}

	@Test
	func `the value, object, and instant doc comment examples`() throws {
		let value = try SOML.Value(parsing: """
			name: 'api-gateway'
			replicas: 3
			""")
		#expect(String(describing: value["replicas"]?.intValue) == "Optional(3)")

		var servers = try SOML.Value(parsing: "servers: [{host: 'a', port: 80}]")
		#expect(servers[path: ["servers", 0, "port"]] == .int(80))
		servers[path: ["servers", 0, "port"]] = 8080
		#expect(servers[path: ["servers", 0, "port"]] == .int(8080))

		var postgres = try SOML.Value(parsing: "postgres: {port: 5432}")
		postgres["postgres"]?["port"] = 6543
		#expect(postgres == ["postgres": ["port": 6543]])

		var object: SOML.Object = ["name": "api-gateway", "replicas": 3]
		object["timeout"] = 30.0
		#expect(object.map { "\($0.key) \($0.value)" } == ["name 'api-gateway'", "replicas 3", "timeout 30.0"])

		let dictionary: [String: SOML.Value] = ["name": "api-gateway", "replicas": 3]
		let fromDictionary = SOML.Object(dictionary)
		#expect(SOML.Object(fromDictionary.filter { $0.key != "replicas" }) == ["name": "api-gateway"])

		let instant = try #require(SOML.Instant("2026-09-19T14:00:00.5+02:00"))
		#expect(instant.description == "2026-09-19T12:00:00.5Z")
		#expect(SOML.Instant(year: 2026, month: 9, day: 19, hour: 14) == SOML.Instant("2026-09-19T14:00:00Z"))
	}

	@Test
	func `the key conversion examples`() {
		#expect("myProperty".convertedFromCamelCase(separator: "-") == "my-property")
		#expect("baseURL".convertedFromCamelCase(separator: "-") == "base-url")
		#expect("myURLProperty".convertedFromCamelCase(separator: "-") == "my-url-property")
		#expect("isHTTP2Enabled".convertedFromCamelCase(separator: "-") == "is-http2-enabled")
		#expect("URL".convertedFromCamelCase(separator: "-") == "url")
		#expect("HTTPServer".convertedFromCamelCase(separator: "-") == "http-server")
	}
}

/**
The text of the decode example in the readme, which the examples after it there use too.
*/
private let readmeText = """
	# The edge service.
	name: 'api-gateway'
	replicas: 3
	timeout: 30.0
	deployed-at: 2026-09-19T14:00:00Z
	labels: ['prod', 'eu-west']
	postgres: {
		host: 'db.internal'
		port: 5432
	}
	"""

extension String {
	/**
	Each untagged code block that a `json` block directly follows, with that block. They hold the same data.
	*/
	fileprivate var jsonExamplePairs: [(soml: String, json: String)] {
		var blocks = [(tag: String, text: String)]()
		var current: (tag: String, lines: [Substring])?

		for line in split(separator: "\n", omittingEmptySubsequences: false) {
			guard line.hasPrefix("```") else {
				current?.lines.append(line)
				continue
			}

			if let block = current {
				blocks.append((block.tag, block.lines.joined(separator: "\n") + "\n"))
				current = nil
			} else {
				current = (line.dropFirst(3).trimmingCharacters(in: .whitespaces), [])
			}
		}

		return zip(blocks, blocks.dropFirst())
			.filter { $0.tag.isEmpty && $1.tag == "json" }
			.map { ($0.text, $1.text) }
	}
}

extension SOML.Value {
	/**
	The value as JSON holds it. JSON has no int, duration, or instant, so its files write a number, the seconds as a number, and a string.
	*/
	fileprivate var asJSONData: SOML.Value {
		switch self {
		case .int(let value):
			.float(Double(value))
		case .duration(let duration):
			.float(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
		case .instant(let instant):
			.string(instant.description)
		case .array(let items):
			.array(items.map(\.asJSONData))
		case .object(let object):
			.object(SOML.Object(object.map { ($0.key, $0.value.asJSONData) }))
		default:
			self
		}
	}
}

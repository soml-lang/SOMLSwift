import Testing
@testable import SOML

@Suite
struct UnknownKeyTests {
	struct Config: Decodable, Equatable {
		var name: String
		var replicas: Int
		var timeout: Double?
		var postgres: Postgres?
		var labels: [String: String]?
		var extra: SOML.Value?

		struct Postgres: Decodable, Equatable {
			var host: String
			var port: Int
		}
	}

	static let strict = {
		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true
		return decoder
	}()

	/**
	The context of the `DecodingError.dataCorrupted` that decoding throws.
	*/
	func errorContext<T: Decodable>(_ type: T.Type, _ source: String, decoder: SOML.Decoder = Self.strict, sourceLocation: SourceLocation = #_sourceLocation) throws -> DecodingError.Context {
		let error = try #require(throws: DecodingError.self, sourceLocation: sourceLocation) {
			try decoder.decode(type, from: source)
		}

		guard case .dataCorrupted(let context) = error else {
			Issue.record("Expected an unknown key error, got \(error)", sourceLocation: sourceLocation)
			throw error
		}

		return context
	}

	@Test
	func `unknown keys are ignored by default`() throws {
		#expect(try SOML.Decoder().decode(Config.self, from: "name: 'api'\nreplicas: 3\nreplcas: 4") == Config(name: "api", replicas: 3))
	}

	@Test
	func `a document with only known keys decodes`() throws {
		let source = "name: 'api'\nreplicas: 3\ntimeout: 1.5\npostgres: {host: 'db', port: 5432}"
		#expect(try Self.strict.decode(Config.self, from: source) == Config(name: "api", replicas: 3, timeout: 1.5, postgres: .init(host: "db", port: 5432)))
	}

	@Test
	func `an unknown key is an error that suggests a close key`() throws {
		let context = try errorContext(Config.self, "name: 'api'\nreplicas: 3\ntimout: 1.5")
		#expect(context.debugDescription == "Unknown key timout, which Config does not read. Did you mean timeout? (line 3, column 1)")
		#expect(context.codingPath.map(\.stringValue) == ["timout"])
	}

	@Test
	func `a long key is suggested in full, so that it can be written as suggested`() throws {
		struct Settings: Decodable {
			var maximumNumberOfConcurrentConnectionsPerHost: Int?
		}

		let context = try errorContext(Settings.self, "maximumNumberOfConcurrentConectionsPerHost: 5")
		#expect(context.debugDescription.hasSuffix(". Did you mean maximumNumberOfConcurrentConnectionsPerHost? (line 1, column 1)"), "Message was: \(context.debugDescription)")
	}

	@Test
	func `a key far from every known key gets no suggestion`() throws {
		let context = try errorContext(Config.self, "name: 'api'\nreplicas: 3\nlogging: true")
		#expect(context.debugDescription == "Unknown key logging, which Config does not read (line 3, column 1)")
	}

	@Test
	func `an object of a type that reads none of its members is checked too`() throws {
		struct Experimental: Decodable, Equatable {}

		struct Settings: Decodable, Equatable {
			var experimental: Experimental
			var optional: Experimental?
			var items: [Experimental]?
		}

		let member = try errorContext(Settings.self, "experimental: {fast-mode: true}")
		#expect(member.debugDescription == "Unknown key fast-mode, which Experimental does not read (line 1, column 16)")
		#expect(member.codingPath.map(\.stringValue) == ["experimental", "fast-mode"])

		// An optional names the type inside it.
		let optional = try errorContext(Settings.self, "experimental: {}\noptional: {a: 1}")
		#expect(optional.debugDescription == "Unknown key a, which Experimental does not read (line 2, column 12)")

		let item = try errorContext(Settings.self, "experimental: {}\nitems: [{}, {b: 1}]")
		#expect(item.codingPath.map(\.stringValue) == ["items", "1", "b"])

		let root = try errorContext(Experimental.self, "a: 1")
		#expect(root.debugDescription == "Unknown key a, which Experimental does not read (line 1, column 1)")

		#expect(try Self.strict.decode(Settings.self, from: "experimental: {}\noptional: null\nitems: [{}]") == Settings(experimental: .init(), items: [.init()]))
		#expect(try SOML.Decoder().decode(Settings.self, from: "experimental: {fast-mode: true}") == Settings(experimental: .init()))
	}

	@Test
	func `an object of a type that reads none of its members is checked with a key strategy and inside a dictionary`() throws {
		struct FeatureFlags: Decodable, Equatable {}

		struct Settings: Decodable, Equatable {
			var featureFlags: FeatureFlags
			var byName: [String: FeatureFlags]
		}

		var decoder = Self.strict
		decoder.keyDecodingStrategy = .convertFromKebabCase

		let member = try errorContext(Settings.self, "feature-flags: {fast-mode: true}\nby-name: {}", decoder: decoder)
		#expect(member.codingPath.map(\.stringValue) == ["featureFlags", "fast-mode"])
		#expect(member.debugDescription.hasSuffix("(line 1, column 17)"))

		let inDictionary = try errorContext(Settings.self, "feature-flags: {}\nby-name: {a: {}, b: {x: 1}}", decoder: decoder)
		#expect(inDictionary.codingPath.map(\.stringValue) == ["byName", "b", "x"])
		#expect(inDictionary.debugDescription.hasPrefix("Unknown key x, which FeatureFlags does not read"))

		#expect(try decoder.decode(Settings.self, from: "feature-flags: {}\nby-name: {a: {}}") == Settings(featureFlags: .init(), byName: ["a": .init()]))
	}

	@Test
	func `a key the document already has is not suggested`() throws {
		let context = try errorContext(Config.self, "name: 'api'\nreplicas: 3\nnames: 'x'")
		#expect(!context.debugDescription.contains("Did you mean"))
	}

	@Test
	func `unknown keys in nested objects and array items have their full coding path`() throws {
		let nested = try errorContext(Config.self, "name: 'api'\nreplicas: 3\npostgres: {host: 'db', port: 1, hots: 'x'}")
		#expect(nested.codingPath.map(\.stringValue) == ["postgres", "hots"])
		// “host” is in the document, so it is not suggested for “hots”.
		#expect(nested.debugDescription.hasSuffix("which Postgres does not read (line 3, column 33)"))

		let item = try errorContext([Config.Postgres].self, "[{host: 'a', port: 1}, {host: 'b', port: 2, x: 3}]")
		#expect(item.codingPath.map(\.stringValue) == ["1", "x"])
	}

	@Test
	func `dictionaries and SOML values take any keys, and the objects inside them are not checked`() throws {
		let source = "name: 'api'\nreplicas: 3\nlabels: {anything: 'x'}\nextra: {any: {deep: 1}}"
		#expect(try Self.strict.decode(Config.self, from: source).labels == ["anything": "x"])
	}

	@Test
	func `the objects inside a dictionary of structs are checked`() throws {
		let context = try errorContext([String: Config.Postgres].self, "primary: {host: 'a', port: 1, extra: 2}")
		#expect(context.codingPath.map(\.stringValue) == ["primary", "extra"])
	}

	@Test
	func `a key strategy reports the key as the document spells it`() throws {
		struct Server: Decodable {
			var maxConnections: Int?
		}

		var decoder = Self.strict
		decoder.keyDecodingStrategy = .convertFromKebabCase
		#expect(try decoder.decode(Server.self, from: "max-connections: 5").maxConnections == 5)

		let context = try errorContext(Server.self, "max-conections: 6", decoder: decoder)
		#expect(context.debugDescription == "Unknown key max-conections, which Server does not read. Did you mean max-connections? (line 1, column 1)")
	}

	enum Action: Decodable, Equatable {
		case move(x: Int)
		case stop
	}

	@Test
	func `a type that reads all keys, like an enum with associated values, decides for itself`() throws {
		#expect(try Self.strict.decode([Action].self, from: "[{move: {x: 1}}, {stop: {}}]") == [.move(x: 1), .stop])

		let context = try errorContext([Action].self, "[{move: {x: 1, y: 2}}]")
		#expect(context.codingPath.map(\.stringValue) == ["0", "move", "y"])
	}

	struct Flattened: Decodable {
		var host: String

		enum Keys: String, CodingKey {
			case server
			case host
		}

		init(from decoder: any Decoder) throws {
			let server = try decoder.container(keyedBy: Keys.self).nestedContainer(keyedBy: Keys.self, forKey: .server)
			self.host = try server.decode(String.self, forKey: .host)
		}
	}

	@Test
	func `a nested container that the type reads is checked too`() throws {
		#expect(try Self.strict.decode(Flattened.self, from: "server: {host: 'db'}").host == "db")

		let context = try errorContext(Flattened.self, "server: {host: 'db', port: 1}")
		#expect(context.codingPath.map(\.stringValue) == ["server", "port"])
	}

	struct Circle: Decodable {
		var type: String
		var radius: Double
	}

	struct Drawing: Decodable {
		var shape: Circle

		enum Keys: String, CodingKey {
			case shape
			case type
		}

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: Keys.self)
			_ = try container.nestedContainer(keyedBy: Keys.self, forKey: .shape).decode(String.self, forKey: .type)
			self.shape = try container.decode(Circle.self, forKey: .shape)
		}
	}

	@Test
	func `a nested container that peeks at a member and the type that decodes it share the known keys`() throws {
		#expect(try Self.strict.decode(Drawing.self, from: "shape: {type: 'circle', radius: 2.0}").shape.radius == 2)

		let context = try errorContext(Drawing.self, "shape: {type: 'circle', radius: 2.0, x: 1}")
		#expect(context.codingPath.map(\.stringValue) == ["shape", "x"])
		#expect(context.debugDescription == "Unknown key x, which Circle does not read (line 1, column 38)")
	}

	struct Inlined: Decodable {
		var name: String
		var server: Server

		struct Server: Decodable {
			var host: String
		}

		enum Keys: String, CodingKey {
			case name
		}

		init(from decoder: any Decoder) throws {
			self.name = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .name)
			self.server = try decoder.singleValueContainer().decode(Server.self)
		}
	}

	@Test
	func `two types that read one object through a single value container share the known keys`() throws {
		#expect(try Self.strict.decode(Inlined.self, from: "name: 'a'\nhost: 'b'").server.host == "b")

		let context = try errorContext(Inlined.self, "name: 'a'\nhost: 'b'\nport: 1")
		#expect(context.debugDescription == "Unknown key port, which Inlined does not read (line 3, column 1)")
	}

	struct WithExtras<Extras: Decodable>: Decodable {
		var name: String
		var extras: Extras

		private enum Keys: String, CodingKey {
			case name
		}

		init(from decoder: any Decoder) throws {
			self.name = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .name)
			self.extras = try decoder.singleValueContainer().decode(Extras.self)
		}
	}

	enum Setting: Decodable, Equatable {
		case server(Server)
		case raw(SOML.Value)

		struct Server: Decodable, Equatable {
			var host: String
		}

		init(from decoder: any Decoder) throws {
			if let server = try? Server(from: decoder) {
				self = .server(server)
			} else {
				self = .raw(try SOML.Value(from: decoder))
			}
		}
	}

	@Test(arguments: [SOML.Decoder.KeyDecodingStrategy.useDefaultKeys, .convertFromKebabCase])
	func `a type that also reads its object whole, as a value or a dictionary, takes any keys`(strategy: SOML.Decoder.KeyDecodingStrategy) throws {
		var decoder = Self.strict
		decoder.keyDecodingStrategy = strategy
		let source = "name: 'a'\nother: 1"
		#expect(try decoder.decode(WithExtras<SOML.Value>.self, from: source).extras == ["name": "a", "other": 1])
		#expect(try decoder.decode(WithExtras<SOML.Object>.self, from: source).extras.count == 2)
		#expect(try decoder.decode(WithExtras<[String: SOML.Value]>.self, from: source).extras.count == 2)
		#expect(try decoder.decode([String: Setting].self, from: "a: {port: 1}").values.first == .raw(["port": 1]))
	}

	struct WithServerAndExtras: Decodable {
		var mainServer: Setting.Server
		var extras: [String: SOML.Value]

		private enum Keys: String, CodingKey {
			case mainServer
		}

		init(from decoder: any Decoder) throws {
			self.mainServer = try decoder.container(keyedBy: Keys.self).decode(Setting.Server.self, forKey: .mainServer)
			self.extras = try decoder.singleValueContainer().decode([String: SOML.Value].self)
		}
	}

	@Test(arguments: [(SOML.Decoder.KeyDecodingStrategy.useDefaultKeys, "mainServer"), (.convertFromKebabCase, "main-server"), (.convertFromSnakeCase, "main_server")])
	func `an object under a converted key that is also read whole takes any keys`(strategy: SOML.Decoder.KeyDecodingStrategy, key: String) throws {
		var decoder = Self.strict
		decoder.keyDecodingStrategy = strategy
		let result = try decoder.decode(WithServerAndExtras.self, from: "\(key): {host: 'a', port: 80}")
		#expect(result.mainServer.host == "a")
		#expect(result.extras[key] == ["host": "a", "port": 80])
	}

	class Base: Decodable {
		var name: String

		private enum Keys: String, CodingKey {
			case name
		}

		required init(from decoder: any Decoder) throws {
			self.name = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .name)
		}
	}

	final class Derived: Base {
		var port: Int

		private enum Keys: String, CodingKey {
			case port
		}

		required init(from decoder: any Decoder) throws {
			self.port = try decoder.container(keyedBy: Keys.self).decode(Int.self, forKey: .port)
			try super.init(from: decoder)
		}
	}

	@Test
	func `a class and its superclass reading one object share the known keys`() throws {
		let value = try Self.strict.decode(Derived.self, from: "name: 'api'\nport: 80")
		#expect(value.name == "api")
		#expect(value.port == 80)

		let context = try errorContext(Derived.self, "name: 'api'\nport: 80\nhost: 'x'")
		#expect(context.codingPath.map(\.stringValue) == ["host"])
	}

	@Test
	func `a missing key names a close key that the document has, with or without the option`() throws {
		for decoder in [SOML.Decoder(), Self.strict] {
			do {
				_ = try decoder.decode(Config.Postgres.self, from: "hots: 'db'\nport: 1")
				Issue.record("Expected an error")
			} catch DecodingError.keyNotFound(_, let context) {
				#expect(context.debugDescription == "No member with the key host. The document has hots. Is it misspelled? (line 1, column 1)")
			}
		}

		do {
			_ = try SOML.Decoder().decode(Config.Postgres.self, from: "port: 1")
			Issue.record("Expected an error")
		} catch DecodingError.keyNotFound(_, let context) {
			#expect(context.debugDescription == "No member with the key host (line 1, column 1)")
		}
	}

	struct Hosts: Decodable {
		var hosts: [String]
		var host: String
	}

	struct HostFirst: Decodable {
		var host: String
		var hosts: [String]
	}

	struct Pool: Decodable {
		var maxConnections: Int
		var maxConnection: Int?
	}

	@Test
	func `a missing key does not name a key that the type reads as a misspelling`() throws {
		func message<T: Decodable>(_ type: T.Type, _ source: String, decoder: SOML.Decoder) throws -> String {
			let error = try #require(throws: DecodingError.self) {
				try decoder.decode(type, from: source)
			}

			guard case .keyNotFound(_, let context) = error else {
				Issue.record("Expected a missing key, got \(error)")
				return ""
			}

			return context.debugDescription
		}

		for decoder in [SOML.Decoder(), Self.strict] {
			#expect(try message(Hosts.self, "hosts: ['a']", decoder: decoder) == "No member with the key host (line 1, column 1)")
			#expect(try message(HostFirst.self, "hosts: ['a']", decoder: decoder) == "No member with the key host (line 1, column 1)")
		}

		var kebab = SOML.Decoder()
		kebab.keyDecodingStrategy = .convertFromKebabCase
		#expect(try message(Pool.self, "max-connection: 1", decoder: kebab) == "No member with the key max-connections (from the coding key “maxConnections”) (line 1, column 1)")

		// A key that the type reads only in another spelling is still a likely misspelling.
		#expect(try message(Pool.self, "maxConnections: 1", decoder: kebab) == "No member with the key max-connections (from the coding key “maxConnections”). The document has maxConnections. Is it misspelled? (line 1, column 1)")
	}

	/**
	A type that reads members with a coding key that accepts any string.
	*/
	struct Dynamic: Decodable {
		struct Key: CodingKey {
			var stringValue: String
			var intValue: Int? { nil }

			init(stringValue: String) {
				self.stringValue = stringValue
			}

			init?(intValue: Int) {
				nil
			}
		}

		var timeout: Int

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: Key.self)
			self.timeout = try container.decode(Int.self, forKey: Key(stringValue: "timeout"))
		}
	}

	@Test
	func `a missing key read with a coding key that accepts any string still gets a suggestion`() throws {
		for decoder in [SOML.Decoder(), Self.strict] {
			let error = try #require(throws: DecodingError.self) {
				try decoder.decode(Dynamic.self, from: "timout: 1")
			}

			guard case .keyNotFound(_, let context) = error else {
				Issue.record("Expected a missing key, got \(error)")
				continue
			}

			#expect(context.debugDescription == "No member with the key timeout. The document has timout. Is it misspelled? (line 1, column 1)")
		}
	}

	final class Named: Base {
		var port: Int

		private enum Keys: String, CodingKey {
			case port
		}

		required init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: Keys.self)
			self.port = try container.decode(Int.self, forKey: .port)
			try super.init(from: container.superDecoder())
		}
	}

	@Test
	func `the object a super decoder reads is checked too`() throws {
		#expect(try Self.strict.decode(Named.self, from: "port: 80\nsuper: {name: 'api'}").name == "api")

		let context = try errorContext(Named.self, "port: 80\nsuper: {name: 'api', x: 1}")
		#expect(context.codingPath.map(\.stringValue) == ["super", "x"])
	}

	struct LenientServer: Decodable {
		var server: Config.Postgres?

		private enum Keys: String, CodingKey {
			case server
		}

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: Keys.self)
			self.server = try? container.decode(Config.Postgres.self, forKey: .server)

			if server == nil {
				_ = try container.decodeIfPresent(SOML.Value.self, forKey: .server)
			}
		}
	}

	@Test
	func `a member that a try? gives up on is skipped by decoding it as a value`() throws {
		#expect(try Self.strict.decode(LenientServer.self, from: "server: {host: 1, port: 2}").server == nil)

		let context = try errorContext(LenientServer.self, "server: {host: 'a', port: 2, x: 3}")
		#expect(context.codingPath.map(\.stringValue) == ["server", "x"])
	}

	@Test
	func `suggestions handle empty keys scalar transpositions and the distance limit`() throws {
		struct RequestedKey: Decodable {
			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: SOMLCodingKey.self)
				let expected = try container.decode(String.self, forKey: SOMLCodingKey(stringValue: "expected"))
				_ = try container.decodeIfPresent(Int.self, forKey: SOMLCodingKey(stringValue: expected))
			}
		}

		let cases: [(unknown: String, expected: String, suggests: Bool)] = [
			("", "a", true),
			("a", "", true),
			("hots", "host", true),
			("timout", "timeout", true),
			("timeouts", "timeout", true),
			("écliar", "éclair", true),
			("e\u{301}", "é", false),
			(String(repeating: "a", count: 63) + "b", String(repeating: "a", count: 63) + "c", true),
			(String(repeating: "a", count: 62) + "bc", String(repeating: "a", count: 62) + "cb", true),
			(String(repeating: "x", count: 64), String(repeating: "x", count: 85), true),
			(String(repeating: "x", count: 64), String(repeating: "x", count: 86), false),
			(String(repeating: "x", count: 65), String(repeating: "x", count: 66), false),
		]

		for (unknown, expected, suggests) in cases {
			let value = SOML.Value.object(SOML.Object([("expected", .string(expected)), (unknown, .int(1))]))
			let context = try errorContext(RequestedKey.self, value.description)
			#expect(context.codingPath.count == 1)
			#expect(context.codingPath.last?.stringValue.hasSameScalars(as: unknown) == true)
			#expect(context.debugDescription.contains(". Did you mean ") == suggests)

			if suggests {
				#expect(context.debugDescription.contains(". Did you mean \(CanonicalWriter.key(expected))?"))
			}
		}
	}

}

@Suite
struct DefaultsTests {
	struct Config: Codable, Equatable {
		var host = "localhost"
		var maxConnections = 100
		var labels = ["default"]
		var tls = TLS()

		struct TLS: Codable, Equatable {
			var enabled = false
			var certificate: String?
		}
	}

	@Test
	func `a member that the document leaves out takes its default`() throws {
		var decoder = SOML.Decoder()
		decoder.keyDecodingStrategy = .convertFromKebabCase
		let config = try decoder.decode(from: "max-connections: 5\ntls: {certificate: 'a.pem'}\nlabels: ['prod']", defaults: Config())
		#expect(config == Config(host: "localhost", maxConnections: 5, labels: ["prod"], tls: .init(enabled: false, certificate: "a.pem")))
	}

	@Test
	func `an empty document gives the defaults, from text, bytes, or a value`() throws {
		let decoder = SOML.Decoder()
		#expect(try decoder.decode(from: "{}", defaults: Config()) == Config())
		#expect(try decoder.decode(from: Array("{}".utf8), defaults: Config()) == Config())
		#expect(try decoder.decode(from: SOML.Value.object([:]), defaults: Config()) == Config())
	}

	@Test
	func `an unknown key and a wrong type are still errors, at their place in the document`() throws {
		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true

		do {
			_ = try decoder.decode(from: "host: 'a'\nhots: 'b'", defaults: Config())
			Issue.record("Expected an error")
		} catch DecodingError.dataCorrupted(let context) {
			#expect(context.debugDescription == "Unknown key hots, which Config does not read (line 2, column 1)")
		}

		do {
			_ = try decoder.decode(from: "host: 'a'\ntls: {enabled: 'yes'}", defaults: Config())
			Issue.record("Expected an error")
		} catch DecodingError.typeMismatch(_, let context) {
			#expect(context.debugDescription.hasSuffix("(line 2, column 7)"))
		}
	}

	@Test
	func `an unknown key suggests a close key that the document leaves to the defaults`() throws {
		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true
		decoder.keyDecodingStrategy = .convertFromKebabCase

		func message(_ source: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> String {
			let error = try #require(throws: DecodingError.self, sourceLocation: sourceLocation) {
				try decoder.decode(from: source, defaults: Config())
			}

			guard case .dataCorrupted(let context) = error else {
				Issue.record("Expected an unknown key error, got \(error)", sourceLocation: sourceLocation)
				return ""
			}

			return context.debugDescription
		}

		#expect(try message("hots: 'b'") == "Unknown key hots, which Config does not read. Did you mean host? (line 1, column 1)")
		#expect(try message("max-conections: 5") == "Unknown key max-conections, which Config does not read. Did you mean max-connections? (line 1, column 1)")
		#expect(try message("tls: {enabld: true}") == "Unknown key enabld, which TLS does not read. Did you mean enabled? (line 1, column 7)")
		#expect(try message("tls: {certficate: 'a.pem'}") == "Unknown key certficate, which TLS does not read. Did you mean certificate? (line 1, column 7)")

		// A key that the document has is still not suggested.
		#expect(try message("host: 'a'\nhots: 'b'") == "Unknown key hots, which Config does not read (line 2, column 1)")
		#expect(try message("tls: {\n\tenabled: true\n\tenabld: true\n}") == "Unknown key enabld, which TLS does not read (line 3, column 2)")

		// The same from a value.
		let error = try #require(throws: DecodingError.self) {
			try decoder.decode(from: SOML.Value.object(["hots": "b"]), defaults: Config())
		}
		guard case .dataCorrupted(let context) = error else {
			Issue.record("Expected an unknown key error, got \(error)")
			return
		}
		#expect(context.debugDescription == "Unknown key hots, which Config does not read. Did you mean host?")
	}

	struct StrategySettings: Codable {
		var serverOptions = ServerOptions()
		var replicas = [Replica()]

		struct ServerOptions: Codable {
			var maxConnections = 100
			var timeout = 30.0
		}

		struct Replica: Codable {
			var host = "localhost"
			var port: Int?
		}
	}

	/**
	The message of the unknown key error for `source`, decoded over the defaults with the kebab-case strategy. It is a method of the suite rather than a function inside the test, because the compiler takes a do-catch in a function nested in a test for one where nothing throws.
	*/
	private func strategyMessage(_ source: String, sourceLocation: SourceLocation = #_sourceLocation) -> String {
		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true
		decoder.keyDecodingStrategy = .convertFromKebabCase

		do {
			_ = try decoder.decode(StrategySettings.self, from: source, defaults: StrategySettings())
			Issue.record("Expected an unknown key error", sourceLocation: sourceLocation)
			return ""
		} catch DecodingError.dataCorrupted(let context) {
			return context.debugDescription
		} catch {
			Issue.record("Expected an unknown key error, got \(error)", sourceLocation: sourceLocation)
			return ""
		}
	}

	@Test
	func `an unknown key suggests a close key with defaults in a nested object that the key strategy names`() {
		#expect(strategyMessage("server-options: {max-conections: 5}") == "Unknown key max-conections, which ServerOptions does not read. Did you mean max-connections? (line 1, column 18)")
		#expect(strategyMessage("server-options: {timeout: 1.0, timout: 2.0}") == "Unknown key timout, which ServerOptions does not read (line 1, column 32)")

		// An array in the document replaces the default one, so its items are found by their index.
		#expect(strategyMessage("replicas: [{host: 'a'}, {host: 'b', prot: 1}]") == "Unknown key prot, which Replica does not read. Did you mean port? (line 1, column 37)")
	}

	@Test
	func `an array in the document replaces the default one`() throws {
		struct Lists: Codable, Equatable {
			var labels = ["a", "b", "c"]
		}

		#expect(try SOML.Decoder().decode(from: "labels: ['z']", defaults: Lists()).labels == ["z"])
		#expect(try SOML.Decoder().decode(from: "labels: []", defaults: Lists()).labels == [])
	}

	@Test
	func `an enum without raw values does not decode after a merge, and a document cannot remove an entry from a default dictionary`() throws {
		enum Mode: Codable {
			case automatic
			case manual(speed: Int)
		}

		struct Settings: Codable {
			var mode = Mode.automatic
			var limits = ["a": 1, "b": 2]
		}

		#expect(throws: DecodingError.self) {
			try SOML.Decoder().decode(from: "mode: {manual: {speed: 2}}", defaults: Settings())
		}

		#expect(try SOML.Decoder().decode(from: "limits: {}", defaults: Settings()).limits == ["a": 1, "b": 2])
		#expect(try SOML.Decoder().decode(from: "limits: {c: 3}", defaults: Settings()).limits == ["a": 1, "b": 2, "c": 3])
	}

	@Test
	func `with unknown keys rejected, a member that the type encodes but does not decode is unknown`() {
		struct Versioned: Codable {
			// Encoded but not decoded, like a `let` constant with an initial value.
			let version: Int
			var name = "a"

			init() {
				version = 1
			}

			enum CodingKeys: CodingKey {
				case version
				case name
			}

			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				version = 1
				name = try container.decode(String.self, forKey: .name)
			}
		}

		var decoder = SOML.Decoder()
		decoder.rejectsUnknownKeys = true

		#expect {
			try decoder.decode(from: "name: 'b'", defaults: Versioned())
		} throws: { error in
			guard case DecodingError.dataCorrupted(let context) = error else {
				return false
			}

			return context.debugDescription == "Unknown key version, which Versioned does not read (line 1, column 1)"
		}
	}
}

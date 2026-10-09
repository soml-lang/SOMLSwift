import Testing
@testable import SOML

/**
The comments of the member or item at the key path written as `path`.
*/
private func comments(_ text: String, _ path: String) throws -> SOML.Document.Comments? {
	try SOML.Document(parsing: text).comments(at: SOML.KeyPath(parsing: path))
}

@Suite
struct DocumentCommentTests {
	@Test
	func `reads the comments above and at the end of the line`() throws {
		let text = "# The port to listen on.\n# Ports below 1024 need root.\nport: 8080 # The default\n"
		#expect(try comments(text, "port") == .init(leading: ["The port to listen on.", "Ports below 1024 need root."], trailing: "The default"))
	}

	@Test
	func `reads only the comments above`() throws {
		#expect(try comments("# Above\nport: 8080\n", "port") == .init(leading: ["Above"]))
	}

	@Test
	func `reads only the comment at the end of the line`() throws {
		#expect(try comments("name: 'a'\nport: 8080 # The default", "port") == .init(trailing: "The default"))
	}

	@Test
	func `a member without comments has none`() throws {
		#expect(try comments("name: 'a'\nport: 8080\n", "port") == .init())
	}

	@Test
	func `a blank line ends the comments above`() throws {
		#expect(try comments("# File header\n\n# Port\nport: 1", "port") == .init(leading: ["Port"]))
		#expect(try comments("# File header\n\nport: 1", "port") == .init())
	}

	@Test
	func `the comment at the end of the line before is not above`() throws {
		let text = "name: 'a' # The name\n# The port\nport: 1"
		#expect(try comments(text, "port") == .init(leading: ["The port"]))
		#expect(try comments(text, "name") == .init(trailing: "The name"))
		#expect(try comments("name: 'a' # The name\nport: 1", "port") == .init())
	}

	@Test
	func `reads the comments of a member in braces`() throws {
		let text = "server: { # The server\n\t# The host\n\thost: 'a', # Primary\n\tport: 1 # Default\n}"
		#expect(try comments(text, "server.host") == .init(leading: ["The host"], trailing: "Primary"))
		#expect(try comments(text, "server.port") == .init(trailing: "Default"))
	}

	@Test
	func `reads the comment after the closing brace of a member whose value spans lines`() throws {
		let text = "# The server\nserver: {\n\thost: 'a'\n} # Main\n"
		#expect(try comments(text, "server") == .init(leading: ["The server"], trailing: "Main"))
	}

	@Test
	func `members on one line have no comment at the end of the line, except the last`() throws {
		let text = "pool: {min: 2, max: 16} # Connections"
		#expect(try comments(text, "pool.min") == .init())
		#expect(try comments(text, "pool.max") == .init())
		#expect(try comments(text, "pool") == .init(trailing: "Connections"))
	}

	@Test
	func `reads the comments of a member whose key contains a dot`() throws {
		let text = "# Host\n'server.host': 'a' # Primary\n'server.port': 1"
		#expect(try comments(text, "'server.host'") == .init(leading: ["Host"], trailing: "Primary"))
		#expect(try comments(text, "'server.port'") == .init())
		#expect(try comments(text, "server") == nil)
	}

	@Test
	func `reads the comments of array items`() throws {
		let text = "ports: [\n\t# HTTP\n\t80, # Plain\n\t# HTTPS\n\t443 # Secure\n]"
		#expect(try comments(text, "ports[0]") == .init(leading: ["HTTP"], trailing: "Plain"))
		#expect(try comments(text, "ports[1]") == .init(leading: ["HTTPS"], trailing: "Secure"))
		#expect(try comments("[\n\t1 # One\n\t2\n]", "[0]") == .init(trailing: "One"))
	}

	@Test
	func `reads block comments above, on their own lines or before the member`() throws {
		#expect(try comments("/* The port */\nport: 1", "port") == .init(leading: ["The port"]))
		#expect(try comments("/* The port */ port: 1", "port") == .init(leading: ["The port"]))
		#expect(try comments("/**/ /* a */\n# b\nport: 1", "port") == .init(leading: ["", "a", "b"]))
	}

	@Test
	func `a block comment that spans lines keeps its line breaks`() throws {
		let text = "/*\n\tThe port.\n\tBelow 1024 needs root.\n*/\nport: 1"
		#expect(try comments(text, "port") == .init(leading: ["\n\tThe port.\n\tBelow 1024 needs root.\n"]))
	}

	@Test
	func `a block comment after the item before is not above`() throws {
		#expect(try comments("[1, /* a */ 2]", "[1]") == .init())
		#expect(try comments("[\n\t1, /* a */ /* b */\n\t2\n]", "[1]") == .init())
	}

	@Test
	func `a comment after an opening bracket on its line is not above`() throws {
		#expect(try comments("[/* a */ 1, 2]", "[0]") == .init())
		#expect(try comments("[ # a\n\t1\n]", "[0]") == .init())
	}

	@Test
	func `a block comment at the end of the line is not the comment at the end of the line`() throws {
		#expect(try comments("port: 1 /* note */", "port") == .init())
		#expect(try comments("port: 1 /* note */ # Default", "port") == .init(trailing: "Default"))
	}

	@Test
	func `a comment between a key and its value is in neither`() throws {
		let text = "a: # About a\n\t1\nb: 2"
		#expect(try comments(text, "a") == .init())
		#expect(try comments(text, "b") == .init())
	}

	@Test
	func `many block comments after an item on one long line take linear time`() throws {
		let text = "[\n" + String(repeating: " ", count: 100_000) + "0," + String(repeating: "/**/", count: 100_000) + "\n1]"
		let document = try SOML.Document(parsing: text)
		let clock = ContinuousClock()
		let duration = clock.measure {
			#expect(document.comments(at: [1]) == .init())
		}
		#expect(duration < .seconds(1))
	}

	@Test
	func `the text drops only one space`() throws {
		#expect(try comments("#  Two spaces\n#No space\nport: 1 #", "port") == .init(leading: [" Two spaces", "No space"], trailing: ""))
	}

	@Test
	func `nothing at the path has no comments`() throws {
		#expect(try comments("port: 1", "host") == nil)
		#expect(try comments("port: 1", "port.number") == nil)
		#expect(try comments("ports: [1]", "ports[1]") == nil)
		#expect(try comments("ports: [1]", "ports.first") == nil)
	}

	@Test
	func `reads back the comment that settingComment sets`() throws {
		let document = try SOML.Document(parsing: "# Above\nserver: {\n\tport: 1, /* note */\n}")

		for comment in ["The default", "", "  spaced  ", "has # and /* and */", "a\u{2028}b"] {
			let edited = try document.settingComment(comment, at: ["server", "port"])
			#expect(edited.comments(at: ["server", "port"])?.trailing == comment)
		}

		#expect(try document.settingComment(nil, at: ["server"]).comments(at: ["server"]) == .init(leading: ["Above"]))
	}
}

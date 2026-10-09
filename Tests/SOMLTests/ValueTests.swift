import Foundation
import Testing
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
@testable import SOML

@Suite
struct ValueTests {
	@Test
	func `literals`() {
		let value: SOML.Value = ["string": "x", "int": 1, "float": 1.5, "bool": true, "null": nil, "array": [1, "two"], "object": ["a": 1]]
		#expect(value["string"] == .string("x"))
		#expect(value["int"] == .int(1))
		#expect(value["float"] == .float(1.5))
		#expect(value["bool"] == .bool(true))
		#expect(value["null"] == .null)
		#expect(value["array"] == .array([.int(1), .string("two")]))
		#expect(value["object"] == .object(["a": .int(1)]))
	}

	@Test
	func `accessors`() throws {
		let instant = try #require(SOML.Instant("2026-09-19T14:00:00Z"))
		#expect(SOML.Value.string("x").stringValue == "x")
		#expect(SOML.Value.int(1).intValue == 1)
		#expect(SOML.Value.float(1.5).floatValue == 1.5)
		#expect(SOML.Value.bool(true).boolValue == true)
		#expect(SOML.Value.instant(instant).instantValue == instant)
		#expect(SOML.Value.duration(.seconds(90)).durationValue == .seconds(90))
		#expect(SOML.Value.array([1]).arrayValue == [1])
		#expect(SOML.Value.object(["a": 1]).objectValue == ["a": 1])
		#expect(SOML.Value.null.isNull)

		// An accessor for another type returns nil, and nothing is converted.
		#expect(SOML.Value.int(1).floatValue == nil)
		#expect(SOML.Value.float(1).intValue == nil)
		#expect(SOML.Value.string("1").intValue == nil)
		#expect(SOML.Value.int(1).stringValue == nil)
		#expect(SOML.Value.null.boolValue == nil)
		#expect(!SOML.Value.int(0).isNull)
		#expect(SOML.Value.array([]).objectValue == nil)
		#expect(SOML.Value.object([:]).arrayValue == nil)
		#expect(SOML.Value.string("x").instantValue == nil)
		#expect(SOML.Value.int(90).durationValue == nil)
	}

	@Test
	func `subscripts`() {
		let value: SOML.Value = ["a": ["b": [10, 20]]]
		#expect(value["a"]?["b"]?[1] == 20)
		#expect(value["a"]?["b"]?[2] == nil)
		#expect(value["a"]?["b"]?[-1] == nil)
		#expect(value["missing"] == nil)
		#expect(value[0] == nil)
		#expect(SOML.Value.int(1)["a"] == nil)
	}

	@Test
	func `subscripts change nested values in place`() throws {
		var value = try SOML.Value(parsing: "postgres: {host: 'db', port: 5432}\nlabels: ['prod', 'eu-west']")
		value["postgres"]?["port"] = 6543
		value["postgres"]?["user"] = "admin"
		value["postgres"]?["host"] = nil
		value["labels"]?[0] = "staging"
		value["labels"]?[1] = nil
		#expect(value == ["postgres": ["port": 6543, "user": "admin"], "labels": ["staging"]])
		#expect(value["postgres"]?.objectValue?.keys == ["port", "user"])
	}

	@Test(.timeLimit(.minutes(1)))
	func `changing a nested value does not copy the object around it`() {
		// With a copy per change, this takes minutes. In place, it takes well under a second.
		let count = 100_000
		var inner = SOML.Object()

		for index in 0..<count {
			inner["k\(index)"] = .int(Int64(index))
		}

		var value = SOML.Value.object(["outer": .object(inner)])
		var list = SOML.Value.array([.array(Array(repeating: .int(0), count: count))])

		for index in 0..<count {
			value["outer"]?["k\(index)"] = .int(0)
			list[0]?[index] = .int(1)
		}

		#expect(value["outer"]?["k\(count - 1)"] == 0)
		#expect(list[0]?[count - 1] == 1)
	}

	@Test
	func `setting through a subscript on the wrong type or out of range does nothing`() {
		var value: SOML.Value = ["a": 1, "list": [1]]
		value["a"]?["b"] = 2
		value["missing"]?["b"] = 2
		value["list"]?[5] = 2
		value["list"]?[-1] = 2
		value["a"]?[0] = 2
		#expect(value == ["a": 1, "list": [1]])

		var scalar = SOML.Value.int(1)
		scalar["a"] = 2
		scalar[0] = 2
		#expect(scalar == .int(1))
	}

	@Test
	func `equality follows the spec`() {
		#expect(SOML.Value.int(1) != .float(1))
		#expect(SOML.Value.float(0) == .float(-0.0))
		#expect(SOML.Value.string("\u{E9}") != .string("e\u{301}"))
		#expect(SOML.Value.string("a") == .string("a"))
		#expect(SOML.Value.object(["a": 1, "b": 2]) == .object(["b": 2, "a": 1]))
		#expect(SOML.Value.array([1, 2]) != .array([2, 1]))
		#expect(SOML.Value.null != .bool(false))
		#expect(SOML.Value.null != .array([]))
		#expect(SOML.Value.object([:]) != .array([]))
		#expect(SOML.Value.string("") != .null)
		#expect(SOML.Value.float(.infinity) == .float(.infinity))
		#expect(SOML.Value.float(.infinity) != .float(-.infinity))
	}

	@Test
	func `hashing agrees with equality`() {
		let pairs: [(SOML.Value, SOML.Value)] = [
			(.float(0), .float(-0.0)),
			(.object(["a": 1, "b": 2]), .object(["b": 2, "a": 1])),
			(.object(["a": ["x": 1, "y": 2]]), .object(["a": ["y": 2, "x": 1]])),
			(.instant(SOML.Instant("2026-09-19T14:00:00Z")!), .instant(SOML.Instant("2026-09-19T16:00:00+02:00")!)),
			(.duration(.seconds(5400)), .duration(.nanoseconds(5_400_000_000_000))),
		]

		for (lhs, rhs) in pairs {
			#expect(lhs == rhs)
			#expect(lhs.hashValue == rhs.hashValue)
		}

		let distinct: Set<SOML.Value> = [.int(1), .float(1), .string("1"), .bool(true), .null, .array([]), .object([:]), .string("\u{E9}"), .string("e\u{301}"), .duration(.nanoseconds(1)), .duration(.zero)]
		#expect(distinct.count == 11)
	}

	@Test
	func `strings that end at another place hash differently, whatever the seed`() {
		// Without a terminator after a string's bytes, the eight zero bytes of the next value's tag could stand in for the end of a string, so these collide for every seed, which lets untrusted input flood a set.
		let zeros = String(repeating: "\u{0}", count: 8)
		let pairs: [(SOML.Value, SOML.Value)] = [
			([.string("a" + zeros), "b"], ["a", .string(zeros + "b")]),
			([.string("a" + zeros), 1], ["a", .string(zeros), 1]),
			(.object(["a" + zeros: "b"]), .object(["a": .string(zeros + "b")])),
			(.object(["a": .object(["b" + zeros: 1])]), .object(["a": .object(["b": .object([zeros: 1])])])),
		]

		for (lhs, rhs) in pairs {
			#expect(lhs != rhs)
			#expect(lhs.hashValue != rhs.hashValue)
		}
	}

	@Test
	func `a value parses from the text of its description`() throws {
		let value: SOML.Value = ["a": [1, 2.5, "x", nil, true, ["b": []]]]
		#expect(try parse("a: \(value["a"]!.description)") == value)
	}

	#if canImport(UniformTypeIdentifiers)
	@Test
	func `the file type has the identifier from the spec`() {
		#expect(UTType.soml.identifier == "com.sindresorhus.soml")
	}
	#endif
}

@Suite
struct ObjectTests {
	@Test
	func `keeps insertion order`() {
		var object = SOML.Object()
		object["c"] = 1
		object["a"] = 2
		object["b"] = 3
		#expect(object.keys == ["c", "a", "b"])
		#expect(object.values == [1, 2, 3])
		#expect(object.map(\.key) == ["c", "a", "b"])
	}

	@Test
	func `keeps source order`() throws {
		let object = try #require(parse("z: 1\na: 2\nm: {x: 3}\nb: 4").objectValue)
		#expect(object.keys == ["z", "a", "m", "b"])
	}

	@Test
	func `replacing a value keeps its position`() {
		var object: SOML.Object = ["a": 1, "b": 2, "c": 3]
		object["b"] = 20
		#expect(object.keys == ["a", "b", "c"])
		#expect(object["b"] == 20)
	}

	@Test
	func `removing a value`() {
		var object: SOML.Object = ["a": 1, "b": 2, "c": 3, "d": 4]
		#expect(object.removeValue(forKey: "b") == 2)
		#expect(object.removeValue(forKey: "missing") == nil)
		#expect(object.keys == ["a", "c", "d"])
		#expect(object["c"] == 3)
		#expect(object["d"] == 4)
		object["c"] = nil
		#expect(object.keys == ["a", "d"])
		#expect(object["d"] == 4)
		object["a"] = 10
		#expect(object.keys == ["a", "d"])
		object["e"] = 5
		#expect(object.keys == ["a", "d", "e"])
		#expect(object.count == 3)
	}

	@Test
	func `removing every value`() {
		var object: SOML.Object = ["a": 1, "b": 2]
		object["a"] = nil
		object["b"] = nil
		#expect(object.isEmpty)
		#expect(object == [:])
	}

	@Test
	func `keys are exact`() {
		var object = SOML.Object()
		object["\u{E9}"] = 1
		object["e\u{301}"] = 2
		#expect(object.count == 2)
		#expect(object["\u{E9}"] == 1)
		#expect(object["e\u{301}"] == 2)
		object["\u{E9}"] = nil
		#expect(object.keys == ["e\u{301}"])
	}

	@Test
	func `duplicate keys in an initializer keep the last value at the first position`() {
		let object = SOML.Object([("a", 1), ("b", 2), ("a", 3)])
		#expect(object.keys == ["a", "b"])
		#expect(object["a"] == 3)
	}

	@Test
	func `an object can be made from a dictionary or a filtered object`() {
		let dictionary: [String: SOML.Value] = ["name": "api-gateway", "replicas": 3]
		let object = SOML.Object(dictionary)
		#expect(object == ["name": "api-gateway", "replicas": 3])

		let filtered = SOML.Object(object.filter { $0.key != "replicas" })
		#expect(filtered == ["name": "api-gateway"])
	}

	@Test
	func `equality ignores order`() {
		let first: SOML.Object = ["a": 1, "b": 2]
		let second: SOML.Object = ["b": 2, "a": 1]
		let third: SOML.Object = ["a": 1, "b": 3]
		let fourth: SOML.Object = ["a": 1]
		#expect(first == second)
		#expect(first.hashValue == second.hashValue)
		#expect(first != third)
		#expect(first != fourth)
		#expect(fourth != first)
	}

	@Test
	func `collection conformance`() {
		let object: SOML.Object = ["a": 1, "b": 2]
		#expect(object.count == 2)
		#expect(object.first?.key == "a")
		#expect(object[object.startIndex].value == 1)
		#expect(Array(object.reversed().map(\.key)) == ["b", "a"])
	}
}

/**
Builds random values, for property tests.
*/
struct ValueGenerator {
	var random: SeededGenerator

	init(seed: UInt64) {
		self.random = SeededGenerator(seed: seed)
	}

	private static let alphabet: [String] = ["a", "b", "z", "A", "0", "9", "-", "_", " ", ".", "'", "\"", "\\", "\n", "\t", "#", "/", "*", ":", ",", "{", "}", "[", "]", "é", "e\u{301}", "日", "😀", "\u{0}", "\u{1}", "\u{1F}", "\u{7F}", "\u{A0}", "\u{2028}", "\u{FEFF}", "\u{FFFE}", "\u{10FFFF}"]

	mutating func string(maximumLength: Int = 12) -> String {
		let length = Int.random(in: 0...maximumLength, using: &random)
		return (0..<length).map { _ in Self.alphabet.randomElement(using: &random)! }.joined()
	}

	mutating func key() -> String {
		switch Int.random(in: 0..<4, using: &random) {
		case 0:
			["a", "name", "content-type", "404", "-", "_x", "true", "2024-01-01"].randomElement(using: &random)!
		default:
			// A key may hold any string, including a line break.
			string(maximumLength: 6)
		}
	}

	mutating func float() -> Double {
		switch Int.random(in: 0..<6, using: &random) {
		case 0:
			[0, 1, -1, 0.5, .infinity, -.infinity, .greatestFiniteMagnitude, .leastNonzeroMagnitude, 1e21, 1e-7].randomElement(using: &random)!
		case 1:
			Double(Int.random(in: -1000...1000, using: &random))
		case 2:
			Double.random(in: -1...1, using: &random)
		default:
			// Any finite bit pattern.
			finiteBitPattern()
		}
	}

	private mutating func finiteBitPattern() -> Double {
		while true {
			let value = Double(bitPattern: random.next())

			if value.isFinite {
				return value
			}
		}
	}

	mutating func instant() -> SOML.Instant {
		let seconds = Int64.random(in: SOML.Instant.minimum.secondsSince1970...SOML.Instant.maximum.secondsSince1970, using: &random)
		let nanoseconds = Bool.random(using: &random) ? 0 : Int.random(in: 0..<1_000_000_000, using: &random)
		return SOML.Instant(secondsSince1970: seconds, nanoseconds: nanoseconds)!
	}

	mutating func scalar() -> SOML.Value {
		switch Int.random(in: 0..<8, using: &random) {
		case 0:
			.string(string())
		case 1:
			.int([0, 1, -1, .max, .min, Int64.random(in: .min ... .max, using: &random)].randomElement(using: &random)!)
		case 2:
			.float(float())
		case 3:
			.bool(Bool.random(using: &random))
		case 4:
			.null
		case 5:
			.instant(instant())
		case 6:
			.duration(.nanoseconds([0, 1, -1, .max, .min, Int64.random(in: .min ... .max, using: &random)].randomElement(using: &random)!))
		default:
			.int(Int64.random(in: -100...100, using: &random))
		}
	}

	mutating func value(depth: Int) -> SOML.Value {
		guard
			depth > 0,
			Int.random(in: 0..<3, using: &random) == 0
		else {
			return scalar()
		}

		return Bool.random(using: &random) ? .array(array(depth: depth)) : .object(object(depth: depth))
	}

	mutating func array(depth: Int) -> [SOML.Value] {
		(0..<Int.random(in: 0...4, using: &random)).map { _ in value(depth: depth - 1) }
	}

	mutating func object(depth: Int) -> SOML.Object {
		var object = SOML.Object()

		for _ in 0..<Int.random(in: 0...4, using: &random) {
			object[key()] = value(depth: depth - 1)
		}

		return object
	}

	mutating func document(depth: Int) -> SOML.Value {
		Bool.random(using: &random) ? .object(object(depth: depth)) : .array(array(depth: depth))
	}
}

@Suite
struct RoundTripTests {
	@Test(arguments: 0..<20)
	func `a random value reads back from its canonical form, which is stable`(_ seed: Int) throws {
		var generator = ValueGenerator(seed: UInt64(seed))

		for _ in 0..<100 {
			let value = generator.document(depth: 5)
			let text = try canonical(value)
			let parsed = try parse(text)
			#expect(parsed == value, "\(text)")
			#expect(try canonical(parsed) == text)
		}
	}

	@Test(arguments: 0..<10)
	func `a random value round-trips through the coders`(_ seed: Int) throws {
		var generator = ValueGenerator(seed: UInt64(1000 + seed))

		for _ in 0..<100 {
			let value = generator.document(depth: 4)
			let data = try SOML.Encoder().encode(value)
			#expect(try SOML.Decoder().decode(SOML.Value.self, from: data) == value)
		}
	}

	@Test
	func `a random document written in other spellings has the same canonical form`() throws {
		var generator = ValueGenerator(seed: 99)

		for _ in 0..<300 {
			let value = generator.document(depth: 4)
			var respeller = Respeller(seed: generator.random.next())
			let respelled = respeller.document(value)
			let parsed: SOML.Value

			do {
				parsed = try parse(respelled)
			} catch {
				Issue.record("\(error)\n\(respelled)")
				continue
			}

			#expect(parsed == value, "\(respelled)")
			#expect(try canonical(parsed) == canonical(value))
		}
	}
}

/**
Writes a value in randomly chosen non-canonical spellings: other quotes, escapes, radixes, underscores, offsets, comments, and layouts.
*/
private struct Respeller {
	var random: SeededGenerator

	init(seed: UInt64) {
		self.random = SeededGenerator(seed: seed)
	}

	mutating func document(_ value: SOML.Value) -> String {
		var text = comment() + "\n"

		if
			case .object(let object) = value,
			!object.isEmpty,
			Bool.random(using: &random)
		{
			for (key, value) in object.shuffled(using: &random) {
				text += "\(self.key(key)):\(space())\(self.value(value))\(comment())\n"
			}

			return text
		}

		return text + self.value(value) + "\n"
	}

	private mutating func space() -> String {
		["", " ", "  ", "\t", " /* x */ ", "\n\t"].randomElement(using: &random)!
	}

	private mutating func comment() -> String {
		["", " # note", " /* note */"].randomElement(using: &random)!
	}

	private mutating func key(_ key: String) -> String {
		if
			!key.isEmpty,
			key.utf8.allSatisfy(\.isBareKeyByte),
			Bool.random(using: &random)
		{
			return key
		}

		return escapedString(key)
	}

	private mutating func value(_ value: SOML.Value) -> String {
		switch value {
		case .string(let string):
			self.string(string)
		case .int(let int):
			integer(int)
		case .float(let float):
			self.float(float)
		case .bool(let bool):
			bool ? "true" : "false"
		case .null:
			"null"
		case .instant(let instant):
			self.instant(instant)
		case .duration(let duration):
			self.duration(duration)
		case .array(let items):
			"[" + items.map { "\(space())\(self.value($0))" }.joined(separator: ",") + (Bool.random(using: &random) && !items.isEmpty ? "," : "") + "\(space())]"
		case .object(let object):
			"{" + object.shuffled(using: &random).map { "\(space())\(key($0.key)):\(space())\(self.value($0.value))" }.joined(separator: ",") + (Bool.random(using: &random) && !object.isEmpty ? "," : "") + "\(space())}"
		}
	}

	private mutating func string(_ string: String) -> String {
		// A literal string cannot hold a `'`, a line break, or a raw control character other than tab.
		let canUseLiteral = !string.unicodeScalars.contains { $0 == "'" || $0 == "\n" || ($0.value < 0x20 && $0 != "\t") || $0.value == 0x7F }

		if
			canUseLiteral,
			Bool.random(using: &random)
		{
			return "'\(string)'"
		}

		return escapedString(string)
	}

	private mutating func escapedString(_ string: String) -> String {
		var text = "\""

		for scalar in string.unicodeScalars {
			switch scalar {
			case "\\":
				text += "\\\\"
			case "\"":
				text += "\\\""
			case "\n":
				text += "\\n"
			case "\t":
				text += Bool.random(using: &random) ? "\\t" : "\t"
			case _ where scalar.value < 0x20 || scalar.value == 0x7F:
				text += "\\u{\(String(scalar.value, radix: 16))}"
			default:
				text += Int.random(in: 0..<4, using: &random) == 0 ? "\\u{\(String(scalar.value, radix: 16))}" : String(scalar)
			}
		}

		return text + "\""
	}

	private mutating func integer(_ value: Int64) -> String {
		guard value >= 0 else {
			return String(value)
		}

		switch Int.random(in: 0..<5, using: &random) {
		case 0:
			return "0x" + String(repeating: "0", count: Int.random(in: 0...2, using: &random)) + String(value, radix: 16, uppercase: true)
		case 1:
			return "0o" + String(value, radix: 8)
		case 2:
			return "0b" + String(value, radix: 2)
		case 3:
			// Underscores between digits.
			return String(value).map(String.init).joined(separator: Bool.random(using: &random) ? "_" : "")
		default:
			return String(value)
		}
	}

	private mutating func float(_ value: Double) -> String {
		if value.isInfinite {
			return value < 0 ? "-infinity" : "infinity"
		}

		// Swift's own spelling, adjusted to SOML: no "+" and no leading zero in the exponent (Swift writes at least two exponent digits, like `1e-07`), and a fraction or an exponent so it stays a float.
		var text = value.description
			.replacing("e+", with: "e")
			.replacing("e-0", with: "e-")
			.replacing("e0", with: "e")

		if
			!text.contains("."),
			!text.contains("e")
		{
			text += ".0"
		}

		if
			value == 0,
			Bool.random(using: &random)
		{
			return "-0.0"
		}

		return text
	}

	/**
	Each unit takes its share of the duration or leaves it to the smaller units, and a zero part may be written, so 1h30m can be 90m, 5400s, or 1h30m0s. The last part may instead take the rest as a fraction with trailing zeros, like 1h1800.000000000000s.
	*/
	private mutating func duration(_ duration: Duration) -> String {
		let nanoseconds = duration.exactNanoseconds!
		var remaining = nanoseconds.magnitude
		var text = nanoseconds < 0 ? "-" : ""
		var hasPart = false

		for (index, (symbol, length)) in Duration.somlUnits.enumerated() {
			// The seconds, milliseconds, or microseconds take the rest, with every nanosecond in the fraction.
			if
				(2...4).contains(index),
				Int.random(in: 0..<6, using: &random) == 0
			{
				let fractionDigits = String(remaining % length)
				let paddedFraction = String(repeating: "0", count: String(length).count - 1 - fractionDigits.count) + fractionDigits
				return text + String(remaining / length) + "." + paddedFraction + String(repeating: "0", count: Int.random(in: 0...12, using: &random)) + symbol
			}

			let isLast = index == Duration.somlUnits.count - 1

			guard isLast || Bool.random(using: &random) else {
				continue
			}

			let count = remaining / length
			remaining %= length

			guard count > 0 || Int.random(in: 0..<4, using: &random) == 0 || (isLast && !hasPart) else {
				continue
			}

			hasPart = true
			text += String(count).map(String.init).joined(separator: Bool.random(using: &random) ? "_" : "") + symbol
		}

		return text
	}

	private mutating func instant(_ instant: SOML.Instant) -> String {
		let offsetMinutes = Int.random(in: -(23 * 60 + 59)...(23 * 60 + 59), using: &random)

		// Shift the local time by the offset, unless that leaves the range.
		guard
			offsetMinutes != 0,
			let local = SOML.Instant(secondsSince1970: instant.secondsSince1970 + Int64(offsetMinutes * 60), nanoseconds: instant.nanoseconds)
		else {
			return instant.description
		}

		var text = String(local.description.dropLast())

		if
			instant.nanoseconds == 0,
			Bool.random(using: &random)
		{
			text += ".000"
		}

		let sign = offsetMinutes < 0 ? "-" : "+"
		let hours = abs(offsetMinutes) / 60
		let minutes = abs(offsetMinutes) % 60
		return text + sign + (hours < 10 ? "0" : "") + String(hours) + ":" + (minutes < 10 ? "0" : "") + String(minutes)
	}
}

@Suite
struct LargeObjectTests {
	@Test
	func `an object past the index threshold behaves the same`() {
		var object = SOML.Object()

		for index in 0..<100 {
			object["key\(index)"] = .int(Int64(index))
		}

		#expect(object.count == 100)
		#expect(object["key0"] == 0)
		#expect(object["key99"] == 99)
		#expect(object["key100"] == nil)

		object["key50"] = "replaced"
		#expect(object["key50"] == "replaced")
		#expect(object.keys[50] == "key50")

		#expect(object.removeValue(forKey: "key10") == 10)
		#expect(object["key10"] == nil)
		#expect(object["key11"] == 11)
		#expect(object.keys[10] == "key11")

		// Shrink below the threshold, so lookups go back to a linear search.
		for index in 0..<100 where index != 10 {
			#expect(object.removeValue(forKey: "key\(index)") != nil)

			if index == 95 {
				#expect(object.keys == ["key96", "key97", "key98", "key99"])
				#expect(object["key97"] == 97)
			}
		}

		#expect(object.isEmpty)
	}

	@Test
	func `exact keys past the index threshold`() {
		var object = SOML.Object()

		for index in 0..<40 {
			object["k\(index)"] = .int(Int64(index))
		}

		object["\u{E9}"] = 1
		object["e\u{301}"] = 2
		#expect(object.count == 42)
		#expect(object["\u{E9}"] == 1)
		#expect(object["e\u{301}"] == 2)
	}

	@Test
	func `a large parsed object`() throws {
		let source = (0..<500).reversed().map { "k\($0): \($0)" }.joined(separator: "\n")
		let object = try #require(parse(source).objectValue)
		#expect(object.count == 500)
		#expect(object["k250"] == 250)
		expectRejected(source + "\nk250: 1", "Duplicate key k250")
		let keys = try #require(parse(canonical(.object(object))).objectValue?.keys)
		#expect(zip(keys, keys.dropFirst()).allSatisfy { $0.utf8.lexicographicallyPrecedes($1.utf8) })
	}

	@Test
	func `random changes to an object agree with a list of pairs, also for keys that start the same`() {
		// A search compares the length and the first seven bytes of the keys first, so many keys share both, and the object grows past the index threshold and shrinks below it.
		let keys = ["", "a", "abcdefg", "abcdefgh", "abcdefgi", "abcdefgé", "abcdefge\u{301}", "\u{E9}", "e\u{301}", String(repeating: "x", count: 300) + "1", String(repeating: "x", count: 300) + "2", String(repeating: "x", count: 301)] + (0..<40).map { "abcdefg\($0)" }
		var generator = SeededGenerator(seed: 7)
		var object = SOML.Object()
		var pairs = [(key: String, value: SOML.Value)]()
		var counts = Set<Int>()

		for step in 0..<20_000 {
			let key = keys[Int.random(in: keys.indices, using: &generator)]
			let position = pairs.firstIndex { $0.key.unicodeScalars.elementsEqual(key.unicodeScalars) }

			// Two sets for each removal keep about two thirds of the keys, around the index threshold of 32.
			if Int.random(in: 0..<3, using: &generator) > 0 {
				object[key] = .int(Int64(step))

				if let position {
					pairs[position].value = .int(Int64(step))
				} else {
					pairs.append((key, .int(Int64(step))))
				}
			} else {
				#expect(object.removeValue(forKey: key) == position.map { pairs.remove(at: $0).value })
			}

			#expect(object[key] == pairs.first { $0.key.unicodeScalars.elementsEqual(key.unicodeScalars) }?.value)
			counts.insert(object.count)
		}

		#expect(counts.contains(20) && counts.contains(45), "The object did not cross the index threshold both ways")

		#expect(object.keys == pairs.map(\.key))
		#expect(object.values == pairs.map(\.value))

		for key in keys {
			#expect(object[key] == pairs.first { $0.key.unicodeScalars.elementsEqual(key.unicodeScalars) }?.value, "\(key)")
		}
	}

	@Test
	func `removing every member from the end of a large object takes linear time`() {
		func object(size: Int) -> SOML.Object {
			SOML.Object((0..<size).map { ("key\($0)", SOML.Value.int(Int64($0))) })
		}

		func removeAll(_ object: SOML.Object) -> SOML.Object {
			var object = object

			for index in (0..<object.count).reversed() {
				object.removeValue(forKey: "key\(index)")
			}

			return object
		}

		let small = object(size: 1000)
		let large = object(size: 16_000)
		#expect(removeAll(large).isEmpty)

		expectLinearTime {
			_ = removeAll(small)
		} large: {
			_ = removeAll(large)
		}
	}

	// Only Apple platforms bridge an `NSString` lazily. Elsewhere it becomes a native string.
	#if canImport(ObjectiveC)
	@Test(arguments: [4, 40])
	func `a bridged key finds the member of a native key with the same scalars, below and past the index threshold`(count: Int) throws {
		// A key from Foundation stored as UTF-16 has no contiguous UTF-8, so its fingerprint and its comparison read a copy.
		func bridged(_ string: String) -> String {
			let units = Array(string.utf16)
			return NSString(characters: units, length: units.count) as String
		}

		let bridgedKey = bridged("abcdefgé\u{1F600}")
		try #require(bridgedKey.utf8.withContiguousStorageIfAvailable { _ in true } == nil)

		var object = SOML.Object()

		for index in 0..<count {
			object["abcdefg\(index)"] = .int(Int64(index))
		}

		object[bridgedKey] = "bridged"
		object["abcdefge\u{301}\u{1F600}"] = "decomposed"
		object[bridged("")] = "empty"

		#expect(object["abcdefgé\u{1F600}"] == "bridged")
		#expect(object[bridged("abcdefge\u{301}\u{1F600}")] == "decomposed")
		#expect(object[""] == "empty")
		#expect(object.count == count + 3)

		object["abcdefgé\u{1F600}"] = "native"
		#expect(object[bridgedKey] == "native")
		#expect(object.count == count + 3)
		#expect(object.removeValue(forKey: bridged("abcdefg0")) == 0)
		#expect(object["abcdefg0"] == nil)
	}
	#endif

	@Test
	func `a document with keys that start the same parses each key, and finds a duplicate`() throws {
		let keys = (0..<20).map { "'abcdefg\($0)'" } + ["'abcdefgé'", "'abcdefge\u{301}'"]
		let object = try #require(parse(keys.enumerated().map { "\($1): \($0)" }.joined(separator: "\n")).objectValue)
		#expect(object.count == keys.count)
		#expect(object["abcdefge\u{301}"] == 21)
		expectRejected("abcdefgh: 1\nabcdefgi: 2\nabcdefgh: 3", "Duplicate key abcdefgh")
	}

	@Test
	func `equality and hashing of large objects ignore order`() {
		let pairs = (0..<50).map { ("key\($0)", SOML.Value.int(Int64($0))) }
		let first = SOML.Object(pairs)
		let second = SOML.Object(pairs.reversed())
		#expect(first == second)
		#expect(first.hashValue == second.hashValue)
	}
}

@Suite
struct MergeTests {
	@Test
	func `objects merge recursively, and other values replace`() throws {
		let defaults = try SOML.Value(parsing: "server: {host: 'localhost', port: 80, tls: {enabled: false}}\nlabels: ['default']\nowner: 'ops'")
		let user = try SOML.Value(parsing: "server: {port: 8080, tls: {enabled: true}}\nlabels: ['prod']\nowner: null\nextra: 1")
		let merged = defaults.merging(user)
		#expect(merged == ["server": ["host": "localhost", "port": 8080, "tls": ["enabled": true]], "labels": ["prod"], "owner": nil, "extra": 1])
		#expect(merged.objectValue?.keys == ["server", "labels", "owner", "extra"])
		#expect(merged["server"]?.objectValue?.keys == ["host", "port", "tls"])
	}

	@Test
	func `a value that is not an object replaces an object, and an object replaces a value that is not one`() {
		#expect((["a": ["b": 1]] as SOML.Value).merging(["a": 2]) == ["a": 2])
		#expect((["a": 2] as SOML.Value).merging(["a": ["b": 1]]) == ["a": ["b": 1]])
		#expect(SOML.Value.int(1).merging(["a": 1]) == ["a": 1])
		#expect((["a": 1] as SOML.Value).merging([1, 2]) == [1, 2])
	}

	@Test
	func `merging with an empty object changes nothing`() throws {
		let value = try SOML.Value(parsing: "a: {b: [1, 2], c: 'x'}")
		#expect(value.merging([:]) == value)
		#expect(SOML.Value.object([:]).merging(value) == value)
	}

	@Test
	func `keys are compared by their Unicode scalars`() {
		let merged = SOML.Object(["\u{E9}": 1] as [String: SOML.Value]).merging(["e\u{301}": 2])
		#expect(merged.keys == ["\u{E9}", "e\u{301}"])
	}
}


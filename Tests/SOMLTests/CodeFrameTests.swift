import Testing
@testable import SOML

@Suite
struct CodeFrameTests {
	@Test(arguments: [0, 500_000, 1_000_000])
	func `invalid continuation runs cannot expand the diagnostic window`(_ anchor: Int) {
		let bytes = [UInt8](repeating: 0x80, count: 1_000_000)
		let window = SOML.ParseError.codeFrameWindow(in: bytes, around: anchor, line: bytes.indices)
		#expect(window.count <= 808)
		#expect(window.lowerBound <= anchor)
		#expect(window.upperBound >= anchor)
	}

	@Test
	func `shows the lines before the error and a caret under it`() throws {
		#expect(try #require(parseError("a: 1\nb: nope")).codeFrame == "  1 | a: 1\n> 2 | b: nope\n    |    ^")
		#expect(try #require(parseError("a: 1\nb: 2\nc: 3\nd: nope")).codeFrame == "  2 | b: 2\n  3 | c: 3\n> 4 | d: nope\n    |    ^")
	}

	@Test
	func `the gutter is as wide as the error's line number`() throws {
		let source = (0..<9).map { "k\($0): \($0)\n" }.joined() + "k9: nope"
		#expect(try #require(parseError(source)).codeFrame == "   8 | k7: 7\n   9 | k8: 8\n> 10 | k9: nope\n     |     ^")
	}

	@Test
	func `keeps tabs before the caret so it lines up`() throws {
		#expect(try #require(parseError("a: {\n\t\tb: nope,\n}")).codeFrame == "  1 | a: {\n> 2 | \t\tb: nope,\n    | \t\t   ^")
	}

	@Test
	func `a blank line has no trailing space`() throws {
		#expect(try #require(parseError("a: 1\n\nb: nope")).codeFrame == "  1 | a: 1\n  2 |\n> 3 | b: nope\n    |    ^")
		#expect(try #require(parseError("")).codeFrame == "> 1 |\n    | ^")
	}

	@Test
	func `a long line is clipped around the error, and the caret stays under it`() throws {
		let source = "a: [" + String(repeating: "1, ", count: 60) + "x" + String(repeating: ", 1", count: 60) + "]"
		let lines = try #require(parseError(source)).codeFrame.split(separator: "\n").map(String.init)
		#expect(lines.count == 2)
		#expect(lines[0].hasPrefix("> 1 | …"))
		#expect(lines[0].hasSuffix("…"))
		#expect(lines[0].count == "> 1 | ".count + 102)

		let caret = try #require(Array(lines[1]).firstIndex(of: "^"))
		#expect(Array(lines[0])[caret] == "x")
	}

	@Test
	func `a long line clipped at one end only has one ellipsis`() throws {
		let start = try #require(parseError("[x" + String(repeating: ", 1", count: 60) + "]")).codeFrame
		#expect(start.hasPrefix("> 1 | [x"))
		#expect(start.contains("…\n"))

		let end = try #require(parseError("[" + String(repeating: "1, ", count: 60) + "x]")).codeFrame
		#expect(end.hasPrefix("> 1 | …"))
		#expect(end.split(separator: "\n")[0].hasSuffix("x]"))
	}

	@Test
	func `characters a terminal would act on are replaced, in the frame and in the message`() throws {
		#expect(try #require(parseError("a: 'x\ry'")).codeFrame == "> 1 | a: 'x\u{FFFD}y'\n    |      ^")

		let error = try #require(parseError("'\u{202E}admin': 1\n'\u{202E}admin': 2"))
		#expect(error.message == "Duplicate key \"\u{FFFD}admin\"")
		#expect(error.codeFrame == "  1 | '\u{FFFD}admin': 1\n> 2 | '\u{FFFD}admin': 2\n    | ^")
	}

	@Test
	func `invalid UTF-8 shows as a replacement character`() throws {
		let error = try #require(#expect(throws: SOML.ParseError.self) {
			try SOML.Value(parsing: Array("a: '".utf8) + [0xFF] + Array("'".utf8))
		})

		#expect(error.codeFrame == "> 1 | a: '\u{FFFD}'\n    |     ^")
	}

	@Test
	func `an error in a huge document makes a small frame quickly`() throws {
		let source = (0..<100_000).map { "k\($0): 1\n" }.joined() + "b: nope"
		let error = try #require(parseError(source))
		#expect(error.codeFrame.utf8.count < 200)
		#expect(error.location.line == 100_001)
	}

	@Test
	func `a long line of multi-byte characters is clipped between characters, with the caret under the error`() throws {
		let source = "a: [" + String(repeating: "'😀é', ", count: 300) + "nope" + String(repeating: ", '😀é'", count: 300) + "]"
		let lines = try #require(parseError(source)).codeFrame.split(separator: "\n").map(String.init)
		#expect(lines[0].hasPrefix("> 1 | …"))
		#expect(lines[0].hasSuffix("…"))
		#expect(!lines[0].unicodeScalars.contains("\u{FFFD}"))

		let caret = try #require(Array(lines[1].unicodeScalars).firstIndex(of: "^"))
		#expect(Array(lines[0].unicodeScalars)[caret] == "n")
	}

	@Test
	func `a long context line of four-byte characters still shows that it was clipped`() {
		let bytes = Array((String(repeating: "😀", count: 150) + "\nb").utf8)
		let lines = SOML.ParseError(message: "", offset: bytes.count - 1, in: bytes).codeFrame.split(separator: "\n")
		// The width is in UTF-16 code units, as in the reference implementation, so 50 emoji fill it.
		#expect(lines[0] == "  1 | " + String(repeating: "😀", count: 50) + "…")
	}

	@Test
	func `a long line is clipped by its length in UTF-16 code units, as in the reference implementation`() throws {
		// 67 characters, but 127 UTF-16 code units, so it is clipped, and the cut does not split an emoji.
		let error = try #require(parseError("a: '" + String(repeating: "😀", count: 60) + "' x"))
		#expect(error.codeFrame == "> 1 | …" + String(repeating: "😀", count: 48) + "' x\n    | " + String(repeating: " ", count: 51) + "^")
	}

	@Test
	func `a line of exactly 100 UTF-16 code units is not clipped, and an emoji that the end of the window would split is left out, as in the reference implementation`() throws {
		// 100 code units.
		let exact = try #require(parseError("k: '" + String(repeating: "😀", count: 46) + "a' x"))
		#expect(exact.codeFrame == "> 1 | k: '" + String(repeating: "😀", count: 46) + "a' x\n    | " + String(repeating: " ", count: 53) + "^")

		// 101 code units.
		let longer = try #require(parseError("k: '" + String(repeating: "😀", count: 47) + "' x"))
		#expect(longer.codeFrame == "> 1 | …: '" + String(repeating: "😀", count: 47) + "' x\n    | " + String(repeating: " ", count: 53) + "^")

		// The window ends in the middle of the 47th emoji.
		let splitAtEnd = try #require(parseError(#"k: "a\q"# + String(repeating: "😀", count: 60) + "\""))
		#expect(splitAtEnd.codeFrame == #"> 1 | k: "a\q"# + String(repeating: "😀", count: 46) + "…\n    |      ^")

		// The pointer is at the very start of the line, on a character that is shown as one code unit.
		let atStart = try #require(parseError("\u{7}" + String(repeating: "😀", count: 60)))
		#expect(atStart.codeFrame == "> 1 | \u{FFFD}" + String(repeating: "😀", count: 49) + "…\n    | ^")
	}

	@Test
	func `a stray continuation byte at the start of a line shows as a replacement character`() {
		let bytes: [UInt8] = [0x80] + Array("é😀".utf8)
		#expect(SOML.ParseError(message: "", offset: 1, in: bytes).codeFrame == "> 1 | \u{FFFD}é😀\n    |  ^")
	}

	@Test
	func `the caret points at the error on any line, also a long one with tabs, wide and combining characters`() {
		// The line is cut to a window around the error, and the caret must still be under the character that the error is at.
		let pool: [String] = ["a", "é", "日", "😀", "\t", " ", "e\u{301}", "-"]
		var generator = SeededGenerator(seed: 7)
		var checked = 0
		var failures = [String]()

		for _ in 0..<5000 {
			let prefix = (0..<Int.random(in: 0...260, using: &generator)).map { _ in pool[Int.random(in: pool.indices, using: &generator)] }.joined()
			let suffix = (0..<Int.random(in: 0...260, using: &generator)).map { _ in pool[Int.random(in: pool.indices, using: &generator)] }.joined()
			let lines = (0..<Int.random(in: 0...3, using: &generator)).map { "k\($0): \(Int.random(in: 0...9, using: &generator))\n" }.joined()
			let source = lines + "a: '" + prefix + "' @ '" + suffix + "'"
			let bytes = Array(source.utf8)
			let errorOffset = bytes.firstIndex(of: UInt8(ascii: "@"))!

			guard let error = parseError(source) else {
				continue
			}

			guard error.location.offset == errorOffset else {
				continue
			}

			checked += 1
			let frameLines = error.codeFrame.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

			guard
				let errorLineIndex = frameLines.firstIndex(where: { $0.hasPrefix(">") }),
				errorLineIndex + 1 < frameLines.count
			else {
				failures.append("No error line in \(error.codeFrame.debugDescription)")
				continue
			}

			let errorLine = Array(frameLines[errorLineIndex].unicodeScalars)
			let caretLine = Array(frameLines[errorLineIndex + 1].unicodeScalars)

			guard let caretIndex = caretLine.firstIndex(of: "^") else {
				failures.append("No caret in \(error.codeFrame.debugDescription)")
				continue
			}

			if caretIndex >= errorLine.count || errorLine[caretIndex] != "@" {
				failures.append("Caret at \(caretIndex) is under \(caretIndex < errorLine.count ? String(errorLine[caretIndex]) : "nothing") in\n\(error.codeFrame)")
			}

			// The error line is at most the maximum width plus two ellipses, and the gutter.
			let textWidth = errorLine.count - (frameLines[errorLineIndex].firstRange(of: "| ").map { frameLines[errorLineIndex].unicodeScalars.distance(from: frameLines[errorLineIndex].unicodeScalars.startIndex, to: $0.upperBound) } ?? 0)

			if textWidth > 102 {
				failures.append("Line too wide: \(textWidth)")
			}
		}

		for failure in failures.prefix(5) {
			Issue.record("\(failure)")
		}

		#expect(checked > 3000, "Only \(checked) checked")
		#expect(failures.isEmpty, "\(failures.count) of \(checked) failed")
	}
}

extension String {
	/**
	Whether every scalar is ASCII.
	*/
	var isASCII: Bool {
		withUTF8Buffer { $0.allSatisfy(UTF8.isASCII) }
	}

	/**
	Converts a camelCase name to words joined by `separator`, like `baseURL` to `base-url`.

	Words split where a lowercase letter or a digit is followed by an uppercase letter, and before the last capital of an uppercase run that is followed by a lowercase letter. This is close to the rule of `JSONEncoder`'s `.convertToSnakeCase`, which differs for a key that starts with capitals: `JSONEncoder` assumes that the first character is lowercase and splits it off, so `URL` becomes `u_rl` and `HTTPServer` becomes `h_ttp_server`, while here they become `url` and `http-server`. It also differs for some keys with digits or underscores: `JSONEncoder` turns `a1B2C3` into `a1_b2c3` and `foo_Bar` into `foo__bar`, while here they become `a1_b2_c3` and `foo_bar`.

	```
	myProperty → my-property
	baseURL → base-url
	myURLProperty → my-url-property
	isHTTP2Enabled → is-http2-enabled
	```
	*/
	func convertedFromCamelCase(separator: Character) -> String {
		// Coding keys are almost always ASCII, and bytes are much faster than `Character`s. The rule is the same.
		if let separatorByte = separator.asciiValue {
			let converted = withUTF8Buffer { bytes -> String? in
				var hasUppercase = false

				for byte in bytes {
					guard UTF8.isASCII(byte) else {
						return nil
					}

					hasUppercase = hasUppercase || byte.isASCIIUppercase
				}

				guard hasUppercase else {
					return self
				}

				var result = [UInt8]()
				result.reserveCapacity(bytes.count + 4)

				// Lowercasing the completed String added another pass and slowed the integrated converter by up to 26% in Swift 6.4 probes; lowercase bytes while inserting separators.
				for (index, byte) in bytes.enumerated() {
					if
						index > 0,
						byte.isASCIIUppercase
					{
						let previous = bytes[index - 1]
						let isFollowedByLowercase = index + 1 < bytes.count && bytes[index + 1].isASCIILowercase

						if
							!previous.isASCIIUppercase || isFollowedByLowercase,
							previous != separatorByte
						{
							result.append(separatorByte)
						}
					}

					result.append(byte.asciiLowercased)
				}

				return String(decoding: result, as: UTF8.self)
			}

			if let converted {
				return converted
			}
		}

		let characters = Array(self)

		// The case of a character is the case of its first scalar, like the letter of a letter with combining marks. `Character.isUppercase` compares a character of several scalars with `==`, which normalizes it and takes quadratic time for a long run of combining marks.
		let cases = characters.map { $0.unicodeScalars.first!.properties }

		var result = ""
		result.reserveCapacity(utf8.count + 4)

		for (index, character) in characters.enumerated() {
			if
				index > 0,
				cases[index].isUppercase
			{
				let previous = characters[index - 1]
				let isFollowedByLowercase = index + 1 < characters.count && cases[index + 1].isLowercase

				if
					!cases[index - 1].isUppercase || isFollowedByLowercase,
					!previous.hasSameScalars(as: separator)
				{
					result.append(separator)
				}
			}

			result += character.lowercased()
		}

		return result
	}

	/**
	Converts words joined by `separator` to camelCase, like `content-type` to `contentType`.

	Leading and trailing separators are kept. A key without separators is returned unchanged.
	*/
	func convertedToCamelCase(separator: Character) -> String {
		if
			let separatorByte = separator.asciiValue,
			!withUTF8Buffer({ $0.contains(separatorByte) })
		{
			return self
		}

		if
			let separatorByte = separator.asciiValue,
			let converted = convertedASCIIToCamelCase(separator: separatorByte)
		{
			return converted
		}

		guard
			let first = firstIndex(where: { !$0.hasSameScalars(as: separator) }),
			let last = lastIndex(where: { !$0.hasSameScalars(as: separator) })
		else {
			return self
		}

		let words = self[first...last].split { $0.hasSameScalars(as: separator) }

		guard words.count > 1 else {
			return self
		}

		var camelCase = words[0].lowercased()
		camelCase.reserveCapacity(utf8.count)

		// Foundation capitalized uses word boundaries: 1BAR becomes 1Bar and a.b becomes A.B, changing the required key spelling.
		for word in words.dropFirst() {
			camelCase += word[word.startIndex].uppercased()
			camelCase += word.dropFirst().lowercased()
		}
		return self[..<first] + camelCase + self[index(after: last)...]
	}

	/**
	Converts ASCII words without allocating an array of characters or substrings. Returns `nil` when Unicode case conversion is needed.
	*/
	private func convertedASCIIToCamelCase(separator: UInt8) -> String? {
		withUTF8Buffer { bytes in
			guard bytes.allSatisfy(UTF8.isASCII) else {
				return nil
			}

			guard
				let first = bytes.firstIndex(where: { $0 != separator }),
				let last = bytes.lastIndex(where: { $0 != separator }),
				bytes[first...last].contains(separator)
			else {
				return self
			}

			// A split/map/join pipeline allocates per word and measured 4–10 times slower than this byte loop.
			var output = [UInt8]()
			output.reserveCapacity(bytes.count)
			output.append(contentsOf: bytes[..<first])
			var startsWord = false

			for byte in bytes[first...last] {
				if byte == separator {
					startsWord = true
					continue
				}

				output.append(startsWord ? byte.asciiUppercased : byte.asciiLowercased)
				startsWord = false
			}

			output.append(contentsOf: bytes[(last + 1)...])
			return String(decoding: output, as: UTF8.self)
		}
	}
}

extension CodingKey {
	/**
	The key of the member that this coding key names in a document, converted with the separator of a key strategy. A key that the decoder took from the document as it is, like the key of a `[String: T]` or an unknown key, is not converted.
	*/
	func documentKey(separator: Character?) -> String {
		// The decoder makes its own keys only for keys that it took from the document as they are.
		guard
			let separator,
			!(self is SOMLCodingKey)
		else {
			return stringValue
		}

		return stringValue.convertedFromCamelCase(separator: separator)
	}
}

extension Character {
	/**
	Whether two characters contain the same Unicode scalars, without canonical-equivalence normalization.
	*/
	func hasSameScalars(as other: Character) -> Bool {
		unicodeScalars.elementsEqual(other.unicodeScalars)
	}
}

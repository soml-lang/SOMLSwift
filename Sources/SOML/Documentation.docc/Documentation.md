# ``SOML``

A strict, fast encoder and decoder for [SOML](https://soml.sh), a config format for humans.

## Overview

Decode and encode your own types with ``SOML/Decoder`` and ``SOML/Encoder``, read documents of unknown shape as a ``SOML/Value``, and edit a file without losing its comments with ``SOML/Document``.

```swift
import SOML

struct Config: Codable {
	let name: String
	let replicas: Int
}

let text =
	"""
	name: 'api-gateway'
	replicas: 3
	"""

let config = try SOML.Decoder().decode(Config.self, from: text)
```

## Topics

### Codable

- ``SOML/Decoder``
- ``SOML/Encoder``

### Values

- ``SOML/Value``
- ``SOML/Object``
- ``SOML/Instant``
- ``SOML/KeyPath``
- ``SOML/Difference``
- ``SOML/JSONFormat``

### Documents

- ``SOML/Document``
- ``SOML/Location``
- ``SOML/Token``
- ``SOML/LexicalContext``

### Errors

- ``SOML/ParseError``
- ``SOML/InvalidValueError``
- ``SOML/EditError``
- ``SOML/JSONError``

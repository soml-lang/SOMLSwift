/**
[SOML](https://soml.sh), a config format for humans: a strict reader, `Codable` support, canonical form, and a formatter and editor that keep comments.

- `SOML.Decoder` and `SOML.Encoder` read and write `Codable` types.
- `SOML.Value` and `SOML.Object` hold a document of unknown shape, and `SOML.Instant` an exact instant.
- `SOML.Document` keeps the source text, to format it or change one member or array item and keep the comments.
- `SOML.KeyPath` is a path to a member or an array item, written as a SOML key with indices in brackets, like `servers[0].host`.
- `SOML.Value(parsingJSON:)` and `jsonText()` convert to and from JSON, and `merging(_:)` merges values for layered config.
- `SOML.ParseError`, `SOML.InvalidValueError`, `SOML.EditError`, and `SOML.JSONError` are the errors.

```swift
import SOML

let config = try SOML.Decoder().decode(Config.self, from: text)
```
*/
public enum SOML {}

import Benchmark
import Foundation
import SOML
import TOMLDecoder

/**
Benchmarks of the shared fixtures, against the most used ways Swift reads JSON and TOML: Foundation's JSON coders and `JSONSerialization`, which ship with the platform, and TOMLDecoder, the most used TOML package.

Each fixture holds the same data in SOML, JSON, and TOML (see `Fixtures/readme.md`):

- Reading into the value type of each library: `SOML.Value`, the result of `JSONSerialization`, and `TOMLTable`, which keeps scalars as text and converts one only when it is read, so it does less work than the others.
- Reading into a `Codable` struct, for `earthquakes`, the one fixture whose JSON and TOML hold the same types as the SOML: in `service` and `platform`, a duration is a string in JSON and TOML.
- Writing the value and the struct. TOMLDecoder only reads.

Fixture parsing, document construction, and coder configuration are excluded from write, format, and configured read measurements.

Run in a release build from the Benchmarks folder:

	swift package benchmark
*/
let benchmarks: @Sendable () -> Void = {
	for fixture in fixtureNames {
		let soml = readFixture("\(fixture).soml")
		let json = Data(readFixture("\(fixture).json").utf8)
		let toml = readFixture("\(fixture).toml")

		Benchmark(
			"read value, \(fixture), SOML",
			configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
		) { benchmark in
			for _ in benchmark.scaledIterations {
				blackHole(try SOML.Value(parsing: soml))
			}
		}

		Benchmark(
			"read value, \(fixture), JSONSerialization",
			configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
		) { benchmark in
			for _ in benchmark.scaledIterations {
				blackHole(try JSONSerialization.jsonObject(with: json))
			}
		}

		Benchmark(
			"read value, \(fixture), TOMLDecoder",
			configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
		) { benchmark in
			for _ in benchmark.scaledIterations {
				blackHole(try TOMLTable(source: toml))
			}
		}

		Benchmark(
			"write value, \(fixture), SOML",
			configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
		) { benchmark in
			let value = try SOML.Value(parsing: soml)

			benchmark.startMeasurement()

			for _ in benchmark.scaledIterations {
				blackHole(try SOML.Encoder().encode(value))
			}

			benchmark.stopMeasurement()
		}

		Benchmark(
			"write value, \(fixture), JSONSerialization",
			configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
		) { benchmark in
			let object = try JSONSerialization.jsonObject(with: json)

			benchmark.startMeasurement()

			for _ in benchmark.scaledIterations {
				blackHole(try JSONSerialization.data(withJSONObject: object))
			}

			benchmark.stopMeasurement()
		}

		Benchmark(
			"format, \(fixture), SOML",
			configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
		) { benchmark in
			let document = try SOML.Document(parsing: soml)

			benchmark.startMeasurement()

			for _ in benchmark.scaledIterations {
				blackHole(document.formatted())
			}

			benchmark.stopMeasurement()
		}
	}

	let earthquakesSOML = readFixture("earthquakes.soml")
	let earthquakesJSON = Data(readFixture("earthquakes.json").utf8)
	let earthquakesTOML = readFixture("earthquakes.toml")

	Benchmark(
		"read struct, earthquakes, SOML",
		configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
	) { benchmark in
		for _ in benchmark.scaledIterations {
			blackHole(try SOML.Decoder().decode(Earthquakes.self, from: earthquakesSOML))
		}
	}

	Benchmark(
		"read struct, earthquakes, JSONDecoder",
		configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
	) { benchmark in
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601WithFraction

		benchmark.startMeasurement()

		for _ in benchmark.scaledIterations {
			blackHole(try decoder.decode(Earthquakes.self, from: earthquakesJSON))
		}

		benchmark.stopMeasurement()
	}

	Benchmark(
		"read struct, earthquakes, TOMLDecoder",
		configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
	) { benchmark in
		for _ in benchmark.scaledIterations {
			blackHole(try TOMLDecoder().decode(Earthquakes.self, from: earthquakesTOML))
		}
	}

	Benchmark(
		"write struct, earthquakes, SOML",
		configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
	) { benchmark in
		let earthquakes = try SOML.Decoder().decode(Earthquakes.self, from: earthquakesSOML)

		benchmark.startMeasurement()

		for _ in benchmark.scaledIterations {
			blackHole(try SOML.Encoder().encode(earthquakes))
		}

		benchmark.stopMeasurement()
	}

	Benchmark(
		"write struct, earthquakes, JSONEncoder",
		configuration: .init(metrics: [.wallClock, .cpuTotal], warmupIterations: 2)
	) { benchmark in
		let earthquakes = try SOML.Decoder().decode(Earthquakes.self, from: earthquakesSOML)
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601

		benchmark.startMeasurement()

		for _ in benchmark.scaledIterations {
			blackHole(try encoder.encode(earthquakes))
		}

		benchmark.stopMeasurement()
	}
}

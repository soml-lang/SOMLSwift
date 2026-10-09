import Foundation

/**
The text of a file in the `Fixtures` folder of the benchmark package, which is a copy of the benchmark fixtures that every SOML implementation shares.
*/
func readFixture(_ name: String) -> String {
	let url = URL(filePath: #filePath)
		.deletingLastPathComponent()
		.appending(path: "../../Fixtures/\(name)")

	return try! String(contentsOf: url, encoding: .utf8)
}

/**
The names of the shared fixtures, each of which is in SOML, JSON, and TOML with the same data.
*/
let fixtureNames = ["service", "platform", "earthquakes"]

/**
The week of earthquakes of the USGS feed, as GeoJSON, with every member a tool reads. An instant is a `Date` in all three formats: SOML and TOML have one, and JSON has its ISO 8601 string.
*/
struct Earthquakes: Codable {
	var type: String
	var metadata: Metadata
	var bbox: [Double]
	var features: [Feature]

	struct Metadata: Codable {
		var generated: Date
		var url: String
		var title: String
		var status: Int
		var api: String
		var count: Int
	}

	struct Feature: Codable {
		var type: String
		var properties: Properties
		var geometry: Geometry
		var id: String
	}

	struct Properties: Codable {
		var mag: Double
		var place: String
		var time: Date
		var updated: Date
		var url: String
		var detail: String
		var status: String
		var tsunami: Int
		var sig: Int
		var net: String
		var code: String
		var ids: String
		var sources: String
		var types: String
		var nst: Int
		var dmin: Double?
		var rms: Double
		var gap: Double
		var magType: String
		var type: String
		var title: String
		var felt: Int?
		var cdi: Double?
		var mmi: Double?
		var alert: String?
	}

	struct Geometry: Codable {
		var type: String
		var coordinates: [Double]
	}
}

extension JSONDecoder.DateDecodingStrategy {
	/**
	ISO 8601 with and without a fraction of a second, as the JSON of the fixtures writes an instant. Foundation's `.iso8601` does not read a fraction.
	*/
	static var iso8601WithFraction: Self {
		.custom { decoder in
			let text = try decoder.singleValueContainer().decode(String.self)

			if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)) {
				return date
			}

			return try Date(text, strategy: .iso8601)
		}
	}
}

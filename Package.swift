// swift-tools-version: 6.3
import PackageDescription

let package = Package(
	name: "SOML",
	platforms: [
		.macOS(.v15),
		.iOS(.v18),
		.tvOS(.v18),
		.watchOS(.v11),
		.visionOS(.v2)
	],
	products: [
		.library(
			name: "SOML",
			targets: [
				"SOML"
			]
		)
	],
	targets: [
		.target(
			name: "SOML"
		),
		.testTarget(
			name: "SOMLTests",
			dependencies: [
				"SOML"
			]
		)
	]
)

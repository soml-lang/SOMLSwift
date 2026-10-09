// swift-tools-version: 6.2
import PackageDescription

let package = Package(
	name: "SOMLFuzz",
	platforms: [
		.macOS(.v15)
	],
	dependencies: [
		.package(path: "..")
	],
	targets: [
		.executableTarget(
			name: "SOMLFuzz",
			dependencies: [
				.product(name: "SOML", package: "SOMLSwift")
			]
		)
	]
)

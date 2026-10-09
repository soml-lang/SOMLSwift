// swift-tools-version: 6.3
import PackageDescription

let package = Package(
	name: "Benchmarks",
	platforms: [
		.macOS(.v15)
	],
	dependencies: [
		.package(path: ".."),
		.package(url: "https://github.com/ordo-one/benchmark", from: "1.37.0"),
		.package(url: "https://github.com/dduan/TOMLDecoder", from: "0.3.0"),
	],
	targets: [
		.executableTarget(
			name: "SOMLBenchmarks",
			dependencies: [
				.product(name: "SOML", package: "SOMLSwift"),
				.product(name: "Benchmark", package: "benchmark"),
				.product(name: "TOMLDecoder", package: "TOMLDecoder"),
			],
			path: "Benchmarks/SOMLBenchmarks",
			plugins: [
				.plugin(name: "BenchmarkPlugin", package: "benchmark")
			]
		)
	]
)

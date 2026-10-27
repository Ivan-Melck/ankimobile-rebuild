// swift-tools-version: 5.9
import PackageDescription
import Foundation
let nativePath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("NativeEngine/target/release").path

let package = Package(
    name: "FlashcardsCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "FlashcardsCore", targets: ["FlashcardsCore"]), .executable(name: "AnkiComparisonDriver", targets: ["AnkiComparisonDriver"])],
    targets: [
        .target(name: "CSchedulingEngine", linkerSettings: [.linkedLibrary("scheduling_engine"), .linkedLibrary("c++", .when(platforms: [.iOS, .macOS])), .linkedLibrary("resolv", .when(platforms: [.iOS, .macOS])), .linkedFramework("Accelerate", .when(platforms: [.macOS])), .linkedFramework("Security", .when(platforms: [.iOS, .macOS])), .linkedFramework("SystemConfiguration", .when(platforms: [.iOS, .macOS])), .unsafeFlags(["-L", nativePath], .when(platforms: [.linux, .macOS]))]),
        .target(name: "FlashcardsCore", dependencies: ["CSchedulingEngine"], resources: [.copy("Resources/RWKV")]),
        .testTarget(name: "FlashcardsCoreTests", dependencies: ["FlashcardsCore"]),
        .executableTarget(name: "AnkiComparisonDriver", dependencies: ["FlashcardsCore"])
    ],
    swiftLanguageVersions: [.v5]
)

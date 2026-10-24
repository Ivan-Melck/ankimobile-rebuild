// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlashcardsCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "FlashcardsCore", targets: ["FlashcardsCore"])],
    targets: [
        .target(name: "FlashcardsCore"),
        .testTarget(name: "FlashcardsCoreTests", dependencies: ["FlashcardsCore"])
    ],
    swiftLanguageVersions: [.v5]
)

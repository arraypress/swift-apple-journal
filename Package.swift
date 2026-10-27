// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-apple-journal",
    // SQLite is read through swift-sqlite-reader; RTF through swift-rich-text. macOS
    // only — Journal's store on a Mac is the one this reads.
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AppleJournal", targets: ["AppleJournal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/arraypress/swift-rich-text.git", from: "0.1.0"),
        .package(url: "https://github.com/arraypress/swift-sqlite-reader.git", from: "0.1.0"),
    ],
    targets: [
        .target(name: "AppleJournal", dependencies: [
            .product(name: "RichText", package: "swift-rich-text"),
            .product(name: "SQLiteReader", package: "swift-sqlite-reader"),
        ]),
        .testTarget(name: "AppleJournalTests", dependencies: ["AppleJournal"]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}

// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-apple-journal",
    // SQLite3 is in the OS; nothing is vendored and nothing is fetched. macOS
    // only — Journal's store on a Mac is the one this reads.
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AppleJournal", targets: ["AppleJournal"]),
    ],
    targets: [
        .target(name: "AppleJournal"),
        .testTarget(name: "AppleJournalTests", dependencies: ["AppleJournal"]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}

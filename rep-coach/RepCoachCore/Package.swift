// swift-tools-version:6.0
import PackageDescription

// The rep-counting logic, kept free of camera, Vision and audio so it builds and runs on a Mac:
// `swift run repcoach-check` exercises it on synthetic movement, and `repcoach-replay` runs it
// over pose recordings captured in the gym
// or made from videos by `repcoach-video`.
let package = Package(
    name: "RepCoachCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "RepCoachCore", targets: ["RepCoachCore"]),
    ],
    targets: [
        .target(name: "RepCoachCore"),
        .executableTarget(name: "repcoach-replay", dependencies: ["RepCoachCore"]),
        // Pose from a video file, written as a recording, for testing on footage of other people.
        .executableTarget(name: "repcoach-video", dependencies: ["RepCoachCore"]),
        // XCTest and Swift Testing ship with Xcode, not the Command Line Tools, so the checks are
        // a plain executable that exits non-zero on failure.
        .executableTarget(name: "repcoach-check", dependencies: ["RepCoachCore"], path: "Tests/RepCoachCoreTests"),
    ]
)

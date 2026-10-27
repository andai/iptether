// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "IPTether",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IPTether", targets: ["IPTether"]),
    ],
    targets: [
        // Config, engine runner, scheduling and CLI discovery. No UI, so it is unit-testable.
        .target(name: "IPTetherCore"),
        // The menu bar app. scripts/build-app.sh wraps it in IPTether.app with the engine.
        .executableTarget(name: "IPTether", dependencies: ["IPTetherCore"]),
        .testTarget(name: "IPTetherCoreTests", dependencies: ["IPTetherCore"]),
    ]
)

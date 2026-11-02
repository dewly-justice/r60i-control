// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SoundcoreKit",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "SoundcoreKit", targets: ["SoundcoreKit"]),
        .executable(name: "scprobe", targets: ["scprobe"]),
    ],
    targets: [
        // Protocol (framing, parsing, encoding; see docs/protocol.md), the IOBluetooth RFCOMM
        // transport, and the @Observable device model the app uses.
        .target(
            name: "SoundcoreKit",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),

        // Command-line probe and hardware test harness, built on SoundcoreKit.
        .executableTarget(
            name: "scprobe",
            dependencies: ["SoundcoreKit"],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist (NSBluetoothAlwaysUsageDescription) into the binary so macOS
                // privacy checks have a usage string for this command-line tool.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", Context.packageDirectory + "/Sources/scprobe/Info.plist",
                ]),
            ]
        ),

        .testTarget(name: "SoundcoreKitTests", dependencies: ["SoundcoreKit"]),
        .testTarget(name: "ScprobeTests", dependencies: ["scprobe", "SoundcoreKit"]),
    ]
)

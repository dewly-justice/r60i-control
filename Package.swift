// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "soundcore",
    platforms: [.macOS(.v27)],
    products: [
        .executable(name: "scprobe", targets: ["scprobe"]),
    ],
    targets: [
        // Pure Swift protocol code (framing, parsing, encoding). No Bluetooth; fully unit-testable.
        // See docs/protocol.md for the byte layouts it implements.
        .target(name: "SoundcoreProtocol"),

        // Phase 1 command-line probe: IOBluetooth RFCOMM transport + CLI.
        .executableTarget(
            name: "scprobe",
            dependencies: ["SoundcoreProtocol"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
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

        .testTarget(
            name: "SoundcoreProtocolTests",
            dependencies: ["SoundcoreProtocol"]
        ),
        .testTarget(
            name: "ScprobeTests",
            dependencies: ["scprobe", "SoundcoreProtocol"]
        ),
    ]
)

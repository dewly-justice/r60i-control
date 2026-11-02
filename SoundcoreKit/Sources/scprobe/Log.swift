import Foundation
import SoundcoreKit

/// Progress and byte logs go to stderr; the parsed result goes to stdout.
@MainActor
final class Log {
    let hexdump: Bool
    private let start = Date()

    init(hexdump: Bool) {
        self.hexdump = hexdump
    }

    func info(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    func handle(_ event: DeviceEvent) {
        switch event {
        case let .info(message):
            info(message)
        case let .push(frame):
            if listening { print(Report.describePush(frame)) }
        case let .link(.sent(bytes, note)):
            self.bytes("→", bytes, note: note)
        case let .link(.received(bytes)):
            self.bytes("←", bytes)
        case let .link(.frame(frame)):
            guard hexdump else { return }
            let label = frame.command.name.map { " (\($0))" } ?? ""
            info("           ↳ frame \(frame.command)\(label), \(frame.body.count)-byte body")
        case let .link(.dropped(bytes, reason)):
            info("warning: dropped \(bytes.count) inbound bytes (\(reason)): \(bytes.hexString)")
        }
    }

    /// Pushes are printed only while `--listen` runs.
    var listening = false

    /// Raw bytes as written to / read from the RFCOMM channel. `arrow` is "→" (to earbuds) or "←" (from earbuds).
    func bytes(_ arrow: String, _ bytes: [UInt8], note: String? = nil) {
        guard hexdump else { return }
        let elapsed = String(format: "+%7.3fs", Date().timeIntervalSince(start))
        var lines = ["\(elapsed) \(arrow) \(bytes.count) bytes\(note.map { "  [\($0)]" } ?? "")"]
        for offset in stride(from: 0, to: bytes.count, by: 16) {
            let row = bytes[offset..<min(offset + 16, bytes.count)]
            lines.append(String(format: "           %04X  ", offset) + row.hexString)
        }
        info(lines.joined(separator: "\n"))
    }
}

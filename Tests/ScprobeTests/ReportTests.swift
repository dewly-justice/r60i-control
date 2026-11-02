import Testing
@testable import scprobe
import SoundcoreProtocol

/// Renders the report from the OpenSCQ30 D1202 fixture (no Bluetooth involved).
@Suite("scprobe report")
struct ReportTests {
    static let body: [UInt8] = [
        1, 1, 9, 9, 0, 0, 48, 49, 46, 56, 51, 48, 49, 46, 56, 51, 49, 50, 48, 50,
        51, 52, 48, 57, 67, 57, 66, 52, 48, 51, 67, 69, 48, 49, 46, 56, 51, 3, 0,
        0, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 255, 0, 0, 120, 120, 120, 120, 120, 120, 120, 120,
        120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 0, 0, 0, 0, 2,
        120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120, 120,
        120, 120, 120, 120, 120, 0, 0, 10, 0xFF, 0xFF, 0x63, 0x66, 0xFF, 0xFF,
        0x44, 0x44, 51, 0, 0x50, 0, 2, 0, 0, 0, 0, 50, 1, 1, 0, 1, 1, 2, 0, 90, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 255, 255, 255,
    ]

    static let connection = ConnectionSummary(
        displayName: "soundcore R60i NC [00-00-00-d1-20-2c]",
        channelID: 15,
        serviceUUID: SoundcoreServiceUUID.d1202c,
        vendorSuffix: "1202C",
        modelConfirmed: true,
        modelNote: "model ID 1202C from service UUID"
    )

    @Test func rendersFixture() throws {
        let report = Report.render(try D1202State(body: Self.body), connection: Self.connection)
        print(report)
        #expect(report.contains("left 01.83 · right 01.83"))
        #expect(report.contains("Noise Canceling"))
        #expect(report.contains("Multi-scene → Transport"))
        #expect(report.contains("Soundcore Signature"))
        #expect(report.contains("(not present)"))
        #expect(report.contains("on, 30 min"))
    }

    @Test func describesSoundModePush() {
        let push = Frame(.deviceToHost, .soundModes, body: [1, 0x50, 0, 2, 0, 0, 0, 0])
        let line = Report.describePush(push)
        print(line)
        #expect(line.contains("Transparency"))
    }
}

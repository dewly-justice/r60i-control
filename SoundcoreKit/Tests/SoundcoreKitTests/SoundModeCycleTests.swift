import Testing
@testable import SoundcoreKit

/// The press-and-hold sound-mode cycle: state offset 0x76 and `06 82` (SoundModeCycle.swift).
@Suite("Sound-mode cycle (protocol.md §6.10)")
struct SoundModeCycleTests {
    /// Our R60i NC reports 0x33: Noise Cancelling ↔ Transparency in both situations, which is
    /// the documented default ("press and hold for 2 s: ANC ↔ Transparency").
    @Test func realCaptureIsTheDefaultCycle() throws {
        let state = try D1202State(body: Array(Fixtures.r60iStateFrame[9..<(Fixtures.r60iStateFrame.count - 1)]))
        #expect(state.soundModeCycles.raw == 0x33)
        #expect(state.soundModeCycles.twoEarbuds.modes == [.noiseCanceling, .transparency])
        #expect(state.soundModeCycles.oneEarbud.modes == [.noiseCanceling, .transparency])
    }

    /// Nibble order as in OpenSCQ30 `AmbientSoundModeCycleTws`: low = TWS connected.
    @Test func replacingTouchesOnlyThatSituation() {
        let cycles = SoundModeCycles(raw: 0x33)
        let withNormal = cycles.twoEarbuds.setting(.normal, included: true)
        #expect(cycles.replacing(withNormal, budsLinked: true).raw == 0x37)
        #expect(cycles.replacing(withNormal, budsLinked: false).raw == 0x73)
    }

    @Test func undocumentedBitIsKept() {
        let cycle = SoundModeCycle(nibble: 0b1011).setting(.normal, included: true)
        #expect(cycle.nibble == 0b1111)
        #expect(cycle.modes == [.noiseCanceling, .transparency, .normal])
    }

    /// `08 EE 00 00 00 | 06 82 | 0B 00 | 37 | C0`.
    @Test func writeFrame() throws {
        let frame = try Requests.setSoundModeCycles(SoundModeCycles(raw: 0x37))
        #expect(frame.encoded() == [0x08, 0xEE, 0x00, 0x00, 0x00, 0x06, 0x82, 0x0B, 0x00, 0x37, 0xC0])
    }

    @Test func refusesACycleOfOne() {
        #expect(throws: EncodeError.self) { try Requests.setSoundModeCycles(SoundModeCycles(raw: 0x31)) }
        #expect(throws: EncodeError.self) { try Requests.setSoundModeCycles(SoundModeCycles(raw: 0x03)) }
    }
}

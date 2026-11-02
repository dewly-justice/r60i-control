import Testing
@testable import SoundcoreKit

@Suite("Framing (protocol.md §2–3)")
struct FrameTests {
    @Test("RequestState matches the OpenSCQ30 test vector")
    func requestStateBytes() {
        // OpenSCQ30 lib/src/devices/soundcore/common/packet/outbound/request_state.rs
        #expect(Requests.requestState().encoded() == [0x08, 0xEE, 0x00, 0x00, 0x00, 0x01, 0x01, 0x0A, 0x00, 0x02])
    }

    @Test("An ACK from the OpenSCQ30 tests decodes as an empty 06 81 frame")
    func decodesAck() {
        var decoder = FrameDecoder()
        let events = decoder.feed([0x09, 0xFF, 0x00, 0x00, 0x01, 0x06, 0x81, 0x0A, 0x00, 0x9A])
        #expect(events == [.frame(Frame(.deviceToHost, .setSoundModes))])
        #expect(decoder.buffer.isEmpty)
    }

    @Test("Checksum wraps at 256")
    func checksumWraps() {
        #expect(Checksum.compute([0xFF, 0x02]) == 0x01)
        #expect(Checksum.compute([]) == 0)
    }

    @Test("A frame delivered one byte at a time is reassembled")
    func fragmented() {
        var decoder = FrameDecoder()
        var frames: [Frame] = []
        for byte in Fixtures.openSCQ30D1202StateFrame {
            for case let .frame(frame) in decoder.feed([byte]) { frames.append(frame) }
        }
        #expect(frames.count == 1)
        #expect(frames.first?.command == .state)
        #expect(frames.first?.body == Fixtures.openSCQ30D1202StateBody)
    }

    @Test("Several frames in one read are all decoded, in order")
    func merged() {
        let ack = Frame(.deviceToHost, .setSoundModes).encoded()
        let push = Frame(.deviceToHost, .soundModes, body: [1, 0x50, 0, 2, 0, 0, 0, 0]).encoded()
        var decoder = FrameDecoder()
        let events = decoder.feed(ack + push + Fixtures.openSCQ30D1202StateFrame)
        let commands = events.compactMap { if case let .frame(f) = $0 { f.command } else { nil } }
        #expect(commands == [.setSoundModes, .soundModes, .state])
    }

    @Test("Garbage and a corrupted frame are dropped; the next good frame still decodes")
    func recovers() {
        var corrupted = Frame(.deviceToHost, .soundModes, body: [0, 0x50, 0, 0, 0, 0, 0, 0]).encoded()
        corrupted[corrupted.count - 1] &+= 1
        let good = Frame(.deviceToHost, .setSoundModes).encoded()

        var decoder = FrameDecoder()
        let events = decoder.feed([0x00, 0x13, 0x37] + corrupted + good)
        let frames = events.compactMap { if case let .frame(f) = $0 { f } else { nil } }
        let discards = events.filter { if case .discarded = $0 { true } else { false } }
        #expect(frames == [Frame(.deviceToHost, .setSoundModes)])
        #expect(!discards.isEmpty)
        #expect(decoder.buffer.isEmpty)
    }

    @Test("A partial header waits for more bytes instead of failing")
    func partialHeader() {
        var decoder = FrameDecoder()
        #expect(decoder.feed([0x09, 0xFF, 0x00]).isEmpty)
        #expect(decoder.buffer == [0x09, 0xFF, 0x00])
    }

    @Test("Host → device frames are not accepted as device → host frames")
    func wrongDirection() {
        var decoder = FrameDecoder()
        let events = decoder.feed(Requests.requestState().encoded())
        #expect(events.allSatisfy { if case .discarded = $0 { true } else { false } })
    }
}

@Suite("Service UUIDs (protocol.md §1)")
struct ServiceUUIDTests {
    @Test func d1202cIsVendorWithModelSuffix() {
        #expect(SoundcoreServiceUUID.isVendor(SoundcoreServiceUUID.d1202c))
        #expect(SoundcoreServiceUUID.vendorSuffix(SoundcoreServiceUUID.d1202c) == "1202C")
        #expect(SoundcoreServiceUUID.format(SoundcoreServiceUUID.d1202c) == "0CF12D31-FAC3-4553-BD80-D6832E71202C")
    }

    @Test func p31iSuffix() {
        // 0CF12D31-FAC3-4553-BD80-D6832E7D1202 (OpenSCQ30 tools/soundcore-device-faker/devices/d1202.toml)
        let p31i = SoundcoreServiceUUID.vendorPrefix + [0x7D, 0x12, 0x02]
        #expect(SoundcoreServiceUUID.vendorSuffix(p31i) == "D1202")
    }

    @Test func serialPortIsNotVendor() {
        #expect(!SoundcoreServiceUUID.isVendor(SoundcoreServiceUUID.serialPort))
        #expect(SoundcoreServiceUUID.format(SoundcoreServiceUUID.serialPort) == "00001101-0000-1000-8000-00805F9B34FB")
    }

    @Test func otherNibbleIsNotVendor() {
        // Byte 13 high nibble must be 7.
        let other = SoundcoreServiceUUID.vendorPrefix + [0x61, 0x20, 0x2C]
        #expect(!SoundcoreServiceUUID.isVendor(other))
    }
}

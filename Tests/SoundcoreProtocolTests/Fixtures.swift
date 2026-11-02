import SoundcoreProtocol

// Byte fixtures. Phase 2 will add fixtures captured from the real R60i NC with `scprobe --hexdump`.

enum Fixtures {
    /// D1202 state body (`01 01`, 152 bytes, firmware 01.83), copied from the
    /// `settings_match_soundcore_app` test in OpenSCQ30 `lib/src/devices/soundcore/d1202.rs` @ e75a68b.
    static let openSCQ30D1202StateBody: [UInt8] = [
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

    /// Same body framed as a device → host `01 01` packet.
    static var openSCQ30D1202StateFrame: [UInt8] {
        Frame(.deviceToHost, .state, body: openSCQ30D1202StateBody).encoded()
    }
}

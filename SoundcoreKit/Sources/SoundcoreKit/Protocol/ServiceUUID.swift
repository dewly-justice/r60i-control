// RFCOMM service selection: docs/protocol.md §1.
// Use the first SDP service whose class UUID matches 0CF12D31-FAC3-4553-BD80-D6832E7xxxxx.
// If none matches, use the standard SPP UUID.

public enum SoundcoreServiceUUID {
    /// 0CF12D31-FAC3-4553-BD80-D6832E7 — the fixed 108 bits (13 bytes + high nibble of byte 13).
    static let vendorPrefix: [UInt8] = [0x0C, 0xF1, 0x2D, 0x31, 0xFA, 0xC3, 0x45, 0x53, 0xBD, 0x80, 0xD6, 0x83, 0x2E]
    static let vendorNibble: UInt8 = 0x7

    /// 0CF12D31-FAC3-4553-BD80-D6832E71202C (OpenSCQ30 `tools/soundcore-device-faker/devices/d1202c.toml`)
    public static let d1202c: [UInt8] = vendorPrefix + [0x71, 0x20, 0x2C]

    /// 00001101-0000-1000-8000-00805F9B34FB
    public static let serialPort: [UInt8] = [0x00, 0x00, 0x11, 0x01, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB]

    /// True for any 128-bit UUID in the Soundcore vendor range.
    public static func isVendor(_ uuid: [UInt8]) -> Bool {
        uuid.count == 16 && uuid.prefix(13).elementsEqual(vendorPrefix) && uuid[13] >> 4 == vendorNibble
    }

    /// The 5 wildcard hex digits of a vendor UUID, e.g. "1202C". These appear to encode the model ID.
    public static func vendorSuffix(_ uuid: [UInt8]) -> String? {
        guard isVendor(uuid) else { return nil }
        let hex = uuid.suffix(3).hexString.filter { $0 != " " }
        return String(String(uuid[13] & 0x0F, radix: 16, uppercase: true) + hex.dropFirst(2))
    }

    /// Model IDs whose state layout is the D1202 one implemented here (OpenSCQ30 `device_model.rs:134-135`).
    /// The P31i (D1202) faker UUID ends in "D1202"; the R60i NC (D1202C) one ends in "1202C".
    public static let d1202Suffixes: Set<String> = ["1202C", "D1202"]

    /// `"0CF12D31-FAC3-4553-BD80-D6832E71202C"`
    public static func format(_ uuid: [UInt8]) -> String {
        guard uuid.count == 16 else { return uuid.hexString }
        let hex = uuid.hexString.filter { $0 != " " }
        let groups = [8, 4, 4, 4, 12]
        var result: [Substring] = []
        var index = hex.startIndex
        for length in groups {
            let end = hex.index(index, offsetBy: length)
            result.append(hex[index..<end])
            index = end
        }
        return result.joined(separator: "-")
    }
}

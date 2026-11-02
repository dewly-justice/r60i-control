// Dual connection (multipoint) device list: docs/protocol.md §6.8.

/// A Bluetooth address as it travels in `0B 01` records and `0B 81/82/83` writes.
///
/// The earbuds send it in reverse byte order: a real R60i NC reported this Mac
/// (5C:9B:A6:6E:D3:17) as 17 D3 6E A6 9B 5C. OpenSCQ30 shows the bytes as received but sends the
/// same bytes back, so on the wire we do the same and only reverse them for display.
public struct MACAddress: Hashable, Sendable, CustomStringConvertible {
    /// Bytes in wire order (reversed).
    public let bytes: [UInt8]

    public init(_ wireBytes: [UInt8]) {
        precondition(wireBytes.count == 6)
        self.bytes = wireBytes
    }

    /// From the usual display order, e.g. `[0x5C, 0x9B, …]` for 5C:9B:….
    public init(displayOrder bytes: [UInt8]) {
        self.init(Array(bytes.reversed()))
    }

    /// Display order, e.g. "5C:9B:A6:6E:D3:17".
    public var description: String {
        bytes.reversed().map { String($0, radix: 16, uppercase: true).leftPadded(2) }.joined(separator: ":")
    }
}

public struct DualConnectionDevice: Hashable, Sendable, Identifiable {
    public var isConnected: Bool
    public var address: MACAddress
    public var name: String

    public var id: MACAddress { address }

    public init(isConnected: Bool, address: MACAddress, name: String) {
        self.isConnected = isConnected
        self.address = address
        self.name = name
    }
}

/// One `0B 01` frame body. A list can span several frames (`index` 1…`total`).
public struct DualConnectionPacket: Hashable, Sendable {
    public var total: UInt8
    /// 1-based. A packet with index 1 starts a new list.
    public var index: UInt8
    public var devices: [DualConnectionDevice]

    public init(body: [UInt8]) throws(ParseError) {
        guard body.count >= 2 else { throw .tooShort(what: "dual-connection packet", needed: 2, got: body.count) }
        total = body[0]
        index = body[1]
        devices = []
        var offset = 2
        while offset < body.count {
            // [length][connected][MAC ×6][name, length − 8 bytes, zero-padded]
            guard body.count - offset >= 8 else {
                throw .tooShort(what: "dual-connection record", needed: 8, got: body.count - offset)
            }
            let length = Int(body[offset])
            let connected = body[offset + 1] == 1
            let address = MACAddress(Array(body[(offset + 2)..<(offset + 8)]))
            let declaredNameLength = max(length - 8, 0)
            // Real devices sometimes send a last record shorter than its length byte (OpenSCQ30).
            let nameLength = min(declaredNameLength, body.count - (offset + 8))
            let nameBytes = body[(offset + 8)..<(offset + 8 + nameLength)].prefix { $0 != 0 }
            devices.append(DualConnectionDevice(
                isConnected: connected,
                address: address,
                name: String(decoding: nameBytes, as: UTF8.self)
            ))
            offset += 8 + nameLength
        }
    }

    public var isLast: Bool { index >= total }
}

extension String {
    func leftPadded(_ width: Int, with pad: Character = "0") -> String {
        count >= width ? self : String(repeating: pad, count: width - count) + self
    }
}

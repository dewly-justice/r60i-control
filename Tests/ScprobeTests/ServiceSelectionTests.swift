import IOBluetooth
import Testing
@testable import scprobe
import SoundcoreProtocol

/// Service selection, using the SDP records macOS cached for a real R60i NC
/// (34-09-c9-f6-14-5a, 2026-11-02). No Bluetooth connection involved.
@Suite("service selection")
@MainActor
struct ServiceSelectionTests {
    static func uuid16(_ value: UInt16) -> [UInt8] {
        var bytes = SoundcoreServiceUUID.serialPort
        bytes[2] = UInt8(value >> 8)
        bytes[3] = UInt8(value & 0xFF)
        return bytes
    }

    static func uuid128(_ hex: String) -> [UInt8] {
        let digits = Array(hex.filter(\.isHexDigit))
        return stride(from: 0, to: digits.count, by: 2).map { UInt8(String(digits[$0...$0 + 1]), radix: 16)! }
    }

    /// The RFCOMM records from the real earbuds (records without a channel left out).
    static let r60iRecords: [ServiceInfo] = [
        ServiceInfo(name: "TOTA ", classUUIDs: [uuid16(0x1101)], channelID: 12),
        ServiceInfo(name: nil, classUUIDs: [uuid16(0x111E)], channelID: 1),
        ServiceInfo(name: nil, classUUIDs: [uuid16(0x1203)], channelID: 1),
        ServiceInfo(name: "BESOTA ", classUUIDs: [uuid128("66666666-6666-6666-6666-666666666666")], channelID: 13),
        ServiceInfo(name: "AVRCP Remote Control Target", classUUIDs: [uuid16(0x110C)], channelID: nil),
        ServiceInfo(name: "soundcore Liberty NC ", classUUIDs: [uuid128("0CF12D31-FAC3-4553-BD80-D6832E71202C")], channelID: 15),
        ServiceInfo(name: "RFCOMM COM ", classUUIDs: [uuid128("DF21FE2C-2515-4FDB-8886-F12C4D67927C")], channelID: 17),
        ServiceInfo(name: nil, classUUIDs: [uuid128("99999999-9999-9999-9999-999999999999")], channelID: 29),
    ]

    @Test func picksVendorServiceOnRealRecords() throws {
        let (service, uuid, suffix) = try #require(Discovery.pickService(Self.r60iRecords))
        #expect(service.channelID == 15)
        #expect(uuid == SoundcoreServiceUUID.d1202c)
        #expect(suffix == "1202C")
    }

    /// The only Serial Port record on the R60i NC is "TOTA" (likely firmware update). Never pick it.
    @Test func neverFallsBackToSerialPort() {
        let withoutVendor = Self.r60iRecords.filter { !$0.classUUIDs.contains(where: SoundcoreServiceUUID.isVendor) }
        #expect(Discovery.pickService(withoutVendor) == nil)
    }

    @Test func vendorServiceWithoutChannelIsSkipped() {
        let records = [ServiceInfo(name: nil, classUUIDs: [SoundcoreServiceUUID.d1202c], channelID: nil)]
        #expect(Discovery.pickService(records) == nil)
    }

    /// The R60i NC publishes ServiceClassIDList as a bare UUID instead of a sequence.
    @Test func classUUIDsAcceptsBareUUID() throws {
        let uuid = try #require(IOBluetoothSDPUUID(bytes: SoundcoreServiceUUID.d1202c, length: 16))
        let element = try #require(IOBluetoothSDPDataElement(elementValue: uuid))
        #expect(Int(element.getTypeDescriptor()) == kBluetoothSDPDataElementTypeUUID)
        #expect(Discovery.classUUIDs(element) == [SoundcoreServiceUUID.d1202c])
    }

    @Test func classUUIDsAcceptsSequenceAndExpands16Bit() throws {
        let vendor = try #require(IOBluetoothSDPUUID(bytes: SoundcoreServiceUUID.d1202c, length: 16))
        let spp = try #require(IOBluetoothSDPUUID.uuid16(0x1101))
        let element = try #require(IOBluetoothSDPDataElement(elementValue: [
            IOBluetoothSDPDataElement(elementValue: spp)!,
            IOBluetoothSDPDataElement(elementValue: vendor)!,
        ] as NSArray))
        #expect(Int(element.getTypeDescriptor()) == kBluetoothSDPDataElementTypeDataElementSequence)
        #expect(Discovery.classUUIDs(element) == [SoundcoreServiceUUID.serialPort, SoundcoreServiceUUID.d1202c])
    }

    @Test func classUUIDsIgnoresOtherTypes() throws {
        let element = try #require(IOBluetoothSDPDataElement(elementValue: NSNumber(value: UInt16(258))))
        #expect(Discovery.classUUIDs(element).isEmpty)
        #expect(Discovery.classUUIDs(nil).isEmpty)
    }
}

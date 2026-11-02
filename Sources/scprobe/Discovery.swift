import Foundation
import IOBluetooth
import SoundcoreProtocol

/// One SDP service record, reduced to what we need.
struct ServiceInfo {
    let name: String?
    let classUUIDs: [[UInt8]]
    let channelID: BluetoothRFCOMMChannelID?
}

/// How the probe reached the earbuds. Plain values, so the report can be tested without Bluetooth.
struct ConnectionSummary {
    let displayName: String
    let channelID: UInt8
    let serviceUUID: [UInt8]
    /// Last 5 hex digits of the vendor service UUID, e.g. "1202C".
    let vendorSuffix: String
    /// True if the device is confirmed to use the D1202 state/write layouts.
    let modelConfirmed: Bool
    let modelNote: String
}

/// The device and RFCOMM channel we'll open.
struct Target {
    let device: IOBluetoothDevice
    let summary: ConnectionSummary
    /// True if the channel came from cached SDP records, without a fresh query.
    let fromCache: Bool
}

@MainActor
final class Discovery: NSObject {
    private let log: Log
    private var sdpStatus: IOReturn?

    init(log: Log) {
        self.log = log
    }

    // MARK: Paired devices

    static func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
    }

    static func label(_ device: IOBluetoothDevice) -> String {
        "\(device.name ?? "(unnamed)") [\(device.addressString ?? "?")]"
    }

    static func services(of device: IOBluetoothDevice) -> [ServiceInfo] {
        (device.services ?? []).compactMap { $0 as? IOBluetoothSDPServiceRecord }.map { record in
            var channel: BluetoothRFCOMMChannelID = 0
            let hasChannel = record.getRFCOMMChannelID(&channel) == kIOReturnSuccess
            return ServiceInfo(
                name: record.getServiceName(),
                classUUIDs: classUUIDs(record.getAttributeDataElement(0x0001)),
                channelID: hasChannel ? channel : nil
            )
        }
    }

    /// The UUIDs in a ServiceClassIDList (SDP attribute 0x0001), each expanded to 128 bits.
    /// The spec says this attribute is a sequence of UUIDs, but the R60i NC publishes a bare
    /// UUID, so both forms are accepted.
    static func classUUIDs(_ element: IOBluetoothSDPDataElement?) -> [[UInt8]] {
        guard let element else { return [] }
        switch Int(element.getTypeDescriptor()) {
        case kBluetoothSDPDataElementTypeUUID:
            guard let uuid = element.getUUIDValue()?.getWithLength(16) else { return [] }
            return [Array(UnsafeRawBufferPointer(start: uuid.bytes, count: uuid.length))]
        case kBluetoothSDPDataElementTypeDataElementSequence, kBluetoothSDPDataElementTypeDataElementAlternative:
            return (element.getArrayValue() ?? []).compactMap { $0 as? IOBluetoothSDPDataElement }.flatMap { child in
                Int(child.getTypeDescriptor()) == kBluetoothSDPDataElementTypeUUID ? classUUIDs(child) : []
            }
        default:
            return []
        }
    }

    /// The Soundcore vendor service (0CF12D31-…-D6832E7xxxxx) with an RFCOMM channel, or nil.
    ///
    /// No Serial Port (0x1101) fallback, unlike OpenSCQ30: on the R60i NC the only record with
    /// that class is "TOTA", which looks like the earbud chip's firmware-update channel
    /// (docs/protocol.md §1). We never send anything to it.
    static func pickService(_ services: [ServiceInfo]) -> (ServiceInfo, uuid: [UInt8], suffix: String)? {
        for service in services where service.channelID != nil {
            if let uuid = service.classUUIDs.first(where: SoundcoreServiceUUID.isVendor),
               let suffix = SoundcoreServiceUUID.vendorSuffix(uuid) {
                return (service, uuid, suffix)
            }
        }
        return nil
    }

    // MARK: Device selection

    func findDevice(address: String?) throws -> IOBluetoothDevice {
        let paired = Self.pairedDevices()

        if let address {
            let normalized = try Self.normalizeAddress(address)
            if let match = paired.first(where: { $0.addressString?.lowercased() == normalized }) {
                return match
            }
            guard let device = IOBluetoothDevice(addressString: normalized) else {
                throw ProbeError.invalidAddress(address)
            }
            log.info("Note: \(normalized) is not in the paired-devices list; trying anyway.")
            return device
        }

        guard !paired.isEmpty else { throw ProbeError.noPairedDevices }

        let byName = paired.filter { ($0.name ?? "").localizedCaseInsensitiveContains("R60i") }
        let byService = paired.filter { device in
            Self.services(of: device).contains { service in
                service.classUUIDs.contains { uuid in
                    SoundcoreServiceUUID.vendorSuffix(uuid).map(SoundcoreServiceUUID.d1202Suffixes.contains) ?? false
                }
            }
        }
        var candidates: [IOBluetoothDevice] = []
        for device in byName + byService where !candidates.contains(where: { $0.addressString == device.addressString }) {
            candidates.append(device)
        }

        switch candidates.count {
        case 0:
            throw ProbeError.deviceNotFound(candidates: paired.map(Self.label))
        case 1:
            return candidates[0]
        default:
            let connected = candidates.filter { $0.isConnected() }
            if connected.count == 1 { return connected[0] }
            throw ProbeError.ambiguousDevice(candidates: candidates.map(Self.label))
        }
    }

    static func normalizeAddress(_ address: String) throws -> String {
        let hex = address.lowercased().filter { $0.isHexDigit }
        let separatorsOK = address.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "-" }
        guard hex.count == 12, separatorsOK else { throw ProbeError.invalidAddress(address) }
        var pairs: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            pairs.append(String(hex[index..<next]))
            index = next
        }
        return pairs.joined(separator: "-")
    }

    // MARK: Service resolution

    func resolveService(on device: IOBluetoothDevice, forceRefresh: Bool) throws -> Target {
        let label = Self.label(device)
        var services = Self.services(of: device)
        var fromCache = true

        if forceRefresh || Self.pickService(services) == nil {
            log.info("Querying Bluetooth services (SDP) on \(label)…")
            refreshSDP(device)
            services = Self.services(of: device)
            fromCache = false
        }

        guard let (service, uuid, suffix) = Self.pickService(services), let channel = service.channelID else {
            throw ProbeError.noService(device: label, records: services.count, connected: device.isConnected())
        }

        let confirmed = SoundcoreServiceUUID.d1202Suffixes.contains(suffix)
        let note = confirmed
            ? "model ID \(suffix) from service UUID"
            : "service UUID suggests model \(suffix), not D1202/D1202C"

        return Target(
            device: device,
            summary: ConnectionSummary(
                displayName: label,
                channelID: channel,
                serviceUUID: uuid,
                vendorSuffix: suffix,
                modelConfirmed: confirmed,
                modelNote: note
            ),
            fromCache: fromCache
        )
    }

    /// Runs an SDP query, waits up to 20 s for it to finish, and logs how it went.
    private func refreshSDP(_ device: IOBluetoothDevice) {
        sdpStatus = nil
        let started = Date()
        let start = device.performSDPQuery(self)
        guard start == kIOReturnSuccess else {
            log.info("Couldn't start the SDP query: \(ioReturnDescription(start))")
            return
        }
        RunLoopWait.until(timeout: 20) { sdpStatus != nil }
        let elapsed = String(format: "%.1f s", Date().timeIntervalSince(started))
        switch sdpStatus {
        case nil:
            log.info("SDP query: no answer from macOS within \(elapsed).")
        case let status? where status != kIOReturnSuccess:
            log.info("SDP query failed after \(elapsed): \(ioReturnDescription(status))")
        default:
            log.info("SDP query finished in \(elapsed).")
        }
    }

    /// IOBluetooth calls this informal-protocol method on the target passed to performSDPQuery.
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        sdpStatus = status
    }

    // MARK: `scprobe list`

    static func printList() throws {
        let paired = pairedDevices()
        guard !paired.isEmpty else { throw ProbeError.noPairedDevices }
        print("Paired Bluetooth devices (services from cached SDP records; nothing is connected):")
        for device in paired {
            let state = device.isConnected() ? "connected" : "not connected"
            print("• \(label(device)) — \(state)")
            let services = Self.services(of: device)
            let picked = pickService(services)
            if let (service, uuid, suffix) = picked, let channel = service.channelID {
                print("    Soundcore vendor service (model \(suffix)) \(SoundcoreServiceUUID.format(uuid)) on RFCOMM channel \(channel)")
            } else if services.isEmpty {
                print("    no cached SDP records")
            } else {
                print("    no Soundcore vendor RFCOMM service in \(services.count) cached SDP records")
            }
            // For Soundcore devices, show every RFCOMM service too, to help diagnose channel problems.
            guard picked != nil || (device.name ?? "").localizedCaseInsensitiveContains("soundcore") else { continue }
            for service in services {
                guard let channel = service.channelID else { continue }
                let uuids = service.classUUIDs.map(SoundcoreServiceUUID.format).joined(separator: ", ")
                let name = service.name?.trimmingCharacters(in: .whitespaces) ?? "(unnamed)"
                print("      RFCOMM \(String(channel).leftPadded(to: 2))  \(name) — \(uuids.isEmpty ? "no class UUID" : uuids)")
            }
        }
    }
}

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
    enum ServiceKind {
        case vendor(suffix: String)
        case serialPort
    }

    let displayName: String
    let channelID: UInt8
    let serviceUUID: [UInt8]
    let kind: ServiceKind
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
            // Attribute 0x0001 = ServiceClassIDList: a sequence of UUIDs.
            let elements = record.getAttributeDataElement(0x0001)?.getArrayValue() ?? []
            let uuids: [[UInt8]] = elements.compactMap { element in
                guard let element = element as? IOBluetoothSDPDataElement,
                      let uuid = element.getUUIDValue()?.getWithLength(16)
                else { return nil }
                return Array(UnsafeRawBufferPointer(start: uuid.bytes, count: uuid.length))
            }
            var channel: BluetoothRFCOMMChannelID = 0
            let hasChannel = record.getRFCOMMChannelID(&channel) == kIOReturnSuccess
            return ServiceInfo(name: record.getServiceName(), classUUIDs: uuids, channelID: hasChannel ? channel : nil)
        }
    }

    /// Soundcore vendor service first, then Serial Port. Only services that have an RFCOMM channel count.
    static func pickService(_ services: [ServiceInfo]) -> (ServiceInfo, [UInt8], ConnectionSummary.ServiceKind)? {
        for service in services where service.channelID != nil {
            if let uuid = service.classUUIDs.first(where: SoundcoreServiceUUID.isVendor),
               let suffix = SoundcoreServiceUUID.vendorSuffix(uuid) {
                return (service, uuid, .vendor(suffix: suffix))
            }
        }
        for service in services where service.channelID != nil {
            if let uuid = service.classUUIDs.first(where: { $0 == SoundcoreServiceUUID.serialPort }) {
                return (service, uuid, .serialPort)
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
            let status = refreshSDP(device)
            if status != kIOReturnSuccess {
                log.info("SDP query did not succeed: \(ioReturnDescription(status))")
            }
            services = Self.services(of: device)
            fromCache = false
        }

        guard let (service, uuid, kind) = Self.pickService(services), let channel = service.channelID else {
            throw ProbeError.noService(device: label)
        }

        let nameMatches = (device.name ?? "").localizedCaseInsensitiveContains("R60i")
        let confirmed: Bool
        let note: String
        switch kind {
        case let .vendor(suffix) where SoundcoreServiceUUID.d1202Suffixes.contains(suffix):
            confirmed = true
            note = "model ID \(suffix) from service UUID"
        case let .vendor(suffix):
            confirmed = false
            note = "service UUID suggests model \(suffix), not D1202/D1202C"
        case .serialPort where nameMatches:
            confirmed = true
            note = "no vendor service; matched by device name"
        case .serialPort:
            confirmed = false
            note = "no vendor service and the name doesn't contain \"R60i\""
        }

        return Target(
            device: device,
            summary: ConnectionSummary(
                displayName: label,
                channelID: channel,
                serviceUUID: uuid,
                kind: kind,
                modelConfirmed: confirmed,
                modelNote: note
            ),
            fromCache: fromCache
        )
    }

    /// Runs an SDP query and waits up to 20 s for it to finish.
    private func refreshSDP(_ device: IOBluetoothDevice) -> IOReturn {
        sdpStatus = nil
        let start = device.performSDPQuery(self)
        guard start == kIOReturnSuccess else { return start }
        RunLoopWait.until(timeout: 20) { sdpStatus != nil }
        return sdpStatus ?? kIOReturnTimeout
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
            if let (service, uuid, kind) = pickService(services), let channel = service.channelID {
                let kindText = switch kind {
                case let .vendor(suffix): "Soundcore vendor service (model \(suffix))"
                case .serialPort: "Serial Port service"
                }
                print("    \(kindText) \(SoundcoreServiceUUID.format(uuid)) on RFCOMM channel \(channel)")
            } else if services.isEmpty {
                print("    no cached SDP records")
            } else {
                print("    no Soundcore or Serial Port RFCOMM service in \(services.count) cached SDP records")
            }
        }
    }
}

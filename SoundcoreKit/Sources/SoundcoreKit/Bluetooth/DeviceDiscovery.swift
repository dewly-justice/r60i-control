import Foundation
import IOBluetooth

/// One SDP service record, reduced to what we need.
public struct ServiceInfo: Sendable, Hashable {
    public let name: String?
    public let classUUIDs: [[UInt8]]
    public let channelID: UInt8?

    public init(name: String?, classUUIDs: [[UInt8]], channelID: UInt8?) {
        self.name = name
        self.classUUIDs = classUUIDs
        self.channelID = channelID
    }
}

/// How we reached the earbuds. Plain values, so it can be shown and tested without Bluetooth.
public struct ConnectionSummary: Sendable, Hashable {
    public let displayName: String
    public let channelID: UInt8
    public let serviceUUID: [UInt8]
    /// Last 5 hex digits of the vendor service UUID, e.g. "1202C".
    public let vendorSuffix: String
    /// True if the earbuds' service UUID says D1202/D1202C, so the D1202 write layouts apply.
    public var modelConfirmed: Bool { SoundcoreServiceUUID.d1202Suffixes.contains(vendorSuffix) }
    /// True if the channel came from cached SDP records, without a fresh query.
    public let fromCache: Bool

    public init(displayName: String, channelID: UInt8, serviceUUID: [UInt8], vendorSuffix: String, fromCache: Bool) {
        self.displayName = displayName
        self.channelID = channelID
        self.serviceUUID = serviceUUID
        self.vendorSuffix = vendorSuffix
        self.fromCache = fromCache
    }

    public var modelNote: String {
        modelConfirmed
            ? "model ID \(vendorSuffix) from service UUID"
            : "service UUID suggests model \(vendorSuffix), not D1202/D1202C"
    }
}

/// Finding the earbuds and their control channel: docs/protocol.md §1.
@MainActor
public enum DeviceDiscovery {
    // MARK: Paired devices

    public static func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
    }

    public static func label(_ device: IOBluetoothDevice) -> String {
        "\(device.name ?? "(unnamed)") [\(device.addressString ?? "?")]"
    }

    /// This Mac's Bluetooth address, to recognize it in the dual-connection device list.
    public static var hostAddress: MACAddress? {
        guard let text = IOBluetoothHostController.default()?.addressAsString() else { return nil }
        let hex = text.filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        let bytes = stride(from: 0, to: 12, by: 2).compactMap { offset -> UInt8? in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)
        }
        return bytes.count == 6 ? MACAddress(displayOrder: bytes) : nil
    }

    public static var isBluetoothPoweredOn: Bool {
        IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
    }

    /// Paired devices that look like a D1202/D1202C: name contains "R60i", or a cached SDP record
    /// carries the D1202 vendor UUID. Connected devices come first.
    public static func candidates() -> [IOBluetoothDevice] {
        let matches = pairedDevices().filter(isCandidate)
        var unique: [IOBluetoothDevice] = []
        for device in matches where !unique.contains(where: { $0.addressString == device.addressString }) {
            unique.append(device)
        }
        return unique.sorted { $0.isConnected() && !$1.isConnected() }
    }

    public static func isCandidate(_ device: IOBluetoothDevice) -> Bool {
        if (device.name ?? "").localizedCaseInsensitiveContains("R60i") { return true }
        return services(of: device).contains { service in
            service.classUUIDs.contains { uuid in
                SoundcoreServiceUUID.vendorSuffix(uuid).map(SoundcoreServiceUUID.d1202Suffixes.contains) ?? false
            }
        }
    }

    /// Picks the device for `address` (any format), or the single candidate.
    public static func findDevice(address: String?) throws(SoundcoreError) -> IOBluetoothDevice {
        let paired = pairedDevices()
        if let address {
            let normalized = try normalizeAddress(address)
            if let match = paired.first(where: { $0.addressString?.lowercased() == normalized }) {
                return match
            }
            guard let device = IOBluetoothDevice(addressString: normalized) else {
                throw .invalidAddress(address)
            }
            return device
        }
        guard !paired.isEmpty else { throw .noPairedDevices }
        let found = candidates()
        switch found.count {
        case 0:
            throw .deviceNotFound(paired: paired.map(label))
        case 1:
            return found[0]
        default:
            let connected = found.filter { $0.isConnected() }
            if connected.count == 1 { return connected[0] }
            throw .ambiguousDevice(found.map(label))
        }
    }

    public static func normalizeAddress(_ address: String) throws(SoundcoreError) -> String {
        let hex = address.lowercased().filter(\.isHexDigit)
        let separatorsOK = address.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "-" }
        guard hex.count == 12, separatorsOK else { throw .invalidAddress(address) }
        var pairs: [String] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            pairs.append(String(hex[index..<next]))
            index = next
        }
        return pairs.joined(separator: "-")
    }

    // MARK: SDP records

    public static func services(of device: IOBluetoothDevice) -> [ServiceInfo] {
        (device.services ?? []).compactMap { $0 as? IOBluetoothSDPServiceRecord }.map { record in
            var channel: BluetoothRFCOMMChannelID = 0
            let hasChannel = record.getRFCOMMChannelID(&channel) == kIOReturnSuccess
            return ServiceInfo(
                name: record.getServiceName()?.trimmingCharacters(in: .whitespaces),
                classUUIDs: classUUIDs(record.getAttributeDataElement(0x0001)),
                channelID: hasChannel ? channel : nil
            )
        }
    }

    /// The UUIDs in a ServiceClassIDList (SDP attribute 0x0001), each expanded to 128 bits.
    /// The spec says this attribute is a sequence of UUIDs, but the R60i NC publishes a bare
    /// UUID, so both forms are accepted.
    public static func classUUIDs(_ element: IOBluetoothSDPDataElement?) -> [[UInt8]] {
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
    public static func pickService(_ services: [ServiceInfo]) -> (service: ServiceInfo, uuid: [UInt8], suffix: String)? {
        for service in services where service.channelID != nil {
            if let uuid = service.classUUIDs.first(where: SoundcoreServiceUUID.isVendor),
               let suffix = SoundcoreServiceUUID.vendorSuffix(uuid) {
                return (service, uuid, suffix)
            }
        }
        return nil
    }

    /// Finds the control channel: cached SDP records first, then a fresh SDP query if the cache
    /// has none (or `forceRefresh`).
    public static func resolveService(
        on device: IOBluetoothDevice,
        forceRefresh: Bool = false,
        log: ((String) -> Void)? = nil
    ) async throws(SoundcoreError) -> ConnectionSummary {
        var services = services(of: device)
        var fromCache = true
        if forceRefresh || pickService(services) == nil {
            log?("Querying Bluetooth services (SDP) on \(label(device))…")
            let started = ContinuousClock.now
            let status = await performSDPQuery(device)
            let elapsed = (ContinuousClock.now - started).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
            switch status {
            case nil: log?("SDP query: no answer from macOS within \(elapsed).")
            case let status? where status != kIOReturnSuccess: log?("SDP query failed after \(elapsed): \(ioReturnDescription(status))")
            default: log?("SDP query finished in \(elapsed).")
            }
            services = Self.services(of: device)
            fromCache = false
        }
        guard let (service, uuid, suffix) = pickService(services), let channel = service.channelID else {
            throw .noService(device: label(device), records: services.count, connected: device.isConnected())
        }
        return ConnectionSummary(
            displayName: label(device), channelID: channel, serviceUUID: uuid,
            vendorSuffix: suffix, fromCache: fromCache
        )
    }

    /// Runs an SDP query. Returns its status, or nil if macOS doesn't answer within `timeout`.
    public static func performSDPQuery(_ device: IOBluetoothDevice, timeout: Duration = .seconds(20)) async -> IOReturn? {
        let query = SDPQuery()
        return await query.run(on: device, timeout: timeout)
    }
}

/// Target object for IOBluetooth's informal `sdpQueryComplete:status:` callback.
@MainActor
final class SDPQuery: NSObject {
    private var continuation: CheckedContinuation<IOReturn?, Never>?

    func run(on device: IOBluetoothDevice, timeout: Duration) async -> IOReturn? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let start = device.performSDPQuery(self)
            if start != kIOReturnSuccess {
                finish(start)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.finish(nil)
            }
        }
    }

    private func finish(_ status: IOReturn?) {
        continuation?.resume(returning: status)
        continuation = nil
    }

    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        onMainActor { [self] in finish(status) }
    }
}

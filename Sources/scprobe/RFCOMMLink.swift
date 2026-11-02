import Foundation
import IOBluetooth
import SoundcoreProtocol

/// An open IOBluetooth RFCOMM channel. All use is on the main thread; callbacks arrive through
/// the main run loop.
@MainActor
final class RFCOMMLink: NSObject {
    private let log: Log
    private var channel: IOBluetoothRFCOMMChannel?
    private(set) var isOpen = false

    var onData: (([UInt8]) -> Void)?

    init(log: Log) {
        self.log = log
    }

    func open(device: IOBluetoothDevice, channelID: BluetoothRFCOMMChannelID) throws {
        var opened: IOBluetoothRFCOMMChannel?
        let status = device.openRFCOMMChannelSync(&opened, withChannelID: channelID, delegate: self)
        guard status == kIOReturnSuccess, let opened else {
            throw ProbeError.openFailed(status)
        }
        channel = opened
        isOpen = true
    }

    /// Writes all bytes, split into MTU-sized chunks.
    func write(_ bytes: [UInt8], note: String? = nil) throws {
        guard let channel, isOpen else { throw ProbeError.channelClosed }
        log.bytes("→", bytes, note: note)
        let mtu = max(Int(channel.getMTU()), 1)
        var offset = 0
        while offset < bytes.count {
            var chunk = Array(bytes[offset..<min(offset + mtu, bytes.count)])
            let status = chunk.withUnsafeMutableBytes { buffer in
                channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
            }
            guard status == kIOReturnSuccess else { throw ProbeError.writeFailed(status) }
            offset += chunk.count
        }
    }

    /// Closes only the RFCOMM channel. The Bluetooth (audio) connection to the earbuds stays up:
    /// we never call IOBluetoothDevice.closeConnection().
    func close() {
        guard let channel else { return }
        if isOpen {
            channel.close()
            RunLoopWait.until(timeout: 1) { !isOpen }
        }
        channel.setDelegate(nil)
        self.channel = nil
        isOpen = false
    }
}

extension RFCOMMLink: @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        // The pointer is only valid during this call, so copy the bytes now.
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        log.bytes("←", bytes)
        onData?(bytes)
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        isOpen = false
    }
}

import Foundation
import IOBluetooth

/// A byte pipe to the earbuds. `RFCOMMLink` is the real one; tests use a fake.
@MainActor
public protocol PacketLink: AnyObject {
    var isOpen: Bool { get }
    /// Called with each chunk of inbound bytes, in order.
    var onReceive: (([UInt8]) -> Void)? { get set }
    /// Called once when the link closes from the far end.
    var onClose: (() -> Void)? { get set }
    func write(_ bytes: [UInt8]) throws(SoundcoreError)
    func close() async
}

/// An IOBluetooth RFCOMM channel. Used only on the main actor; IOBluetooth delivers its
/// callbacks through the main run loop.
@MainActor
public final class RFCOMMLink: NSObject, PacketLink {
    private var channel: IOBluetoothRFCOMMChannel?
    private var openContinuation: CheckedContinuation<Void, any Error>?
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []

    public private(set) var isOpen = false
    public var onReceive: (([UInt8]) -> Void)?
    public var onClose: (() -> Void)?

    override init() {}

    /// Opens the channel without blocking the main thread.
    ///
    /// On macOS 27 the first RFCOMM open in a process silently fails: `openRFCOMMChannelAsync`
    /// returns success but never calls back (the sync variant returns kIOReturnError after ~3 s),
    /// and bluetoothd never sees a request. An immediate retry opens in well under a second.
    /// So the first attempt gets a short timeout, and failed attempts are retried.
    public static func open(
        device: IOBluetoothDevice,
        channelID: UInt8,
        attemptTimeouts: [Duration] = [.seconds(4), .seconds(8), .seconds(8)],
        log: ((String) -> Void)? = nil
    ) async throws(SoundcoreError) -> RFCOMMLink {
        var lastError = SoundcoreError.openTimedOut
        for (attempt, timeout) in attemptTimeouts.enumerated() {
            let link = RFCOMMLink()
            do {
                try await link.open(device: device, channelID: channelID, timeout: timeout)
                return link
            } catch let error as SoundcoreError {
                lastError = error
            } catch {
                lastError = .openTimedOut
            }
            if attempt < attemptTimeouts.count - 1 {
                log?("Opening RFCOMM channel \(channelID) failed (\(lastError)); retrying…")
            }
        }
        throw lastError
    }

    private func open(device: IOBluetoothDevice, channelID: UInt8, timeout: Duration) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            openContinuation = continuation
            var opened: IOBluetoothRFCOMMChannel?
            let status = device.openRFCOMMChannelAsync(&opened, withChannelID: channelID, delegate: self)
            channel = opened
            guard status == kIOReturnSuccess else {
                finishOpen(.failure(SoundcoreError.openFailed(status)))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, self.openContinuation != nil else { return }
                self.channel?.close()
                self.finishOpen(.failure(SoundcoreError.openTimedOut))
            }
        }
    }

    private func finishOpen(_ result: Result<Void, any Error>) {
        guard let continuation = openContinuation else { return }
        openContinuation = nil
        if case .failure = result {
            channel?.setDelegate(nil)
            channel = nil
        }
        continuation.resume(with: result)
    }

    /// Writes all bytes, split into MTU-sized chunks.
    public func write(_ bytes: [UInt8]) throws(SoundcoreError) {
        guard let channel, isOpen else { throw .channelClosed }
        let mtu = max(Int(channel.getMTU()), 1)
        var offset = 0
        while offset < bytes.count {
            var chunk = Array(bytes[offset..<min(offset + mtu, bytes.count)])
            let status = chunk.withUnsafeMutableBytes { buffer in
                channel.writeSync(buffer.baseAddress, length: UInt16(buffer.count))
            }
            guard status == kIOReturnSuccess else { throw .writeFailed(status) }
            offset += chunk.count
        }
    }

    /// Closes only the RFCOMM channel and waits up to 1 s for it to finish. The Bluetooth (audio)
    /// connection to the earbuds stays up: we never call IOBluetoothDevice.closeConnection().
    public func close() async {
        guard let channel else { return }
        onClose = nil
        if isOpen {
            channel.close()
            await withCheckedContinuation { continuation in
                closeWaiters.append(continuation)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.resumeCloseWaiters()
                }
            }
        }
        channel.setDelegate(nil)
        self.channel = nil
        isOpen = false
    }

    private func resumeCloseWaiters() {
        let waiters = closeWaiters
        closeWaiters = []
        waiters.forEach { $0.resume() }
    }
}

extension RFCOMMLink: IOBluetoothRFCOMMChannelDelegate {
    nonisolated public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        onMainActor { [self] in
            if error == kIOReturnSuccess {
                isOpen = true
                finishOpen(.success(()))
            } else {
                finishOpen(.failure(SoundcoreError.openFailed(error)))
            }
        }
    }

    nonisolated public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        // The pointer is only valid during this call, so copy the bytes now.
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        onMainActor { [self] in onReceive?(bytes) }
    }

    nonisolated public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        onMainActor { [self] in
            let wasOpen = isOpen
            isOpen = false
            resumeCloseWaiters()
            if openContinuation != nil {
                finishOpen(.failure(SoundcoreError.channelClosed))
            } else if wasOpen {
                onClose?()
            }
        }
    }
}

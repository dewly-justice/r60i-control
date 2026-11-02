import AVFoundation
import CoreAudio
import os
import Speech

/// Captures the Mac's built-in microphone and hands its audio to the speech analyzer.
///
/// It uses `AVCaptureSession` with that one device rather than `AVAudioEngine`: the engine's
/// input node opens the *default* input as soon as it's touched, and when the earbuds are the
/// default input that switches them from A2DP to the hands-free profile (measured: 44.1 → 16 kHz),
/// so everything they play drops to call quality. The capture session opens only the device it's
/// given, and delivers audio already in the analyzer's format. Callbacks arrive on a private queue,
/// so nothing here is main-actor isolated.
final class AudioCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case noMicrophone
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .noMicrophone: "This Mac has no built-in microphone. Live Translation doesn't use the earbuds' microphone, which would drop them to call quality."
            case .unsupportedFormat: "The microphone's audio format can't be converted for speech recognition."
            }
        }
    }

    private static let log = Logger(subsystem: "dev.local.R60iControl", category: "translation")

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.local.R60iControl.capture")
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    /// Only used if the session delivers something other than the analyzer's format.
    private var converter: AVAudioConverter?
    private var buffers = 0

    /// The microphone being recorded, for display.
    private(set) var deviceName: String?

    func start(analyzerFormat: AVAudioFormat, into continuation: AsyncStream<AnalyzerInput>.Continuation) throws {
        guard let microphone = Self.builtInMicrophone() else { throw CaptureError.noMicrophone }
        deviceName = microphone.localizedName
        self.analyzerFormat = analyzerFormat
        self.continuation = continuation

        session.beginConfiguration()
        let input = try AVCaptureDeviceInput(device: microphone)
        guard session.canAddInput(input) else { throw CaptureError.unsupportedFormat }
        session.addInput(input)
        let output = AVCaptureAudioDataOutput()
        output.audioSettings = Self.settings(for: analyzerFormat)
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError.unsupportedFormat }
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
        Self.log.info("capture: \(microphone.localizedName, privacy: .public) → \(analyzerFormat.description, privacy: .public)")
    }

    func stop() {
        session.stopRunning()
        queue.sync {
            continuation = nil
        }
    }

    // MARK: AVCaptureAudioDataOutputSampleBufferDelegate (capture queue)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let continuation, let analyzerFormat, let description = sampleBuffer.formatDescription else { return }
        guard let format = AVAudioFormat(formatDescription: description) else { return }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        ) == noErr else { return }

        buffers += 1
        if buffers == 1 {
            Self.log.info("capture: first buffer, \(frames) frames of \(format.description, privacy: .public)")
        }
        if format == analyzerFormat {
            continuation.yield(AnalyzerInput(buffer: buffer))
        } else if let converted = convert(buffer, to: analyzerFormat) {
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let source = buffer
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }

    // MARK: Devices

    private static func builtInMicrophone() -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
            .devices
            .first { UInt32(bitPattern: $0.transportType) == kAudioDeviceTransportTypeBuiltIn }
    }

    /// Linear PCM settings matching the analyzer's format, so no conversion is needed.
    private static func settings(for format: AVAudioFormat) -> [String: Any] {
        let isFloat = format.commonFormat == .pcmFormatFloat32 || format.commonFormat == .pcmFormatFloat64
        let bits = switch format.commonFormat {
        case .pcmFormatInt16: 16
        case .pcmFormatInt32, .pcmFormatFloat32: 32
        case .pcmFormatFloat64: 64
        default: 16
        }
        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: bits,
            AVLinearPCMIsFloatKey: isFloat,
            AVLinearPCMIsNonInterleaved: !format.isInterleaved,
        ]
    }

    /// Whether sound currently plays on a Bluetooth device (the earbuds), where reading a
    /// translation aloud can't feed back into the Mac's microphone.
    static func outputIsBluetooth() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return false }
        address.mSelector = kAudioDevicePropertyTransportType
        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}

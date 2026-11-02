import Foundation
import IOBluetooth
import SoundcoreProtocol

// scprobe — Phase 1 probe for the Soundcore R60i NC (D1202C).
// It only sends `01 01` (request state) and `06 81` (set sound modes). See docs/protocol.md §12.

@MainActor
func run(_ options: Options) throws {
    let log = Log(hexdump: options.hexdump)

    switch options.action {
    case .help:
        print(CLI.usage)
        return
    case .list:
        try Discovery.printList()
        return
    case .state, .setMode:
        break
    }

    let discovery = Discovery(log: log)
    let device = try discovery.findDevice(address: options.address)
    var target = try discovery.resolveService(on: device, forceRefresh: false)

    let link = RFCOMMLink(log: log)
    log.info("Connecting to \(target.summary.displayName) on RFCOMM channel \(target.summary.channelID)…")
    do {
        try link.open(device: device, channelID: target.summary.channelID)
    } catch ProbeError.openFailed(let status) where target.fromCache {
        // A cached SDP record may hold an old channel number. Refresh once and retry.
        log.info("Open failed (\(ioReturnDescription(status))); refreshing SDP records and retrying once…")
        target = try discovery.resolveService(on: device, forceRefresh: true)
        try link.open(device: device, channelID: target.summary.channelID)
    }
    defer { link.close() }
    log.info("Connected.")

    let session = Session(link: link, log: log)
    session.onPush = { frame in print(Report.describePush(frame)) }

    let state = try session.readState()

    switch options.action {
    case .state:
        print(Report.render(state, connection: target.summary))
    case let .setMode(mode):
        try setMode(mode, current: state, connection: target.summary, session: session, log: log)
    case .list, .help:
        break
    }

    if options.listenSeconds > 0 {
        log.info("Listening for pushed packets for \(options.listenSeconds) s (Ctrl-C to stop)…")
        Interrupt.install()
        session.listen(seconds: options.listenSeconds) { Interrupt.requested }
        if !link.isOpen { log.info("The earbuds closed the channel.") }
    }
}

@MainActor
func setMode(_ mode: AmbientSoundMode, current state: D1202State, connection: ConnectionSummary, session: Session, log: Log) throws {
    guard connection.modelConfirmed else { throw ProbeError.unconfirmedModel(connection.modelNote) }

    let current = state.soundModes
    let currentName = current.ambient?.displayName ?? "unknown (\(current.ambientRaw))"
    guard current.ambient != mode else {
        print("Sound mode is already \(mode.displayName); nothing sent.")
        return
    }

    var desired = current
    desired.ambient = mode
    let frame: Frame
    do {
        frame = try Requests.setSoundModes(desired)
    } catch {
        throw ProbeError.encode(error)
    }

    // Report any byte (other than the mode byte) that OpenSCQ30-style normalization changed.
    let normalized = zip(current.raw, frame.body).enumerated().filter { $0.offset != 0 && $0.element.0 != $0.element.1 }
    for (index, (was, now)) in normalized {
        log.info("note: sound-modes byte \(index) normalized \([was].hexString) → \([now].hexString) (same as OpenSCQ30)")
    }

    print("Sound mode: \(currentName) → \(mode.displayName)")
    _ = try session.send(frame)
    log.info("Earbuds acknowledged 06 81. Reading state back to confirm…")

    var confirmed = try session.readState()
    for _ in 0..<2 where confirmed.soundModes.ambient != mode {
        RunLoopWait.until(timeout: 0.3) { false }
        confirmed = try session.readState()
    }
    guard confirmed.soundModes.ambient == mode else {
        throw ProbeError.modeNotApplied(
            expected: mode,
            got: confirmed.soundModes.ambient?.displayName ?? "unknown (\(confirmed.soundModes.ambientRaw))"
        )
    }
    print("Confirmed: sound mode is now \(mode.displayName). Sound-modes bytes: \(confirmed.soundModes.raw.hexString)")
}

/// Ctrl-C during --listen ends listening cleanly so the RFCOMM channel gets closed.
@MainActor
enum Interrupt {
    static var requested = false
    private static var source: DispatchSourceSignal?

    static func install() {
        guard source == nil else { return }
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { Interrupt.requested = true }
        }
        source.resume()
        self.source = source
    }
}

// MARK: - Entry point

let exitCode: Int32 = MainActor.assumeIsolated {
    let options: Options
    do {
        options = try CLI.parse(Array(CommandLine.arguments.dropFirst()))
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 2
    }
    do {
        try run(options)
        return 0
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 1
    }
}
exit(exitCode)

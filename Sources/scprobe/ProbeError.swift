import Foundation
import IOKit
import SoundcoreProtocol

enum ProbeError: Error, CustomStringConvertible {
    case usage(String)
    case noPairedDevices
    case deviceNotFound(candidates: [String])
    case ambiguousDevice(candidates: [String])
    case invalidAddress(String)
    case noService(device: String, records: Int, connected: Bool)
    case openFailed(IOReturn)
    case writeFailed(IOReturn)
    case channelClosed
    case timeout(Command)
    case parse(ParseError)
    case encode(EncodeError)
    case unconfirmedModel(String)
    case modeNotApplied(expected: AmbientSoundMode, got: String)
    case interrupted

    var description: String {
        switch self {
        case let .usage(message):
            "\(message)\nRun `scprobe --help` for usage."
        case .noPairedDevices:
            """
            No paired Bluetooth devices are visible to scprobe.
            • Pair the earbuds in System Settings → Bluetooth first.
            • If they are paired, Bluetooth permission may be missing: System Settings →
              Privacy & Security → Bluetooth, then enable the terminal app you ran this from.
            """
        case let .deviceNotFound(candidates):
            """
            Couldn't find a paired Soundcore R60i NC.
            Paired devices: \(candidates.isEmpty ? "(none)" : candidates.joined(separator: ", "))
            Use `scprobe list` to inspect them, or pass --address.
            """
        case let .ambiguousDevice(candidates):
            "Several possible earbuds found: \(candidates.joined(separator: ", ")). Pick one with --address."
        case let .invalidAddress(address):
            "Not a valid Bluetooth address: \(address)"
        case let .noService(device, records, connected):
            """
            Found no Soundcore RFCOMM service (0CF12D31-…-D6832E7xxxxx) among the \(records) SDP records \
            of \(device), which is \(connected ? "connected" : "not connected") to this Mac.
            • Take the earbuds out of the case, make sure they're connected to this Mac, and retry.
            • `scprobe list` shows every RFCOMM service they publish; send me its output.
            """
        case let .openFailed(status):
            """
            Opening the RFCOMM channel failed: \(ioReturnDescription(status)).
            • Make sure the earbuds are out of the case and connected (or connectable) to this Mac.
            • Close the Soundcore app on your phone if it is in the foreground, then retry.
            """
        case let .writeFailed(status):
            "Writing to the RFCOMM channel failed: \(ioReturnDescription(status))"
        case .channelClosed:
            "The earbuds closed the RFCOMM channel."
        case let .timeout(command):
            "No reply to \(command) \(command.name.map { "(\($0)) " } ?? "")after 3 attempts (0.5 s, 1 s, 1.5 s)."
        case let .parse(error):
            "Couldn't parse the reply: \(error)"
        case let .encode(error):
            error.description
        case let .unconfirmedModel(details):
            "Refusing to write: can't confirm this is a D1202/D1202C (\(details)). Reads still work."
        case let .modeNotApplied(expected, got):
            "Sent the mode change, but the earbuds now report \(got) instead of \(expected.displayName)."
        case .interrupted:
            "Interrupted."
        }
    }
}

func ioReturnDescription(_ status: IOReturn) -> String {
    let hex = String(format: "0x%08X", UInt32(bitPattern: status))
    let name: String? = switch status {
    case kIOReturnSuccess: "success"
    case kIOReturnError: "general error"
    case kIOReturnNoDevice: "no such device"
    case kIOReturnNotPermitted: "not permitted"
    case kIOReturnNotPrivileged: "not privileged"
    case kIOReturnBusy: "device busy"
    case kIOReturnTimeout: "timed out"
    case kIOReturnNotOpen: "device not open"
    case kIOReturnNotAttached: "device not attached"
    case kIOReturnNotResponding: "device not responding"
    case kIOReturnAborted: "aborted"
    default: nil
    }
    return name.map { "\($0) (\(hex))" } ?? hex
}

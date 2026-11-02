import Foundation
import IOKit

/// Errors from finding, connecting to, and talking to the earbuds. Descriptions are written for
/// people, with a hint where one helps.
public enum SoundcoreError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case bluetoothOff
    case noPairedDevices
    case deviceNotFound(paired: [String])
    case ambiguousDevice([String])
    case invalidAddress(String)
    case noService(device: String, records: Int, connected: Bool)
    case openFailed(IOReturn)
    case openTimedOut
    case writeFailed(IOReturn)
    case channelClosed
    case timeout(Command)
    case parse(ParseError)
    case encode(EncodeError)
    case notConnected
    case unconfirmedModel(String)
    /// The earbuds acknowledged a write but the state doesn't show it.
    case notApplied(String)

    public var description: String {
        switch self {
        case .bluetoothOff:
            "Bluetooth is turned off."
        case .noPairedDevices:
            """
            No paired Bluetooth devices are visible.
            • Pair the earbuds in System Settings → Bluetooth first.
            • If they are paired, Bluetooth permission may be missing: System Settings →
              Privacy & Security → Bluetooth.
            """
        case let .deviceNotFound(paired):
            """
            Couldn't find a paired Soundcore R60i NC.
            Paired devices: \(paired.isEmpty ? "(none)" : paired.joined(separator: ", "))
            """
        case let .ambiguousDevice(candidates):
            "Several possible earbuds found: \(candidates.joined(separator: ", ")). Pick one by address."
        case let .invalidAddress(address):
            "Not a valid Bluetooth address: \(address)"
        case let .noService(device, records, connected):
            """
            Found no Soundcore RFCOMM service (0CF12D31-…-D6832E7xxxxx) among the \(records) SDP records \
            of \(device), which is \(connected ? "connected" : "not connected") to this Mac. \
            Take the earbuds out of the case, make sure they're connected to this Mac, and retry.
            """
        case let .openFailed(status):
            """
            Opening the control channel failed: \(ioReturnDescription(status)). Make sure the \
            earbuds are out of the case and connected to this Mac.
            """
        case .openTimedOut:
            "The earbuds didn't open the control channel in time."
        case let .writeFailed(status):
            "Sending to the earbuds failed: \(ioReturnDescription(status))"
        case .channelClosed:
            "The earbuds closed the control channel."
        case let .timeout(command):
            "No reply to \(command) \(command.name.map { "(\($0)) " } ?? "")after 3 attempts."
        case let .parse(error):
            "Couldn't parse the earbuds' reply: \(error)"
        case let .encode(error):
            error.description
        case .notConnected:
            "The earbuds aren't connected."
        case let .unconfirmedModel(details):
            "Refusing to change settings: can't confirm these are D1202/D1202C earbuds (\(details))."
        case let .notApplied(details):
            "The earbuds accepted the change but didn't apply it. \(details)"
        }
    }

    public var errorDescription: String? { description }
}

public func ioReturnDescription(_ status: IOReturn) -> String {
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

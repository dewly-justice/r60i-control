import SoundcoreKit

enum ProbeError: Error, CustomStringConvertible {
    case usage(String)
    case device(SoundcoreError)
    case notApplied(String)

    var description: String {
        switch self {
        case let .usage(message):
            "\(message)\nRun `scprobe --help` for usage."
        case let .device(error):
            error.description
        case let .notApplied(details):
            "The earbuds acknowledged the write, but the state doesn't show the change: \(details)"
        }
    }
}

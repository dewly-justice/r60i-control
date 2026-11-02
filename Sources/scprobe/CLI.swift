import SoundcoreProtocol

struct Options {
    enum Action: Equatable {
        case state
        case setMode(AmbientSoundMode)
        case list
        case help
    }

    var action: Action = .state
    var hexdump = false
    var address: String?
    var listenSeconds: Double = 0
}

enum CLI {
    static let usage = """
    scprobe — talk to Soundcore R60i NC (D1202C) earbuds over Bluetooth RFCOMM.

    USAGE
      scprobe [options] [state]                  read and print the device state (default)
      scprobe [options] set-mode <mode>          mode: anc | transparency | normal
      scprobe list                               list paired devices and their Soundcore service

    OPTIONS
      --hexdump             log every byte sent (→) and received (←) to stderr
      --address <addr>      use this Bluetooth address instead of auto-detecting
                            (format AA-BB-CC-DD-EE-FF or AA:BB:CC:DD:EE:FF)
      --listen <seconds>    after the command, keep the channel open and print packets the
                            earbuds push (e.g. press/hold a bud to change ANC). Ctrl-C stops early.
      -h, --help            show this help

    The earbuds must be paired with this Mac and out of the case. They don't need to be
    playing audio. The first run asks for Bluetooth permission.
    """

    static func parse(_ arguments: [String]) throws(ProbeError) -> Options {
        var options = Options()
        var positionals: [String] = []
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "-h", "--help", "help":
                options.action = .help
                return options
            case "--hexdump":
                options.hexdump = true
            case "--address":
                guard let value = iterator.next() else { throw .usage("--address needs a value") }
                options.address = value
            case "--listen":
                guard let value = iterator.next(), let seconds = Double(value), seconds >= 0 else {
                    throw .usage("--listen needs a number of seconds")
                }
                options.listenSeconds = seconds
            default:
                if argument.hasPrefix("-") { throw .usage("unknown option \(argument)") }
                positionals.append(argument)
            }
        }

        switch positionals.first {
        case nil, "state":
            guard positionals.count <= 1 else { throw .usage("unexpected argument \(positionals[1])") }
            options.action = .state
        case "list":
            guard positionals.count == 1 else { throw .usage("unexpected argument \(positionals[1])") }
            options.action = .list
        case "set-mode":
            guard positionals.count == 2 else { throw .usage("set-mode needs exactly one mode: anc | transparency | normal") }
            switch positionals[1].lowercased() {
            case "anc", "nc", "noise-canceling": options.action = .setMode(.noiseCanceling)
            case "transparency", "transparent", "ambient": options.action = .setMode(.transparency)
            case "normal", "off": options.action = .setMode(.normal)
            default: throw .usage("unknown mode \(positionals[1]); use anc | transparency | normal")
            }
        case let other?:
            throw .usage("unknown command \(other)")
        }
        return options
    }
}

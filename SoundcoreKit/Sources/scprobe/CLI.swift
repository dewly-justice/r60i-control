import SoundcoreKit

/// One setting change, as typed on the command line. Each maps to one SoundcoreDevice method.
enum Setting: Equatable {
    case ambient(AmbientSoundMode)
    case noiseCancelingMode(NoiseCancelingMode)
    case ancLevel(Int)
    case scene(MultiSceneMode)
    case transparency(TransparencyMode)
    case wind(Bool)
    case realTimeAdaptive(Bool)
    case eqPreset(EqualizerPreset)
    case eqCustom([Int])
    /// nil = off
    case spatial(SpatialAudioMode?)
    case button(EarbudSide, GestureKind, ButtonAction?)
    case resetButtons
    /// The modes "Switch Sound Mode" cycles through now (two- or one-earbud cycle).
    case soundModeCycle(Set<AmbientSoundMode>)
    case dualConnections(Bool)
    /// nil = off
    case autoPowerOff(AutoPowerOffDuration?)
    case touchTone(Bool)
    case lowBatteryPrompt(Bool)
    case ldac(Bool)
    /// nil = off
    case volumeLimit(UInt8?)
    case decibelRefresh(DecibelRefreshRate)
    case dualConnect(MACAddress)
    case dualDisconnect(MACAddress)
    case dualForget(MACAddress)
}

struct Options {
    enum Action: Equatable {
        case state
        case set(Setting)
        case devices
        case list
        case help
    }

    var action: Action = .state
    var hexdump = false
    var address: String?
    var listenSeconds: Double = 0
    var refreshSDP = false
}

enum CLI {
    static let usage = """
    scprobe — talk to Soundcore R60i NC (D1202C) earbuds over Bluetooth RFCOMM.

    USAGE
      scprobe [options] [state]             read and print the device state (default)
      scprobe [options] set-mode <mode>     anc | transparency | normal
      scprobe [options] set <setting> <value>
      scprobe [options] devices             list the dual-connection devices
      scprobe list                          list paired devices and their RFCOMM services

    SETTINGS (each is one write from docs/protocol.md §7.2; the state is re-read afterwards
    and the changed lines are printed)
      mode anc|transparency|normal          nc-mode manual|adaptive|multi-scene
      anc-level 1-5                         scene transport|outdoor|indoor
      transparency full|vocal               wind on|off
      realtime-adaptive on|off              spatial off|music|movie|gaming
      eq <preset name or id>                eq-custom <8 values in dB, comma-separated>
      button left|right single|double|triple|long <action>
            action: volume-up volume-down previous next sound-mode voice-assistant play-pause none
      buttons-reset                         dual on|off
      cycle <modes, comma-separated>        modes press-and-hold cycles through: anc,transparency,normal
      auto-off off|10|20|30|60              touch-tone on|off
      low-battery-prompt on|off             ldac on|off
      volume-limit off|75|80|85|90|95|100   db-refresh realtime|10s|1min
      dual-connect <MAC>   dual-disconnect <MAC>   dual-forget <MAC>  (MAC from `devices`)

    OPTIONS
      --hexdump             log every byte sent (→) and received (←) to stderr
      --address <addr>      use this Bluetooth address instead of auto-detecting
      --listen <seconds>    afterwards, keep the channel open and print pushed packets
      --refresh-sdp         ignore cached SDP records and query the earbuds
      -h, --help            show this help
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
            case "--refresh-sdp":
                options.refreshSDP = true
            case "--address":
                guard let value = iterator.next() else { throw .usage("--address needs a value") }
                options.address = value
            case "--listen":
                guard let value = iterator.next(), let seconds = Double(value), seconds >= 0 else {
                    throw .usage("--listen needs a number of seconds")
                }
                options.listenSeconds = seconds
            default:
                if argument.hasPrefix("-"), Double(argument) == nil { throw .usage("unknown option \(argument)") }
                positionals.append(argument)
            }
        }

        switch positionals.first {
        case nil, "state":
            try expectCount(positionals, 1)
            options.action = .state
        case "list":
            try expectCount(positionals, 1)
            options.action = .list
        case "devices":
            try expectCount(positionals, 1)
            options.action = .devices
        case "set-mode":
            guard positionals.count == 2 else { throw .usage("set-mode needs one mode: anc | transparency | normal") }
            options.action = .set(.ambient(try ambient(positionals[1])))
        case "set":
            options.action = .set(try setting(Array(positionals.dropFirst())))
        case let other?:
            throw .usage("unknown command \(other)")
        }
        return options
    }

    private static func expectCount(_ positionals: [String], _ count: Int) throws(ProbeError) {
        if positionals.count > count { throw .usage("unexpected argument \(positionals[count])") }
    }

    static func setting(_ words: [String]) throws(ProbeError) -> Setting {
        guard let name = words.first?.lowercased() else { throw .usage("set needs a setting; see --help") }
        let values = Array(words.dropFirst())
        func value(_ count: Int = 1) throws(ProbeError) -> [String] {
            guard values.count == count else {
                throw .usage("set \(name) needs \(count) value\(count == 1 ? "" : "s")")
            }
            return values.map { $0.lowercased() }
        }
        func onOff() throws(ProbeError) -> Bool {
            switch try value()[0] {
            case "on", "true", "1", "yes": return true
            case "off", "false", "0", "no": return false
            case let other: throw .usage("\(name): expected on or off, got \(other)")
            }
        }
        func mac() throws(ProbeError) -> MACAddress {
            let hex = try value()[0].filter(\.isHexDigit)
            guard hex.count == 12 else { throw .usage("\(name): expected a MAC address like AA:BB:CC:DD:EE:FF") }
            let bytes = stride(from: 0, to: 12, by: 2).map { offset -> UInt8 in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
            }
            return MACAddress(displayOrder: bytes)
        }

        switch name {
        case "mode":
            return .ambient(try ambient(try value()[0]))
        case "nc-mode":
            switch try value()[0] {
            case "manual": return .noiseCancelingMode(.manual)
            case "adaptive": return .noiseCancelingMode(.adaptive)
            case "multi-scene", "scene": return .noiseCancelingMode(.multiScene)
            case let other: throw .usage("nc-mode: unknown value \(other)")
            }
        case "anc-level":
            guard let level = Int(try value()[0]), (1...5).contains(level) else { throw .usage("anc-level: 1 to 5") }
            return .ancLevel(level)
        case "scene":
            switch try value()[0] {
            case "transport": return .scene(.transport)
            case "outdoor": return .scene(.outdoor)
            case "indoor": return .scene(.indoor)
            case let other: throw .usage("scene: unknown value \(other)")
            }
        case "transparency":
            switch try value()[0] {
            case "full", "fully-transparent": return .transparency(.fullyTransparent)
            case "vocal", "vocal-mode": return .transparency(.vocalMode)
            case let other: throw .usage("transparency: unknown value \(other)")
            }
        case "wind":
            return .wind(try onOff())
        case "realtime-adaptive":
            return .realTimeAdaptive(try onOff())
        case "eq":
            guard !values.isEmpty else { throw .usage("eq needs a preset name or id") }
            let query = values.joined(separator: " ").lowercased()
            let simplified = { (text: String) in text.lowercased().filter { $0.isLetter || $0.isNumber } }
            guard let preset = EqualizerPreset.all.first(where: {
                String($0.id) == query || simplified($0.name) == simplified(query)
            }) else {
                throw .usage("eq: unknown preset \(query); presets: \(EqualizerPreset.all.map(\.name).joined(separator: ", "))")
            }
            return .eqPreset(preset)
        case "eq-custom":
            let parts = try value()[0].split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 8, parts.allSatisfy({ $0.map { (-12.0...12.0).contains($0) } ?? false }) else {
                throw .usage("eq-custom: 8 comma-separated dB values from -12 to 12")
            }
            return .eqCustom(parts.map { Int(($0! * 10).rounded()) })
        case "spatial":
            switch try value()[0] {
            case "off": return .spatial(nil)
            case "music": return .spatial(.music)
            case "movie": return .spatial(.movie)
            case "gaming", "game": return .spatial(.gaming)
            case let other: throw .usage("spatial: unknown value \(other)")
            }
        case "button":
            let parts = try value(3)
            let side: EarbudSide = switch parts[0] {
            case "left", "l": .left
            case "right", "r": .right
            default: throw .usage("button: side must be left or right")
            }
            let kind: GestureKind = switch parts[1] {
            case "single": .single
            case "double": .double
            case "triple": .triple
            case "long", "hold": .long
            default: throw .usage("button: gesture must be single, double, triple or long")
            }
            let action: ButtonAction? = switch parts[2] {
            case "volume-up": .volumeUp
            case "volume-down": .volumeDown
            case "previous": .previousTrack
            case "next": .nextTrack
            case "sound-mode": .ambientSoundMode
            case "voice-assistant": .voiceAssistant
            case "play-pause": .playPause
            case "none", "disabled": nil
            default: throw .usage("button: unknown action \(parts[2])")
            }
            return .button(side, kind, action)
        case "buttons-reset":
            _ = try value(0)
            return .resetButtons
        case "cycle":
            var modes = Set<AmbientSoundMode>()
            for name in try value()[0].split(separator: ",") {
                switch name {
                case "anc", "noise-canceling": modes.insert(.noiseCanceling)
                case "transparency": modes.insert(.transparency)
                case "normal": modes.insert(.normal)
                default: throw .usage("cycle: unknown mode \(name) (anc, transparency, normal)")
                }
            }
            guard modes.count >= 2 else { throw .usage("cycle: needs at least two modes") }
            return .soundModeCycle(modes)
        case "dual":
            return .dualConnections(try onOff())
        case "auto-off":
            switch try value()[0] {
            case "off": return .autoPowerOff(nil)
            case let minutes:
                guard let duration = AutoPowerOffDuration.allCases.first(where: { String($0.minutes) == minutes }) else {
                    throw .usage("auto-off: off, 10, 20, 30 or 60")
                }
                return .autoPowerOff(duration)
            }
        case "touch-tone":
            return .touchTone(try onOff())
        case "low-battery-prompt":
            return .lowBatteryPrompt(try onOff())
        case "ldac":
            return .ldac(try onOff())
        case "volume-limit":
            let text = try value()[0]
            if text == "off" { return .volumeLimit(nil) }
            guard let db = UInt8(text), VolumeLimit.decibelSteps.contains(db) else {
                throw .usage("volume-limit: off or 75, 80, 85, 90, 95, 100")
            }
            return .volumeLimit(db)
        case "db-refresh":
            switch try value()[0] {
            case "realtime", "real-time": return .decibelRefresh(.realTime)
            case "10s": return .decibelRefresh(.tenSeconds)
            case "1min", "60s": return .decibelRefresh(.oneMinute)
            case let other: throw .usage("db-refresh: unknown value \(other)")
            }
        case "dual-connect":
            return .dualConnect(try mac())
        case "dual-disconnect":
            return .dualDisconnect(try mac())
        case "dual-forget":
            return .dualForget(try mac())
        default:
            throw .usage("unknown setting \(name); see --help")
        }
    }

    static func ambient(_ text: String) throws(ProbeError) -> AmbientSoundMode {
        switch text.lowercased() {
        case "anc", "nc", "noise-canceling": .noiseCanceling
        case "transparency", "transparent", "ambient": .transparency
        case "normal", "off": .normal
        default: throw .usage("unknown mode \(text); use anc | transparency | normal")
        }
    }
}

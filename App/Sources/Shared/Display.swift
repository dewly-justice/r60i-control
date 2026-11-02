import SoundcoreKit

// User-facing names and SF Symbols for the protocol enums. Wording follows the Soundcore app.

extension AmbientSoundMode {
    /// Display order, as in the Soundcore app.
    static let menuOrder: [AmbientSoundMode] = [.noiseCanceling, .normal, .transparency]

    var title: String {
        switch self {
        case .noiseCanceling: "Noise Cancelling"
        case .normal: "Normal"
        case .transparency: "Transparency"
        }
    }

    var shortTitle: String {
        switch self {
        case .noiseCanceling: "ANC"
        case .normal: "Normal"
        case .transparency: "Transparency"
        }
    }

    var symbol: String {
        switch self {
        case .noiseCanceling: "waveform.slash"
        case .normal: "waveform"
        case .transparency: "ear.and.waveform"
        }
    }
}

extension NoiseCancelingMode {
    var title: String {
        switch self {
        case .adaptive: "Adaptive"
        case .manual: "Manual"
        case .multiScene: "Scene"
        }
    }
}

extension MultiSceneMode {
    var title: String {
        switch self {
        case .transport: "Transport"
        case .outdoor: "Outdoor"
        case .indoor: "Indoor"
        }
    }

    var symbol: String {
        switch self {
        case .transport: "tram"
        case .outdoor: "tree"
        case .indoor: "house"
        }
    }
}

extension TransparencyMode {
    var title: String {
        switch self {
        case .fullyTransparent: "Fully Transparent"
        case .vocalMode: "Vocal Mode"
        }
    }
}

extension SpatialAudioMode {
    var title: String {
        switch self {
        case .music: "Music"
        case .movie: "Movie"
        case .gaming: "Gaming"
        }
    }
}

extension ButtonAction {
    var title: String {
        switch self {
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .previousTrack: "Previous Track"
        case .nextTrack: "Next Track"
        case .ambientSoundMode: "Switch Sound Mode"
        case .voiceAssistant: "Voice Assistant"
        case .playPause: "Play/Pause"
        }
    }
}

extension GestureKind {
    var symbol: String {
        switch self {
        case .single: "hand.tap"
        case .double: "hand.tap"
        case .triple: "hand.tap"
        case .long: "hand.point.up.left"
        }
    }
}

extension AutoPowerOffDuration {
    var title: String { "\(minutes) minutes" }
}

extension BatteryLevel {
    /// SF Symbol for this level, or nil if not available.
    func symbol(charging: Bool) -> String? {
        guard let percent else { return nil }
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

extension D1202State {
    /// The lowest battery among the buds that report one, for the menu bar.
    var lowestEarbudPercent: Int? {
        [leftBattery.level.percent, rightBattery.level.percent].compactMap { $0 }.min()
    }
}

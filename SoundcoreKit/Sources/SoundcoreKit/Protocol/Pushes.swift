// Applying pushed (unsolicited) frames to the cached state: docs/protocol.md §6.3–§6.9.

extension D1202State {
    /// Updates the state from a pushed frame. Returns false if the frame isn't a state push
    /// this module understands (or is malformed), in which case nothing changes.
    /// `01 01` (full state) and `0B 01` (device list) are handled by the caller.
    @discardableResult
    public mutating func apply(push frame: Frame) -> Bool {
        let body = frame.body
        switch frame.command {
        case .soundModes:
            guard let modes = try? SoundModes(bytes: body) else { return false }
            soundModes = modes
        case .batteryLevel:
            // [left, right], optionally followed by 2 unknown bytes.
            guard body.count >= 2 else { return false }
            leftBattery.level = BatteryLevel(raw: body[0])
            rightBattery.level = BatteryLevel(raw: body[1])
        case .batteryCharging:
            guard body.count >= 2 else { return false }
            leftBattery.isCharging = body[0] == 1
            rightBattery.isCharging = body[1] == 1
        case .twsStatus:
            // OpenSCQ30 rejects any extra bytes.
            guard body.count == 2 else { return false }
            tws = TWSStatus(hostDeviceRaw: body[0], isConnected: body[1] == 1)
        case .firmwareAndSerial:
            guard body.count >= 26 else { return false }
            firmwareLeft = FirmwareVersion(raw: Array(body[0..<5]))
            firmwareRight = FirmwareVersion(raw: Array(body[5..<10]))
            serialNumber = Self.ascii(Array(body[10..<26]))
        case .ldacState:
            guard body.count == 1 else { return false }
            ldac = body[0] == 1
        default:
            return false
        }
        return true
    }
}

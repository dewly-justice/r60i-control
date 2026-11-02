extension Sequence<UInt8> {
    /// `"08 EE 00 00 00"`
    public var hexString: String {
        map { byte in
            let digits = String(byte, radix: 16, uppercase: true)
            return digits.count == 1 ? "0" + digits : digits
        }
        .joined(separator: " ")
    }
}

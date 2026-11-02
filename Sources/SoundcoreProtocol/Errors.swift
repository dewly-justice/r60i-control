public enum ParseError: Error, Hashable, Sendable, CustomStringConvertible {
    case tooShort(what: String, needed: Int, got: Int)
    case unexpectedCommand(expected: Command, got: Command)

    public var description: String {
        switch self {
        case let .tooShort(what, needed, got):
            "\(what): need at least \(needed) bytes, got \(got)"
        case let .unexpectedCommand(expected, got):
            "expected command \(expected), got \(got)"
        }
    }
}

public enum EncodeError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The current state holds values outside what OpenSCQ30 documents, so writing it back
    /// could send something unconfirmed.
    case unknownValues([String])

    public var description: String {
        switch self {
        case let .unknownValues(fields):
            "refusing to write: the device reported values outside the documented set (\(fields.joined(separator: ", ")))"
        }
    }
}

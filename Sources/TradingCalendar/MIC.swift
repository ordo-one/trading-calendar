/// Market Identifier Code (ISO 10383).
/// A string-based struct with all ISO 10383 codes available as static constants.
/// Users can also create custom MICs: `MIC("XCUS")`.
public struct MIC: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral, Codable {
    public let code: String

    public init(_ code: String) {
        self.code = code
    }

    public init(stringLiteral value: String) {
        self.code = value
    }

    public var description: String { code }
}

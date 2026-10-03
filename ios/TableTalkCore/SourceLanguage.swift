import Foundation

public enum SourceLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"

    public var id: String { rawValue }
    public var code: String { rawValue }
    public var displayName: String { self == .english ? "English" : "Español" }
    public var other: SourceLanguage { self == .english ? .spanish : .english }
}

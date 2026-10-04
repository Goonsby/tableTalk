import Foundation

public struct ConversationTurn: Identifiable, Equatable, Sendable {
    public let id: UInt64
    public let sourceLanguage: SourceLanguage
    public let source: String
    public let translation: String?
    public let translationFailed: Bool

    /// The receiving panel stays pending (nil) until translation completes.
    public func text(for language: SourceLanguage) -> String? {
        language == sourceLanguage ? source : translation
    }
}

/// Bounded, memory-only history. Own this value on the UI's main actor.
/// Generation checks prevent late recognition or translation from restoring cleared text.
public struct ConversationLedger: Sendable {
    public static let maxTurns = 12
    public private(set) var generation: UInt64 = 0
    public private(set) var turns: [ConversationTurn] = []
    private var nextID: UInt64 = 0

    public init() {}

    public func isCurrent(_ expected: UInt64) -> Bool { generation == expected }

    @discardableResult
    public mutating func invalidate() -> UInt64 {
        generation &+= 1
        return generation
    }

    public mutating func clear() {
        invalidate()
        turns.removeAll(keepingCapacity: false)
    }

    @discardableResult
    public mutating func addSource(expected: UInt64, language: SourceLanguage, source: String) -> UInt64? {
        let cleaned = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCurrent(expected), !cleaned.isEmpty else { return nil }
        nextID &+= 1
        turns.append(ConversationTurn(id: nextID, sourceLanguage: language, source: cleaned,
                                      translation: nil, translationFailed: false))
        if turns.count > Self.maxTurns { turns.removeFirst(turns.count - Self.maxTurns) }
        return nextID
    }

    @discardableResult
    public mutating func finish(expected: UInt64, id: UInt64, translation: String?, failed: Bool) -> Bool {
        guard isCurrent(expected), let index = turns.firstIndex(where: { $0.id == id }) else { return false }
        let old = turns[index]
        let cleaned = translation?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usable = !failed && cleaned?.isEmpty == false ? cleaned : nil
        turns[index] = ConversationTurn(id: old.id, sourceLanguage: old.sourceLanguage, source: old.source,
                                       translation: usable, translationFailed: failed || usable == nil)
        return true
    }
}

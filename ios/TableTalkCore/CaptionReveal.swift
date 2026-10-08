/// Reveals complete words without changing the caption's original layout or graphemes.
public struct CaptionReveal: Equatable, Sendable {
    public let text: String
    public private(set) var visibleCharacters: Int

    private let totalCharacters: Int
    private let wordEnds: [Int]
    private let wordsPerTick: Int
    private var revealedWords: Int

    public init(text: String, enabled: Bool = true) {
        let characters = Array(text)
        var ends: [Int] = []
        for index in characters.indices where !characters[index].isWhitespace {
            let next = index + 1
            guard next == characters.count || characters[next].isWhitespace else { continue }
            var end = next
            while end < characters.count && characters[end].isWhitespace { end += 1 }
            ends.append(end)
        }

        self.text = text
        totalCharacters = characters.count
        wordEnds = ends
        // Group long captions so the caller's timer needs at most 32 advances.
        wordsPerTick = max(1, (ends.count + 31) / 32)
        let revealImmediately = !enabled || ends.isEmpty
        visibleCharacters = revealImmediately ? characters.count : 0
        revealedWords = revealImmediately ? ends.count : 0
    }

    public var isComplete: Bool { visibleCharacters == totalCharacters }

    public var visibleText: String { String(text.prefix(visibleCharacters)) }
    public var hiddenText: String { String(text.dropFirst(visibleCharacters)) }

    public mutating func advance() {
        guard !isComplete else { return }
        revealedWords = min(revealedWords + wordsPerTick, wordEnds.count)
        visibleCharacters = wordEnds[revealedWords - 1]
    }

    public mutating func finish() {
        visibleCharacters = totalCharacters
        revealedWords = wordEnds.count
    }
}

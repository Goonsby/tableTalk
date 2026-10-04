import Foundation

/// A bounded 16 kHz mono buffer. This is a conservative input filter, not speech detection.
/// Own the value on one queue. Neither this type nor the ledger persists content to disk.
public struct AudioSamples: Sendable {
    public static let sampleRate = 16_000
    public static let maxSeconds = 12
    public static let capacity = sampleRate * maxSeconds
    public static let minimumSamples = sampleRate / 2
    public static let minimumRMS = 0.002

    private var storage: [Float] = []
    private var sumSquares: Double = 0

    public init() { storage.reserveCapacity(Self.capacity) }

    public var count: Int { storage.count }
    public var samples: [Float] { storage }
    public var seconds: Double { Double(count) / Double(Self.sampleRate) }
    public var rms: Double { count == 0 ? 0 : sqrt(sumSquares / Double(count)) }
    public var isFull: Bool { count == Self.capacity }
    public var worthDecoding: Bool { count >= Self.minimumSamples && rms >= Self.minimumRMS }

    /// Only accepts available capacity; nonfinite values become silence and PCM is clipped.
    public mutating func append(_ samples: [Float]) {
        let accepted = min(samples.count, Self.capacity - count)
        for sample in samples.prefix(accepted) {
            let value: Float = sample.isFinite ? min(1, max(-1, sample)) : 0
            storage.append(value)
            sumSquares += Double(value) * Double(value)
        }
    }

    /// Best-effort wipe of this buffer. Swift copies and OS/inference memory are not erased.
    public mutating func clear() {
        for index in storage.indices { storage[index] = 0 }
        storage.removeAll(keepingCapacity: false)
        sumSquares = 0
    }
}

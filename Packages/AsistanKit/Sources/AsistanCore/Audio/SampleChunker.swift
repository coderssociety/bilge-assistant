/// Re-frames arbitrary-length audio buffers into fixed-size chunks (the VAD model needs exactly 4096 samples).
public struct SampleChunker: Sendable {
    public let chunkSize: Int
    private var pending: [Float] = []

    public init(chunkSize: Int) {
        precondition(chunkSize > 0, "chunkSize must be positive")
        self.chunkSize = chunkSize
        pending.reserveCapacity(chunkSize * 2)
    }

    public var pendingCount: Int { pending.count }

    public mutating func append(_ samples: [Float]) -> [[Float]] {
        pending.append(contentsOf: samples)
        var chunks: [[Float]] = []
        var start = 0
        while pending.count - start >= chunkSize {
            chunks.append(Array(pending[start..<start + chunkSize]))
            start += chunkSize
        }
        if start > 0 { pending.removeFirst(start) }
        return chunks
    }

    public mutating func reset() {
        pending.removeAll(keepingCapacity: true)
    }
}

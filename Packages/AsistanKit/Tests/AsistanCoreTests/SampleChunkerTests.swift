import Testing
@testable import AsistanCore

@Suite("SampleChunker")
struct SampleChunkerTests {
    @Test("emits fixed-size chunks and carries the remainder")
    func chunking() {
        var chunker = SampleChunker(chunkSize: 4)
        #expect(chunker.append([1, 2, 3]) == [])
        #expect(chunker.append([4, 5, 6, 7, 8, 9]) == [[1, 2, 3, 4], [5, 6, 7, 8]])
        #expect(chunker.pendingCount == 1)
    }

    @Test("reset drops pending samples")
    func reset() {
        var chunker = SampleChunker(chunkSize: 4)
        _ = chunker.append([1, 2])
        chunker.reset()
        #expect(chunker.append([3, 4, 5, 6]) == [[3, 4, 5, 6]])
    }
}

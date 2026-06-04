import Foundation
import Koma
import Testing

struct KomaVectorQuantizationTests {
    /// Deterministic pseudo-vector in `[-0.5, 0.5)` (LCG) so the recall assertion is reproducible.
    private func vector(seed: UInt64, dimension: Int) -> [Double] {
        var state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1
        return (0 ..< dimension).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) * (1.0 / 9_007_199_254_740_992.0) - 0.5
        }
    }

    @Test
    func `encodeInt8 produces one signed byte per dimension`() {
        #expect(KomaVector.encodeInt8([1, 0, -1, 0.5]).count == 4)
    }

    @Test
    func `int8 over-fetch contains the exact nearest neighbors`() {
        let dimension = 64
        let documents = (0 ..< 300).map { vector(seed: UInt64($0), dimension: dimension) }
        let query = vector(seed: 9999, dimension: dimension)

        // Exact top-10 by full-precision cosine.
        let exactScores = documents.map { KomaVector.cosine(query, $0) }
        let exactTop = Set(documents.indices.sorted { exactScores[$0] > exactScores[$1] }.prefix(10))

        // int8 top-50 by integer dot product of the quantized codes (5x over-fetch).
        let codes = documents.map(KomaVector.encodeInt8)
        let queryCode = KomaVector.encodeInt8(query)
        let int8Scores = codes.map { KomaVector.scoreInt8(queryCode, $0) }
        let candidates = Set(documents.indices.sorted { int8Scores[$0] > int8Scores[$1] }.prefix(50))

        // Every exact neighbor survives the int8 pre-filter, so over-fetch + full-precision rerank
        // recovers the exact top-k.
        #expect(exactTop.isSubset(of: candidates))
    }
}

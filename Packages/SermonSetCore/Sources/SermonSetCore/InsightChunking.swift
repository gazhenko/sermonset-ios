import Foundation

public struct InsightChunk: Sendable, Hashable {
    public var indexes: [Int]
    public var text: String
    public init(indexes: [Int], text: String) { self.indexes = indexes; self.text = text }
}
public enum InsightChunking {
    /// UTF-8 bytes are a conservative token upper bound, including index prefixes.
    /// Long segments become separate bounded excerpts that retain their source index.
    public static func chunks(transcript: Transcript, maxBytes: Int = 1600) -> [InsightChunk] {
        let limit = max(64, maxBytes)
        var chunks: [InsightChunk] = [], indexes: [Int] = [], text = ""
        func flush() {
            if !text.isEmpty { chunks.append(InsightChunk(indexes: Array(Set(indexes)).sorted(), text: text)); indexes = []; text = "" }
        }
        for (index, segment) in transcript.segments.enumerated() where segment.isFinal {
            let prefix = "[\(index)] "
            var piece = prefix
            // A grapheme can contain arbitrarily many combining marks. Scalars
            // keep the byte bound valid even for that input.
            for scalar in segment.text.unicodeScalars {
                let next = String(scalar)
                if piece.utf8.count + next.utf8.count + 1 > limit {
                    flush(); chunks.append(InsightChunk(indexes: [index], text: piece)); piece = prefix
                }
                piece += next
            }
            if text.utf8.count + piece.utf8.count + 1 > limit { flush() }
            indexes.append(index); text += piece + "\n"
        }
        flush()
        return chunks
    }
}

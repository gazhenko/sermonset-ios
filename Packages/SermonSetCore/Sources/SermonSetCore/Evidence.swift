import Foundation
import CryptoKit

public enum EvidenceValidator {
    public static func validSegments(_ segments: [TranscriptSegment]) -> Bool {
        guard Set(segments.map(\.id)).count == segments.count else { return false }
        var previousStart = 0.0
        for segment in segments {
            guard segment.start.isFinite, segment.end.isFinite, segment.start >= previousStart, segment.end >= segment.start, segment.confidence.isFinite, (0...1).contains(segment.confidence) else { return false }
            previousStart = segment.start
        }
        return true
    }
    public static func range(transcript: Transcript, indexes: [Int]) -> EvidenceRange? {
        let unique = Array(Set(indexes)).sorted()
        guard !unique.isEmpty, unique.allSatisfy({ transcript.segments.indices.contains($0) && transcript.segments[$0].isFinal }) else { return nil }
        let segments = unique.map { transcript.segments[$0] }
        return EvidenceRange(transcriptID: transcript.id, segmentIDs: segments.map(\.id), start: segments.map(\.start).min()!, end: segments.map(\.end).max()!)
    }
    public static func isValid(_ evidence: EvidenceRange, transcript: Transcript) -> Bool {
        guard evidence.transcriptID == transcript.id, !evidence.segmentIDs.isEmpty, Set(evidence.segmentIDs).count == evidence.segmentIDs.count else { return false }
        let segments = evidence.segmentIDs.compactMap { id in transcript.segments.first { $0.id == id } }
        return segments.count == evidence.segmentIDs.count && segments.allSatisfy(\.isFinal) && evidence.start == segments.map(\.start).min() && evidence.end == segments.map(\.end).max()
    }
    public static func isLowEvidence(_ evidence: EvidenceRange, transcript: Transcript) -> Bool {
        !isValid(evidence, transcript: transcript) || transcript.segments.filter { evidence.segmentIDs.contains($0.id) }.contains { $0.confidence < 0.65 }
    }
    public static func hasInventedQuotation(_ text: String, source: String) -> Bool {
        let characters = Array(text)
        return quotationSpans(characters).contains { span in
            !source.contains(String(characters[(span.open + 1)..<span.close]))
        }
    }
    public static func paraphrase(_ text: String) -> String {
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var delimiters = Set(quotationSpans(characters).flatMap { [$0.open, $0.close] })
        // Also remove unmatched boundary quotes. An unpaired possessive in the
        // body (Jesus’ presence) is not a quotation delimiter.
        let quoteMarks: Set<Character> = ["\"", "“", "”", "'", "‘", "’"]
        for index in characters.indices {
            guard quoteMarks.contains(characters[index]) || characters[index].isWhitespace else { break }
            if quoteMarks.contains(characters[index]) { delimiters.insert(index) }
        }
        for index in characters.indices.reversed() {
            guard quoteMarks.contains(characters[index]) || characters[index].isWhitespace else { break }
            if quoteMarks.contains(characters[index]) { delimiters.insert(index) }
        }
        return String(characters.indices.filter { !delimiters.contains($0) }.map { characters[$0] }).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func quotationSpans(_ characters: [Character]) -> [(open: Int, close: Int)] {
        var stack: [(index: Int, single: Bool)] = []
        var spans: [(open: Int, close: Int)] = []
        for index in characters.indices {
            let mark = characters[index]
            guard ["\"", "“", "”", "'", "‘", "’"].contains(mark) else { continue }
            let wordBefore = index > 0 && (characters[index - 1].isLetter || characters[index - 1].isNumber)
            let wordAfter = index + 1 < characters.count && (characters[index + 1].isLetter || characters[index + 1].isNumber)
            // U+2019 and ASCII apostrophes within a word are never quotes,
            // including inside an enclosing quoted span.
            if (mark == "’" || mark == "'") && wordBefore && wordAfter { continue }
            let single = mark == "'" || mark == "‘" || mark == "’"
            let canClose = mark == "”" || mark == "’" || mark == "\"" || (mark == "'" && !wordAfter)
            if canClose, let position = stack.lastIndex(where: { $0.single == single }) {
                let opening = stack[position]
                stack.removeSubrange(position...)
                spans.append((open: opening.index, close: index))
            } else if mark == "“" || mark == "‘" || mark == "\"" || (!wordBefore && (mark == "'" || mark == "’")) {
                stack.append((index: index, single: single))
            }
        }
        return spans
    }
    public static func contentHash(_ transcript: Transcript) -> String {
        let payload = transcript.segments.map { "\($0.id)|\($0.start)|\($0.end)|\($0.text)|\($0.confidence)|\($0.isFinal)" }.joined(separator: "\n")
        return SHA256.hash(data: Data(((transcript.localeIdentifier ?? "en_US") + "\n" + payload).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ExtractiveInsightsAdapter: Sendable {
    public init() {}
    public func generate(transcript: Transcript, moments: [MarkedMoment]) -> SermonInsights {
        let eligible = transcript.segments.indices.filter { transcript.segments[$0].isFinal && !transcript.segments[$0].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let ranked = eligible.sorted { a, b in
            func score(_ index: Int) -> Double {
                let segment = transcript.segments[index]
                let marked = moments.contains { $0.audioAssetID == nil || $0.audioAssetID == transcript.audioAssetID ? ($0.time >= segment.start && $0.time <= segment.end) : false }
                return (marked ? 10 : 0) + segment.confidence
            }
            return score(a) == score(b) ? a < b : score(a) > score(b)
        }
        let takeaways = ranked.prefix(3).map { index in
            let evidence = EvidenceValidator.range(transcript: transcript, indexes: [index])!
            return Takeaway(text: transcript.segments[index].text, evidence: evidence, isLowEvidence: EvidenceValidator.isLowEvidence(evidence, transcript: transcript))
        }
        let outline = eligible.enumerated().filter { offset, _ in offset == 0 || offset == eligible.count / 2 || offset == eligible.count - 1 }.map { _, index in
            OutlineItem(title: transcript.segments[index].text, start: transcript.segments[index].start, evidence: EvidenceValidator.range(transcript: transcript, indexes: [index]))
        }
        return SermonInsights(sermonID: transcript.sermonID, transcriptID: transcript.id, transcriptRevision: transcript.revision, generator: "Extractive — no model", promptVersion: "extractive-v1", outline: outline, takeaways: takeaways, transcriptChecksumSHA256: EvidenceValidator.contentHash(transcript), generatorRuntime: "Extractive-v1")
    }
}

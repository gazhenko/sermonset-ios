import Foundation
import SermonSetCore

struct SpeechWord: Sendable, Equatable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var confidence: Double
}

struct SpeakerTurn: Sendable {
    var speaker: String
    var start: TimeInterval
    var end: TimeInterval
}

enum SpeechSegmentation {
    static func speaker(for word: SpeechWord, turns: [SpeakerTurn]) -> String? {
        var overlap: [String: Double] = [:]
        for turn in turns {
            overlap[turn.speaker, default: 0] += max(0, min(word.end, turn.end) - max(word.start, turn.start))
        }
        // Stable tie breaking, and no guessed speaker for a word in a gap.
        return overlap.keys.sorted().filter { overlap[$0, default: 0] > 0 }.max {
            overlap[$0, default: 0] < overlap[$1, default: 0]
        }
    }

    static func segments(words: [SpeechWord], turns: [SpeakerTurn], offset: TimeInterval = 0) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = [], sentence: [SpeechWord] = []
        var currentSpeaker: String?
        func flush() {
            guard let first = sentence.first, let last = sentence.last else { return }
            let confidence = sentence.reduce(0) { $0 + $1.confidence } / Double(sentence.count)
            result.append(TranscriptSegment(start: first.start + offset, end: last.end + offset,
                text: sentence.map(\.text).joined(separator: " "), confidence: confidence, speaker: currentSpeaker,
                speechDuration: sentence.reduce(0) { $0 + max(0, $1.end - $1.start) }))
            sentence.removeAll(keepingCapacity: true)
        }
        for word in words.sorted(by: { $0.start < $1.start }) {
            guard word.start.isFinite, word.end.isFinite, word.start >= 0, word.end >= word.start,
                  word.end - word.start <= 30, word.confidence.isFinite,
                  !word.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let speaker = speaker(for: word, turns: turns)
            if !sentence.isEmpty, speaker != currentSpeaker || word.end - sentence[0].start > 30 { flush() }
            currentSpeaker = speaker
            var cleaned = word; cleaned.confidence = max(0, min(1, word.confidence))
            sentence.append(cleaned)
            let ending = word.text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’»)]}"))
            if let last = ending.last, ".!?…。！？".contains(last) { flush() }
        }
        flush()
        return result
    }
}

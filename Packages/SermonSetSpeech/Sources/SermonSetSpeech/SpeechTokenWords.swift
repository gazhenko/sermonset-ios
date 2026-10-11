import Foundation
import FluidAudio

enum SpeechTokenWords {
    static func words(from tokens: [TokenTiming]) -> [SpeechWord] {
        // Use FluidAudio's grouping to preserve punctuation and the repaired
        // batch timings, then aggregate confidence for the same token groups.
        let timings = buildWordTimings(from: tokens)
        var groups: [[Float]] = [], current: [Float] = []
        var currentText = ""
        for timing in tokens {
            let token = timing.token
            guard !token.isEmpty, token != "<blank>", token != "<pad>" else { continue }
            let boundary = isWordBoundary(token) || currentText.isEmpty
            if boundary, !currentText.isEmpty {
                if !currentText.trimmingCharacters(in: .whitespaces).isEmpty { groups.append(current) }
                current = []; currentText = ""
            }
            currentText += boundary ? stripWordBoundaryPrefix(token) : token
            current.append(timing.confidence)
        }
        if !currentText.trimmingCharacters(in: .whitespaces).isEmpty { groups.append(current) }
        return timings.enumerated().map { index, word in
            let confidences = index < groups.count ? groups[index] : []
            let confidence = confidences.isEmpty ? 0 : confidences.reduce(0) { $0 + Double($1) } / Double(confidences.count)
            return SpeechWord(text: word.word, start: word.startTime, end: word.endTime, confidence: confidence)
        }
    }
}

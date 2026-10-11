import Foundation
import NaturalLanguage

public struct NotesSentence: Codable, Hashable, Sendable {
    public var number: Int
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval
    public var segmentIndexes: [Int]
    public var nonPointRole: NotesRole?
    public var speakerLabel: String? = nil
    public var isPrimarySpeaker: Bool? = nil
    public var promptLine: String { "[\(number)] " + (speakerLabel.map { "\($0): " } ?? "") + text }
}
public struct NotesCue: Codable, Hashable, Sendable {
    public var sentenceNumber: Int
    public var ordinal: Int
    public var text: String
}
public struct NotesSection: Codable, Hashable, Sendable {
    public var number: Int
    public var sentences: [NotesSentence]
    public var announcedPoint: Int?
    public var forcedRole: NotesRole?
    public var start: TimeInterval { sentences.first?.start ?? 0 }
    public var text: String { sentences.map(\.promptLine).joined(separator: "\n") }
    public var segmentIndexes: [Int] { Array(Set(sentences.flatMap(\.segmentIndexes))).sorted() }
}

public enum NotesPreparation {
    public static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: #"\b(?:um|uh|erm)\b[,\s]*"#, with: "", options: [.regularExpression, .caseInsensitive])
        // Repeated phrases and words are speech stutters, not extra evidence.
        for _ in 0..<4 {
            let next = result.replacingOccurrences(of: #"\b([\p{L}’']+(?:\s+[\p{L}’']+){0,5})[,\s]+\1\b"#, with: "$1", options: [.regularExpression, .caseInsensitive])
            if next == result { break }; result = next
        }
        return result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func sentences(_ transcript: Transcript) -> [NotesSentence] {
        var result: [NotesSentence] = []
        var words: [String] = [], indexes: [Int] = []
        let primary = transcript.primarySpeaker
        var speakers: [String] = []
        for segment in transcript.segments where segment.isFinal {
            if let speaker = segment.speaker, !speakers.contains(speaker) { speakers.append(speaker) }
        }
        let others = speakers.filter { $0 != primary }
        func flush() {
            let text = clean(words.joined(separator: " "))
            if !text.isEmpty, let first = indexes.first, let last = indexes.last {
                let speaker = transcript.segments[first].speaker
                let isPrimary = primary.map { speaker == $0 }
                let label: String? = speakers.count > 1
                    ? (isPrimary == true ? "Preacher" : speaker.flatMap { others.firstIndex(of: $0) }.map { "Speaker \($0 + 2)" } ?? "Unidentified speaker") : nil
                result.append(NotesSentence(number: result.count + 1, text: text, start: transcript.segments[first].start, end: transcript.segments[last].end, segmentIndexes: indexes, nonPointRole: isPrimary == false ? .discussion : nil, speakerLabel: label, isPrimarySpeaker: isPrimary))
            }
            words = []; indexes = []
        }
        for (index, segment) in transcript.segments.enumerated() where segment.isFinal {
            if let last = indexes.last, transcript.segments[last].speaker != segment.speaker { flush() }
            for word in clean(segment.text).split(whereSeparator: \.isWhitespace).map(String.init) {
                if indexes.last != index { indexes.append(index) }
                words.append(word)
                if word.range(of: #"[.!?][\"”’']*$"#, options: .regularExpression) != nil { flush() }
                // Very long unpunctuated single segments must also remain bounded.
                else if words.count >= 80 { flush() }
            }
            if words.count >= 40 { flush() }
        }
        flush()
        for i in result.indices {
            guard result[i].isPrimarySpeaker != false else { continue }
            let text = result[i].text.lowercased()
            if i < min(6, result.count), text.range(of: #"\b(welcome|announcements?|good morning|good evening|thanks for coming|thank you for coming)\b"#, options: .regularExpression) != nil {
                result[i].nonPointRole = .welcome
            }
            if i >= max(0, result.count - 8), text.range(of: #"\b(let us pray|let's pray|let’s pray|bow (?:our|your) heads|closing prayer|amen)\b"#, options: .regularExpression) != nil {
                // A closing prayer continues through the remaining sentences.
                for j in i..<result.count where result[j].isPrimarySpeaker != false { result[j].nonPointRole = .closing }
                break
            }
        }
        return result
    }
    public static func cues(_ sentences: [NotesSentence]) -> [NotesCue] {
        let pattern = #"\b(?:(?:my|our|the)\s+(first|second|third|fourth|fifth|sixth|seventh|final|last|next)\s+(?:point|thing|truth|principle|key|lesson|step|idea)|point\s+(?:number\s+)?(one|two|three|four|five|six|seven|eight|nine|ten|\d+)|number\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)|(secondly|thirdly|and finally|lastly))\b"#
        let regex = try! NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        var result: [NotesCue] = []
        let ordinals = ["first": 1, "one": 1, "second": 2, "two": 2, "secondly": 2, "third": 3, "three": 3, "thirdly": 3, "fourth": 4, "four": 4, "fifth": 5, "five": 5, "sixth": 6, "six": 6, "seventh": 7, "seven": 7, "eight": 8, "nine": 9, "ten": 10]
        for sentence in sentences where sentence.nonPointRole == nil {
            guard result.last.map({ sentence.number - $0.sentenceNumber >= 6 }) ?? true,
                  let match = regex.firstMatch(in: sentence.text, range: NSRange(sentence.text.startIndex..., in: sentence.text)),
                  let full = Range(match.range, in: sentence.text) else { continue }
            let label = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: sentence.text).map { String(sentence.text[$0]).lowercased() } }.first ?? "next"
            let ordinal = ordinals[label] ?? Int(label) ?? ((result.last?.ordinal ?? 0) + 1)
            // Repeating a point label much later does not announce a new point.
            if result.last?.ordinal == ordinal { continue }
            result.append(NotesCue(sentenceNumber: sentence.number, ordinal: ordinal, text: String(sentence.text[full])))
        }
        return result
    }
    public static func pointsAnnounced(_ cues: [NotesCue]) -> Bool {
        cues.count >= 2 && zip(cues, cues.dropFirst()).allSatisfy { $0.ordinal < $1.ordinal }
    }
    public static func sections(_ sentences: [NotesSentence], cues: [NotesCue], client: any NotesModelClient, targetTokens: Int = 2200) async throws -> [NotesSection] {
        let budget = min(targetTokens, try await client.inputBudget(stage: .map))
        guard budget >= 128 else { throw SermonSetError(title: "Notes unavailable", message: "The on-device model has too little room to read this sermon.") }
        var result: [NotesSection] = [], current: [NotesSentence] = []
        var point: Int?
        let cueNumbers = Dictionary(uniqueKeysWithValues: cues.enumerated().map { ($0.element.sentenceNumber, $0.offset + 1) })
        func append() {
            guard !current.isEmpty else { return }
            result.append(NotesSection(number: result.count + 1, sentences: current, announcedPoint: point, forcedRole: current.first?.nonPointRole))
            current = []
        }
        for sentence in sentences {
            try Task.checkCancellation()
            if let cue = cueNumbers[sentence.number] { append(); point = cue }
            if !current.isEmpty, current.last?.nonPointRole != sentence.nonPointRole { append() }
            let candidate = NotesSection(number: result.count + 1, sentences: current + [sentence], announcedPoint: point)
            if try await client.tokenCount(NotesPrompts.mapInput(candidate)) > budget { append() }
            // Sentence cleaning caps ordinary input; don't feed pathological input unchecked.
            if try await client.tokenCount(NotesPrompts.mapInput(NotesSection(number: 1, sentences: [sentence]))) > budget {
                throw SermonSetError(title: "Notes unavailable", message: "A transcript sentence is too large for the on-device model. Shorten it in the transcript and try again.")
            }
            current.append(sentence)
        }
        append(); return result
    }
}

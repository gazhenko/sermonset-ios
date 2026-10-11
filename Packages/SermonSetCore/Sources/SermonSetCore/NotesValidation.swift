import Foundation
import NaturalLanguage

/// All model prose passes through the same machinery and quotation checks.
public enum NotesValidation {
    static let machinery = #"\[\s*\d+(?:\s*[,–-]\s*\d+)*\s*\]|\bsegments?\s+(?:number\s+)?\d+(?:(?:\s*,\s*|\s+and\s+)\d+)*|\bsection\s+\d+|\bc\d+-n\d+\b|\bciting\b|\bindex(?:es|ing)?\b"#
    public static func hasMachinery(_ text: String) -> Bool { text.range(of: machinery, options: [.regularExpression, .caseInsensitive]) != nil }
    public static func stripMachinery(_ text: String) -> String {
        text.replacingOccurrences(of: machinery, with: "", options: [.regularExpression, .caseInsensitive]).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func words(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
    public static func text(_ text: String, source: String, maxWords: Int? = nil) -> String? {
        // Strip for diagnostics, but reject changed prose: deleting IDs cannot repair meaning.
        let stripped = stripMachinery(text)
        guard !hasMachinery(text), !stripped.isEmpty, maxWords.map({ words(stripped) <= $0 }) ?? true,
              !EvidenceValidator.hasInventedQuotation(stripped, source: source) else { return nil }
        let cleaned = EvidenceValidator.paraphrase(stripped)
        let allowed = groundingSource(source)
        guard words(cleaned) <= (maxWords ?? 80),
              cleaned.matches(of: /(?:[1-3]\s+)?[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?\s+\d+:\d+(?:[–-]\d+)?/).allSatisfy({ scripture(String($0.output), source: source) != nil }),
              cleaned.matches(of: /\b\p{Lu}[\p{L}’'-]*(?:\s+\p{Lu}[\p{L}’'-]*)+/).allSatisfy({ allowedName(String($0.output), source: allowed) }) else { return nil }
        let tagger = NLTagger(tagSchemes: [.nameType]); tagger.string = cleaned
        var inventedName = false
        tagger.enumerateTags(in: cleaned.startIndex..<cleaned.endIndex, unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitPunctuation]) { tag, range in
            if (tag == .personalName || tag == .placeName || tag == .organizationName), !allowedName(String(cleaned[range]), source: allowed) { inventedName = true }
            return true
        }
        return inventedName ? nil : cleaned
    }
    public static func normalized(_ text: String) -> String {
        NotesPreparation.clean(text).lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func canQuote(_ sentence: NotesSentence, transcript: Transcript) -> Bool {
        guard !sentence.segmentIndexes.isEmpty,
              sentence.segmentIndexes.allSatisfy({ transcript.segments.indices.contains($0) }) else { return false }
        guard let primary = transcript.primarySpeaker else { return true }
        return sentence.segmentIndexes.allSatisfy { transcript.segments[$0].speaker == primary }
    }
    public static func keyPhrase(_ text: String, sentence: NotesSentence?, transcript: Transcript) -> KeyPhrase? {
        guard let sentence, canQuote(sentence, transcript: transcript), !hasMachinery(text), words(text) <= 20 else { return nil }
        let needle = normalized(text)
        guard !needle.isEmpty, (" " + normalized(sentence.text) + " ").contains(" " + needle + " "),
              let range = EvidenceValidator.range(transcript: transcript, indexes: sentence.segmentIndexes) else { return nil }
        // Choose the shortest matching original span, so optional leading fillers
        // do not become part of a phrase merely because normalization ignores them.
        let sourceWords = sentence.segmentIndexes.flatMap { index in
            transcript.segments[index].text.split(whereSeparator: \.isWhitespace).map { (text: String($0), segment: index) }
        }
        var best: Range<Int>?
        for start in sourceWords.indices {
            guard !normalized(sourceWords[start].text).isEmpty else { continue }
            for end in (start + 1)...min(sourceWords.count, start + 20) {
                let candidate = sourceWords[start..<end].map(\.text).joined(separator: " ")
                if normalized(candidate) == needle {
                    if best == nil || end - start < best!.count { best = start..<end }
                    break
                }
            }
        }
        guard let best else { return nil }
        let indexes = Array(Set(sourceWords[best].map(\.segment))).sorted()
        let evidence = EvidenceValidator.range(transcript: transcript, indexes: indexes) ?? range
        return KeyPhrase(text: sourceWords[best].map(\.text).joined(separator: " "), start: transcript.segments[indexes[0]].start, evidence: evidence)
    }
    public static func scripture(_ reference: String, source: String) -> String? {
        guard !hasMachinery(reference) else { return nil }
        return ScriptureDetector.validate(reference, source: source)
    }
    public static func firstSentence(_ text: String) -> String {
        let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = text
        var first = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in first = String(text[range]); return false }
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func sentenceCount(_ text: String) -> Int {
        let tokenizer = NLTokenizer(unit: .sentence); tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in count += 1; return true }
        return count
    }
    public static func heading(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\s*(?:\d+[.)]?|point\s+(?:number\s+)?(?:one|two|three|four|five|six|seven|eight|nine|ten)|(?:first|second|third|fourth|fifth|sixth|seventh|final|last)(?:\s+point)?)\s*[:.)-]?\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
    }
    public static func trim(_ value: String, to limit: Int) -> String {
        value.split(whereSeparator: \.isWhitespace).prefix(limit).joined(separator: " ")
    }
    private static let divineNames = "God Jesus Christ Lord Holy Spirit Father"
    private static func allowedName(_ name: String, source: String) -> Bool {
        if source.localizedCaseInsensitiveContains(name) { return true }
        let divine = Set(normalized(divineNames).split(separator: " "))
        let parts = normalized(name).split(separator: " ").filter { $0 != "the" }
        return !parts.isEmpty && parts.allSatisfy { divine.contains($0) }
    }
    private static func groundingSource(_ source: String) -> String {
        source + " " + divineNames + " " + ScriptureDetector.references(in: source).map(\.text).joined(separator: " ")
    }
    public static func snappedPhrase(_ value: String, sentence: NotesSentence?, transcript: Transcript) -> KeyPhrase? {
        guard let sentence, !value.isEmpty else { return nil }
        if let exact = keyPhrase(value, sentence: sentence, transcript: transcript) { return exact }
        let words = sentence.text.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count <= 20 { return keyPhrase(sentence.text, sentence: sentence, transcript: transcript) }
        let wanted = Set(normalized(value).split(separator: " "))
        let stop: Set<Substring> = ["a", "an", "the", "and", "or", "to", "of", "in", "is", "it", "that", "we", "you"]
        var best: String?, score = 0
        for start in 0...words.count - 20 {
            let span = words[start..<start + 20].joined(separator: " ")
            let overlap = Set(normalized(span).split(separator: " ")).intersection(wanted).subtracting(stop).count
            if overlap > score { score = overlap; best = span }
        }
        return best.flatMap { keyPhrase($0, sentence: sentence, transcript: transcript) }
    }
    public static func section(_ output: ModelSectionNotes, section: NotesSection, transcript: Transcript, onRepair: (String, String) -> Void = { _, _ in }) -> ModelSectionNotes? {
        let source = transcript.segments.filter(\.isFinal).map(\.text).joined(separator: " ")
        let allowed = groundingSource(source)
        func repair(_ value: String, field: String, limit: Int) -> String {
            var result = stripMachinery(value)
            if result != value { onRepair(field, "stripMachinery") }
            let paraphrased = EvidenceValidator.paraphrase(result)
            if paraphrased != result { onRepair(field, "removeQuotationMarks") }
            result = paraphrased
            let citations = try! NSRegularExpression(pattern: #"(?:[1-3]\s+)?[A-Z][a-z]+(?:\s+[A-Z][a-z]+)?\s+\d+:\d+(?:[–-]\d+)?"#)
            for match in citations.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                if scripture(String(result[range]), source: source) == nil { result.removeSubrange(range); onRepair(field, "dropUnheardReference") }
            }
            // Preserve useful prose while removing names absent from the entire
            // transcript. Divine names remain valid in a church Bible study.
            let tagger = NLTagger(tagSchemes: [.nameType]); tagger.string = result
            var ranges: [Range<String.Index>] = []
            tagger.enumerateTags(in: result.startIndex..<result.endIndex, unit: .word, scheme: .nameType, options: [.joinNames, .omitWhitespace, .omitPunctuation]) { tag, range in
                if (tag == .personalName || tag == .placeName || tag == .organizationName), !allowedName(String(result[range]), source: allowed) { ranges.append(range) }
                return true
            }
            for range in ranges.reversed() { result.removeSubrange(range); onRepair(field, "dropUnheardName") }
            if words(result) > limit { result = trim(result, to: limit); onRepair(field, "trimWords") }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var result = output
        result.summary = repair(output.summary, field: "summary", limit: 80)
        guard !normalized(result.summary).isEmpty, !hasMachinery(result.summary) else { onRepair("summary", normalized(result.summary).isEmpty ? "empty" : "remainingMachinery"); return nil }
        result.pointHeading = Self.heading(repair(Self.heading(output.pointHeading), field: "pointHeading", limit: 8))
        result.illustration = repair(output.illustration, field: "illustration", limit: 40)
        result.application = repair(output.application, field: "application", limit: 40)
        result.scripture = output.scripture.compactMap { reference in
            let valid = scripture(reference, source: source)
            if valid == nil { onRepair("scripture", "dropUnheardReference") }
            return valid
        }
        if section.sentences.allSatisfy({ $0.isPrimarySpeaker == false }) { result.role = .discussion }
        else if let forced = section.forcedRole { result.role = forced }
        let sentence = section.sentences.first { $0.number == output.keyPhraseSentence }
        let phrase = snappedPhrase(output.keyPhrase, sentence: sentence, transcript: transcript)
        if phrase?.text != output.keyPhrase { onRepair("keyPhrase", phrase == nil ? "dropUnmatchedPhrase" : "snapToSourceSpan") }
        result.keyPhrase = phrase?.text ?? ""
        return result
    }
    public static func notes(_ output: ModelSermonNotes, sections: [GroundedSectionNotes], transcript: Transcript, announcedCount: Int?, engine: String) -> SermonNotes? {
        let source = transcript.segments.filter(\.isFinal).map(\.text).joined(separator: " ")
        let prose = [output.title, output.bigIdea, output.mainPassage] + output.thisWeek + output.questions + output.points.flatMap { [$0.heading, $0.summary] + $0.scripture }
        guard !prose.contains(where: hasMachinery),
              let idea = text(output.bigIdea, source: source, maxWords: 20), sentenceCount(idea) == 1,
              !idea.lowercased().hasPrefix("this sermon is about"),
              announcedCount.map({ output.points.count == $0 }) ?? (2...4).contains(output.points.count),
              (1...3).contains(output.thisWeek.count), output.questions.count == 2 else { return nil }
        let supporting = sections.filter { $0.notes != nil && $0.notes?.role != .welcome && $0.notes?.role != .closing }
        let available = supporting.filter { $0.notes?.role != .discussion }
        guard !available.isEmpty else { return nil }
        var points: [SermonPoint] = []
        let ordered = output.points.sorted { a, b in
            let aStart = available.filter { a.sectionNumbers.contains($0.section.number) }.map(\.section.start).min() ?? .greatestFiniteMagnitude
            let bStart = available.filter { b.sectionNumbers.contains($0.section.number) }.map(\.section.start).min() ?? .greatestFiniteMagnitude
            return aStart < bStart
        }
        for (offset, point) in ordered.enumerated() {
            let references = supporting.filter { point.sectionNumbers.contains($0.section.number) }
            let cited = references.contains { $0.notes?.role != .discussion } ? references : []
            // A missing citation never silently deletes a point. Use the announced
            // point's complete section range, or the corresponding teaching section.
            let fallback = available.filter { $0.section.announcedPoint == offset + 1 }
            // Announced points must cover every announced stretch exactly once;
            // duplicate model citations cannot make the middle point disappear.
            if announcedCount != nil && fallback.isEmpty { return nil }
            let selected = announcedCount != nil ? fallback : (!cited.isEmpty ? cited : (!fallback.isEmpty ? fallback : [available[min(offset, available.count - 1)]]))
            let indexes = Array(Set(selected.flatMap { $0.section.segmentIndexes })).sorted()
            guard let heading = text(point.heading, source: source, maxWords: 8), let summary = text(point.summary, source: source),
                  (1...2).contains(sentenceCount(summary)), let evidence = EvidenceValidator.range(transcript: transcript, indexes: indexes) else { return nil }
            let start = selected.map(\.section.start).min() ?? evidence.start
            let phrase = selected.compactMap { item -> KeyPhrase? in
                guard let map = item.notes else { return nil }
                return keyPhrase(map.keyPhrase, sentence: item.section.sentences.first { $0.number == map.keyPhraseSentence }, transcript: transcript)
            }.first
            let unnumbered = Self.heading(heading)
            guard !unnumbered.isEmpty else { return nil }
            points.append(SermonPoint(heading: unnumbered, summary: summary, scripture: point.scripture.compactMap { scripture($0, source: source) }, keyPhrase: phrase, start: start, evidence: evidence))
        }
        let actions = output.thisWeek.compactMap { text($0, source: source) }
        let questions = output.questions.compactMap { text($0, source: source) }
        guard actions.count == output.thisWeek.count, questions.count == 2,
              actions.allSatisfy(startsWithVerb), questions.allSatisfy({ $0.hasSuffix("?") && $0.range(of: #"\b(you|your)\b"#, options: [.regularExpression, .caseInsensitive]) != nil }) else { return nil }
        return SermonNotes(title: output.title.isEmpty ? nil : text(output.title, source: source, maxWords: 7), bigIdea: idea, mainPassage: scripture(output.mainPassage, source: source) ?? ScriptureDetector.mainPassage(in: source), pointsAnnounced: announcedCount != nil, points: points.sorted { $0.start < $1.start }, thisWeek: actions, questions: questions, engine: engine)
    }
    public static func startsWithVerb(_ text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.lexicalClass]); tagger.string = text
        guard !text.isEmpty else { return false }
        let tag = tagger.tag(at: text.startIndex, unit: .word, scheme: .lexicalClass).0
        // Imperatives such as "Practice" and "Share" are ambiguous without a
        // subject; include common action verbs when Apple's tagger calls them nouns.
        let verb = text.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
        return tag == .verb || ["pray", "read", "ask", "name", "practice", "practise", "share", "serve", "give", "make", "take", "write", "listen", "invite", "choose", "notice", "remember", "trust", "thank", "call", "visit", "set", "spend", "offer", "start", "seek", "reflect", "forgive", "help", "wait", "bring", "keep", "turn", "leave", "find", "tell", "open", "let"].contains(verb)
    }
}

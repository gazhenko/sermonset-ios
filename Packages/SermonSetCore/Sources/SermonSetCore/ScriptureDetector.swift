import Foundation

/// Parses what was heard, independently of either model's spelling or formatting.
public enum ScriptureDetector {
    public struct Reference: Hashable, Sendable {
        public var book: String
        public var chapter: Int
        public var verses: String?
        public var chapterReference: String { "\(book) \(chapter)" }
        public var text: String { chapterReference + (verses.map { ":" + $0 } ?? "") }
    }
    static let books = ["Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles", "Ezra", "Nehemiah", "Esther", "Job", "Psalms", "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi", "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians", "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews", "James", "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation"]
    private static func pattern(_ book: String) -> String {
        let variants = ["Samuel": "samu(?:el|al|els)", "Psalms": "psalms?|salms?", "Matthew": "mat(?:t)?hew", "Revelation": "revelations?", "Philippians": "phil(?:l)?ip(?:p)?ians", "Thessalonians": "thes(?:s)?alonians", "Song of Solomon": "song of (?:solomon|songs)"]
        let parts = book.split(separator: " ", maxSplits: 1)
        if parts.count == 2, let n = Int(parts[0]) {
            let prefix = [1: "(?:1|1st|first|one|i)", 2: "(?:2|2nd|second|two|ii)", 3: "(?:3|3rd|third|three|iii)"][n]!
            let base = String(parts[1])
            return prefix + #"\s+"# + (variants[base] ?? NSRegularExpression.escapedPattern(for: base))
        }
        return "(?:" + (variants[book] ?? NSRegularExpression.escapedPattern(for: book)) + ")"
    }
    private static func numbers(_ text: String) -> String {
        let values = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "hundred": 100]
        let unit = "(?:" + values.keys.sorted().joined(separator: "|") + ")"
        let regex = try! NSRegularExpression(pattern: "\\b" + unit + "(?:[ -]+" + unit + ")*\\b", options: .caseInsensitive)
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: text), let replacement = Range(match.range, in: result) else { continue }
            var total = 0
            for word in text[range].lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }) {
                let value = values[String(word)] ?? 0
                total = value == 100 ? max(1, total) * 100 : total + value
            }
            result.replaceSubrange(replacement, with: String(total))
        }
        return result
    }
    public static func mentions(_ book: String, in source: String) -> Bool {
        source.range(of: "\\b" + pattern(book) + "\\b", options: [.regularExpression, .caseInsensitive]) != nil
    }
    public static func references(in source: String) -> [Reference] {
        let source = numbers(source)
        var found: [(Int, Reference)] = []
        for book in books {
            let expression = "\\b" + pattern(book) + #"\s*,?\s+(?:chapter\s+)?(\d{1,3})(?:\s*(?::|,\s*(?:verses?\s+)?|\s+verses?\s+)(\d{1,3})(?:\s*(?:to|through|[-–—])\s*(\d{1,3}))?)?\b"#
            let regex = try! NSRegularExpression(pattern: expression, options: .caseInsensitive)
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                func integer(_ i: Int) -> Int? { Range(match.range(at: i), in: source).flatMap { Int(source[$0]) } }
                guard let chapter = integer(1), (1...150).contains(chapter) else { continue }
                let first = integer(2), last = integer(3)
                guard first.map({ (1...176).contains($0) }) ?? true, last.map({ (first ?? 1)...176 ~= $0 }) ?? true else { continue }
                let verses = first.map { String($0) + (last.map { "–\($0)" } ?? "") }
                found.append((match.range.location, Reference(book: book, chapter: chapter, verses: verses)))
            }
        }
        // A numbered book also contains the unnumbered name (e.g. 1 John).
        return found.sorted { $0.0 < $1.0 }.filter { candidate in
            !found.contains { other in other.0 < candidate.0 && other.1.book.hasSuffix(" " + candidate.1.book) && other.1.chapter == candidate.1.chapter && candidate.0 - other.0 < 8 }
        }.map(\.1)
    }
    public static func heard(in source: String) -> String {
        var seen: Set<String> = []
        let references = references(in: source).map(\.text).filter { seen.insert($0).inserted }
        return "References heard: " + (references.isEmpty ? "none" : references.joined(separator: "; "))
    }
    public static func mainPassage(in source: String) -> String? {
        let references = references(in: source)
        let counts = Dictionary(grouping: references, by: \.chapterReference).mapValues(\.count)
        var best: Reference?
        for reference in references where (counts[reference.chapterReference] ?? 0) > (best.flatMap { counts[$0.chapterReference] } ?? 0) { best = reference }
        return best?.chapterReference
    }
    public static func validate(_ reference: String, source: String) -> String? {
        let clean = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = references(in: clean).first, mentions(parsed.book, in: source) {
            let heard = references(in: source)
            if heard.contains(where: { $0.book == parsed.book && $0.chapter == parsed.chapter && (parsed.verses == nil || $0.verses == parsed.verses) }) { return parsed.text }
            return nil
        }
        return books.first { clean.range(of: "^" + pattern($0) + "$", options: [.regularExpression, .caseInsensitive]) != nil && mentions($0, in: source) }
    }
}

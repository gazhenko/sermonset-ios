import Foundation

public enum NotesJSON {
    /// Accepts prose/code fences around one object and trailing commas. Repairs
    /// only punctuation outside strings, preserving quoted scripture/phrases.
    public static func decode<T: Decodable>(_ type: T.Type, from response: String) throws -> T {
        let characters = Array(response)
        guard let start = characters.firstIndex(of: "{") else { throw CocoaError(.coderReadCorrupt) }
        var inString = false, escaped = false, depth = 0
        var end: Int?
        for index in start..<characters.count {
            let c = characters[index]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
            else if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { end = index; break } }
        }
        guard let end else { throw CocoaError(.coderReadCorrupt) }
        var repaired = ""; inString = false; escaped = false
        for index in start...end {
            let c = characters[index]
            if !inString && c == "," {
                var next = index + 1
                while next <= end && characters[next].isWhitespace { next += 1 }
                if next <= end && (characters[next] == "}" || characters[next] == "]") { continue }
            }
            repaired.append(c)
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
        }
        return try JSONDecoder().decode(type, from: Data(repaired.utf8))
    }
}

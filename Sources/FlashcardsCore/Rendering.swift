import Foundation

public enum CardRenderer {
    private static let cloze = try! NSRegularExpression(pattern: #"\{\{c([1-9][0-9]*)::(.*?)(?:::(.*?))?\}\}"#, options: [.dotMatchesLineSeparators])

    public static func clozeIndices(in text: String) -> [Int] {
        let ns = text as NSString
        return Array(Set(cloze.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            Int(ns.substring(with: $0.range(at: 1))).map { $0 - 1 }
        })).sorted()
    }

    public static func templateIndices(for note: Note) -> [Int] {
        switch note.kind {
        case .basic: return [0]
        case .basicAndReversed: return [0, 1]
        case .cloze: return clozeIndices(in: note.front)
        }
    }

    public static func question(note: Note, templateIndex: Int) -> String {
        switch note.kind {
        case .basic: return note.front
        case .basicAndReversed: return templateIndex == 1 ? note.back : note.front
        case .cloze: return renderCloze(note.front, index: templateIndex, reveal: false)
        }
    }

    public static func answerField(note: Note, templateIndex: Int) -> String {
        switch note.kind {
        case .basic: return note.back
        case .basicAndReversed: return templateIndex == 1 ? note.front : note.back
        case .cloze:
            let rendered = renderCloze(note.front, index: templateIndex, reveal: true)
            return rendered + (note.back.isEmpty ? "" : "<br><br>" + note.back)
        }
    }

    public static func answer(note: Note, templateIndex: Int) -> String {
        if note.kind == .cloze { return answerField(note: note, templateIndex: templateIndex) }
        return question(note: note, templateIndex: templateIndex) + "<hr id=\"answer\">" + answerField(note: note, templateIndex: templateIndex)
    }

    /// Text for browser rows/search, retaining authored Unicode and decoding common HTML entities.
    public static func plainText(_ html: String) -> String {
        var result = html.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)<br\s*/?>|</(?:p|div|li|h[1-6])>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        for (entity, replacement) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func renderCloze(_ text: String, index: Int, reveal: Bool) -> String {
        let ns = text as NSString
        let matches = cloze.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for match in matches.reversed() {
            let selected = Int(ns.substring(with: match.range(at: 1))) == index + 1
            let body = ns.substring(with: match.range(at: 2))
            let replacement: String
            if selected && !reveal {
                let hint = match.range(at: 3).location == NSNotFound ? "..." : ns.substring(with: match.range(at: 3))
                replacement = "<span class=\"cloze\">[" + hint + "]</span>"
            } else if selected {
                replacement = "<span class=\"cloze\">" + body + "</span>"
            } else { replacement = body }
            if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }
}

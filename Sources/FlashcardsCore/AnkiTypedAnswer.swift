import Foundation

/// The desktop reviewer handles [[type:...]] after backend template rendering.
/// Keep that presentation step separate from both scheduling and note content.
public struct AnkiTypedAnswer: Sendable {
    public let expected: String
    public let combining: Bool
    public let font: String
    public let size: Int
    private static let pattern = try! NSRegularExpression(pattern: #"\[\[type:(.+?)\]\]"#)
    public func questionHTML(_ html: String) -> String {
        let family = font.replacingOccurrences(of: "'", with: "\\27 ").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
        let input = expected.isEmpty ? "" : "<input id=\"typeans\" type=\"text\" aria-label=\"Your answer\" autocomplete=\"off\" autocapitalize=\"off\" style=\"font-family:'\(family)';font-size:\(size)px;max-width:100%;box-sizing:border-box\" onkeydown=\"if(event.key==='Enter'){event.preventDefault();pycmd('ans');}\">"
        return replace(html, with: input)
    }
    public func replacingMarkers(in html: String, with comparison: String) -> String { replace(html, with: expected.isEmpty ? "" : comparison) }
    private func replace(_ html: String, with value: String) -> String {
        Self.pattern.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: NSRegularExpression.escapedTemplate(for: value))
    }
    static func field(in html: String) -> String? {
        guard let match = pattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
}

extension AnkiCollection {
    public func typedAnswer(cardID: String, question: String) throws -> AnkiTypedAnswer? {
        guard var name = AnkiTypedAnswer.field(in: question) else { return nil }
        var cloze = false, combining = true
        if name.hasPrefix("cloze:") { cloze = true; name = String(name.dropFirst(6)) }
        if name.hasPrefix("nc:") { combining = false; name = String(name.dropFirst(3)) }
        let card = try getCard(cardID), note = try getNote(card["noteId"].string), type = try notetype(note["notetypeId"].string)
        guard let index = type["fields"].array.firstIndex(where: { $0["name"].string == name }), note["fields"].array.indices.contains(index) else {
            throw CollectionError.invalidInput("The typed-answer template refers to an unknown field: \(name).")
        }
        var expected = note["fields"].array[index].string
        if cloze { expected = try backend.call("CardRendering", "ExtractClozeForTyping", ["text": .string(expected), "ordinal": .number(Double(card["templateIdx"].int + 1))])["val"].string }
        let config = type["fields"].array[index]["config"]
        return AnkiTypedAnswer(expected: expected, combining: combining, font: config["fontName"].string, size: max(12, config["fontSize"].int))
    }
    public func compareTypedAnswer(_ answer: AnkiTypedAnswer, provided: String) throws -> String {
        try backend.call("CardRendering", "CompareAnswer", ["expected": .string(answer.expected), "provided": .string(provided), "combining": .bool(answer.combining)])["val"].string
    }
}

import Foundation

extension CollectionStore {
    /// AND search with quoted values and negation: deck:"French Verbs" -is:suspended tag:verbs.
    /// This intentionally implements a documented subset of Anki's search language.
    public func search(_ query: String, now: Date = Date()) -> [StudyCard] {
        return readDocument { doc in
            Self.studyCards(in: doc).filter { Self.matches($0, query: query, now: now) }.sorted { $0.note.createdAt == $1.note.createdAt ? $0.card.templateIndex < $1.card.templateIndex : $0.note.createdAt < $1.note.createdAt }
        }
    }

    static func matches(_ item: StudyCard, query: String, now: Date) -> Bool {
        let tokens = Self.searchTokens(query)
        return tokens.allSatisfy { raw in
                    let negated = raw.hasPrefix("-")
                    let token = (negated ? String(raw.dropFirst()) : raw).lowercased()
                    let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    let value = parts.count == 2 ? String(parts[1]) : ""
                    let match: Bool
                    switch parts.first.map(String.init) {
                    case "deck" where parts.count == 2: match = item.deck.name.lowercased() == value || item.deck.name.lowercased().hasPrefix(value + "::")
                    case "tag" where parts.count == 2: match = item.tags.contains { $0.lowercased() == value || $0.lowercased().hasPrefix(value + "::") }
                    case "flag" where parts.count == 2: match = Int(value) == item.card.flag
                    case "is" where parts.count == 2:
                        switch value {
                        case "new": match = item.card.state == .new
                        case "learn", "learning": match = item.card.state == .learning || item.card.state == .relearning
                        case "review": match = item.card.state == .review
                        case "suspended": match = item.card.suspended
                        case "buried": match = item.card.isBuried(at: now)
                        case "due": match = !item.card.suspended && !item.card.isBuried(at: now) && item.card.state != .new && item.card.due <= now
                        default: match = false
                        }
                    case "prop" where parts.count == 2:
                        match = numericMatch(value, item: item, now: now)
                    default:
                        if ["front", "back"].contains(parts.first.map(String.init) ?? ""), parts.count == 2 {
                            match = CardRenderer.plainText(parts[0] == "front" ? item.note.front : item.note.back).range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                            return negated ? !match : match
                        }
                        let text = [CardRenderer.plainText(item.note.front), CardRenderer.plainText(item.note.back), item.deck.name, item.tags.joined(separator: " ")].joined(separator: " ")
                        match = text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    }
                    return negated ? !match : match
                }
    }

    private static func numericMatch(_ expression: String, item: StudyCard, now: Date) -> Bool {
        let pattern = "^(ivl|reps|lapses|ease|due)(<=|>=|!=|=|<|>)(-?[0-9]+(?:[.][0-9]+)?)$"
        guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: expression, range: NSRange(expression.startIndex..., in: expression)) else { return false }
        func part(_ n: Int) -> String { String(expression[Range(m.range(at: n), in: expression)!]) }
        guard let target = Double(part(3)) else { return false }
        let values = ["ivl": item.card.intervalDays, "reps": Double(item.card.reps), "lapses": Double(item.card.lapses), "ease": item.card.easeFactor, "due": item.card.due.timeIntervalSince(now) / 86400]
        guard let value = values[part(1)] else { return false }
        switch part(2) { case "<": return value < target; case ">": return value > target; case "<=": return value <= target; case ">=": return value >= target; case "!=": return value != target; default: return value == target }
    }

    private static func searchTokens(_ query: String) -> [String] {
        var tokens: [String] = [], current = "", quoted = false, escaped = false
        for character in query {
            if escaped { current.append(character); escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" { quoted.toggle() }
            else if character.isWhitespace && !quoted {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else { current.append(character) }
        }
        if escaped { current.append("\\") }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

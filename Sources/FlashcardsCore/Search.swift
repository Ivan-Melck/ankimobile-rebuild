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
                    let value = parts.count == 2 ? unescape(String(parts[1])) : ""
                    let match: Bool
                    if let numeric = numericFieldComparison(token, item: item) { return negated ? !numeric : numeric }
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
                            let text = CardRenderer.plainText(parts[0] == "front" ? item.note.front : item.note.back)
                            match = numericFieldRange(value, text: text) ?? (text.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
                            return negated ? !match : match
                        }
                        let text = [CardRenderer.plainText(item.note.front), CardRenderer.plainText(item.note.back), item.deck.name, item.tags.joined(separator: " ")].joined(separator: " ")
                        match = text.range(of: unescape(token), options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    }
                    return negated ? !match : match
                }
    }

    private static func unescape(_ text: String) -> String {
        var output = "", escaped = false
        for char in text { if escaped { output.append(char); escaped = false } else if char == "\\" { escaped = true } else { output.append(char) } }
        if escaped { output.append("\\") }; return output
    }
    private static func numericFieldComparison(_ expression: String, item: StudyCard) -> Bool? {
        let pattern = "^(front|back)(<=|>=|=|<|>)(-?[0-9]+(?:[.][0-9]+)?)$"
        guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: expression, range: NSRange(expression.startIndex..., in: expression)) else { return nil }
        func part(_ n: Int) -> String { String(expression[Range(m.range(at: n), in: expression)!]) }
        let text = CardRenderer.plainText(part(1) == "front" ? item.note.front : item.note.back).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(text), value.isFinite, let target = Double(part(3)), target.isFinite else { return false }
        switch part(2) { case "<": return value < target; case ">": return value > target; case "<=": return value <= target; case ">=": return value >= target; default: return value == target }
    }
    private static func numericFieldRange(_ expression: String, text: String) -> Bool? {
        guard let left = expression.first, let right = expression.last, ["[", "("].contains(left), ["]", ")"].contains(right) else { return nil }
        let limits = expression.dropFirst().dropLast().split(separator: ",", omittingEmptySubsequences: false)
        guard limits.count == 2, let low = Double(limits[0].trimmingCharacters(in: .whitespaces)), let high = Double(limits[1].trimmingCharacters(in: .whitespaces)), low.isFinite, high.isFinite else { return nil }
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else { return false }
        return (left == "[" ? value >= low : value > low) && (right == "]" ? value <= high : value < high)
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
            if escaped { current.append("\\"); current.append(character); escaped = false }
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

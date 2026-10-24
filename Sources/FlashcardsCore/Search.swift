import Foundation

extension CollectionStore {
    /// AND search with quoted values and negation: deck:"French Verbs" -is:suspended tag:verbs.
    /// This intentionally implements a documented subset of Anki's search language.
    public func search(_ query: String, now: Date = Date()) -> [StudyCard] {
        let tokens = Self.searchTokens(query)
        return readDocument { doc in
            Self.studyCards(in: doc).filter { item in
                tokens.allSatisfy { raw in
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
                    default:
                        let text = [CardRenderer.plainText(item.note.front), CardRenderer.plainText(item.note.back), item.deck.name, item.tags.joined(separator: " ")].joined(separator: " ")
                        match = text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    }
                    return negated ? !match : match
                }
            }.sorted { $0.note.createdAt == $1.note.createdAt ? $0.card.templateIndex < $1.card.templateIndex : $0.note.createdAt < $1.note.createdAt }
        }
    }

    private static func searchTokens(_ query: String) -> [String] {
        var tokens: [String] = [], current = "", quoted = false
        for character in query {
            if character == "\"" { quoted.toggle() }
            else if character.isWhitespace && !quoted {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else { current.append(character) }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

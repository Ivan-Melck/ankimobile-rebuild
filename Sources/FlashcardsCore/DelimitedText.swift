import Foundation

extension CollectionStore {
    /// Columns: Front, Back, Tags. Optional header. Imports are all-or-nothing.
    @discardableResult public func importDelimitedText(_ text: String, deckID: UUID, delimiter: Character = ",") throws -> ImportResult {
        let rows = try DelimitedText.parse(text, delimiter: delimiter)
        return try mutate { doc in
            guard doc.decks.contains(where: { $0.id == deckID }) else { throw CollectionError.notFound("Deck not found.") }
            var imported = 0, skipped = 0
            let before = doc.cards.count
            var existing = Set(doc.cards.filter { $0.deckID == deckID }.map(\.noteID))
            var fronts = Set(doc.notes.filter { existing.contains($0.id) }.map(\.front))
            for (index, row) in rows.enumerated() {
                if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
                if index == 0 && row.first?.lowercased() == "front" && row.dropFirst().first?.lowercased() == "back" { continue }
                guard (2...3).contains(row.count) else { throw CollectionError.malformedCSV("Row \(index + 1) needs Front, Back, and optional Tags columns.") }
                if fronts.contains(row[0]) { skipped += 1; continue }
                let note = try Self.insertNote(into: &doc, deckID: deckID, front: row[0], back: row[1], tags: row.count == 3 ? [row[2]] : [], kind: .basic)
                existing.insert(note.id); fronts.insert(note.front); imported += 1
            }
            return ImportResult(importedNotes: imported, importedCards: doc.cards.count - before, skippedDuplicates: skipped)
        }
    }

    public func exportDelimitedText(deckID: UUID? = nil, delimiter: Character = ",") -> String {
        readDocument { doc in
            let selected = Set(doc.cards.filter { deckID == nil || $0.deckID == deckID }.map(\.noteID))
            let rows = [["Front", "Back", "Tags"]] + doc.notes.filter { selected.contains($0.id) }.map { [$0.front, $0.back, $0.tags.joined(separator: " ")] }
            return rows.map { $0.map { DelimitedText.escape($0, delimiter: delimiter) }.joined(separator: String(delimiter)) }.joined(separator: "\r\n") + "\r\n"
        }
    }
}

enum DelimitedText {
    static func escape(_ field: String, delimiter: Character) -> String {
        if field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func parse(_ raw: String, delimiter: Character) throws -> [[String]] {
        guard delimiter == "," || delimiter == "\t" else { throw CollectionError.malformedCSV("Choose comma or tab as the delimiter.") }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let text = normalized.hasPrefix("\u{FEFF}") ? String(normalized.dropFirst()) : normalized
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false
        var iterator = text.makeIterator()
        while let c = iterator.next() {
            if quoted {
                if c == "\"" { quoted = false; closed = true } else { field.append(c) }
            } else if closed && c == "\"" {
                field.append("\""); quoted = true; closed = false
            } else if c == delimiter {
                row.append(field); field = ""; closed = false
            } else if c == "\n" {
                row.append(field); rows.append(row); row = []; field = ""; closed = false
            } else if c == "\"" && field.isEmpty && !closed {
                quoted = true
            } else {
                guard !closed && c != "\"" else { throw CollectionError.malformedCSV("Unexpected character after a quoted field.") }
                field.append(c)
            }
        }
        guard !quoted else { throw CollectionError.malformedCSV("A quoted field was not closed.") }
        if !row.isEmpty || !field.isEmpty || closed { row.append(field); rows.append(row) }
        return rows
    }
}

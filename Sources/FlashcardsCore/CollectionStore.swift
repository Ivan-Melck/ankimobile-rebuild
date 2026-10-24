import Foundation

struct ReviewUndo: Codable {
    var card: Card
    var logID: UUID
}

struct CollectionDocument: Codable {
    static let currentVersion = 1
    var format = "flashcards-collection"
    var schemaVersion = currentVersion
    var id = UUID()
    var defaultDeckID: UUID
    var decks: [Deck]
    var notes: [Note] = []
    var cards: [Card] = []
    var reviewLogs: [ReviewLog] = []
    var undo: ReviewUndo?
    var schedulingPresets: [SchedulingPreset]?

    static func empty() -> CollectionDocument {
        let deck = Deck(name: "Default")
        return CollectionDocument(defaultDeckID: deck.id, decks: [deck])
    }
}

/// A small, editable collection repository. Each mutation validates a copy, atomically saves it,
/// and only then publishes it in memory. A failed save therefore leaves the live collection intact.
/// Calls on one instance are serialized. Use a single store instance per collection file/process.
/// This JSON format is specific to this rebuild; it is not an Anki collection database.
public final class CollectionStore {
    public let fileURL: URL?
    public let calendar: Calendar
    private let scheduler: any ReviewScheduler
    private let lock = NSRecursiveLock()
    private var document: CollectionDocument
    var documentForPlanning: CollectionDocument { document }

    public init(fileURL: URL? = nil, scheduler: any ReviewScheduler = ApproximateLocalScheduler(), calendar: Calendar = .current) throws {
        self.fileURL = fileURL; self.scheduler = scheduler; self.calendar = calendar
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            document = try Self.decode(Data(contentsOf: fileURL))
            try Self.validate(document)
        } else {
            document = .empty()
            try persist(document)
        }
    }

    public var decks: [Deck] { locked { document.decks.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } } }
    public var notes: [Note] { locked { document.notes } }
    public var cards: [Card] { locked { document.cards } }
    public var reviewLogs: [ReviewLog] { locked { document.reviewLogs } }
    public var defaultDeckID: UUID { locked { document.defaultDeckID } }
    public var canUndo: Bool { locked { document.undo != nil } }

    @discardableResult public func createDeck(name: String) throws -> Deck {
        try mutate { doc in
            let name = try Self.validDeckName(name, in: doc)
            var options = DeckOptions(); options.scheduling = SchedulingOptions()
            let deck = Deck(name: name, options: options)
            doc.decks.append(deck)
            return deck
        }
    }

    public func renameDeck(id: UUID, name: String) throws {
        try mutate { doc in
            guard let index = doc.decks.firstIndex(where: { $0.id == id }) else { throw CollectionError.notFound("Deck not found.") }
            doc.decks[index].name = try Self.validDeckName(name, in: doc, excluding: id)
        }
    }

    public func updateDeckOptions(id: UUID, options: DeckOptions) throws {
        try mutate { doc in
            guard let index = doc.decks.firstIndex(where: { $0.id == id }) else { throw CollectionError.notFound("Deck not found.") }
            guard options.newCardsPerDay >= 0, options.reviewCardsPerDay >= 0 else { throw CollectionError.invalidInput("Daily limits cannot be negative.") }
            doc.decks[index].options = options
        }
    }

    /// Moves cards into the chosen destination (Default by default), then deletes the deck.
    public func deleteDeck(id: UUID, movingCardsTo destinationID: UUID? = nil) throws {
        try mutate { doc in
            guard id != doc.defaultDeckID else { throw CollectionError.invalidInput("The default deck cannot be deleted.") }
            let target = destinationID ?? doc.defaultDeckID
            guard target != id, doc.decks.contains(where: { $0.id == target }), doc.decks.contains(where: { $0.id == id }) else {
                throw CollectionError.invalidInput("Choose an existing destination deck.")
            }
            for index in doc.cards.indices where doc.cards[index].deckID == id { doc.cards[index].deckID = target }
            doc.decks.removeAll { $0.id == id }
        }
    }

    @discardableResult public func addNote(deckID: UUID, front: String, back: String, tags: [String] = [], kind: NoteKind = .basic) throws -> Note {
        try mutate { doc in
            try Self.insertNote(into: &doc, deckID: deckID, front: front, back: back, tags: tags, kind: kind)
        }
    }

    /// Keeps scheduling for surviving templates; removed templates are deleted and new ones start fresh.
    @discardableResult public func updateNote(id: UUID, front: String, back: String, tags: [String] = [], kind: NoteKind = .basic) throws -> Note {
        try mutate { doc in
            guard let index = doc.notes.firstIndex(where: { $0.id == id }) else { throw CollectionError.notFound("Note not found.") }
            var note = doc.notes[index]
            let oldKind = note.kind
            note.front = front; note.back = back; note.tags = Self.normalizedTags(tags); note.kind = kind; note.modifiedAt = Date()
            try Self.validateNote(note)
            let oldCards = doc.cards.filter { $0.noteID == id }
            guard let deckID = oldCards.first?.deckID else { throw CollectionError.invalidBackup("Note has no cards.") }
            let indices = CardRenderer.templateIndices(for: note)
            // Basic and reversed share forward-template semantics. Cloze templates do not.
            let reset = (oldKind == .cloze) != (kind == .cloze)
            doc.cards.removeAll { $0.noteID == id && (reset || !indices.contains($0.templateIndex)) }
            for templateIndex in indices where !doc.cards.contains(where: { $0.noteID == id && $0.templateIndex == templateIndex }) {
                doc.cards.append(Card(noteID: id, deckID: deckID, templateIndex: templateIndex))
            }
            doc.notes[index] = note
            return note
        }
    }

    public func deleteNote(id: UUID) throws {
        try mutate { doc in
            guard doc.notes.contains(where: { $0.id == id }) else { throw CollectionError.notFound("Note not found.") }
            doc.cards.removeAll { $0.noteID == id }
            doc.notes.removeAll { $0.id == id }
        }
    }

    public func moveCards(ids: [UUID], toDeckID: UUID) throws {
        try mutate { doc in
            guard doc.decks.contains(where: { $0.id == toDeckID }) else { throw CollectionError.notFound("Deck not found.") }
            let selected = Set(ids)
            guard selected.isSubset(of: Set(doc.cards.map(\.id))) else { throw CollectionError.notFound("Card not found.") }
            for index in doc.cards.indices where selected.contains(doc.cards[index].id) { doc.cards[index].deckID = toDeckID }
        }
    }

    public func studyQueue(deckID: UUID? = nil, now: Date = Date()) -> [StudyCard] {
        locked { Self.queue(in: document, deckID: deckID, now: now, calendar: calendar) }
    }

    public func deckCounts(deckID: UUID, now: Date = Date()) -> DeckCounts {
        locked {
            let queue = Self.queue(in: document, deckID: deckID, now: now, calendar: calendar)
            return DeckCounts(new: queue.filter { $0.card.state == .new }.count,
                              learning: queue.filter { $0.card.state == .learning || $0.card.state == .relearning }.count,
                              review: queue.filter { $0.card.state == .review }.count,
                              total: document.cards.filter { $0.deckID == deckID }.count)
        }
    }

    public func studyCard(id: UUID) -> StudyCard? { locked { Self.studyCards(in: document).first { $0.id == id } } }

    /// Uses the same injected engine as answer(), without changing the card or review history.
    public func scheduledDelay(cardID: UUID, rating: ReviewRating, now: Date = Date()) -> TimeInterval? {
        locked {
            guard let card = document.cards.first(where: { $0.id == cardID }) else { return nil }
            guard let next = try? advancedSchedule(card: card, rating: rating, now: now, doc: document) ?? scheduler.schedule(card: card, rating: rating, at: now) else { return nil }
            let delay = next.due.timeIntervalSince(now)
            return delay.isFinite && delay > 0 ? delay : nil
        }
    }

    @discardableResult public func answer(cardID: UUID, rating: ReviewRating, now: Date = Date(), durationSeconds: Double = 0) throws -> ReviewLog {
        try mutate(clearUndo: false) { doc in
            guard durationSeconds.isFinite, durationSeconds >= 0, now.timeIntervalSince1970.isFinite else { throw CollectionError.invalidInput("Invalid review time.") }
            guard let index = doc.cards.firstIndex(where: { $0.id == cardID }) else { throw CollectionError.notFound("Card not found.") }
            let old = doc.cards[index]
            guard !old.suspended, !old.isBuried(at: now), old.state == .new || old.due <= now || Self.options(in: doc, deckID: old.deckID, card: old, now: now).engine == .rwkvInstant else {
                throw CollectionError.invalidInput("This card is suspended, buried, or not due yet.")
            }
            let next = try advancedSchedule(card: old, rating: rating, now: now, doc: doc) ?? scheduler.schedule(card: old, rating: rating, at: now)
            guard next.id == old.id, next.noteID == old.noteID, next.deckID == old.deckID,
                  next.templateIndex == old.templateIndex, next.suspended == old.suspended, next.flag == old.flag,
                  next.due > now else { throw CollectionError.invalidInput("The scheduler returned an invalid card.") }
            let log = ReviewLog(cardID: cardID, deckID: old.deckID, rating: rating, reviewedAt: now,
                                previousState: old.state, previousIntervalDays: old.intervalDays,
                                scheduledIntervalDays: next.intervalDays, durationSeconds: durationSeconds)
            doc.cards[index] = next; doc.reviewLogs.append(log); doc.undo = ReviewUndo(card: old, logID: log.id)
            return log
        }
    }

    public func undoLastReview() throws {
        try mutate(clearUndo: false) { doc in
            guard let undo = doc.undo, let index = doc.cards.firstIndex(where: { $0.id == undo.card.id }),
                  doc.reviewLogs.last?.id == undo.logID else { throw CollectionError.nothingToUndo }
            doc.cards[index] = undo.card
            doc.reviewLogs.removeLast()
            doc.undo = nil
        }
    }

    public func setSuspended(cardID: UUID, suspended: Bool) throws {
        try editCard(cardID) { $0.suspended = suspended }
    }

    public func bury(cardID: UUID, until: Date? = nil) throws {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        try editCard(cardID) { $0.buriedUntil = until ?? tomorrow }
    }

    public func unbury(cardID: UUID) throws { try editCard(cardID) { $0.buriedUntil = nil } }

    public func setFlag(cardID: UUID, flag: Int) throws {
        guard (0...7).contains(flag) else { throw CollectionError.invalidInput("Flag must be between 0 and 7.") }
        try editCard(cardID) { $0.flag = flag }
    }

    public func statistics(deckID: UUID? = nil, now: Date = Date()) -> CollectionStatistics {
        locked {
            let cards = document.cards.filter { deckID == nil || $0.deckID == deckID }
            let logs = document.reviewLogs.filter { deckID == nil || $0.deckID == deckID }
            let day = calendar.startOfDay(for: now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!
            let today = logs.filter { $0.reviewedAt >= day && $0.reviewedAt < tomorrow && $0.reviewedAt <= now }
            let history = logs.filter { $0.reviewedAt <= now }
            return CollectionStatistics(totalCards: cards.count,
                newCards: cards.filter { $0.state == .new }.count,
                learningCards: cards.filter { $0.state == .learning || $0.state == .relearning }.count,
                reviewCards: cards.filter { $0.state == .review }.count,
                suspendedCards: cards.filter(\.suspended).count,
                dueCards: Self.queue(in: document, deckID: deckID, now: now, calendar: calendar).count,
                reviewsToday: today.count,
                retention: history.isEmpty ? 0 : Double(history.filter { $0.rating != .again }.count) / Double(history.count),
                reviewSecondsToday: today.reduce(0) { $0 + $1.durationSeconds })
        }
    }

    /// Portable rebuild-specific JSON, including scheduling, tags, review history, and review undo.
    public func exportBackup() throws -> Data { try locked { try Self.encode(document) } }

    /// Replaces this collection only after the complete backup is decoded and validated.
    public func restoreBackup(_ data: Data) throws {
        try locked {
            let replacement = try Self.decode(data)
            try Self.validate(replacement)
            try persist(replacement)
            document = replacement
        }
    }

    // MARK: Transaction and validation internals

    func locked<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try operation()
    }

    @discardableResult func mutate<T>(clearUndo: Bool = true, _ operation: (inout CollectionDocument) throws -> T) throws -> T {
        try locked {
            var next = document
            let result = try operation(&next)
            if clearUndo { next.undo = nil }
            try Self.validate(next)
            try persist(next)
            document = next
            return result
        }
    }

    func readDocument<T>(_ operation: (CollectionDocument) -> T) -> T { locked { operation(document) } }

    private func editCard(_ id: UUID, operation: (inout Card) -> Void) throws {
        try mutate { doc in
            guard let index = doc.cards.firstIndex(where: { $0.id == id }) else { throw CollectionError.notFound("Card not found.") }
            operation(&doc.cards[index])
        }
    }

    static func insertNote(into doc: inout CollectionDocument, deckID: UUID, front: String, back: String, tags: [String], kind: NoteKind) throws -> Note {
        guard doc.decks.contains(where: { $0.id == deckID }) else { throw CollectionError.notFound("Deck not found.") }
        let note = Note(front: front, back: back, tags: normalizedTags(tags), kind: kind)
        try validateNote(note)
        doc.notes.append(note)
        for index in CardRenderer.templateIndices(for: note) { doc.cards.append(Card(noteID: note.id, deckID: deckID, templateIndex: index)) }
        return note
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func validDeckName(_ raw: String, in doc: CollectionDocument, excluding id: UUID? = nil) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw CollectionError.invalidInput("Deck name cannot be empty.") }
        guard !doc.decks.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw CollectionError.invalidInput("A deck with that name already exists.")
        }
        return name
    }

    static func studyCards(in doc: CollectionDocument) -> [StudyCard] {
        let notes = Dictionary(uniqueKeysWithValues: doc.notes.map { ($0.id, $0) })
        let decks = Dictionary(uniqueKeysWithValues: doc.decks.map { ($0.id, $0) })
        return doc.cards.compactMap { card in
            guard let note = notes[card.noteID], let deck = decks[card.deckID] else { return nil }
            return StudyCard(card: card, note: note, deck: deck)
        }
    }

    static func queue(in doc: CollectionDocument, deckID: UUID?, now: Date, calendar: Calendar) -> [StudyCard] {
        let day = calendar.startOfDay(for: now)
        let logs = doc.reviewLogs.filter { $0.reviewedAt >= day && $0.reviewedAt <= now }
        var output: [StudyCard] = []
        let all = studyCards(in: doc)
        for deck in doc.decks where deckID == nil || deck.id == deckID {
            let options = Self.options(in: doc, deckID: deck.id)
            var scores: [UUID: Double] = [:]
            let candidates = all.filter { item in
                let card = item.card
                guard card.deckID == deck.id, !card.suspended, !card.isBuried(at: now) else { return false }
                let effective = Self.options(in: doc, deckID: deck.id, card: card, now: now)
                if let index = doc.reviewLogs.lastIndex(where: { $0.cardID == card.id }) {
                    let last = doc.reviewLogs[index]
                    if now.timeIntervalSince(last.reviewedAt) < Double(effective.minimumSeconds) { return false }
                    let intervening = doc.reviewLogs.suffix(from: index + 1).filter { $0.cardID != card.id && $0.reviewedAt <= now }.count
                    if intervening < effective.minimumOtherReviews { return false }
                }
                let needsScore = effective.engine == .rwkvInstant || options.reviewOrder == .lowRecall || options.reviewOrder == .relativeOverdueness
                if needsScore, effective.engine != .legacy, card.state != .new,
                   let request = try? NativeScheduling.request(op: "predict", doc: doc, options: effective, deckID: deck.id, card: card, now: now),
                   let prediction = try? NativeScheduling.call(request, as: MemoryPrediction.self), let recall = prediction.retrievability {
                    scores[card.id] = options.reviewOrder == .relativeOverdueness ? recall / effective.desiredRetention : recall
                    if effective.engine == .rwkvInstant, card.state == .review { return recall <= effective.desiredRetention }
                }
                return card.state == .new || card.due <= now
            }
            let introduced = Set(logs.filter { $0.deckID == deck.id && $0.previousState == .new }.map(\.cardID)).count
            let reviewed = Set(logs.filter { $0.deckID == deck.id && $0.previousState == .review }.map(\.cardID)).count
            let new = candidates.filter { $0.card.state == .new }.sorted { cardOrder($0.card, $1.card) }.prefix(max(0, deck.options.newCardsPerDay - introduced))
            let reviews = candidates.filter { $0.card.state == .review }.sorted {
                switch options.reviewOrder {
                case .lowRecall, .relativeOverdueness:
                    if let a = scores[$0.id], let b = scores[$1.id], a != b { return a < b }
                case .intervalAscending: if $0.card.intervalDays != $1.card.intervalDays { return $0.card.intervalDays < $1.card.intervalDays }
                case .intervalDescending: if $0.card.intervalDays != $1.card.intervalDays { return $0.card.intervalDays > $1.card.intervalDays }
                case .due:
                    if options.engine == .rwkvInstant, let a = scores[$0.id], let b = scores[$1.id], a != b { return a < b }
                }
                return cardOrder($0.card, $1.card)
            }.prefix(max(0, deck.options.reviewCardsPerDay - reviewed))
            let learning = candidates.filter { $0.card.state == .learning || $0.card.state == .relearning }.sorted { cardOrder($0.card, $1.card) }
            switch options.learningOrder {
            case .before: output += learning + Array(reviews) + Array(new)
            case .after: output += Array(reviews) + learning + Array(new)
            case .mixed:
                var mixed: [StudyCard] = []; let revs = Array(reviews)
                for i in 0..<max(learning.count, revs.count) {
                    if i < revs.count { mixed.append(revs[i]) }; if i < learning.count { mixed.append(learning[i]) }
                }
                output += mixed + Array(new)
            }
        }
        return output
    }

    private static func priority(_ state: CardState) -> Int {
        switch state { case .learning, .relearning: return 0; case .review: return 1; case .new: return 2 }
    }
    private static func cardOrder(_ lhs: Card, _ rhs: Card) -> Bool {
        lhs.due == rhs.due ? lhs.id.uuidString < rhs.id.uuidString : lhs.due < rhs.due
    }

    private func persist(_ doc: CollectionDocument) throws {
        guard let fileURL else { return }
        let data = try Self.encode(doc)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    static func encode(_ doc: CollectionDocument) throws -> Data {
        let encoder = JSONEncoder()
        // Preserve Date's native reference-epoch Double without lossy epoch arithmetic.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(doc)
    }

    static func decode(_ data: Data) throws -> CollectionDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        // Inspect version before decoding fields that may have changed in future schemas.
        struct Header: Decodable { let format: String; let schemaVersion: Int }
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) }
        catch { throw CollectionError.invalidBackup("The file is not a valid Flashcards rebuild backup.") }
        guard header.format == "flashcards-collection" else { throw CollectionError.invalidBackup("Unrecognized collection format.") }
        guard header.schemaVersion == CollectionDocument.currentVersion else { throw CollectionError.unsupportedSchema(header.schemaVersion) }
        do { return try decoder.decode(CollectionDocument.self, from: data) }
        catch { throw CollectionError.invalidBackup("The collection is incomplete or contains invalid data: \(error.localizedDescription)") }
    }

    static func validateNote(_ note: Note) throws {
        guard !note.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CollectionError.invalidInput("The front field cannot be empty.") }
        let indices = CardRenderer.templateIndices(for: note)
        guard !indices.isEmpty, indices.count <= 10_000, indices.allSatisfy({ $0 >= 0 && $0 < 10_000 }) else {
            throw CollectionError.invalidInput("A cloze note needs at least one deletion, such as {{c1::answer}} (c1 through c10000).")
        }
        guard note.createdAt.timeIntervalSince1970.isFinite, note.modifiedAt.timeIntervalSince1970.isFinite,
              note.tags == normalizedTags(note.tags) else { throw CollectionError.invalidInput("The note contains invalid dates or tags.") }
    }

    static func validate(_ doc: CollectionDocument) throws {
        func require(_ valid: Bool, _ message: String) throws {
            if !valid { throw CollectionError.invalidBackup(message) }
        }
        try require(doc.format == "flashcards-collection" && doc.schemaVersion == CollectionDocument.currentVersion, "Invalid collection format.")
        try require(Set(doc.decks.map(\.id)).count == doc.decks.count && Set(doc.notes.map(\.id)).count == doc.notes.count && Set(doc.cards.map(\.id)).count == doc.cards.count && Set(doc.reviewLogs.map(\.id)).count == doc.reviewLogs.count, "Collection contains duplicate identifiers.")
        let deckIDs = Set(doc.decks.map(\.id)), noteIDs = Set(doc.notes.map(\.id))
        try require(Set(doc.cards.map { NativeScheduling.numericID($0.id) }).count == doc.cards.count &&
                    Set(doc.notes.map { NativeScheduling.numericID($0.id) }).count == doc.notes.count &&
                    Set(doc.decks.map { NativeScheduling.numericID($0.id) }).count == doc.decks.count, "Collection identifiers collide in the native scheduling engine.")
        let presets = doc.schedulingPresets ?? []
        try require(Set(presets.map(\.id)).count == presets.count && presets.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "Invalid scheduling presets.")
        try require(deckIDs.contains(doc.defaultDeckID), "The collection is missing its default deck.")
        var names = Set<String>()
        for preset in doc.schedulingPresets ?? [] { try preset.options.validate() }
        for deck in doc.decks {
            try deck.options.scheduling?.validate()
            try require(Set((deck.options.rules ?? []).map(\.id)).count == (deck.options.rules ?? []).count, "Duplicate scheduling rules.")
            for rule in deck.options.rules ?? [] {
                try require(!rule.query.isEmpty && rule.retention.isFinite && (0.7...0.99).contains(rule.retention), "Invalid scheduling rule.")
                try require(rule.presetID == nil || (doc.schedulingPresets ?? []).contains(where: { $0.id == rule.presetID }), "Missing rule preset.")
            }
            try require(deck.options.presetID == nil || (doc.schedulingPresets ?? []).contains(where: { $0.id == deck.options.presetID }), "Missing scheduling preset.")
            let name = deck.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            try require(!name.isEmpty && names.insert(name).inserted, "Deck names must be nonempty and unique.")
            try require(deck.options.newCardsPerDay >= 0 && deck.options.reviewCardsPerDay >= 0 && deck.createdAt.timeIntervalSince1970.isFinite, "Invalid deck options or date.")
        }
        let noteMap = Dictionary(uniqueKeysWithValues: doc.notes.map { ($0.id, $0) })
        var templates = Set<String>()
        for note in doc.notes { try validateNote(note) }
        for card in doc.cards {
            try require(deckIDs.contains(card.deckID) && noteIDs.contains(card.noteID), "A card references a missing note or deck.")
            try require(CardRenderer.templateIndices(for: noteMap[card.noteID]!).contains(card.templateIndex), "A card references a missing note template.")
            try require(templates.insert("\(card.noteID):\(card.templateIndex)").inserted, "A note has duplicate template cards.")
            try validateCard(card)
        }
        try require(Set(doc.cards.map(\.noteID)) == noteIDs, "A note has no cards.")
        for log in doc.reviewLogs {
            try require(log.reviewedAt.timeIntervalSince1970.isFinite && log.previousIntervalDays.isFinite && log.previousIntervalDays >= 0 && log.scheduledIntervalDays.isFinite && log.scheduledIntervalDays >= 0 && log.durationSeconds.isFinite && log.durationSeconds >= 0, "A review log contains invalid values.")
        }
        if let undo = doc.undo {
            try require(doc.reviewLogs.last?.id == undo.logID && doc.reviewLogs.last?.cardID == undo.card.id && doc.cards.contains(where: { $0.id == undo.card.id && $0.noteID == undo.card.noteID && $0.deckID == undo.card.deckID && $0.templateIndex == undo.card.templateIndex }), "Invalid review undo record.")
            try validateCard(undo.card)
        }
    }

    private static func validateCard(_ card: Card) throws {
        guard card.due.timeIntervalSince1970.isFinite, card.intervalDays.isFinite, card.intervalDays >= 0,
              card.easeFactor.isFinite, (1.0...10.0).contains(card.easeFactor), card.reps >= 0, card.lapses >= 0,
              card.lapses <= card.reps, (0...7).contains(card.flag),
              card.buriedUntil.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              card.lastReviewedAt.map({ $0.timeIntervalSince1970.isFinite }) ?? true else {
            throw CollectionError.invalidBackup("A card contains invalid scheduling values.")
        }
    }
}

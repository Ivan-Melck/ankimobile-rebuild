import Foundation

public enum NoteKind: String, Codable, CaseIterable, Sendable {
    case basic
    case basicAndReversed
    case cloze

    public var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .basicAndReversed: return "Basic (and reversed card)"
        case .cloze: return "Cloze"
        }
    }
}

public struct DeckOptions: Codable, Equatable, Sendable {
    public var newCardsPerDay: Int
    public var reviewCardsPerDay: Int
    public var scheduling: SchedulingOptions?
    public var presetID: UUID?
    public var rules: [SchedulingRule]?
    public init(newCardsPerDay: Int = 20, reviewCardsPerDay: Int = 200) {
        self.newCardsPerDay = newCardsPerDay
        self.reviewCardsPerDay = reviewCardsPerDay
    }
}

public struct Deck: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var options: DeckOptions
    public var createdAt: Date
    public init(id: UUID = UUID(), name: String, options: DeckOptions = .init(), createdAt: Date = Date()) {
        self.id = id; self.name = name; self.options = options; self.createdAt = createdAt
    }
}

public struct Note: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var front: String
    public var back: String
    public var tags: [String]
    public var kind: NoteKind
    public var createdAt: Date
    public var modifiedAt: Date
    public init(id: UUID = UUID(), front: String, back: String, tags: [String] = [], kind: NoteKind = .basic,
                createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id; self.front = front; self.back = back; self.tags = tags; self.kind = kind
        self.createdAt = createdAt; self.modifiedAt = modifiedAt
    }
}

public enum CardState: String, Codable, CaseIterable, Sendable {
    case new, learning, review, relearning
}

public struct Card: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var noteID: UUID
    public var deckID: UUID
    /// Zero for forward cards; one for reverse cards. Cloze indices are deletion number minus one.
    public var templateIndex: Int
    public var state: CardState
    public var due: Date
    public var intervalDays: Double
    public var easeFactor: Double
    public var reps: Int
    public var lapses: Int
    public var suspended: Bool
    public var buriedUntil: Date?
    public var flag: Int
    public var lastReviewedAt: Date?
    public init(id: UUID = UUID(), noteID: UUID, deckID: UUID, templateIndex: Int = 0, due: Date = Date()) {
        self.id = id; self.noteID = noteID; self.deckID = deckID; self.templateIndex = templateIndex
        self.state = .new; self.due = due; self.intervalDays = 0; self.easeFactor = 2.5
        self.reps = 0; self.lapses = 0; self.suspended = false; self.buriedUntil = nil
        self.flag = 0; self.lastReviewedAt = nil
    }
    public func isBuried(at date: Date) -> Bool { buriedUntil.map { $0 > date } ?? false }
}

public enum ReviewRating: Int, Codable, CaseIterable, Sendable {
    case again = 1, hard = 2, good = 3, easy = 4
    public var displayName: String {
        switch self { case .again: return "Again"; case .hard: return "Hard"; case .good: return "Good"; case .easy: return "Easy" }
    }
}

public struct ReviewLog: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var cardID: UUID
    public var deckID: UUID
    public var rating: ReviewRating
    public var reviewedAt: Date
    public var previousState: CardState
    public var previousIntervalDays: Double
    public var scheduledIntervalDays: Double
    public var durationSeconds: Double
    /// Preset selected before answering; preserves causal RWKV preset state during replay.
    public var schedulingPresetID: UUID?
    public init(id: UUID = UUID(), cardID: UUID, deckID: UUID, rating: ReviewRating, reviewedAt: Date,
                previousState: CardState, previousIntervalDays: Double, scheduledIntervalDays: Double, durationSeconds: Double = 0) {
        self.id = id; self.cardID = cardID; self.deckID = deckID; self.rating = rating; self.reviewedAt = reviewedAt
        self.previousState = previousState; self.previousIntervalDays = previousIntervalDays
        self.scheduledIntervalDays = scheduledIntervalDays; self.durationSeconds = durationSeconds
    }
}

public struct StudyCard: Identifiable, Equatable, Sendable {
    public var card: Card
    public var note: Note
    public var deck: Deck
    public var id: UUID { card.id }
    public var questionHTML: String { CardRenderer.question(note: note, templateIndex: card.templateIndex) }
    public var answerHTML: String { CardRenderer.answer(note: note, templateIndex: card.templateIndex) }
    public var question: String { questionHTML }
    public var answer: String { CardRenderer.answerField(note: note, templateIndex: card.templateIndex) }
    public var tags: [String] { note.tags }
}

public struct DeckCounts: Equatable, Sendable {
    public var new: Int
    public var learning: Int
    public var review: Int
    public var total: Int
}

public struct CollectionStatistics: Equatable, Sendable {
    public var totalCards: Int
    public var newCards: Int
    public var learningCards: Int
    public var reviewCards: Int
    public var suspendedCards: Int
    public var dueCards: Int
    public var reviewsToday: Int
    /// Fraction of all logged answers that were Hard, Good, or Easy, in [0, 1].
    public var retention: Double
    public var reviewSecondsToday: Double
}

public struct ImportResult: Equatable, Sendable {
    public var importedNotes: Int
    public var importedCards: Int
    public var skippedDuplicates: Int
}

public enum CollectionError: Error, LocalizedError, Equatable {
    case notFound(String)
    case invalidInput(String)
    case invalidBackup(String)
    case unsupportedSchema(Int)
    case nothingToUndo
    case malformedCSV(String)
    public var errorDescription: String? {
        switch self {
        case .notFound(let text), .invalidInput(let text), .invalidBackup(let text), .malformedCSV(let text): return text
        case .unsupportedSchema(let version): return "Collection schema \(version) is not supported."
        case .nothingToUndo: return "There is no review to undo."
        }
    }
}

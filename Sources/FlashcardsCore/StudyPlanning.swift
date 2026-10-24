import Foundation
import CSchedulingEngine

public enum SchedulingEngine: String, Codable, CaseIterable, Sendable {
    case legacy, fsrs6, fsrs7, rwkvCurve, rwkvInstant
    public var title: String { switch self {
    case .legacy: return "Classic"; case .fsrs6: return "FSRS-6"; case .fsrs7: return "FSRS-7"
    case .rwkvCurve: return "RWKV · Curve"; case .rwkvInstant: return "RWKV · Instant"
    } }
    public var detail: String { switch self {
    case .legacy: return "The rebuild’s original interval scheduler."
    case .fsrs6: return "A proven memory model with personalized parameters."
    case .fsrs7: return "Fast and slow memory traces, including same-day reviews."
    case .rwkvCurve: return "Neural recall curves informed by your review history."
    case .rwkvInstant: return "Prioritize cards by their predicted recall right now. FSRS-7 supplies due dates."
    } }
    public var isRWKV: Bool { self == .rwkvCurve || self == .rwkvInstant }
}
public enum ReviewOrder: String, Codable, CaseIterable, Sendable {
    case due, lowRecall, relativeOverdueness, intervalAscending, intervalDescending
    public var title: String { switch self { case .due: return "Due date"; case .lowRecall: return "Lowest recall first"; case .relativeOverdueness: return "Relative overdueness"; case .intervalAscending: return "Shortest interval first"; case .intervalDescending: return "Longest interval first" } }
}
public enum LearningOrder: String, Codable, CaseIterable, Sendable {
    case before, mixed, after
    public var title: String { switch self { case .before: return "Before reviews"; case .mixed: return "Mix with reviews"; case .after: return "After reviews" } }
}
public struct SchedulingOptions: Codable, Equatable, Sendable {
    public var engine: SchedulingEngine = .fsrs7
    public var desiredRetention: Double = 0.9
    public var maximumInterval: Int = 36500
    public var learnAheadMinutes: Int?
    public var allowSameDay: Bool = true
    public var skipLearning: Bool = false
    public var skipRelearning: Bool = false
    public var enforceGradeOrder: Bool = true
    public var reviewOrder: ReviewOrder = .due
    public var learningOrder: LearningOrder = .before
    public var minimumOtherReviews: Int = 0
    public var minimumSeconds: Int = 0
    public var rwkvModel: String = "sm56"
    public var precision: String = "cards_int4_notes_int8"
    public var includeSameDayInAnalysis: Bool = true
    public var parameters: [Double] = []
    public init(engine: SchedulingEngine = .fsrs7) { self.engine = engine }
    public func validate() throws {
        guard desiredRetention.isFinite, (0.7...0.99).contains(desiredRetention), (1...36500).contains(maximumInterval),
              (0...60).contains(learnAheadMinutes ?? 0), (0...10000).contains(minimumOtherReviews), (0...86400).contains(minimumSeconds),
              ["sm56", "sm55", "sm40", "sm36", "legacy"].contains(rwkvModel),
              ["f32", "int8", "int4", "cards_int4_notes_int8"].contains(precision),
              parameters.allSatisfy({ $0.isFinite }), parameters.isEmpty || parameters.count == (engine == .fsrs6 ? 21 : 34) else {
            throw CollectionError.invalidInput("Check retention, interval, repeat spacing, and model parameters.")
        }
    }
}
public struct SchedulingPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var options: SchedulingOptions
    public init(id: UUID = UUID(), name: String, options: SchedulingOptions) { self.id = id; self.name = name; self.options = options }
}
public struct SchedulingRule: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var query: String
    public var retention: Double
    public var presetID: UUID?
    public init(id: UUID = UUID(), query: String, retention: Double, presetID: UUID? = nil) {
        self.id = id; self.query = query; self.retention = retention; self.presetID = presetID
    }
}
public struct MemoryPrediction: Decodable, Equatable, Sendable {
    public var intervals: [Double?]
    public var retrievability: Double?
    public var stability: Double?
    public var difficulty: Double?
    public var probabilities: [Double]?
}
public struct WorkloadPoint: Decodable, Sendable {
    public var retention: Double
    public var reviews: Int
    public var seconds: Double
    public var memorized: Double
    public var efficiency: Double { seconds > 0 ? memorized / (seconds / 60) : 0 }
}
public struct WorkloadForecast: Decodable, Sendable { public var points: [WorkloadPoint] }
public struct CalibrationResult: Decodable, Sendable {
    public var log_loss: Double
    public var rmse: Double
    public var samples: Int
}
struct NativeEvent: Encodable {
    var id: Int64; var note: Int64; var deck: Int64; var preset: Int64?; var time: Double; var rating: Int
    var seconds: Double; var state: Int; var interval: Double; var reps: Int; var lapses: Int
}
struct NativeRequest: Encodable {
    var op: String; var engine: String; var model: String; var path: String; var precision: String
    var retention: Double; var max_interval: Int; var parameters: [Double]
    var history: [NativeEvent]; var cards: [NativeEvent]; var card: NativeEvent?
    var days: Int; var new_limit: Int; var review_limit: Int; var include_same_day: Bool
    var grade_order: Bool; var time_series: Bool; var scope_deck: Int64?
}
enum NativeScheduling {
    private struct Failure: Decodable { var error: String }
    static func call<T: Decodable>(_ request: NativeRequest, as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(request)
        let text = String(decoding: data, as: UTF8.self)
        guard let ptr = text.withCString({ scheduling_engine_request($0) }) else { throw CollectionError.invalidInput("The scheduling engine returned no result.") }
        defer { scheduling_engine_free(ptr) }
        let result = Data(String(cString: ptr).utf8)
        if let failure = try? JSONDecoder().decode(Failure.self, from: result) { throw CollectionError.invalidInput(failure.error) }
        return try JSONDecoder().decode(type, from: result)
    }
    static func numericID(_ id: UUID) -> Int64 {
        // Stable across launches and platforms; keep IDs positive for simulator-generated cards.
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        return Int64(bytes.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } & 0x7fff_ffff_ffff_ffff)
    }
    static func event(_ card: Card, time: Date) -> NativeEvent {
        NativeEvent(id: numericID(card.id), note: numericID(card.noteID), deck: numericID(card.deckID), preset: nil,
                    time: time.timeIntervalSince1970, rating: 3, seconds: 0,
                    state: card.state == .new ? 0 : card.state == .learning ? 1 : card.state == .review ? 2 : 3,
                    interval: card.intervalDays, reps: card.reps, lapses: card.lapses)
    }
    static func request(op: String, doc: CollectionDocument, options: SchedulingOptions, deckID: UUID?, card: Card? = nil, now: Date, days: Int = 30, timeSeries: Bool = false) throws -> NativeRequest {
        try options.validate()
        let cardMap = Dictionary(uniqueKeysWithValues: doc.cards.map { ($0.id, $0) })
        let history = doc.reviewLogs.filter { $0.reviewedAt <= now }.sorted { $0.reviewedAt < $1.reviewedAt }.compactMap { log -> NativeEvent? in
            guard var e = cardMap[log.cardID].map({ event($0, time: log.reviewedAt) }) else { return nil }
            e.deck = numericID(log.deckID); e.preset = log.schedulingPresetID.map(numericID); e.rating = log.rating.rawValue; e.seconds = log.durationSeconds
            e.interval = log.previousIntervalDays; e.reps = 0; e.lapses = 0
            e.state = log.previousState == .new ? 0 : log.previousState == .learning ? 1 : log.previousState == .review ? 2 : 3
            return e
        }
        let deck = doc.decks.first { $0.id == deckID }
        let path = Bundle.module.url(forResource: options.rwkvModel, withExtension: "bin", subdirectory: "RWKV")?.path ?? ""
        return NativeRequest(op: op, engine: options.engine.isRWKV ? "rwkv" : options.engine.rawValue,
            model: options.rwkvModel, path: path, precision: options.precision, retention: options.desiredRetention,
            max_interval: options.maximumInterval, parameters: options.parameters, history: history,
            cards: doc.cards.filter { (deckID == nil || $0.deckID == deckID) && !$0.suspended && !$0.isBuried(at: now) }.map { card in
                var value = event(card, time: now); value.preset = deck?.options.presetID.map(numericID); return value
            },
            card: card.map { card in
                var value = event(card, time: now)
                value.preset = CollectionStore.effectivePresetID(in: doc, deckID: card.deckID, card: card, now: now).map(numericID)
                return value
            }, days: days, new_limit: deck?.options.newCardsPerDay ?? 20,
            review_limit: deck?.options.reviewCardsPerDay ?? 200, include_same_day: options.includeSameDayInAnalysis,
            grade_order: options.enforceGradeOrder, time_series: timeSeries, scope_deck: deckID.map(numericID))
    }
}

extension CollectionStore {
    public var schedulingPresets: [SchedulingPreset] { readDocument { $0.schedulingPresets ?? [] } }
    public func savePreset(_ preset: SchedulingPreset) throws {
        try preset.options.validate()
        guard !preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CollectionError.invalidInput("Give the preset a name.") }
        try mutate { doc in
            var presets = doc.schedulingPresets ?? []
            if let i = presets.firstIndex(where: { $0.id == preset.id }) { presets[i] = preset } else { presets.append(preset) }
            doc.schedulingPresets = presets
        }
    }
    public func schedulingOptions(deckID: UUID) -> SchedulingOptions {
        readDocument { doc in Self.options(in: doc, deckID: deckID) }
    }
    static func options(in doc: CollectionDocument, deckID: UUID, card: Card? = nil, now: Date = Date()) -> SchedulingOptions {
        guard let deck = doc.decks.first(where: { $0.id == deckID }) else { return .init(engine: .legacy) }
        var options = (doc.schedulingPresets ?? []).first { $0.id == deck.options.presetID }?.options ?? deck.options.scheduling ?? .init(engine: .legacy)
        if let card, let item = Self.studyCards(in: doc).first(where: { $0.id == card.id }),
           let rule = deck.options.rules?.first(where: { Self.matches(item, query: $0.query, now: now) }) {
            if let preset = (doc.schedulingPresets ?? []).first(where: { $0.id == rule.presetID }) { options = preset.options }
            options.desiredRetention = rule.retention
        }
        return options
    }
    static func effectivePresetID(in doc: CollectionDocument, deckID: UUID, card: Card, now: Date) -> UUID? {
        guard let deck = doc.decks.first(where: { $0.id == deckID }) else { return nil }
        if let item = Self.studyCards(in: doc).first(where: { $0.id == card.id }),
           let rule = deck.options.rules?.first(where: { Self.matches(item, query: $0.query, now: now) }), let id = rule.presetID { return id }
        return deck.options.presetID
    }
    public func prediction(cardID: UUID, now: Date = Date()) throws -> MemoryPrediction {
        try locked {
            guard let c = documentForPlanning.cards.first(where: { $0.id == cardID }) else { throw CollectionError.notFound("Card not found.") }
            let doc = documentForPlanning
            let options = Self.options(in: doc, deckID: c.deckID, card: c, now: now)
            guard options.engine != .legacy else { throw CollectionError.invalidInput("Choose FSRS or RWKV in Deck Options to see memory predictions.") }
            return try NativeScheduling.call(NativeScheduling.request(op: "predict", doc: doc, options: options, deckID: c.deckID, card: c, now: now), as: MemoryPrediction.self)
        }
    }
    public func forecast(deckID: UUID, days: Int = 30, now: Date = Date()) throws -> WorkloadForecast {
        let doc = readDocument { $0 }; let options = Self.options(in: doc, deckID: deckID)
        guard options.engine != .legacy else { throw CollectionError.invalidInput("Choose FSRS or RWKV before comparing retention targets.") }
        return try NativeScheduling.call(NativeScheduling.request(op: "simulate", doc: doc, options: options, deckID: deckID, now: now, days: days), as: WorkloadForecast.self)
    }
    public func evaluate(deckID: UUID, timeSeries: Bool = false, now: Date = Date()) throws -> CalibrationResult {
        let doc = readDocument { $0 }; let options = Self.options(in: doc, deckID: deckID)
        guard options.engine != .legacy else { throw CollectionError.invalidInput("Choose a memory model first.") }
        let request = try NativeScheduling.request(op: "evaluate", doc: doc, options: options, deckID: deckID, now: now, timeSeries: timeSeries)
        return try NativeScheduling.call(request, as: CalibrationResult.self)
    }
    public func optimize(deckID: UUID, now: Date = Date()) throws -> [Double] {
        let doc = readDocument { $0 }; let options = Self.options(in: doc, deckID: deckID)
        guard options.engine == .fsrs6 || options.engine == .fsrs7 else { throw CollectionError.invalidInput("Parameter optimization is available for FSRS. RWKV uses its trained model weights.") }
        let request = try NativeScheduling.request(op: "optimize", doc: doc, options: options, deckID: deckID, now: now)
        struct Result: Decodable { var parameters: [Double] }
        return try NativeScheduling.call(request, as: Result.self).parameters
    }
    func advancedSchedule(card: Card, rating: ReviewRating, now: Date, doc: CollectionDocument) throws -> Card? {
        var options = Self.options(in: doc, deckID: card.deckID, card: card, now: now)
        guard options.engine != .legacy else { return nil }
        // Instant ranks with RWKV and deliberately uses FSRS-7 for due dates, as in the fork.
        if options.engine == .rwkvInstant { options.engine = .fsrs7; options.parameters = [] }
        let request = try NativeScheduling.request(op: "predict", doc: doc, options: options, deckID: card.deckID, card: card, now: now)
        let prediction = try NativeScheduling.call(request, as: MemoryPrediction.self)
        guard prediction.intervals.count == 4, let interval = prediction.intervals[rating.rawValue - 1], interval.isFinite, interval >= 0 else { throw CollectionError.invalidInput("The model returned an invalid interval.") }
        var days = min(Double(options.maximumInterval), max(1 / 86400, interval))
        if !options.allowSameDay || ((card.state == .new || card.state == .learning) && options.skipLearning) || ((rating == .again || card.state == .relearning) && options.skipRelearning) { days = max(1, days.rounded()) }
        var next = card; next.intervalDays = days; next.due = now.addingTimeInterval(days * 86400)
        next.reps += 1; if rating == .again && card.state != .new { next.lapses += 1 }
        next.state = days < 1 ? (rating == .again && card.state != .new ? .relearning : .learning) : .review
        next.lastReviewedAt = now
        return next
    }
}

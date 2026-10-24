import Foundation
import CSchedulingEngine

/// A complete, lossless JSON value for the backend's protobuf JSON protocol.
/// Anki IDs remain decimal strings; converting them through Double loses precision.
public enum AnkiValue: Equatable, Codable, Sendable {
    case object([String: AnkiValue]), array([AnkiValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode([String: AnkiValue].self) { self = .object(value) }
        else { self = .array(try c.decode([AnkiValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let value): try c.encode(value); case .array(let value): try c.encode(value)
        case .string(let value): try c.encode(value); case .number(let value): try c.encode(value)
        case .bool(let value): try c.encode(value); case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> AnkiValue { get { if case .object(let o) = self { return o[key] ?? .null }; return .null } set { var o = object; o[key] = newValue; self = .object(o) } }
    public var object: [String: AnkiValue] { if case .object(let o) = self { return o }; return [:] }
    public var array: [AnkiValue] { if case .array(let a) = self { return a }; return [] }
    public var string: String { switch self { case .string(let s): return s; case .number(let n): return n.rounded() == n ? String(format: "%.0f", n) : String(n); default: return "" } }
    public var double: Double { if case .number(let n) = self { return n }; return Double(string) ?? 0 }
    public var int: Int { Int(double) }
    public var bool: Bool { if case .bool(let b) = self { return b }; return false }
}

/// Owns a real Anki backend session. Calls are thread-safe; long operations should run
/// on a worker queue. Abort and progress remain callable while sync/import is running.
public final class AnkiBackend: @unchecked Sendable {
    public let handle: UInt64
    private struct Request: Encodable { var op: String; var handle: UInt64 = 0; var service: String?; var method: String?; var input: AnkiValue = .object([:]) }
    private struct Response: Decodable { var result: AnkiValue?; var error: String? }
    private static func send(_ request: Request) throws -> AnkiValue {
        let text = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        guard let pointer = text.withCString({ anki_backend_request($0) }) else { throw CollectionError.invalidInput("No response from Anki.") }
        defer { scheduling_engine_free(pointer) }
        let response = try JSONDecoder().decode(Response.self, from: Data(String(cString: pointer).utf8))
        if let error = response.error { throw CollectionError.invalidInput(error) }
        return response.result ?? .object([:])
    }
    public init() throws { handle = UInt64(try Self.send(Request(op: "create"))["handle"].double) }
    deinit { _ = try? Self.send(Request(op: "destroy", handle: handle)) }
    @discardableResult public func call(_ service: String, _ method: String, _ input: [String: AnkiValue] = [:]) throws -> AnkiValue {
        try Self.send(Request(op: "call", handle: handle, service: "Backend\(service)Service", method: method, input: .object(input)))
    }
    public func perform(_ operation: String, input: [String: AnkiValue]) throws -> AnkiValue {
        try Self.send(Request(op: operation, handle: handle, input: .object(input)))
    }
    public static func schema(_ name: String) throws -> AnkiValue { try send(Request(op: "schema", input: .object(["name": .string(name)]))) }
    public static func catalog() throws -> AnkiValue { try send(Request(op: "catalog")) }
}

/// Uses Anki's own SQLite schema, IDs, templates, media database and review history.
/// Opening an existing user collection must be done on an explicit imported copy.
public final class AnkiCollection: @unchecked Sendable {
    public let backend: AnkiBackend
    public let directory: URL
    public var collectionURL: URL { directory.appendingPathComponent("collection.anki2") }
    public var mediaURL: URL { directory.appendingPathComponent("collection.media", isDirectory: true) }
    public var mediaDBURL: URL { directory.appendingPathComponent("collection.media.db2") }
    public init(directory: URL) throws {
        self.directory = directory; backend = try AnkiBackend()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaURL, withIntermediateDirectories: true)
        try open()
    }
    deinit { try? close() }
    public func open() throws { try backend.call("Collection", "OpenCollection", ["collectionPath": .string(collectionURL.path), "mediaFolderPath": .string(mediaURL.path), "mediaDbPath": .string(mediaDBURL.path)]) }
    public func close() throws { try backend.call("Collection", "CloseCollection") }
    public func deckTree() throws -> AnkiValue { try backend.call("Decks", "DeckTree", ["now": .string(String(Int64(Date().timeIntervalSince1970)))]) }
    public func decks() throws -> [AnkiValue] { try backend.call("Decks", "GetDeckNames", ["skipEmptyDefault": .bool(false), "includeFiltered": .bool(true)])["entries"].array }
    public func notetypes() throws -> [AnkiValue] { try backend.call("Notetypes", "GetNotetypeNames")["entries"].array }
    public func selectDeck(_ id: String) throws { try backend.call("Decks", "SetCurrentDeck", ["did": .string(id)]) }
    public func queuedCards() throws -> AnkiValue { try backend.call("Scheduler", "GetQueuedCards", ["fetchLimit": .number(1)]) }
    public func getCard(_ id: String) throws -> AnkiValue { try backend.call("Cards", "GetCard", ["cid": .string(id)]) }
    public func getNote(_ id: String) throws -> AnkiValue { try backend.call("Notes", "GetNote", ["nid": .string(id)]) }
    public func notetype(_ id: String) throws -> AnkiValue { try backend.call("Notetypes", "GetNotetype", ["ntid": .string(id)]) }
    public func search(_ query: String) throws -> [String] { try backend.call("Search", "SearchCards", ["search": .string(query)])["ids"].array.map(\.string) }
    public func addNote(notetypeID: String, deckID: String, fields: [String], tags: [String] = []) throws -> String {
        var note = try backend.call("Notes", "NewNote", ["ntid": .string(notetypeID)])
        note["fields"] = .array(fields.map(AnkiValue.string)); note["tags"] = .array(tags.map(AnkiValue.string))
        return try backend.call("Notes", "AddNote", ["note": note, "deckId": .string(deckID)])["noteId"].string
    }
    public func updateNote(_ note: AnkiValue) throws { try backend.call("Notes", "UpdateNotes", ["notes": .array([note])]) }
    public func render(cardID: String) throws -> (question: String, answer: String, css: String) {
        let result = try backend.call("CardRendering", "RenderExistingCard", ["cardId": .string(cardID), "partialRender": .bool(false)])
        func html(_ nodes: AnkiValue) -> String { nodes.array.map { $0["text"].string }.joined() }
        let question = html(result["questionNodes"])
        return (question, html(result["answerNodes"]).replacingOccurrences(of: "{{FrontSide}}", with: question), result["css"].string)
    }
    public func answer(queued: AnkiValue, rating: Int, seconds: Double) throws {
        let names = ["again", "hard", "good", "easy"]
        guard (1...4).contains(rating) else { throw CollectionError.invalidInput("Invalid answer rating.") }
        let states = queued["states"]
        var input: [String: AnkiValue] = ["cardId": queued["card"]["id"], "currentState": states["current"], "newState": states[names[rating - 1]], "rating": .number(Double(rating - 1)), "answeredAtMillis": .string(String(Int64(Date().timeIntervalSince1970 * 1000))), "millisecondsTaken": .number(min(3_600_000, max(0, seconds * 1000).rounded()))]
        let values = queued["rwkvPrediction"]["s90s"].array
        if queued["rwkvPrediction"]["curveEnabled"].bool, values.indices.contains(rating - 1), values[rating - 1].double > 0 { input["rwkvS90"] = values[rating - 1] }
        if queued["rwkvPrediction"]["retrievability"] != .null { input["rwkvRetrievability"] = queued["rwkvPrediction"]["retrievability"] }
        if queued["rwkvPrediction"]["reviewKind"] != .null { input["rwkvReviewKind"] = queued["rwkvPrediction"]["reviewKind"] }
        try backend.call("Scheduler", "AnswerCard", input)
    }
    public func undo() throws { try backend.call("Collection", "Undo") }
    public func exportCollection(to url: URL, includeMedia: Bool = true) throws {
        let result = Result { try backend.call("ImportExport", "ExportCollectionPackage", ["outPath": .string(url.path), "includeMedia": .bool(includeMedia), "legacy": .bool(false)]) }
        try open() // Anki closes the collection while exporting, even if export fails.
        _ = try result.get()
    }
}

extension AnkiCollection {
    /// Imports into a newly created profile. Existing profiles are never replaced.
    public static func importFile(_ source: URL, intoNewDirectory destination: URL) throws -> AnkiCollection {
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw CollectionError.invalidInput("Choose a new profile directory for import.") }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            if source.pathExtension.lowercased() == "colpkg" {
                let importer = try AnkiBackend()
                try importer.call("ImportExport", "ImportCollectionPackage", ["colPath": .string(destination.appendingPathComponent("collection.anki2").path), "backupPath": .string(source.path), "mediaFolder": .string(destination.appendingPathComponent("collection.media").path), "mediaDb": .string(destination.appendingPathComponent("collection.media.db2").path)])
            } else if source.pathExtension.lowercased() != "apkg" {
                try FileManager.default.copyItem(at: source, to: destination.appendingPathComponent("collection.anki2"))
            }
            let collection = try AnkiCollection(directory: destination)
            if source.pathExtension.lowercased() == "apkg" { try collection.backend.call("ImportExport", "ImportAnkiPackage", ["packagePath": .string(source.path), "options": .object([:])]) }
            // CheckDatabase is a repair operation in Anki: it can normalize
            // fields/tags and rewrite notes. Import must not silently repair.
            return collection
        } catch { try? FileManager.default.removeItem(at: destination); throw error }
    }
    public func login(username: String, password: String, endpoint: String? = nil) throws -> AnkiValue {
        var input: [String: AnkiValue] = ["username": .string(username), "password": .string(password)]
        if let endpoint { input["endpoint"] = .string(endpoint) }
        return try backend.call("Sync", "SyncLogin", input)
    }
    public func sync(auth: AnkiValue) throws -> AnkiValue { try backend.call("Sync", "SyncCollection", ["auth": auth, "syncMedia": .bool(true)]) }
    public func fullSync(auth: AnkiValue, upload: Bool, serverUSN: AnkiValue? = nil) throws {
        var input: [String: AnkiValue] = ["auth": auth, "upload": .bool(upload)]
        if let serverUSN { input["serverUsn"] = serverUSN }
        try backend.call("Sync", "FullUploadOrDownload", input)
    }
}

extension AnkiCollection {
    public func prepareReview(deckID: String, model: String = "sm56", precision: String = "cards_int4_notes_int8") throws -> AnkiValue {
        try selectDeck(deckID)
        let configs = try backend.call("DeckConfig", "GetDeckConfigsForUpdate", ["did": .string(deckID)])
        if !configs["cardStateCustomizer"].string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CollectionError.invalidInput("This collection uses a custom scheduling script that this build cannot run yet. Reviews are paused to preserve your scheduling.")
        }
        let rwkv = configs["allConfig"].array.contains { $0["config"]["config"]["rwkvReviewEnabled"].bool || $0["config"]["config"]["rwkvReviewInstantOrderEnabled"].bool }
        var predictions: AnkiValue = .object([:])
        var preparedQueue: AnkiValue?
        if rwkv {
            guard let path = Bundle.module.url(forResource: model, withExtension: "bin", subdirectory: "RWKV")?.path else { throw CollectionError.invalidInput("RWKV model weights are unavailable.") }
            var dynamicReplay = configs["allConfig"].array.contains { entry in
                let config = entry["config"]["config"]
                return (config["rwkvReviewEnabled"].bool || config["rwkvReviewInstantOrderEnabled"].bool) && config["rwkvReviewDynamicPresetReplay"].bool
            }
            if let encoded = try? backend.call("Config", "GetConfigJson", ["val": .string("rwkvDynamicPresetReplay")])["json"].string,
               let data = Data(base64Encoded: encoded), let setting = try? JSONDecoder().decode(Bool.self, from: data) { dynamicReplay = setting }
            let prepared = try backend.perform("rwkv_prepare", input: ["deckId": .string(deckID), "model": .string(model), "path": .string(path), "precision": .string(precision), "dynamicPresetReplay": .bool(dynamicReplay)])
            predictions = prepared["predictions"]; preparedQueue = prepared["queue"]
        }
        var queue = try preparedQueue ?? queuedCards()
        var cards = queue["cards"].array
        for index in cards.indices {
            let card = cards[index]["card"], prediction = predictions[card["id"].string]
            let deck = try backend.call("Decks", "GetDeck", ["did": card["deckId"]])
            let actualDeck = deck["normal"] == .null ? try backend.call("Decks", "GetDeck", ["did": card["originalDeckId"]]) : deck
            let config = try backend.call("DeckConfig", "GetDeckConfig", ["dcid": actualDeck["normal"]["configId"]])["config"]
            guard prediction != .null else {
                if config["rwkvReviewEnabled"].bool { throw CollectionError.invalidInput("RWKV Curve cannot prepare this card’s review context yet. Review it on desktop to preserve your scheduling.") }
                continue
            }
            var metadata = prediction; metadata["curveEnabled"] = .bool(config["rwkvReviewEnabled"].bool)
            cards[index]["rwkvPrediction"] = metadata
            if config["rwkvReviewEnabled"].bool {
                var input: [String: AnkiValue] = ["cardId": card["id"]]
                for (i, name) in ["again", "hard", "good", "easy"].enumerated() where prediction["intervals"].array.indices.contains(i) { input[name] = prediction["intervals"].array[i] }
                cards[index]["states"] = try backend.call("Scheduler", "SchedulingStatesWithIntervals", input)
            }
        }
        queue["cards"] = .array(cards); return queue
    }
}

extension AnkiCollection {
    public func deckConfiguration(_ deckID: String) throws -> (all: AnkiValue, selected: AnkiValue) {
        let value = try backend.call("DeckConfig", "GetDeckConfigsForUpdate", ["did": .string(deckID)])
        guard let config = value["allConfig"].array.first(where: { $0["config"]["id"] == value["currentDeck"]["configId"] })?["config"] else { throw CollectionError.notFound("This deck has no scheduling preset.") }
        return (value, config)
    }
    public func saveDeckConfiguration(_ config: AnkiValue, deckID: String, original: AnkiValue) throws {
        let shared = ["cardStateCustomizer", "newCardsIgnoreReviewLimit", "fsrs", "applyAllParentLimits", "fsrsHealthCheck", "loadBalancerEnabled", "fsrsShortTermWithStepsEnabled", "fsrsLearningQueuesDisabled", "reviewFuzzEnabled", "reviewFuzzBase", "reviewFuzzFactorShort", "reviewFuzzFactorMid", "reviewFuzzFactorLong"]
        var input = original.object.filter { shared.contains($0.key) }
        input["targetDeckId"] = .string(deckID); input["configs"] = .array([config]); input["limits"] = original["currentDeck"]["limits"]
        try backend.call("DeckConfig", "UpdateDeckConfigs", input)
    }
}

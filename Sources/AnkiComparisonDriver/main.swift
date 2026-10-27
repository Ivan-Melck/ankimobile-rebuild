import Foundation
import FlashcardsCore

guard ProcessInfo.processInfo.environment["ANKI_COMPARISON_ISOLATED"] == "1" else {
    FileHandle.standardError.write(Data("Run through tools/comparison/run.py: audited namespace isolation is required.\n".utf8))
    exit(EXIT_FAILURE)
}

// JSON-lines transport around the shipping Swift collection API. Scheduling
// decisions are never reimplemented here. The orchestrator supplies only copies.
var collection: AnkiCollection?
var current: AnkiValue?
func requireCollection() throws -> AnkiCollection {
    guard let collection else { throw CollectionError.invalidInput("Open a comparison copy first.") }
    return collection
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
while let line = readLine() {
    do {
        let request = try JSONDecoder().decode(AnkiValue.self, from: Data(line.utf8))
        let result: AnkiValue
        switch request["op"].string {
        case "clock":
            result = .string(String(Int64((Date().timeIntervalSince1970 * 1000).rounded())))
        case "open":
            collection = try AnkiCollection(directory: URL(fileURLWithPath: request["directory"].string))
            current = nil; result = .object([:])
        case "close":
            try collection?.close(); collection = nil; current = nil; result = .object([:])
        case "prepare":
            guard let collection else { throw CollectionError.invalidInput("Open a comparison copy first.") }
            result = try collection.prepareReview(deckID: request["deckId"].string, model: request["model"].string, precision: request["precision"].string)
            current = result["cards"].array.first
        case "answer":
            guard let collection, let current else { throw CollectionError.invalidInput("Prepare a card first.") }
            try collection.answer(queued: current, rating: request["rating"].int, seconds: request["seconds"].double)
            result = .object([:])
        case "undo":
            try collection?.undo(); current = nil; result = .object([:])
        case "redo":
            result = try requireCollection().backend.call("Collection", "Redo"); current = nil
        case "call":
            result = try requireCollection().backend.call(request["service"].string, request["method"].string, request["input"].object)
        case "inspect":
            result = try requireCollection().backend.perform("comparison_inspect", input: [:])
        case "queue":
            result = try requireCollection().backend.call("Scheduler", "GetQueuedCards", ["fetchLimit": .number(1000)])
        case "queueScores":
            var scores: [String: AnkiValue] = [:]
            for id in request["cards"].array {
                scores[id.string] = try requireCollection().backend.call("Scheduler", "GetRwkvRetrievabilityScore", ["cid":id])["retrievability"]
            }
            result = .object(scores)
        default: throw CollectionError.invalidInput("Unknown comparison operation.")
        }
        print(String(decoding: try encoder.encode(AnkiValue.object(["result": result])), as: UTF8.self))
    } catch {
        let response = AnkiValue.object(["error": .string(String(describing: error))])
        print(String(decoding: try! encoder.encode(response), as: UTF8.self))
    }
    fflush(stdout)
}

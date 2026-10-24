import XCTest
@testable import FlashcardsCore

final class AnkiCompatibilityTests: XCTestCase {
    var directories: [URL] = []
    override func tearDown() { for url in directories { try? FileManager.default.removeItem(at: url) }; directories = [] }
    func directory(_ create: Bool = true) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("anki-compat-\(UUID().uuidString)")
        directories.append(url)
        if create { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return url
    }
    func testBackendCatalogExposesWholePinnedServiceSurface() throws {
        let catalog = try AnkiBackend.catalog()
        let names = catalog["services"].array.map { $0["name"].string }
        XCTAssertTrue(names.contains("BackendSyncService"))
        XCTAssertTrue(names.contains("BackendImportExportService"))
        XCTAssertTrue(names.contains("BackendSchedulerService"))
        XCTAssertGreaterThan(catalog["services"].array.flatMap { $0["methods"].array }.count, 200)
    }
    func testRealCollectionCreateRenderReviewUndoAndReopen() throws {
        let url = try directory(), col = try AnkiCollection(directory: url)
        let types = try col.notetypes(); XCTAssertFalse(types.isEmpty)
        let basic = try XCTUnwrap(types.first { $0["name"].string == "Basic" })
        let nid = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Real Anki front", "Real Anki back"], tags: ["compatibility"])
        XCTAssertFalse(nid.isEmpty)
        let ids = try col.search("tag:compatibility"); XCTAssertEqual(ids.count, 1)
        let rendered = try col.render(cardID: ids[0]); XCTAssertTrue(rendered.question.contains("Real Anki front")); XCTAssertTrue(rendered.answer.contains("Real Anki back"))
        try col.selectDeck("1")
        let queued = try XCTUnwrap(col.queuedCards()["cards"].array.first)
        try col.answer(queued: queued, rating: 4, seconds: 3)
        XCTAssertEqual(try col.getCard(ids[0])["reps"].int, 1)
        try col.undo(); XCTAssertEqual(try col.getCard(ids[0])["reps"].int, 0)
        try col.close(); try col.open()
        XCTAssertEqual(try col.getNote(nid)["tags"].array.map(\.string), ["compatibility"])
        XCTAssertTrue(try col.backend.call("Collection", "CheckDatabase")["problems"].array.isEmpty)
        try col.close()
    }
    func testCollectionPackageRoundTripPreservesIDsHistoryTemplatesAndMedia() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        let nid = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["<img src=\"pixel.svg\">Q", "A"])
        try Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\"/>".utf8).write(to: col.mediaURL.appendingPathComponent("pixel.svg"))
        try col.selectDeck("1")
        let queued = try XCTUnwrap(col.queuedCards()["cards"].array.first)
        try col.answer(queued: queued, rating: 3, seconds: 7)
        let before = try col.getCard(queued["card"]["id"].string)
        let package = col.directory.appendingPathComponent("roundtrip.colpkg")
        try col.exportCollection(to: package)
        XCTAssertEqual(try col.getNote(nid)["id"].string, nid, "Export must reopen the source collection")
        let imported = try AnkiCollection.importFile(package, intoNewDirectory: directory(false))
        let after = try imported.getCard(before["id"].string)
        for field in ["id", "noteId", "deckId", "reps", "lapses", "interval", "due", "customData"] { XCTAssertEqual(before[field], after[field], field) }
        XCTAssertEqual(try col.notetype(basic["id"].string), try imported.notetype(basic["id"].string))
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.mediaURL.appendingPathComponent("pixel.svg").path))
        XCTAssertEqual(try imported.search("").count, 1)
        try col.close(); try imported.close()
    }
    func testUpstreamLegacyPackageFixtureUsesAnkiImporter() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("Vendor/anki/pylib/tests/support/media.apkg")
        let imported = try AnkiCollection.importFile(file, intoNewDirectory: directory(false))
        XCTAssertFalse(try imported.search("").isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: imported.mediaURL.path).isEmpty)
        try imported.close()
    }
    func testFailedImportDoesNotChangeExistingCollection() throws {
        let col = try AnkiCollection(directory: directory())
        let before = try Data(contentsOf: col.collectionURL)
        let invalid = try directory().appendingPathComponent("bad.colpkg"); try Data("invalid".utf8).write(to: invalid)
        let dest = try directory(false)
        XCTAssertThrowsError(try AnkiCollection.importFile(invalid, intoNewDirectory: dest))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertEqual(try Data(contentsOf: col.collectionURL), before)
        try col.close()
    }
    func testTwoClientsSyncThroughForkServer() throws {
        guard let endpoint = ProcessInfo.processInfo.environment["ANKI_SYNC_TEST_ENDPOINT"] else { throw XCTSkip("Run scripts/test-sync.sh to start the isolated fork sync server.") }
        let a = try AnkiCollection(directory: directory()), b = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(a.notetypes().first { $0["name"].string == "Basic" })
        let nid = try a.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Sync \(UUID().uuidString)", "Original"], tags: ["sync-test"])
        let authA = try a.login(username: "compatibility", password: "fixture-password", endpoint: endpoint)
        _ = try a.sync(auth: authA); try a.fullSync(auth: authA, upload: true)
        let authB = try b.login(username: "compatibility", password: "fixture-password", endpoint: endpoint)
        let response = try b.sync(auth: authB)
        try b.fullSync(auth: authB, upload: false, serverUSN: response["serverMediaUsn"])
        XCTAssertEqual(try b.getNote(nid)["fields"].array[1].string, "Original")
        var note = try b.getNote(nid); note["fields"] = .array([note["fields"].array[0], .string("Edited on second client")]); try b.updateNote(note)
        _ = try b.sync(auth: authB); _ = try a.sync(auth: authA)
        XCTAssertEqual(try a.getNote(nid)["fields"].array[1].string, "Edited on second client")
        try a.selectDeck("1"); let queued = try XCTUnwrap(a.queuedCards()["cards"].array.first)
        try a.answer(queued: queued, rating: 4, seconds: 2)
        _ = try a.sync(auth: authA); _ = try b.sync(auth: authB)
        XCTAssertEqual(try b.getCard(queued["card"]["id"].string)["reps"].int, 1)
        XCTAssertFalse(try b.backend.call("Stats", "GetReviewLogs", ["cid": queued["card"]["id"]])["entries"].array.isEmpty)
        try a.close(); try b.close()
    }

    func testImportedRWKVInstantUsesCanonicalHistoryAndSurvivesUndo() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        _ = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["RWKV", "Instant"])
        let settings = try col.deckConfiguration("1")
        var config = settings.selected, algorithm = config["config"], all = settings.all
        algorithm["rwkvReviewInstantOrderEnabled"] = .bool(true); algorithm["rwkvReviewEnabled"] = .bool(false); config["config"] = algorithm; all["fsrs"] = .bool(true)
        try col.saveDeckConfiguration(config, deckID: "1", original: all)
        let queued = try XCTUnwrap(col.prepareReview(deckID: "1")["cards"].array.first)
        XCTAssertNotEqual(queued["rwkvPrediction"], .null)
        XCTAssertFalse(queued["rwkvPrediction"]["curveEnabled"].bool)
        var fallbackOnly = queued; fallbackOnly["rwkvPrediction"] = .null
        try col.answer(queued: fallbackOnly, rating: 3, seconds: 6)
        let fallbackMemory = try col.getCard(queued["card"]["id"].string)["memoryState"]
        try col.undo()
        try col.answer(queued: queued, rating: 3, seconds: 6)
        let answered = try col.getCard(queued["card"]["id"].string)
        XCTAssertEqual(answered["memoryState"], fallbackMemory, "Instant must retain the selected FSRS fallback's stored memory state")
        try col.undo()
        let again = try XCTUnwrap(col.prepareReview(deckID: "1")["cards"].array.first)
        XCTAssertEqual(again["rwkvPrediction"], queued["rwkvPrediction"])
        try col.answer(queued: again, rating: 3, seconds: 6)
        let package = col.directory.appendingPathComponent("rwkv.colpkg"); try col.exportCollection(to: package)
        let imported = try AnkiCollection.importFile(package, intoNewDirectory: directory(false))
        XCTAssertTrue(try imported.deckConfiguration("1").selected["config"]["rwkvReviewInstantOrderEnabled"].bool)
        let history = try imported.backend.call("Scheduler", "RwkvHistoricalReviewInputs", ["history": .object([:])])
        XCTAssertEqual(history["reviews"].array.count, 1)
        XCTAssertEqual(history["reviews"].array[0]["cardId"].string, queued["card"]["id"].string)
        _ = try imported.prepareReview(deckID: "1")
        try col.close(); try imported.close()
    }

    func testRWKVCurveUsesBackendStatesAndPreservesItsMetadata() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        _ = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Curve", "Metadata"])
        let settings = try col.deckConfiguration("1")
        var config = settings.selected, algorithm = config["config"], all = settings.all
        algorithm["rwkvReviewEnabled"] = .bool(true); config["config"] = algorithm; all["fsrs"] = .bool(true)
        try col.saveDeckConfiguration(config, deckID: "1", original: all)
        let queued = try XCTUnwrap(col.prepareReview(deckID: "1")["cards"].array.first)
        XCTAssertTrue(queued["rwkvPrediction"]["curveEnabled"].bool)
        XCTAssertGreaterThan(queued["rwkvPrediction"]["s90s"].array[3].double, 0)
        try col.answer(queued: queued, rating: 4, seconds: 4)
        let logs = try col.backend.call("Stats", "GetReviewLogs", ["cid": queued["card"]["id"]])["entries"].array
        XCTAssertEqual(logs.count, 1)
        let package = col.directory.appendingPathComponent("curve.colpkg"); try col.exportCollection(to: package)
        let imported = try AnkiCollection.importFile(package, intoNewDirectory: directory(false))
        XCTAssertEqual(try imported.backend.call("Stats", "GetReviewLogs", ["cid": queued["card"]["id"]])["entries"], .array(logs))
        try col.close(); try imported.close()
    }
    func testConfigSavePreservesEveryUneditedField() throws {
        let col = try AnkiCollection(directory: directory())
        let settings = try col.deckConfiguration("1")
        var config = settings.selected, fields = config["config"]
        fields["desiredRetention"] = .number(0.95); config["config"] = fields
        try col.saveDeckConfiguration(config, deckID: "1", original: settings.all)
        let after = try col.deckConfiguration("1")
        for (key, value) in settings.selected["config"].object where key != "desiredRetention" { XCTAssertEqual(after.selected["config"][key], value, key) }
        XCTAssertEqual(after.selected["config"]["desiredRetention"].double, 0.95, accuracy: 0.0001)
        XCTAssertGreaterThan(try AnkiBackend.schema("anki.deck_config.DeckConfig.Config")["fields"].array.count, 70)
        try col.close()
    }

    func testPrivateCollectionCopyRoundTrip() throws {
        guard let path = ProcessInfo.processInfo.environment["ANKI_COMPAT_COLLECTION_DIR"] else {
            throw XCTSkip("Optional private fixture: use scripts/snapshot-anki.py, then set ANKI_COMPAT_COLLECTION_DIR.")
        }
        // The backend only opens a disposable second copy, never the supplied fixture.
        let original = URL(fileURLWithPath: path), working = try directory(false)
        try FileManager.default.copyItem(at: original, to: working)
        let col = try AnkiCollection(directory: working)
        let ids = try col.search("")
        XCTAssertFalse(ids.isEmpty)
        let types = try col.notetypes(), decks = try col.decks()
        var cards: [String: AnkiValue] = [:], notes: [String: AnkiValue] = [:]
        var renderedKinds = Set<String>()
        for id in ids {
            let card = try col.getCard(id); cards[id] = card
            let nid = card["noteId"].string
            if notes[nid] == nil { notes[nid] = try col.getNote(nid) }
            let kind = notes[nid]!["notetypeId"].string + ":" + card["templateIdx"].string
            if renderedKinds.insert(kind).inserted { _ = try col.render(cardID: id) }
        }
        let history = try col.backend.call("Scheduler", "RwkvHistoricalReviewInputs", ["history": .object([:])])
        let package = working.appendingPathComponent("private-roundtrip.colpkg")
        try col.exportCollection(to: package)
        let imported = try AnkiCollection.importFile(package, intoNewDirectory: directory(false))
        XCTAssertTrue(try imported.search("") == ids, "Private collection card IDs changed")
        XCTAssertTrue(try imported.notetypes() == types, "Private collection note types changed")
        XCTAssertTrue(try imported.decks() == decks, "Private collection decks changed")
        for (id, expected) in cards { XCTAssertTrue(try imported.getCard(id) == expected, "A private card changed during round trip") }
        var changedNoteFields: [String: Int] = [:]
        for (id, expected) in notes {
            let actual = try imported.getNote(id)
            for key in Set(expected.object.keys).union(actual.object.keys) where expected[key] != actual[key] { changedNoteFields[key, default: 0] += 1 }
        }
        XCTAssertTrue(changedNoteFields.isEmpty, "Private note differences by protobuf field: \(changedNoteFields)")
        let replay = try imported.backend.call("Scheduler", "RwkvHistoricalReviewInputs", ["history": .object([:])])
        XCTAssertTrue(replay["reviews"] == history["reviews"], "Private canonical RWKV history changed")
        for type in types {
            XCTAssertTrue(try imported.notetype(type["id"].string) == col.notetype(type["id"].string), "A private template changed")
        }
        let media = try FileManager.default.contentsOfDirectory(atPath: col.mediaURL.path).sorted()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: imported.mediaURL.path).sorted() == media, "Private media filenames changed")
        for name in media {
            XCTAssertTrue(try Data(contentsOf: col.mediaURL.appendingPathComponent(name)) == Data(contentsOf: imported.mediaURL.appendingPathComponent(name)), "A private media file changed")
        }
        // Aggregate counts only; no private fields, deck names or templates in logs.
        print("Private compatibility: \(cards.count) cards, \(notes.count) notes, \(types.count) note types, \(decks.count) decks, \(media.count) media files, \(history["reviews"].array.count) canonical history rows.")
        try col.close(); try imported.close()
    }

}

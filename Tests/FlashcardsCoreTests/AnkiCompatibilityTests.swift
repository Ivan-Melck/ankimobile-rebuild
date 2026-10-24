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
    func testTypedAnswersUseRealTemplateMarkersAndBackendComparison() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        var type = try col.notetype(basic["id"].string), templates = type["templates"].array, template = templates[0], config = template["config"]
        config["qFormat"] = .string("{{Front}}<br>{{type:Back}}")
        config["aFormat"] = .string("{{FrontSide}}<hr id=answer>{{type:Back}}")
        template["config"] = config; templates[0] = template; type["templates"] = .array(templates)
        try col.backend.call("Notetypes", "UpdateNotetype", type.object)
        let nid = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Capital of France", "<b>Paris</b>"])
        let cid = try XCTUnwrap(col.search("nid:\(nid)").first), rendered = try col.render(cardID: cid)
        let answer = try XCTUnwrap(col.typedAnswer(cardID: cid, question: rendered.question))
        XCTAssertTrue(answer.questionHTML(rendered.question).contains("id=\"typeans\""))
        XCTAssertFalse(answer.questionHTML(rendered.question).contains("[[type:"))
        let comparison = try col.compareTypedAnswer(answer, provided: "Paris")
        XCTAssertTrue(comparison.contains("typeGood"))
        XCTAssertFalse(answer.replacingMarkers(in: rendered.answer, with: comparison).contains("[[type:"))
        let escaped = try col.compareTypedAnswer(answer, provided: "<script>alert(1)</script>")
        XCTAssertFalse(escaped.contains("<script>"))
        try col.close()
    }
    func testTypedClozeExtractsOnlyTheCurrentOrdinal() throws {
        let col = try AnkiCollection(directory: directory())
        let cloze = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Cloze" })
        let nid = try col.addNote(notetypeID: cloze["id"].string, deckID: "1", fields: ["{{c1::one}} and {{c2::two}}", ""])
        let cards = try col.search("nid:\(nid)")
        XCTAssertEqual(cards.count, 2)
        for cid in cards {
            let card = try col.getCard(cid)
            let typed = try XCTUnwrap(col.typedAnswer(cardID: cid, question: "[[type:cloze:Text]]"))
            XCTAssertEqual(typed.expected, card["templateIdx"].int == 0 ? "one" : "two")
        }
        try col.close()
    }
    func testFrontSideKeepsQuestionAudioSeparateFromAnswerAudio() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        let nid = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Question [sound:front.wav]", "Answer [sound:back.wav]"])
        let rendered = try col.render(cardID: XCTUnwrap(col.search("nid:\(nid)").first))
        XCTAssertEqual(rendered.questionAVTags.map { $0["soundOrVideo"].string }, ["front.wav"])
        XCTAssertEqual(rendered.answerAVTags.map { $0["soundOrVideo"].string }, ["back.wav"])
        XCTAssertTrue(rendered.answer.contains("[anki:play:q:0]")); XCTAssertTrue(rendered.answer.contains("[anki:play:a:0]"))
        XCTAssertFalse(rendered.answer.contains("[sound:"))
        try col.close()
    }
    func testUnknownDesktopTemplateFilterPausesInsteadOfDroppingItsBehavior() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        var type = try col.notetype(basic["id"].string), templates = type["templates"].array, template = templates[0], config = template["config"]
        config["qFormat"] = .string("{{desktop_plugin_filter:Front}}")
        template["config"] = config; templates[0] = template; type["templates"] = .array(templates)
        try col.backend.call("Notetypes", "UpdateNotetype", type.object)
        let nid = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Plugin", "Answer"])
        let cid = try XCTUnwrap(col.search("nid:\(nid)").first), before = try col.getCard(cid)
        XCTAssertThrowsError(try col.render(cardID: cid))
        XCTAssertEqual(try col.getCard(cid), before)
        try col.close()
    }
    func testCachedLatexUsesAnkisMediaFilenames() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        let nid = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["[latex]x^2+1[/latex]", "Cached image"])
        let rendered = try col.render(cardID: XCTUnwrap(col.search("nid:\(nid)").first))
        XCTAssertTrue(rendered.question.contains("<img")); XCTAssertTrue(rendered.question.contains("latex-"))
        XCTAssertFalse(rendered.question.contains("[latex]"))
        try col.close()
    }
    func testStockImageOcclusionRendersShapeDataOnBothSides() throws {
        let col = try AnkiCollection(directory: directory())
        try col.backend.call("ImageOcclusion", "AddImageOcclusionNotetype")
        let named = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Image Occlusion" })
        let type = try col.notetype(named["id"].string)
        let indexes = try col.backend.call("ImageOcclusion", "GetImageOcclusionFields", ["notetypeId": named["id"]])["fields"]
        var fields = Array(repeating: "", count: type["fields"].array.count)
        fields[indexes["occlusions"].int] = "{{c1::image-occlusion:rect:left=.2:top=.2:width=.5:height=.5}}"
        fields[indexes["image"].int] = "<img src=\"synthetic.svg\">"
        let nid = try col.addNote(notetypeID: named["id"].string, deckID: "1", fields: fields)
        let rendered = try col.render(cardID: XCTUnwrap(col.search("nid:\(nid)").first))
        XCTAssertTrue(rendered.question.contains("data-shape=\"rect\""))
        XCTAssertTrue(rendered.question.contains("anki.imageOcclusion.setup"))
        XCTAssertTrue(rendered.answer.contains("cloze-highlight"))
        try col.close()
    }
    func testCustomizedImageOcclusionTemplateRetainsImageAndCallback() throws {
        let col = try AnkiCollection(directory: directory())
        try col.backend.call("ImageOcclusion", "AddImageOcclusionNotetype")
        let named = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Image Occlusion" })
        var type = try col.notetype(named["id"].string), templates = type["templates"].array
        let callback = #"anki.imageOcclusion.setup({onDidDrawShapes:(data,ctx)=>{const c=ctx.canvas;const alpha=ctx.getImageData(Math.floor(c.width*.35),Math.floor(c.height*.35),1,1).data[3];document.getElementById('io-status').append(data.activeShapes.length?(alpha?'Mask ready':'Mask missing'):'Answer masks ready')}});"#
        for i in templates.indices {
            var template = templates[i], config = template["config"]
            for key in ["qFormat", "aFormat"] { config[key] = .string(config[key].string.replacingOccurrences(of: "anki.imageOcclusion.setup();", with: callback)) }
            template["config"] = config; templates[i] = template
        }
        type["templates"] = .array(templates); try col.backend.call("Notetypes", "UpdateNotetype", type.object)
        let indexes = try col.backend.call("ImageOcclusion", "GetImageOcclusionFields", ["notetypeId": named["id"]])["fields"]
        var fields = Array(repeating: "", count: type["fields"].array.count)
        fields[indexes["occlusions"].int] = "{{c1::image-occlusion:rect:left=.2:top=.2:width=.5:height=.5}}"
        fields[indexes["image"].int] = "<img src=\"fixture.svg\">"
        fields[indexes["header"].int] = "<div id=\"io-status\"></div>"
        let nid = try col.addNote(notetypeID: named["id"].string, deckID: "1", fields: fields)
        let rendered = try col.render(cardID: XCTUnwrap(col.search("nid:\(nid)").first))
        XCTAssertTrue(rendered.question.contains("fixture.svg"))
        XCTAssertTrue(rendered.question.contains("id=\"io-status\""))
        XCTAssertTrue(rendered.question.contains("onDidDrawShapes"))
        try col.close()
    }
    private func filteredDeck(_ collection: AnkiCollection, noteID: String) throws -> String {
        var filtered = try collection.backend.call("Decks", "GetOrCreateFilteredDeck", ["did": .string("0")])
        filtered["name"] = .string("Synthetic filtered deck")
        var config = filtered["config"]; config["reschedule"] = .bool(true)
        config["searchTerms"] = .array([.object(["search": .string("nid:\(noteID)"), "limit": .number(10)])]); filtered["config"] = config
        return try collection.backend.call("Decks", "AddOrUpdateFilteredDeck", filtered.object)["id"].string
    }
    func testStandardFilteredDeckReviewUsesOriginalPresetAndUndo() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        let nid = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Filtered", "Original preset"])
        let deck = try filteredDeck(col, noteID: nid)
        let queued = try XCTUnwrap(col.prepareReview(deckID: deck)["cards"].array.first)
        XCTAssertNotEqual(queued["states"]["current"]["filtered"], .null)
        try col.answer(queued: queued, rating: 4, seconds: 3)
        XCTAssertEqual(try col.getCard(queued["card"]["id"].string)["reps"].int, 1)
        try col.undo(); XCTAssertEqual(try col.getCard(queued["card"]["id"].string)["deckId"].string, deck)
        try col.close()
    }
    func testRWKVFilteredContextPausesBeforeChangingReviewHistory() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        let nid = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Filtered RWKV", "Pending parity"])
        let settings = try col.deckConfiguration("1")
        var config = settings.selected, algorithm = config["config"]
        algorithm["rwkvReviewInstantOrderEnabled"] = .bool(true); config["config"] = algorithm
        try col.saveDeckConfiguration(config, deckID: "1", original: settings.all)
        let deck = try filteredDeck(col, noteID: nid), cid = try XCTUnwrap(col.search("nid:\(nid)").first)
        let before = try col.getCard(cid)
        XCTAssertThrowsError(try col.prepareReview(deckID: deck))
        XCTAssertEqual(try col.getCard(cid), before)
        XCTAssertTrue(try col.backend.call("Stats", "GetReviewLogs", ["cid": .string(cid)])["entries"].array.isEmpty)
        try col.close()
    }
    func testRealCollectionCreateRenderReviewUndoAndReopen() throws {
        let url = try directory(), col = try AnkiCollection(directory: url)
        let types = try col.notetypes(); XCTAssertFalse(types.isEmpty)
        let basic = try XCTUnwrap(types.first { $0["name"].string == "Basic" })
        let nid = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Real Anki front", "Real Anki back"], tags: ["compatibility"])
        XCTAssertFalse(nid.isEmpty)
        let ids = try col.search("tag:compatibility"); XCTAssertEqual(ids.count, 1)
        let rendered = try col.render(cardID: ids[0]); XCTAssertTrue(rendered.question.contains("Real Anki front")); XCTAssertTrue(rendered.answer.contains("Real Anki back"))
        let av = try col.backend.call("CardRendering", "ExtractAvTags", ["text": .string(rendered.question), "questionSide": .bool(true)])
        XCTAssertTrue(av["text"].string.contains("Real Anki front"))
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
        let media = Data("Synthetic sync media \(UUID().uuidString)".utf8)
        try media.write(to: a.mediaURL.appendingPathComponent("sync-fixture.txt"))
        let authA = try a.login(username: "compatibility", password: "fixture-password", endpoint: endpoint)
        let initial = try a.sync(auth: authA)
        try a.fullSync(auth: authA, upload: true, serverUSN: .number(Double(initial["serverMediaUsn"].int)))
        try finishMedia(a)
        let authB = try b.login(username: "compatibility", password: "fixture-password", endpoint: endpoint)
        let response = try b.sync(auth: authB)
        try b.fullSync(auth: authB, upload: false, serverUSN: .number(Double(response["serverMediaUsn"].int)))
        try finishMedia(b)
        XCTAssertEqual(try b.getNote(nid)["fields"].array[1].string, "Original")
        XCTAssertEqual(try Data(contentsOf: b.mediaURL.appendingPathComponent("sync-fixture.txt")), media)
        var note = try b.getNote(nid); note["fields"] = .array([note["fields"].array[0], .string("Edited on second client")]); try b.updateNote(note)
        _ = try b.sync(auth: authB); _ = try a.sync(auth: authA)
        XCTAssertEqual(try a.getNote(nid)["fields"].array[1].string, "Edited on second client")
        try a.selectDeck("1"); let queued = try XCTUnwrap(a.queuedCards()["cards"].array.first)
        try a.answer(queued: queued, rating: 4, seconds: 2)
        _ = try a.sync(auth: authA); _ = try b.sync(auth: authB)
        XCTAssertEqual(try b.getCard(queued["card"]["id"].string)["reps"].int, 1)
        XCTAssertFalse(try b.backend.call("Stats", "GetReviewLogs", ["cid": queued["card"]["id"]])["entries"].array.isEmpty)
        try finishMedia(a); try finishMedia(b)
        var noteA = try a.getNote(nid), noteB = try b.getNote(nid)
        noteA["fields"] = .array([noteA["fields"].array[0], .string("Conflict A")])
        noteB["fields"] = .array([noteB["fields"].array[0], .string("Conflict B")])
        try a.updateNote(noteA)
        // Anki resolves note conflicts with second-resolution modification
        // times. Give the later offline edit a distinct timestamp.
        let previousSecond = Int(Date().timeIntervalSince1970)
        while Int(Date().timeIntervalSince1970) == previousSecond { Thread.sleep(forTimeInterval: 0.01) }
        try b.updateNote(noteB)
        _ = try a.sync(auth: authA); _ = try b.sync(auth: authB); _ = try a.sync(auth: authA)
        XCTAssertEqual(try a.getNote(nid)["fields"], try b.getNote(nid)["fields"], "Both clients must converge after a conflicting edit")
        try b.backend.call("Notes", "RemoveNotes", ["noteIds": .array([.string(nid)])])
        _ = try b.sync(auth: authB); _ = try a.sync(auth: authA)
        XCTAssertThrowsError(try a.getNote(nid))
        try finishMedia(a); try finishMedia(b)
        try a.close(); try b.close()
    }
    private func finishMedia(_ collection: AnkiCollection) throws {
        let deadline = Date().addingTimeInterval(15)
        while try collection.backend.call("Sync", "MediaSyncStatus")["active"].bool {
            guard Date() < deadline else { XCTFail("Local fixture media sync timed out"); return }
            Thread.sleep(forTimeInterval: 0.01)
        }
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

    func testUnsupportedSchedulingScriptPausesBeforeAnyReviewWrites() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        let nid = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Custom", "Scheduling"])
        let cid = try XCTUnwrap(col.search("nid:\(nid)").first), before = try col.getCard(cid)
        let settings = try col.deckConfiguration("1")
        var all = settings.all; all["cardStateCustomizer"] = .string("customData.good.example = 1;")
        try col.saveDeckConfiguration(settings.selected, deckID: "1", original: all)
        XCTAssertThrowsError(try col.prepareReview(deckID: "1"))
        XCTAssertEqual(try col.getCard(cid), before)
        XCTAssertTrue(try col.backend.call("Stats", "GetReviewLogs", ["cid": .string(cid)])["entries"].array.isEmpty)
        try col.close()
    }

    func testRWKVUsesSyntheticSameDayKindAfterGraduatingFromLearning() throws {
        let col = try AnkiCollection(directory: directory())
        let basic = try XCTUnwrap(col.notetypes().first { $0["name"].string == "Basic" })
        _ = try col.addNote(notetypeID: basic["id"].string, deckID: "1", fields: ["Synthetic", "Context"])
        let settings = try col.deckConfiguration("1")
        var config = settings.selected, algorithm = config["config"], all = settings.all
        algorithm["rwkvReviewInstantOrderEnabled"] = .bool(true); algorithm["rwkvReviewMinimumReviewsPerDay"] = .number(2); algorithm["rwkvReviewMinInterveningReviews"] = .number(0); algorithm["rwkvReviewMinElapsedSecs"] = .number(0); config["config"] = algorithm; all["fsrs"] = .bool(true); all["fsrsShortTermWithStepsEnabled"] = .bool(true)
        try col.saveDeckConfiguration(config, deckID: "1", original: all)
        let queued = try XCTUnwrap(col.prepareReview(deckID: "1")["cards"].array.first)
        try col.answer(queued: queued, rating: 4, seconds: 3)
        let next = try XCTUnwrap(col.prepareReview(deckID: "1")["cards"].array.first)
        XCTAssertEqual(next["rwkvPrediction"]["reviewKind"].int, 3)
        XCTAssertEqual(next["rwkvPrediction"]["queueReviewKind"].int, 1)
        try col.close()
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

    func testPrivateCanonicalHistoryCanWarmRWKVInstant() throws {
        guard let path = ProcessInfo.processInfo.environment["ANKI_COMPAT_COLLECTION_DIR"] else { throw XCTSkip("Optional private snapshot fixture.") }
        let working = try directory(), source = URL(fileURLWithPath: path).appendingPathComponent("collection.anki2")
        try FileManager.default.copyItem(at: source, to: working.appendingPathComponent("collection.anki2"))
        let col = try AnkiCollection(directory: working)
        let tree = try col.deckTree()
        let deckID = tree["children"].array.max { $0["totalIncludingChildren"].int < $1["totalIncludingChildren"].int }?["deckId"].string ?? "1"
        let ntid = try XCTUnwrap(col.notetypes().first?["id"].string), type = try col.notetype(ntid)
        var fields = Array(repeating: "Private replay smoke fixture", count: type["fields"].array.count)
        fields[0] = "{{c1::Private replay smoke fixture}}"
        let nid = try col.addNote(notetypeID: ntid, deckID: deckID, fields: fields)
        let cid = try XCTUnwrap(col.search("nid:\(nid)").first)
        let settings = try col.deckConfiguration(deckID)
        var config = settings.selected, algorithm = config["config"], all = settings.all
        algorithm["rwkvReviewInstantOrderEnabled"] = .bool(true); algorithm["rwkvReviewEnabled"] = .bool(false); config["config"] = algorithm; all["fsrs"] = .bool(true)
        try col.saveDeckConfiguration(config, deckID: deckID, original: all)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let weights = root.appendingPathComponent("Sources/FlashcardsCore/Resources/RWKV/sm56.bin")
        let start = Date()
        let response = try col.backend.perform("rwkv_prepare", input: ["deckId": .string(deckID), "model": .string("sm56"), "path": .string(weights.path), "precision": .string("cards_int4_notes_int8")])
        let prediction = response["predictions"][cid]
        XCTAssertNotEqual(prediction, .null)
        XCTAssertTrue((0...1).contains(prediction["retrievability"].double))
        XCTAssertTrue(prediction["intervals"].array.allSatisfy { $0.double.isFinite && $0.double > 0 })
        print("Private canonical RWKV warmup and \(response["predictions"].object.count) candidate predictions completed in \(Date().timeIntervalSince(start)) seconds.")
        try col.close()
    }

}

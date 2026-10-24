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
}

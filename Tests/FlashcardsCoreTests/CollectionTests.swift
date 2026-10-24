import XCTest
@testable import FlashcardsCore

final class CollectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func store() throws -> CollectionStore {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return try CollectionStore(calendar: calendar)
    }
    func testBasicReversedAndClozeGenerateExpectedCards() throws {
        let s = try store()
        _ = try s.addNote(deckID: s.defaultDeckID, front: "one", back: "two")
        _ = try s.addNote(deckID: s.defaultDeckID, front: "three", back: "four", kind: .basicAndReversed)
        let cloze = try s.addNote(deckID: s.defaultDeckID, front: "{{c1::Paris}} is in {{c2::France::country}}. {{c1::Seine}}", back: "Extra", kind: .cloze)
        XCTAssertEqual(s.cards.count, 5)
        let cards = s.search("").filter { $0.note.id == cloze.id }
        XCTAssertEqual(cards.map(\.card.templateIndex), [0, 1])
        XCTAssertEqual(cards[1].questionHTML, "Paris is in <span class=\"cloze\">[country]</span>. Seine")
        XCTAssertTrue(cards[0].answerHTML.contains("Extra"))
    }
    func testInvalidNoteDoesNotPartiallyMutateCollection() throws {
        let s = try store(), before = try store().notes.count
        XCTAssertThrowsError(try s.addNote(deckID: s.defaultDeckID, front: "plain", back: "", kind: .cloze))
        XCTAssertThrowsError(try s.addNote(deckID: UUID(), front: "hello", back: ""))
        XCTAssertEqual(s.notes.count, before); XCTAssertTrue(s.cards.isEmpty)
    }
    func testTemplateChangesPreserveSurvivorsAndResetClozeTransition() throws {
        let s = try store()
        let note = try s.addNote(deckID: s.defaultDeckID, front: "front", back: "back")
        let forward = s.cards[0]
        _ = try s.answer(cardID: forward.id, rating: .easy, now: now)
        _ = try s.updateNote(id: note.id, front: "front", back: "back", kind: .basicAndReversed)
        XCTAssertEqual(s.cards.count, 2)
        XCTAssertEqual(s.cards.first { $0.id == forward.id }?.reps, 1)
        _ = try s.updateNote(id: note.id, front: "{{c1::front}}", back: "back", kind: .cloze)
        XCTAssertEqual(s.cards.count, 1); XCTAssertNotEqual(s.cards[0].id, forward.id)
        XCTAssertEqual(s.cards[0].state, .new)
    }
    func testAnswerAndUndoRestoreExactCardAndHistory() throws {
        let s = try store()
        _ = try s.addNote(deckID: s.defaultDeckID, front: "front", back: "back")
        let original = s.cards[0]
        _ = try s.answer(cardID: original.id, rating: .easy, now: now, durationSeconds: 3)
        XCTAssertEqual(s.cards[0].state, .review)
        XCTAssertEqual(s.cards[0].due, now.addingTimeInterval(4 * 86400))
        XCTAssertEqual(s.statistics(now: now).reviewsToday, 1)
        XCTAssertEqual(s.statistics(now: now).reviewSecondsToday, 3)
        XCTAssertTrue(s.canUndo)
        try s.undoLastReview()
        XCTAssertEqual(s.cards[0], original); XCTAssertTrue(s.reviewLogs.isEmpty)
        XCTAssertThrowsError(try s.undoLastReview())
    }
    func testLearningStepsAndRelearning() throws {
        let scheduler = ApproximateLocalScheduler()
        var card = Card(noteID: UUID(), deckID: UUID())
        card = scheduler.schedule(card: card, rating: .good, at: now)
        XCTAssertEqual(card.state, .learning); XCTAssertEqual(card.due, now.addingTimeInterval(600))
        card = scheduler.schedule(card: card, rating: .good, at: card.due)
        XCTAssertEqual(card.state, .review); XCTAssertEqual(card.intervalDays, 1)
        card = scheduler.schedule(card: card, rating: .again, at: card.due)
        XCTAssertEqual(card.state, .relearning); XCTAssertEqual(card.lapses, 1)
        XCTAssertEqual(card.intervalDays, 1)
        card = scheduler.schedule(card: card, rating: .good, at: card.due)
        XCTAssertEqual(card.state, .review); XCTAssertEqual(card.intervalDays, 1)
    }
    func testDailyLimitsAndNextDayRollover() throws {
        let s = try store()
        try s.updateDeckOptions(id: s.defaultDeckID, options: .init(newCardsPerDay: 1, reviewCardsPerDay: 1))
        _ = try s.addNote(deckID: s.defaultDeckID, front: "one", back: "")
        _ = try s.addNote(deckID: s.defaultDeckID, front: "two", back: "")
        XCTAssertEqual(s.studyQueue(now: now).count, 1)
        let first = s.studyQueue(now: now)[0]
        _ = try s.answer(cardID: first.id, rating: .good, now: now)
        XCTAssertTrue(s.studyQueue(now: now).isEmpty)
        XCTAssertEqual(s.studyQueue(now: now.addingTimeInterval(600)).first?.id, first.id)
        _ = try s.answer(cardID: first.id, rating: .good, now: now.addingTimeInterval(600))
        XCTAssertEqual(s.studyQueue(now: now.addingTimeInterval(86400)).filter { $0.card.state == .new }.count, 1)
    }
    func testSuspendBuryMoveAndDeleteDeck() throws {
        let s = try store(); let deck = try s.createDeck(name: "French")
        _ = try s.addNote(deckID: deck.id, front: "one", back: "")
        let id = s.cards[0].id
        try s.setSuspended(cardID: id, suspended: true)
        XCTAssertTrue(s.studyQueue(now: now).isEmpty)
        XCTAssertThrowsError(try s.answer(cardID: id, rating: .easy, now: now))
        try s.setSuspended(cardID: id, suspended: false)
        try s.bury(cardID: id, until: now.addingTimeInterval(60))
        XCTAssertTrue(s.studyQueue(now: now).isEmpty)
        XCTAssertEqual(s.studyQueue(now: now.addingTimeInterval(60)).count, 1)
        try s.deleteDeck(id: deck.id)
        XCTAssertEqual(s.cards[0].deckID, s.defaultDeckID)
        XCTAssertThrowsError(try s.deleteDeck(id: s.defaultDeckID))
    }
    func testSearchQuotedDeckTagsNegationAndStates() throws {
        let s = try store(); let deck = try s.createDeck(name: "French Verbs")
        _ = try s.addNote(deckID: deck.id, front: "Étudier", back: "study", tags: ["verbs::regular"])
        let card = s.cards[0]
        XCTAssertEqual(s.search("deck:\"French Verbs\" tag:verbs etudier is:new").count, 1)
        XCTAssertTrue(s.search("deck:Default").isEmpty)
        try s.setSuspended(cardID: card.id, suspended: true)
        XCTAssertTrue(s.search("-is:suspended").isEmpty)
        XCTAssertEqual(s.search("is:suspended").count, 1)
        try s.setFlag(cardID: card.id, flag: 3)
        XCTAssertEqual(s.search("flag:3").count, 1)
        XCTAssertTrue(s.search("is:due", now: now).isEmpty)
    }
    func testCSVQuotedFieldsMultilineUnicodeAndDuplicates() throws {
        let s = try store()
        let csv = "\u{FEFF}Front,Back,Tags\r\n\"hello, world\",\"a \"\"quote\"\"\nnext line\",tag\r\nGrüße,你好,unicode\r\nGrüße,duplicate,\r\n"
        let result = try s.importDelimitedText(csv, deckID: s.defaultDeckID)
        XCTAssertEqual(result.importedNotes, 2); XCTAssertEqual(result.skippedDuplicates, 1)
        XCTAssertEqual(s.notes[0].front, "hello, world")
        XCTAssertEqual(s.notes[0].back, "a \"quote\"\nnext line")
        let other = try store()
        _ = try other.importDelimitedText(s.exportDelimitedText(), deckID: other.defaultDeckID)
        XCTAssertEqual(other.notes.map(\.front), s.notes.map(\.front))
        XCTAssertEqual(other.notes.map(\.back), s.notes.map(\.back))
        _ = try other.importDelimitedText("a\tb\ttags\n", deckID: other.defaultDeckID, delimiter: "\t")
        XCTAssertEqual(other.notes.count, 3)
    }
    func testMalformedImportRollsBackEntireTransaction() throws {
        let s = try store()
        XCTAssertThrowsError(try s.importDelimitedText("one,two\ninvalid\n", deckID: s.defaultDeckID))
        XCTAssertTrue(s.notes.isEmpty)
        XCTAssertThrowsError(try s.importDelimitedText("\"unterminated,two", deckID: s.defaultDeckID))
        XCTAssertThrowsError(try s.importDelimitedText("\"valid\"oops,two", deckID: s.defaultDeckID))
        XCTAssertTrue(s.cards.isEmpty)
    }
    func testBackupRoundTripPreservesHistoryAndUndo() throws {
        let s = try store()
        _ = try s.addNote(deckID: s.defaultDeckID, front: "q", back: "a")
        let original = s.cards[0]
        _ = try s.answer(cardID: original.id, rating: .easy, now: now)
        let restored = try store(); try restored.restoreBackup(s.exportBackup())
        XCTAssertEqual(restored.cards, s.cards); XCTAssertEqual(restored.notes, s.notes); XCTAssertEqual(restored.reviewLogs, s.reviewLogs)
        try restored.undoLastReview(); XCTAssertEqual(restored.cards[0], original)
    }
    func testInvalidBackupsNeverReplaceLiveData() throws {
        let s = try store()
        _ = try s.addNote(deckID: s.defaultDeckID, front: "q", back: "a")
        let before = try s.exportBackup()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: before) as? [String: Any])
        json["schemaVersion"] = 999
        XCTAssertThrowsError(try s.restoreBackup(JSONSerialization.data(withJSONObject: json)))
        json["schemaVersion"] = 1; json["decks"] = []
        XCTAssertThrowsError(try s.restoreBackup(JSONSerialization.data(withJSONObject: json)))
        XCTAssertEqual(try s.exportBackup(), before)
    }
    func testPersistAndReopenOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("collection.json")
        let s = try CollectionStore(fileURL: url)
        _ = try s.addNote(deckID: s.defaultDeckID, front: "persist", back: "me")
        let reopened = try CollectionStore(fileURL: url)
        XCTAssertEqual(reopened.notes, s.notes); XCTAssertEqual(reopened.cards, s.cards)
    }
    func testFailedDiskSaveDoesNotPublishInMemory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("collection.json")
        let s = try CollectionStore(fileURL: url)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        XCTAssertThrowsError(try s.createDeck(name: "must not appear"))
        XCTAssertEqual(s.decks.count, 1)
    }
    func testDeckValidationAndTagNormalization() throws {
        let s = try store()
        XCTAssertThrowsError(try s.createDeck(name: "  "))
        XCTAssertThrowsError(try s.createDeck(name: "default"))
        let n = try s.addNote(deckID: s.defaultDeckID, front: "q", back: "", tags: ["b a", "a"])
        XCTAssertEqual(n.tags, ["a", "b"])
    }
    func testPlainTextPreservesUnicodeAndRemovesScripts() {
        XCTAssertEqual(CardRenderer.plainText("<script>alert('x')</script><p>Grüße &amp; 你好</p>"), "Grüße & 你好")
    }
}

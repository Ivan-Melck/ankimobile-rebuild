import XCTest
@testable import FlashcardsCore

final class StudyPlanningTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func make(_ engine: SchedulingEngine = .fsrs7) throws -> CollectionStore {
        let s = try CollectionStore()
        var options = DeckOptions(); options.scheduling = SchedulingOptions(engine: engine)
        try s.updateDeckOptions(id: s.defaultDeckID, options: options)
        _ = try s.addNote(deckID: s.defaultDeckID, front: "Capital?", back: "Paris", tags: ["exam"])
        return s
    }
    func testFSRSVersionsUsePublishedInitialIntervals() throws {
        let s = try make(), id = s.cards[0].id
        let p = try s.prediction(cardID: id, now: now)
        XCTAssertEqual(try XCTUnwrap(p.intervals[2]), 4.7777247, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(p.intervals[3]), 53.869392, accuracy: 0.0001)
        var o = s.decks[0].options; o.scheduling = SchedulingOptions(engine: .fsrs6)
        try s.updateDeckOptions(id: s.defaultDeckID, options: o)
        let six = try s.prediction(cardID: id, now: now)
        XCTAssertNotEqual(six.intervals, p.intervals)
    }
    func testModernPreviewMatchesSavedAnswerAndUndoRestoresPredictions() throws {
        for engine in [SchedulingEngine.fsrs6, .fsrs7, .rwkvCurve, .rwkvInstant] {
            let s = try make(engine), id = s.cards[0].id
            let before = try s.exportBackup(), initial = try s.prediction(cardID: id, now: now)
            let delay = try XCTUnwrap(s.scheduledDelay(cardID: id, rating: .good, now: now))
            XCTAssertGreaterThan(delay, 0)
            XCTAssertEqual(try s.exportBackup(), before)
            _ = try s.answer(cardID: id, rating: .good, now: now, durationSeconds: 4)
            XCTAssertEqual(s.cards[0].due.timeIntervalSince(now), delay, accuracy: 0.001)
            let later = try s.prediction(cardID: id, now: now.addingTimeInterval(86400))
            XCTAssertNotNil(later.retrievability)
            try s.undoLastReview()
            XCTAssertEqual(try s.exportBackup(), before)
            XCTAssertEqual(try s.prediction(cardID: id, now: now), initial)
        }
    }
    func testEveryRWKVModelAndPrecisionLoadsAndProducesFiniteIntervals() throws {
        let s = try make(.rwkvCurve), id = s.cards[0].id
        for model in ["sm56", "sm55", "sm40", "sm36", "legacy"] {
            for precision in ["f32", "int8", "int4", "cards_int4_notes_int8"] {
                var o = s.decks[0].options; o.scheduling?.rwkvModel = model; o.scheduling?.precision = precision
                try s.updateDeckOptions(id: s.defaultDeckID, options: o)
                let p = try s.prediction(cardID: id, now: now)
                XCTAssertEqual(p.intervals.count, 4)
                XCTAssertTrue(p.intervals.allSatisfy { $0.map { $0.isFinite && $0 > 0 } ?? false }, "\(model)/\(precision)")
            }
        }
    }
    func testSameDayAndLearningSwitchesChangeRealIntervals() throws {
        let s = try make(), id = s.cards[0].id
        XCTAssertLessThan(try XCTUnwrap(s.scheduledDelay(cardID: id, rating: .again, now: now)), 86400)
        var o = s.decks[0].options; o.scheduling?.skipLearning = true
        try s.updateDeckOptions(id: s.defaultDeckID, options: o)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(s.scheduledDelay(cardID: id, rating: .again, now: now)), 86400)
    }
    func testRepeatSpacingAndLearningOrderPersistAcrossBackup() throws {
        let s = try make(); let id = s.cards[0].id
        var o = s.decks[0].options; o.scheduling?.minimumOtherReviews = 1; o.scheduling?.minimumSeconds = 10
        o.scheduling?.learningOrder = .after
        try s.updateDeckOptions(id: s.defaultDeckID, options: o)
        _ = try s.answer(cardID: id, rating: .again, now: now)
        XCTAssertTrue(s.studyQueue(now: now.addingTimeInterval(86400)).isEmpty)
        _ = try s.addNote(deckID: s.defaultDeckID, front: "Another", back: "Answer")
        _ = try s.answer(cardID: s.cards[1].id, rating: .good, now: now.addingTimeInterval(1))
        XCTAssertFalse(s.studyQueue(now: now.addingTimeInterval(86400)).isEmpty)
        let restored = try CollectionStore(); try restored.restoreBackup(s.exportBackup())
        XCTAssertEqual(restored.schedulingOptions(deckID: restored.defaultDeckID), s.schedulingOptions(deckID: s.defaultDeckID))
    }
    func testPresetAndFirstMatchingRuleDriveRetention() throws {
        let s = try make(); let id = s.cards[0].id
        let base = try XCTUnwrap(s.prediction(cardID: id, now: now).intervals[2])
        var settings = SchedulingOptions(engine: .fsrs6); settings.desiredRetention = 0.95
        let preset = SchedulingPreset(name: "Exam prep", options: settings); try s.savePreset(preset)
        var o = s.decks[0].options; o.rules = [SchedulingRule(query: "tag:exam", retention: 0.95, presetID: preset.id), SchedulingRule(query: "is:new", retention: 0.7)]
        try s.updateDeckOptions(id: s.defaultDeckID, options: o)
        let changed = try XCTUnwrap(s.prediction(cardID: id, now: now).intervals[2])
        XCTAssertLessThan(changed, base)
        let restored = try CollectionStore(); try restored.restoreBackup(s.exportBackup())
        XCTAssertEqual(restored.schedulingPresets, s.schedulingPresets)
        XCTAssertEqual(try restored.prediction(cardID: id, now: now).intervals, try s.prediction(cardID: id, now: now).intervals)
    }
    func testForecastUsesExistingCardsAndLeavesCollectionUntouched() throws {
        for engine in [SchedulingEngine.fsrs6, .fsrs7, .rwkvCurve] {
            let s = try make(engine)
            for i in 0..<4 { _ = try s.addNote(deckID: s.defaultDeckID, front: "Q\(i)", back: "A") }
            _ = try s.answer(cardID: s.cards[0].id, rating: .good, now: now)
            let before = try s.exportBackup()
            let forecast = try s.forecast(deckID: s.defaultDeckID, days: 7, now: now)
            XCTAssertEqual(forecast.points.count, 4)
            XCTAssertTrue(forecast.points.allSatisfy { $0.seconds.isFinite && $0.seconds >= 0 && $0.memorized.isFinite && $0.memorized >= 0 && $0.reviews > 0 }, "\(engine): \(forecast.points)")
            XCTAssertEqual(try s.exportBackup(), before)
        }
    }
    func testInsufficientHistoryHasActionableError() throws {
        let s = try make()
        XCTAssertThrowsError(try s.optimize(deckID: s.defaultDeckID)) { XCTAssertTrue($0.localizedDescription.contains("100")) }
        XCTAssertThrowsError(try s.evaluate(deckID: s.defaultDeckID)) { XCTAssertTrue($0.localizedDescription.contains("follow-up")) }
    }
    func testOldBackupWithoutPlanningFieldsStillDecodesAsClassic() throws {
        let s = try CollectionStore(); _ = try s.addNote(deckID: s.defaultDeckID, front: "old", back: "data")
        let data = try s.exportBackup(); XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("scheduling"))
        let restored = try CollectionStore(); try restored.restoreBackup(data)
        XCTAssertEqual(restored.schedulingOptions(deckID: restored.defaultDeckID).engine, .legacy)
    }
    func testNumericAndFieldSearch() throws {
        let s = try make()
        XCTAssertEqual(s.search("prop:reps=0 front:Capital -back:London").count, 1)
        XCTAssertTrue(s.search("prop:lapses>0").isEmpty)
        XCTAssertEqual(s.search("tag:exam prop:ivl<=1").count, 1)
    }
    func testInvalidSettingsAreTransactional() throws {
        let s = try make(); let before = try s.exportBackup()
        var o = s.decks[0].options; o.scheduling?.desiredRetention = .nan
        XCTAssertThrowsError(try s.updateDeckOptions(id: s.defaultDeckID, options: o))
        XCTAssertEqual(try s.exportBackup(), before)
    }
    func testCalibrationAndFittingUseRealRecordedHistory() throws {
        let s = try make()
        for i in 0..<39 { _ = try s.addNote(deckID: s.defaultDeckID, front: "History \(i)", back: "Answer") }
        try s.mutate { doc in
            for card in doc.cards {
                for step in 0..<5 {
                    let rating: ReviewRating = step == 2 && card.id.uuidString.first!.asciiValue! % 3 == 0 ? .again : (step == 4 ? .easy : .good)
                    doc.reviewLogs.append(ReviewLog(cardID: card.id, deckID: card.deckID, rating: rating,
                        reviewedAt: now.addingTimeInterval(Double(-100 + step * step * 4) * 86400),
                        previousState: step == 0 ? .new : .review, previousIntervalDays: Double(step + 1), scheduledIntervalDays: Double(step + 2), durationSeconds: 8))
                }
            }
        }
        for engine in [SchedulingEngine.fsrs6, .fsrs7, .rwkvCurve] {
            var options = s.decks[0].options; options.scheduling = SchedulingOptions(engine: engine)
            try s.updateDeckOptions(id: s.defaultDeckID, options: options)
            let result = try s.evaluate(deckID: s.defaultDeckID, now: now)
            XCTAssertEqual(result.samples, 160)
            XCTAssertTrue(result.log_loss.isFinite && result.log_loss >= 0)
            XCTAssertTrue(result.rmse.isFinite && (0...1).contains(result.rmse))
            if !engine.isRWKV {
                let parameters = try s.optimize(deckID: s.defaultDeckID, now: now)
                XCTAssertEqual(parameters.count, engine == .fsrs6 ? 21 : 34)
                XCTAssertTrue(parameters.allSatisfy(\.isFinite))
            }
        }
    }

    func testNumericFieldsRangesAndEscapedComparisonLiterals() throws {
        let s = try make()
        _ = try s.addNote(deckID: s.defaultDeckID, front: "12.5", back: "8")
        _ = try s.addNote(deckID: s.defaultDeckID, front: "front>10", back: "Literal comparator")
        XCTAssertEqual(s.search("front>10 back<=8").count, 1)
        XCTAssertEqual(s.search("front:[12,13)").count, 1)
        XCTAssertTrue(s.search("front:(12.5,13]").isEmpty)
        XCTAssertEqual(s.search(#"front\>10"#).first?.note.back, "Literal comparator")
    }
    func testLearningAheadOnlyWhenOtherQueuesAreEmpty() throws {
        let s = try make(), id = s.cards[0].id
        _ = try s.answer(cardID: id, rating: .again, now: now)
        XCTAssertTrue(s.studyQueue(now: now).isEmpty)
        var options = s.decks[0].options; options.scheduling?.learnAheadMinutes = 10
        try s.updateDeckOptions(id: s.defaultDeckID, options: options)
        XCTAssertEqual(s.studyQueue(now: now).first?.id, id)
        _ = try s.addNote(deckID: s.defaultDeckID, front: "Other", back: "Card")
        XCTAssertFalse(s.studyQueue(now: now).contains { $0.id == id })
    }
    func testDynamicPresetIsLoggedBeforeCardPropertiesChange() throws {
        let s = try make(.rwkvCurve), id = s.cards[0].id
        let preset = SchedulingPreset(name: "First answer", options: SchedulingOptions(engine: .rwkvCurve)); try s.savePreset(preset)
        var options = s.decks[0].options; options.rules = [SchedulingRule(query: "prop:reps=0", retention: 0.95, presetID: preset.id)]
        try s.updateDeckOptions(id: s.defaultDeckID, options: options)
        let log = try s.answer(cardID: id, rating: .good, now: now)
        XCTAssertEqual(log.schedulingPresetID, preset.id)
        let prediction = try s.prediction(cardID: id, now: now.addingTimeInterval(86400))
        let restored = try CollectionStore(); try restored.restoreBackup(s.exportBackup())
        XCTAssertEqual(try restored.prediction(cardID: id, now: now.addingTimeInterval(86400)), prediction)
    }

}

import XCTest

final class AnkiNativeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testNativeAnkiCreateReviewUndoAndPersistence() {
        let app = XCUIApplication(); app.launchArguments = ["--anki-testing", "--reset-test-collection"]; app.launch()
        XCTAssertTrue(app.tables["ankiDeckList"].waitForExistence(timeout: 15))
        app.buttons["Add"].tap()
        let front = app.textViews["ankiField.0"]
        XCTAssertTrue(front.waitForExistence(timeout: 5)); front.tap(); front.typeText("A real Anki collection")
        let back = app.textViews["ankiField.1"]; back.tap(); back.typeText("History stays with the card")
        app.buttons["ankiSaveNote"].tap()
        app.tables["ankiDeckList"].cells.firstMatch.tap()
        XCTAssertTrue(app.buttons["ankiShowAnswer"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.webViews.staticTexts["A real Anki collection"].waitForExistence(timeout: 10))
        app.buttons["ankiShowAnswer"].tap()
        XCTAssertTrue(app.webViews.staticTexts["History stays with the card"].waitForExistence(timeout: 10))
        app.buttons["ankiRate.4"].tap()
        XCTAssertTrue(app.buttons["ankiStudyDone"].waitForExistence(timeout: 10))
        app.buttons["Study Actions"].tap(); app.buttons["Undo Last Answer"].tap()
        XCTAssertTrue(app.buttons["ankiShowAnswer"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "13-Native-Anki-Review"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["Study Actions"].tap(); app.buttons["Edit Note"].tap()
        let editedBack = app.textViews["ankiField.1"]; editedBack.tap(); editedBack.typeText(" Updated native answer")
        app.buttons["ankiSaveNote"].tap()
        XCTAssertTrue(app.buttons["ankiShowAnswer"].waitForExistence(timeout: 10)); app.buttons["ankiShowAnswer"].tap()
        XCTAssertTrue(app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Updated native answer")).firstMatch.waitForExistence(timeout: 10))
        app.terminate(); app.launchArguments = ["--anki-testing"]; app.launch()
        app.navigationBars.buttons["Browse"].tap()
        XCTAssertTrue(app.tables["ankiBrowser"].cells.firstMatch.waitForExistence(timeout: 10))
        app.tables["ankiBrowser"].cells.firstMatch.tap()
        XCTAssertTrue((app.textViews["ankiField.1"].value as? String ?? "").contains("Updated native answer"))
    }
    func testRealDeckOptionsAndSyncScreens() {
        let app = XCUIApplication(); app.launchArguments = ["--anki-testing", "--reset-test-collection"]; app.launch()
        XCTAssertTrue(app.tables["ankiDeckList"].waitForExistence(timeout: 15))
        app.tables["ankiDeckList"].cells.firstMatch.swipeLeft(); app.buttons["Options"].tap()
        XCTAssertTrue(app.tables["ankiOptions"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "14-Native-Anki-Options"; attachment.lifetime = .keepAlways; add(attachment)
        app.navigationBars.buttons["Decks"].tap(); app.buttons["Synchronize"].tap()
        XCTAssertTrue(app.tables["ankiSync"].waitForExistence(timeout: 5))
        let sync = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); sync.name = "15-Anki-Sync"; sync.lifetime = .keepAlways; add(sync)
    }
    func testNativeTypedAnswerCard() {
        let app = XCUIApplication(); app.launchArguments = ["--anki-testing", "--reset-test-collection"]; app.launch()
        XCTAssertTrue(app.tables["ankiDeckList"].waitForExistence(timeout: 15))
        app.buttons["Add"].tap(); app.tables.cells.containing(.staticText, identifier: "Note Type").firstMatch.tap()
        app.staticTexts["Basic (type in the answer)"].tap()
        let front = app.textViews["ankiField.0"]; front.tap(); front.typeText("Capital of France")
        let back = app.textViews["ankiField.1"]; back.tap(); back.typeText("Paris")
        app.buttons["ankiSaveNote"].tap(); app.tables["ankiDeckList"].cells.firstMatch.tap()
        let input = app.webViews.textFields["Your answer"]
        XCTAssertTrue(input.waitForExistence(timeout: 20)); input.tap(); input.typeText("Paris")
        app.buttons["ankiShowAnswer"].tap()
        XCTAssertTrue(app.buttons["ankiRate.3"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["Paris"].firstMatch.waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = "16-Typed-Answer"; attachment.lifetime = .keepAlways; add(attachment)
    }
}

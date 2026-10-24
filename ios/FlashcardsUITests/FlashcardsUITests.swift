import XCTest

final class FlashcardsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-collection"]
        app.launch()
        XCTAssertTrue(app.tables["deckList"].waitForExistence(timeout: 10))
        return app
    }
    private func screenshot(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways
        add(image)
    }
    func testCreateStudyEditAndPersist() {
        let app = launch()
        screenshot("01-Decks")
        app.buttons["Add/Export"].tap()
        app.staticTexts["Add Note"].tap()
        let front = app.textViews["noteFront"]
        XCTAssertTrue(front.waitForExistence(timeout: 5))
        front.tap(); front.typeText("Capital of France?")
        app.textViews["noteBack"].tap(); app.textViews["noteBack"].typeText("Paris")
        screenshot("02-Editor")
        app.buttons["saveNote"].tap()
        app.navigationBars.buttons["Decks"].tap()
        app.tables["deckList"].cells.firstMatch.tap()
        XCTAssertTrue(app.buttons["showAnswer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts["Capital of France?"].waitForExistence(timeout: 10))
        screenshot("03-Question")
        app.webViews.firstMatch.tap()
        XCTAssertTrue(app.webViews.staticTexts["Paris"].waitForExistence(timeout: 10))
        screenshot("04-Answer")
        app.buttons["rate.easy"].tap()
        XCTAssertTrue(app.buttons["studyDone"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Study Actions"].tap()
        app.buttons["Undo Last Answer"].tap()
        XCTAssertTrue(app.buttons["showAnswer"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Decks"].tap()
        app.navigationBars.buttons["Search"].tap()
        XCTAssertTrue(app.tables["cardBrowser"].cells.firstMatch.waitForExistence(timeout: 5))
        screenshot("05-Browser")
        app.tables["cardBrowser"].cells.firstMatch.tap()
        let editBack = app.textViews["noteBack"]
        XCTAssertTrue(editBack.waitForExistence(timeout: 5))
        editBack.tap(); editBack.typeText(" edited")
        app.buttons["saveNote"].tap()
        app.terminate()
        // Relaunch without reset to verify that edits were saved to disk.
        app.launchArguments = ["--ui-testing"]; app.launch()
        app.navigationBars.buttons["Search"].tap()
        app.tables["cardBrowser"].cells.firstMatch.tap()
        XCTAssertTrue(app.textViews["noteBack"].waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews["noteBack"].value as? String)?.contains("edited") == true)
    }
    func testDeckCreationAndAppearance() {
        let app = launch()
        app.buttons["Add/Export"].tap(); app.staticTexts["Create Deck"].tap()
        let name = app.textFields["newDeckName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("French")
        app.alerts.buttons["Create"].tap()
        app.navigationBars.buttons["Decks"].tap()
        XCTAssertTrue(app.tables["deckList"].cells.containing(.staticText, identifier: "French").firstMatch.exists)
        app.navigationBars.buttons["Settings"].tap()
        app.segmentedControls["appearance"].buttons["Dark"].tap()
        screenshot("06-Dark-Preferences")
        app.navigationBars.buttons["Decks"].tap()
        screenshot("07-Dark-Decks")
    }
}

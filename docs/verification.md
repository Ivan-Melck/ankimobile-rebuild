# Verification

The final native code revision is `e25ead87877601ada4449a6887faf0e9cb7452f2`. Its [GitHub simulator run](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40105137856) builds the app with Xcode 16.4 on a macOS 15 hosted runner and uses an iPhone 16 Pro simulator. **Result: passed — 17 core tests and both XCUITest flows, zero failures.** See that run for the logs, `.xcresult`, screenshots, and simulator `.app`.

The portable core suite contains 17 behavior tests covering note/card generation, cloze templates, scheduling and interval previews, daily limits and rollover, undo, suspend/bury/move/deck deletion, quoted search, CSV quoting/Unicode/duplicates, import rollback, backup validation, persistence and failed-save rollback. `swift test` passes locally on Linux and on the macOS runner.

The two XCUITest flows exercise:

- Add a note, study it, tap the card to reveal its answer, rate it, undo, browse/edit it, terminate the app and verify the edit after relaunch.
- Create a deck, switch to dark appearance, and return to the deck list.

Screenshots are captured at deck list, editor, question, answer, browser, dark preferences and dark deck list states. Selected permanent copies are in [screenshots/](screenshots/). These are screenshots of the rebuild. They are not reference images from the original IPA and do not establish pixel equality.

The source supports iPhone and iPad with an iOS 15.2 deployment target. Runtime checks so far cover the hosted iPhone simulator. Physical devices, older iOS runtimes, iPad, landscape, large collections, the full accessibility workflow, and exact original-app fidelity remain unverified.

# Verification

## Fork integration

The fork integration has 32 portable XCTest checks, including published initial FSRS intervals, all five RWKV models and four precision modes, answer/preview/undo consistency, persisted preset routing, numeric search, learn-ahead, repeat spacing, backups, real-history calibration/fitting, and forecasts that leave live data unchanged. They pass on Linux and on the macOS runner. The Rust parity harness independently checks SM36, SM40v2, SM55 and SM56 against the fork’s published probability/curve vectors at a maximum absolute error of `1e-5`.

The first integration [simulator run](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40112241519) passed at source revision `22e5e88ed5a3a6e3c3cb1492a7c0e205ea18e6b1`: 28 core tests, neural vector parity, native iOS build, and three XCUITest flows, zero failures. The additional flow compares retention targets, applies a target, selects RWKV, edits retention, restarts the app, and simulates again using the saved engine.

The subsequent [simulator run](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40113342780) passed at revision `fb8d06b117fccd7c05ad4cc04bfa6a08fb99e25e`: **32 core tests, neural vector parity, native iOS build and all three XCUITest flows, zero failures.** Screenshots below were inspected for layout and clipping; the retention editor’s fixed-height subtitle was replaced by a scrolling layout. The checked-in Xcode project comes from this run.

After that run, three small presentation changes shorten “Scheduling preset” to “Preset”, display fractional reviews/day, and place Card Rules’ Edit beside Add so Back remains visible. Those Swift files were parser-checked; the recorded simulator captures precede these presentation-only changes.

<img src="screenshots/study-plan.png" width="230" alt="Native Study Plan"> <img src="screenshots/retention-comparison.png" width="230" alt="Retention workload comparison"> <img src="screenshots/retention-target.png" width="230" alt="Retention target editor">

## Initial reconstruction baseline

The initial native code revision was `e25ead87877601ada4449a6887faf0e9cb7452f2`. Its [GitHub simulator run](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40105137856) builds the app with Xcode 16.4 on a macOS 15 hosted runner and uses an iPhone 16 Pro simulator. **Result: passed — 17 core tests and both XCUITest flows, zero failures.** See that run for the logs, `.xcresult`, screenshots, and simulator `.app`.

The portable core suite contains 17 behavior tests covering note/card generation, cloze templates, scheduling and interval previews, daily limits and rollover, undo, suspend/bury/move/deck deletion, quoted search, CSV quoting/Unicode/duplicates, import rollback, backup validation, persistence and failed-save rollback. `swift test` passes locally on Linux and on the macOS runner.

The two XCUITest flows exercise:

- Add a note, study it, tap the card to reveal its answer, rate it, undo, browse/edit it, terminate the app and verify the edit after relaunch.
- Create a deck, switch to dark appearance, and return to the deck list.

Screenshots are captured at deck list, editor, question, answer, browser, dark preferences and dark deck list states. Selected permanent copies are in [screenshots/](screenshots/). These are screenshots of the rebuild. They are not reference images from the original IPA and do not establish pixel equality.

The source supports iPhone and iPad with an iOS 15.2 deployment target. Runtime checks so far cover the hosted iPhone simulator. Physical devices, older iOS runtimes, iPad, landscape, large collections, the full accessibility workflow, and exact original-app fidelity remain unverified.

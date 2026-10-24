# Verification

## Real Anki collection path

The full shared backend [simulator run](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40127162417) passed at revision `631760f917ee001afe806e102abba52055cd1293`: host checks, native iOS build and the three existing legacy UI test flows. The new native Anki screens and RWKV collection coordinator are subsequent changes and require their own simulator run.

Local checks now pass 54 core tests (three optional fixture/server tests skip in an ordinary run). These cover actual collection creation/rendering/review/undo, package import, lossless round trips, failed-import isolation, config preservation and RWKV Instant/Curve replay, synthetic same-day context, typed answers and cloze typing. A source-derived regression also covers repeated synthetic same-day reviews and exact revlog matching after undo. The isolated sync test is run separately with `scripts/test-sync.sh`. Model vector tests and older JSON-path tests remain separate evidence.

With the user's authorization, a private local profile was copied without opening its source database in SQLite. Database/WAL source hashes were verified unchanged after testing. A second disposable copy passed `.colpkg` export/import comparison of **8,478 cards, 6,402 notes, 10 note types, 5 decks, 31,230 canonical RWKV history rows and 13,876 media files**. Every card and note protobuf, template, history row, media filename and media byte sequence matched. No collection contents or media were uploaded. This caught and fixed an automatic repair-on-import operation that rewrote note timestamps.

A separate smoke test warmed the canonical private history and produced 2,057 candidate predictions in approximately 2.2 seconds on the local Linux host. Two synthetic clients also passed full sync, media transfer, note edits, distinct-timestamp conflict convergence, note deletion and review-history sync against the local fork server. Same-second conflicting edits reproduced a pinned-backend limitation. Repeated fast sync tests also reproduced missed deletions when a mutation and sync completion share a millisecond; the pinned meta comparison treats equal collection mtimes as unchanged. Normal-flow tests explicitly separate those timestamps; these backend races remain unresolved.

The [native UI run at 9a7ccce](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40129073643) compiled the new iOS screens and passed deck-options/sync navigation plus all three legacy UI flows, but caught a blank review document. The [subsequent run at 7dddcac](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40131313281) passed native rendering, grading/undo up to the edit step, typed-answer cards, options/sync navigation and all three legacy flows; the review/edit test exposed a modal keyboard-focus failure. The editor now uses a full-screen presentation and the render/media changes have expanded runtime checks.

The [expanded native run at 2f6e509](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40134642699) passed the native create/review/grade/undo/edit/restart flow, typed answers, options/sync navigation, local image/audio loading, sequential playback without overlap, algebra/chemistry typesetting and all three legacy flows. Its image-occlusion fixture failed with a blank canvas. A browser reproduction identified stalled animation-frame setup; the renderer now has a bounded one-shot fallback. This fix and a direct iOS RWKV Instant/FSRS-6 persistence fixture are awaiting the next simulator result.

The [run at dfa1c0a](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40137129213) passed the native image-occlusion mask/reveal and RWKV Instant/FSRS-6 review-persistence fixtures, plus six other UI flows. The create/review test caught an intermittent blank WebKit document after saving correctly entered fields. The next change delays initial review preparation until the screen is onscreen, validates document readiness, retries a missing document once, handles content-process termination and withholds answer controls while loading. Its simulator rerun is pending.

This validates preservation for that fixture. Live AnkiWeb, exact desktop RWKV review-order parity, filtered/same-day edge cases and complete rendering/UI parity remain outstanding. See the [compatibility inventory](compatibility.md).

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

# Verification

## Current workspace state — 2026-10-27

The results below are retained validation records. After the final passing run,
the user requested deletion of the local test environment. The private fork
Python environment (`Vendor/anki/out/pyenv`), generated reference/Rust/Swift
builds, temporary test collections, clock library and local test logs were
removed. The installed Anki and its data were not modified.

Project/fork source, test scripts, the sanitized report, checked-in screenshots
and ignored static-analysis tools/evidence remain. Historical private fixtures
are not retained. No tests were rerun after deletion; follow the
[rebuild instructions](../tools/comparison/README.md) to recreate an isolated
environment deliberately. The latest validated application source remains
`db7314a998b705db47f50c27184d8497751b39eb`; later documentation/cleanup work
does not represent a new application build.

## Independent RWKV comparison — 2026-10-27

The app already pinned the newest `JSchoreels/anki` main revision,
`96af4ca9d214e71743b1186fd2ceab1a7e7e3f32`; GitHub main and all five model
hashes were checked again before comparison. No newer main commits required
importing. App source `4cb2621226abce0882c4b5801abeb988a348880d` fixes differences
found by executing that original fork against the shipping Swift collection API.

**All 840 synthetic differential cases passed:** 20,115 review preparations,
20,093 answers and 100,553 comparisons. The matrix crosses five models
(Legacy, SM36, SM40v2, SM55, SM56), four recurrent precisions (F32, INT8, INT4,
mixed card INT4/note INT8), Instant/Curve/both, and fourteen scenarios:
standard, mixed presets, refresh every three answers, undo, redo, reopen,
next-day reopening, FSRS 4/5/7, dynamic-retention configuration, **active FSRS 7
dynamic retention**, dynamic preset replay and disabled grade ordering.
The active-retention flag was asserted in all sixty corresponding cases.
FSRS 6 is the standard fallback in the other scenarios.

The independent reference builds the original Python/Rust binding and executes
the fork's actual reviewer fetch, empty-queue recovery, post-answer refresh,
prediction, answer metadata, warmup and undo/redo reconciliation methods.
Window drawing is omitted and GUI task dispatch runs synchronously. The app
peer uses `AnkiCollection`, shared with iOS, on Linux. Comparisons include the
displayed card, counts, complete candidate scores/order, all answer states,
neural heads/intervals, card/note/revlog/grave rows, and all recurrent-module
hashes. Floats use absolute/relative tolerance `1e-5`; integers, strings and
recurrent-byte hashes compare exactly. This does not test asynchronous GUI
races or establish desktop/iOS visual equality.

This caught and fixed learning-card prediction outside the review candidate
set, learn-ahead elapsed-time inputs, Curve S90 in review/relearning states,
displayed-card preservation during deferred refresh, candidate input caching,
refresh cadence, undo/redo counters and temporary same-day context, and the
distinction between candidate eligibility targets and displayed per-grade
dynamic retention.

Every reference and app process passed a mandatory namespace audit: live user
Anki data hidden, installed launcher masked, host files read-only and host
network unreachable. Profiles/clocks are private temporary fixtures. Local
Anki was neither stopped nor opened by these tests. No private collection,
media or process logs are included in the
[sanitized case report](evidence/rwkv-differential-2026-10-27.json).
See [reproduction instructions](../tools/comparison/README.md).

The local core suite also passed **56 tests**, with four optional private/server
fixtures skipped. Both sync tests passed separately inside an audited private
network namespace. The added regression reproduced stale candidates after
incoming reviews and full download, then passed after clearing reviewer-local
state on the fork's sync-change signal and full replacement. The existing FSRS-6
fallback survives both operations. The
[final iOS run](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40565026742)
passed at source `db7314a998b705db47f50c27184d8497751b39eb`: **56 core tests**
(four optional fixtures skipped), neural-vector checks, **both server sync
tests**, the native iOS build and **all nine iPhone UI tests** (six real-Anki,
three legacy), zero failures.

The matrix ran at `4cb2621`; the subsequent sync-only cache invalidation is
covered by the separate server regression. This establishes the named
synthetic RWKV scenarios. Filtered RWKV decks,
custom scheduling scripts, candidate-refresh/exit-refresh modes, external
Python add-ons, large-profile/device latency and live AnkiWeb acceptance
remain outside this result, as do continuous midnight UI transitions and
historical preset migrations/complex overlay rules. See the
[compatibility inventory](compatibility.md).

## Earlier real-Anki validation — 2026-10-24

The [earlier iPhone simulator run](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40139231893) passed at source revision `b9cd43cfe3c34f2fe8db68deed73002b6fe7f699` on 2026-10-24 UTC. The project/scheme comparison and screenshots in this section describe that revision; the final 2026-10-27 result is above.

- **54 core tests**, with three optional fixture/server tests skipped in the ordinary run, zero failures.
- Neural prediction-vector checks against the pinned fork, with a maximum absolute error of `1e-5`.
- A separate isolated two-client sync test: collection upload/download, media transfer, edits, review history, distinct-timestamp conflict convergence and note deletion.
- **Nine iPhone UI flows**, zero failures: six native Anki flows and three legacy reconstruction flows.

Native runtime coverage includes create/review/rate/undo/edit/restart persistence, typed answers, real deck-options/sync navigation, image/audio loading, sequential playback without overlap, offline algebra/chemistry typesetting, German/Japanese text, image-occlusion mask pixels and answer reveal, and actual RWKV Instant inference with an FSRS-6 fallback and persisted review history. The collection coordinator also has a source-derived regression through four same-day reviews and undo. The fallback's stored memory state and version survive review and package import/export.

Earlier runs exposed blank review documents, modal keyboard focus, stalled image-occlusion animation frames and missing HTML encoding. The final code waits for the reviewer to appear, validates the loaded document before showing answer controls, allows one bounded recovery, rejects stale navigation callbacks, handles WebKit process termination, declares UTF-8 and adds a one-shot fallback for image-occlusion drawing. The final captures were inspected for the affected rendering and layout issues. Diagnostic fixture labels are part of the test notes, not application status messages.

<img src="screenshots/native-review.png" width="230" alt="Native Anki card review"> <img src="screenshots/native-options.png" width="230" alt="Native Anki deck options"> <img src="screenshots/native-typed-answer.png" width="230" alt="Native typed-answer comparison">

### Historical private local collection check

With the user's authorization, the local profile was copied as database/WAL bytes without opening the source database in SQLite. Source hashes were checked unchanged after testing. Those tests used a second disposable copy, which is no longer retained; collection contents and media were never uploaded or synced to a real account. This historical run is distinct from the later synthetic-only matrix.

The private-fixture run passed **22 checks**, with only the separate server test skipped. Its `.colpkg` export/import comparison preserved **8,478 cards, 6,402 notes, 10 note types, 5 decks, 31,230 canonical RWKV history rows and 13,876 media files**. Every card/note protobuf, template, history row, media filename and media byte sequence matched. This caught and fixed automatic repair on import, which had rewritten note timestamps.

A separate replay smoke check warmed the full canonical history and produced **2,057 candidate predictions in approximately 2.2 seconds** on the local Linux host. This is host performance evidence, not an iPhone large-collection benchmark or desktop order-parity result.

### Acceptance limits

**Full Anki/fork feature parity is not established.** The synthetic desktop RWKV matrix above now covers mixed presets and the named lifecycle cases. Live AnkiWeb, filtered RWKV reviews, custom scheduling scripts, advanced native tools and broader real-collection/device/format cases remain outstanding. Model and precision are local profile settings and must match desktop for comparable RWKV behavior. See the [compatibility inventory](compatibility.md).

The pinned backend also has unresolved sync races: conflicting note edits within one second can diverge, and a mutation sharing a millisecond with sync completion can be missed because collection mtimes compare equal. Normal-flow tests explicitly separate timestamps; passing them does not certify these races are fixed.

## Earlier JSON-path fork integration

The earlier JSON-based integration reached 32 portable XCTest checks, including initial FSRS intervals, all five RWKV models/four precisions, answer/preview/undo, preset routing, search, learn-ahead, repeat spacing, backups, calibration/fitting and forecasts. They passed on Linux/macOS in the recorded runs below. The retained Rust parity harness checks SM36, SM40v2, SM55 and SM56 against published vectors at maximum absolute error `1e-5`; its latest passing execution is included in the final CI result above.

The first integration [simulator run](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40112241519) passed at source revision `22e5e88ed5a3a6e3c3cb1492a7c0e205ea18e6b1`: 28 core tests, neural vector parity, native iOS build, and three XCUITest flows, zero failures. The additional flow compares retention targets, applies a target, selects RWKV, edits retention, restarts the app, and simulates again using the saved engine.

The subsequent [simulator run](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40113342780) passed at revision `fb8d06b117fccd7c05ad4cc04bfa6a08fb99e25e`: **32 core tests, neural vector parity, native iOS build and all three XCUITest flows, zero failures.** Screenshots below were inspected for layout and clipping; the retention editor’s fixed-height subtitle was replaced by a scrolling layout. Those legacy captures predate the native Anki collection path.

At that stage, three presentation changes shortened “Scheduling preset” to “Preset”, displayed fractional reviews/day, and placed Card Rules’ Edit beside Add. The captures below predate those edits. Subsequent native/legacy UI runs, including the final nine-flow run above, supersede the earlier parser-only validation status.

<img src="screenshots/study-plan.png" width="230" alt="Native Study Plan"> <img src="screenshots/retention-comparison.png" width="230" alt="Retention workload comparison"> <img src="screenshots/retention-target.png" width="230" alt="Retention target editor">

## Initial reconstruction baseline

The initial native code revision was `e25ead87877601ada4449a6887faf0e9cb7452f2`. Its [GitHub simulator run](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40105137856) builds the app with Xcode 16.4 on a macOS 15 hosted runner and uses an iPhone 16 Pro simulator. **Result: passed — 17 core tests and both XCUITest flows, zero failures.** See that run for the logs, `.xcresult`, screenshots, and simulator `.app`.

That initial portable core suite contained 17 behavior tests covering note/card generation, cloze templates, scheduling and interval previews, limits/rollover, undo, suspend/bury/move/deck deletion, search, CSV, import rollback, backup validation and persistence. It passed on Linux and macOS at that revision; the final suite contains 56 tests with four optional skips in its ordinary run.

The two XCUITest flows exercise:

- Add a note, study it, tap the card to reveal its answer, rate it, undo, browse/edit it, terminate the app and verify the edit after relaunch.
- Create a deck, switch to dark appearance, and return to the deck list.

Screenshots are captured at deck list, editor, question, answer, browser, dark preferences and dark deck list states. Selected permanent copies are in [screenshots/](screenshots/). These are screenshots of the rebuild. They are not reference images from the original IPA and do not establish pixel equality.

The source supports iPhone and iPad with an iOS 15.2 deployment target. Runtime checks so far cover the hosted iPhone simulator. Physical devices, older iOS runtimes, iPad, landscape, large collections, the full accessibility workflow, and exact original-app fidelity remain unverified.

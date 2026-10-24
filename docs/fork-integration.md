# Anki fork integration

Reference: JSchoreels/anki at `96af4ca9d214e71743b1186fd2ceab1a7e7e3f32`.

## Native workflows

| Fork capability | iOS integration |
| --- | --- |
| FSRS-6 and FSRS-7 | Deck Options → Memory model; the exact pinned Rust library computes all four answer intervals |
| RWKV Curve / Instant | Curve schedules from the neural recall curve; Instant ranks eligible review cards by recall and uses FSRS-7 for due dates |
| Small / legacy RWKV models | Advanced options offer SM56 (default), SM55, SM40v2, SM36 and Legacy |
| F32 / INT8 / INT4 recurrent state | Advanced options include the fork’s mixed INT4-card / INT8-note default |
| Desired retention | A focused percentage slider and the Study Plan comparison; 70–99% |
| Same-day scheduling / skip queues | Explicit deck switches; sub-day scheduling down to one second |
| Review priority / repeat spacing | Due date, recall, relative overdueness, interval order; minimum elapsed seconds and intervening reviews |
| Intraday learning placement | Before, mixed with, or after review cards |
| Dynamic desired retention / presets | Ordered card-search rules can override retention and select a saved shared preset |
| Help Me Decide / workload simulation | Actual FSRS or RWKV simulation of this deck at 80/85/90/95%; 30/90/365-day horizon, review cost, memorized cards and efficiency |
| Calibration | FSRS final-fit and time-series validation, or causal RWKV replay; log loss and recall-bin RMSE |
| Parameter optimization | Fits FSRS-6/7 after 100 follow-up reviews; preview then apply fitted parameters |
| Card predictions | Reviewer → Study Actions → Card Insights; recall, stability, difficulty where available, and four raw answer intervals |
| Numeric and field searches | `prop:ivl>=10`, `prop:reps`, `prop:lapses`, `prop:ease`, `prop:due`, `front:`, `back:`, quoting and backslash escaping |

## Deliberate platform boundaries and remaining differences

This is a native mobile integration of the fork’s scheduling features, not a port of its complete desktop application. Qt webviews, desktop add-on execution, installer/update mechanisms, Python packaging, and platform-specific desktop optimizations do not belong in the iOS UI.

The fork’s collection-wide SQLite cache/checkpoint management is replaced by a rebuildable in-process inference cache over the rebuild’s JSON review history. No opaque neural state is required in backups. Switching models, restoring a backup or undoing an answer replays the recorded history. The cache is derived; backups retain source reviews, presets, rules and FSRS parameters. Historic imported Anki collections are not supported by this rebuild yet; CSV imports start new cards. Existing local backups without scheduling fields keep Classic scheduling. Fresh app collections start with FSRS-7.

Forecasts compare **uniform retention** on the selected deck. They respect deck size, current memory history, maximum interval and daily limits. Conditional rules, repeat-spacing constraints and learning placement are not modeled by the forecast. The engine’s workload simulation uses its standard review-time/rating assumptions rather than fitted user timing. The iOS retention comparison does not expose every desktop simulator sweep, cost-ADR training, advanced classifier option, graph, diagnostic or optimizer hyperparameter. These are not claimed as implemented. Estimates are labeled as estimates in the UI.

RWKV Instant’s fallback due-date calculator is fixed to FSRS-7 in this implementation. Recall and relative-overdueness ordering require a memory model. Classic preserves the original rebuild scheduler; its advanced model-only controls have no effect. The local search grammar remains an explicit subset of Anki’s full search language, limited to the two editable note fields and documented properties.

## Architecture / modification points

- `Sources/FlashcardsCore/StudyPlanning.swift`: typed configuration, shared presets, conditional rules, JSON bridge, scheduling policy.
- `NativeEngine/src/lib.rs`: C ABI, history conversion, model loading, prediction, simulation, evaluation and fitting. Engine exceptions are returned as JSON errors.
- `NativeEngine/src/rwkv/`: fork inference implementation. Keep it independently updatable; make integration changes in adapters.
- `ios/Flashcards/Controllers/StudyPlanController.swift`: decision flow and native workload bars.
- `DeckOptionsController`, `SchedulingPresetsController`, `CalibrationController`: focused option/editing/analysis flows.
- `scripts/build-native.sh`: host, device and simulator Rust builds. XcodeGen invokes it before compiling the app; the workflow builds the host engine before portable tests.

## Build

Install Rust with rustup, Swift and (on macOS) Xcode + XcodeGen. Run `scripts/build-native.sh && swift test`. On macOS, `xcodegen generate`, then build the Flashcards scheme. Rust iOS targets are installed automatically by the build script. Model files are SwiftPM resources, so the same weights ship in host tests and the iOS app.

The complete derivative source is public in this repository. See `THIRD_PARTY_NOTICES.md` and `LICENSE` for provenance and licensing.

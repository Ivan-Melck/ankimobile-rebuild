# Anki fork integration

The default app uses the full fork backend and real Anki collections. Status is
recorded as of 2026-10-27; see [current compatibility](compatibility.md),
[architecture](architecture.md) and [verification](verification.md).

Reference: JSchoreels/anki at `96af4ca9d214e71743b1186fd2ceab1a7e7e3f32`.

## Current real-Anki integration

- Shared SQLite storage, package import/export, arbitrary note fields/templates,
  backend search/rendering, scheduling and sync; native UIKit screens.
- Actual fork RWKV inference with canonical replay, five models and four state
  precisions. Instant retains the selected FSRS fallback rather than forcing FSRS 7.
- Learning/relearning inputs, Curve S90, deferred queue refresh, candidate
  caching and undo/redo matched the original in 840 synthetic cases, including
  active FSRS-7 dynamic retention and mixed presets.
- Incoming normal-sync changes and full transfers clear reviewer-local caches;
  separate server regressions verify newly downloaded candidates and FSRS 6.
- Final code `db7314a` passed 56 core checks (four optional skips), both sync
  tests, neural vectors, the iOS build and nine UI tests.

Filtered RWKV, custom scheduling scripts, some refresh modes and desktop Python
add-ons remain unsupported or outside the acceptance scope. Full parity is not
established. The local test environment/builds and temporary fixtures/logs have
been deleted; source, scripts and sanitized evidence remain.

## Historical legacy JSON workflows

The following features belong to Collection Tools → Original Local Collection.
Its simulations, rules and calibration do not schedule imported Anki data.

### Legacy workflow inventory

| Fork capability | iOS integration |
| --- | --- |
| FSRS-6 and FSRS-7 | Deck Options → Memory model; the exact pinned Rust library computes all four answer intervals |
| RWKV Curve / Instant | Curve schedules from the neural recall curve; Instant ranks eligible review cards by recall and uses FSRS-7 for due dates |
| Small / legacy RWKV models | Advanced options offer SM56 (default), SM55, SM40v2, SM36 and Legacy |
| F32 / INT8 / INT4 recurrent state | Advanced options include the fork’s mixed INT4-card / INT8-note default |
| Desired retention | A focused percentage slider and the Study Plan comparison; 70–99% |
| Same-day scheduling / skip queues | Explicit deck switches; sub-day scheduling down to one second |
| Review priority / repeat spacing | Due date, recall, relative overdueness, interval order; minimum elapsed seconds and intervening reviews, with the Instant last-learning-card exception |
| Intraday learning placement | Before, mixed with, or after review cards; optional 0–60 minute learn-ahead only when other queues are empty |
| Dynamic desired retention / presets | Ordered card-search rules can override retention and select a saved shared preset |
| Help Me Decide / workload simulation | Actual FSRS or RWKV simulation of this deck at 80/85/90/95%; 30/90/365-day horizon, review cost, memorized cards and efficiency |
| Calibration | FSRS final-fit and time-series validation, or causal RWKV replay; log loss and recall-bin RMSE |
| Parameter optimization | Fits FSRS-6/7 after 100 follow-up reviews; preview then apply fitted parameters |
| Card predictions | Reviewer → Study Actions → Card Insights; recall, stability, difficulty where available, and four raw answer intervals |
| Numeric and field searches | `prop:ivl>=10`, `prop:reps`, `prop:lapses`, `prop:ease`, `prop:due`, `front:`, `back:`, `Front>5`, `Back:[1,10)`, quoting and escaped literal comparisons |

### Legacy platform boundaries and remaining differences

This is a native mobile integration of the fork’s scheduling features, not a port of its complete desktop application. Qt webviews, desktop add-on execution, installer/update mechanisms, Python packaging, and platform-specific desktop optimizations do not belong in the iOS UI.

In the legacy path, the fork’s collection-wide SQLite cache/checkpoint management is replaced by a rebuildable in-process inference cache over JSON review history. Answers record the preset chosen before card properties change. Switching models, restoring a backup or undoing an answer replays that history; backups retain reviews, presets, rules and FSRS parameters. This JSON path does not import historic Anki collections; use the default real-Anki profile/package workflow for those. Legacy CSV imports start new cards, old JSON backups without scheduling fields keep Classic, and new legacy collections default to FSRS 7.

Forecasts compare **uniform retention** on the selected deck. They respect deck size, current memory history, maximum interval and daily limits. Conditional rules, repeat-spacing constraints and learning placement are not modeled by the forecast. The engine’s workload simulation uses its standard review-time/rating assumptions rather than fitted user timing. The iOS retention comparison does not expose every desktop simulator sweep, cost-ADR training, advanced classifier option, graph, diagnostic or optimizer hyperparameter. These are not claimed as implemented. Estimates are labeled as estimates in the UI.

Only the legacy JSON Instant implementation fixes the fallback to FSRS 7; the current real-Anki path preserves its selected fallback. Legacy recall/relative-overdueness ordering require a memory model, Classic retains the original rebuild scheduler, and the two-field search grammar is a subset of Anki search. The default real-Anki browser uses the full pinned backend parser.

### Legacy modification points

- `Sources/FlashcardsCore/StudyPlanning.swift`: typed configuration, shared presets, conditional rules, JSON bridge, scheduling policy.
- `NativeEngine/src/lib.rs`: C ABI, history conversion, model loading, prediction, simulation, evaluation and fitting. Engine exceptions are returned as JSON errors.
- `NativeEngine/src/rwkv/`: fork inference implementation. Keep it independently updatable; make integration changes in adapters.
- `ios/Flashcards/Controllers/StudyPlanController.swift`: decision flow and native workload bars.
- `DeckOptionsController`, `SchedulingPresetsController`, `CalibrationController`: focused option/editing/analysis flows.
- `scripts/build-native.sh`: host, device and simulator Rust builds. XcodeGen invokes it before compiling the app; the workflow builds the host engine before portable tests.

## Build

Follow the [main build instructions](../README.md#build-for-iphone-or-ipad).
For Linux tests, rebuild and use the [audited test workflow](../tools/comparison/README.md);
prior local environments/binaries no longer exist. Rust iOS targets are installed
by the build script. Model files are SwiftPM resources shared by host tests and iOS.

The complete derivative source is public in this repository. See `THIRD_PARTY_NOTICES.md` and `LICENSE` for provenance and licensing.

# Architecture

Status: 2026-10-27. The architecture below describes the current real-Anki path;
historical JSON planning is separate. The 840-case synthetic comparison and
final iOS/sync validation passed within the [documented scope](verification.md).
Local generated test environments/builds have since been removed; source and
reproduction scripts are retained.

The default app uses UIKit navigation and WKWebView card documents over the full pinned Anki backend. `AnkiAppState` owns one real `AnkiCollection`, profile-scoped model preferences and Keychain authentication. Each profile has its own `collection.anki2`, media folder and media database. Imports create new profiles and preserve existing ones.

`AnkiBackend.swift` sends lossless protobuf JSON through a small C ABI. `full_backend.rs` reflects the fork’s generated service catalog and forwards calls to `Backend.run_service_method`; it does not translate collection objects through the original rebuild’s data model. Protobuf int64 values remain decimal strings. The backend registry lock is released before operations, allowing concurrent progress/cancellation during sync.

`Vendor/anki` pins the complete public fork. Its Rust collection owns schema migration, scheduling, search, rendering, package import/export, SQLite transactions and sync. Shared backend changes stay in the public fork; mobile adapters live outside the submodule. `scripts/prepare-backend.sh` initializes the backend and its translation dependencies. Protobuf descriptors are embedded at build time.

`collection_rwkv.rs` loads the actual fork inference runtime, consumes canonical history/input-row RPCs and publishes candidate scores to the Anki queue builder. IDs are preserved; nonnumeric preset IDs use the desktop’s Blake2b mapping. Candidate inputs are cached for the scheduler day and refreshed for answered/dirty cards. Queue refresh cadence and displayed-card preservation follow the desktop policy. Displayed learning cards use their live scheduling-state elapsed time, separately from ordinary candidate scoring. Candidate eligibility uses the configured retention target; the displayed prediction can use per-grade dynamic targets.

Canonical history identity changes rebuild recurrent state. Undo/redo reconcile answer counters, restored cards and temporary same-day context. Normal sync with incoming collection changes, full collection transfer and collection open/close clear reviewer-local caches. No neural state replaces persisted history. Curve intervals pass through backend state construction, and S90 updates future review/relearning memory states and Curve answer metadata. Model and precision are local profile settings and must match desktop for comparable behavior. Unsupported and unverified combinations remain in [compatibility](compatibility.md).

The native reviewer accepts prepared backend states, renders backend HTML and CSS, and submits the chosen state to `AnswerCard`. Template JavaScript is enabled. A disposable viewer directory contains hard links to regular media files (copy fallback) and the rendered HTML; [WebKit file loading](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl(_:allowingreadaccessto:)) grants read access only to that directory. Collection databases and authentication files are excluded. Navigation starts only when the viewer is attached to a window; document readiness gates answer controls, with one bounded retry for a missing document or terminated WebKit process. Bundled MathJax and the fork’s image-occlusion canvas renderer run offline; cached LaTeX uses backend-generated media names. Audio tags retain their question/answer side and play sequentially with native TTS; the restricted message bridge exposes reveal/replay, never sync credentials or arbitrary backend calls. External links open in the system browser. Rendering runtime gaps are documented separately from collection preservation.

The original JSON implementation remains accessible as a separate local collection, and existing JSON data is retained. Its `CollectionStore`, `StudyPlanning` and scheduling C ABI support the earlier reconstruction and simulation screens. They are not used to schedule imported real Anki collections. The legacy UI test launch flag still tests those flows; `--anki-testing` creates an isolated real Anki profile.

The source of build settings is `project.yml`. XcodeGen includes native source files; the pre-build script produces the Rust static library for the selected simulator/device architecture. Linux/macOS XCTest covers collection/replay operations. The macOS workflow builds UIKit and runs native Anki and legacy UI tests using disposable fixtures.

`AnkiComparisonDriver` wraps the shipping Swift collection API. The independent reference executes the pinned fork's Python/Rust binding and actual reviewer fetch, recovery and post-answer methods; rendering is omitted and GUI dispatch is synchronous. Linux peers run in separate audited bubblewrap namespaces. A controlled wall clock affects only those peers; monotonic time stays real. `validation-comparison` enables observation-only SQL/recurrent snapshots and is absent from shipping builds. Sync checks place both synthetic clients and the fork server inside one private network namespace. See [comparison reproduction](../tools/comparison/README.md).

The checked-in sanitized report survives cleanup. Deleted virtual environments,
executables, temporary profiles and logs must be regenerated before local tests;
historical private fixtures are not retained. No public CI job uses a personal
collection or the workstation's installed Anki.

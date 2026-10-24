# Anki compatibility contract

The collection path uses the complete shared backend from JSchoreels/anki,
revision `96af4ca9d214e71743b1186fd2ceab1a7e7e3f32`. This is a versioned target,
not a claim of compatibility with every past or future Anki release or add-on.
**Full feature parity is not yet established.** Data preservation, scheduling,
sync, and native UI behavior have separate acceptance checks.

## Acceptance inventory

| Capability | Implementation and evidence | Remaining acceptance work |
| --- | --- | --- |
| Collection format | Real Anki SQLite, original 64-bit IDs, notes, cards, decks, templates, config bytes and revlogs. No conversion through rebuild JSON. | More historical schemas and interrupted migrations. |
| Collection packages | Anki's `.colpkg` importer/exporter, including media. Private collection round trip compares every card/note, templates, canonical replay rows and media bytes. | More legacy package versions and archive corruption cases. |
| Deck packages | Anki's `.apkg` importer; upstream media package fixture passes. | Merge conflicts, scheduling-preserving exports and modern package variants. |
| Search | Complete pinned backend parser and search engine; native browser calls it directly. | Native saved-search/tag navigation, RWKV-dependent search preparation. |
| Note types and templates | Arbitrary note fields and existing templates retained. Backend renders existing cards. Native source-field editor works with arbitrary fields. | Full template/field management, rich HTML editor and image occlusion authoring. |
| Media | Anki media folder/database, package round trips, a scoped WKWebView media workspace and sequential audio/video/TTS playback. | The new image/audio/playback fixtures require their iOS run. More device formats, recording, attachment editing and media conflict cases remain to validate. |
| Standard scheduling | Actual SM-2 and FSRS 4/5/6/7 scheduler, learning/relearning, limits, parent aggregation, burying, fuzz and rollover from the pinned backend. No reimplementation of these policies. | Standard filtered-deck answer/undo tests pass. Broader differential sequences, filtered/custom study authoring UI and custom JavaScript scheduling remain. |
| RWKV history | Canonical fork RPC prepares replay rows, including IDs, preset routing, forget semantics and elapsed time. Model/precision are local per-profile settings. | Large-profile replay latency, persistent checkpoints and desktop cache/replay comparisons. |
| RWKV Instant | Native coordinator scores candidates; backend owns eligibility, ordering and intervening-review constraints. Candidate scoring uses the ordinary state; the displayed card uses its live same-day context. Keeps the stored FSRS fallback version. Import/answer/undo replay test passes. | Exact desktop parity for mixed presets, filtered decks, candidate refresh modes and nondefault refresh cadence. Unported refresh controls are read-only; their stored values are preserved. |
| RWKV Curve | Actual fork inference; answer intervals pass through `SchedulingStatesWithIntervals`. S90 metadata is written only for Curve, not Instant-only reviews. Backend grade-dependent retention targets and synthetic same-day kinds are included. | All filtered/relearning contexts, rescheduling and differential desktop parity. Unprepared Curve contexts pause reviews rather than substitute another scheduler. |
| Deck options | Native grouped editor uses actual backend configuration. Unknown/opaque settings are retained when saving. | More focused advanced workflows, shared-preset selection/creation, simulator/calibration integration with real collections. |
| Undo | Real backend undo, including scheduling and revlogs. RWKV state is derived again after changed history. | Multi-operation UI, redo and interrupted-session checks. Closing/exporting clears the in-memory undo stack as upstream does. |
| Sync | Actual fork sync client. Two local test clients pass full upload/download, media transfer, edits, review history, conflicting edits with distinct timestamps and note deletions against the fork server. Native login, Keychain token, cancellation and full-sync choices. | Live AnkiWeb, media conflicts/deletions and failure recovery acceptance. Same-second concurrent note edits reproduced divergence in the pinned backend; this remains unresolved. |
| Profiles and backups | Imports create separate profiles; profile switcher retains previous collections. Full-sync UI creates an Anki backup before replacement. Failed import does not replace a current profile. | Backup restoration UI and all full-sync failure modes. |
| Rendering runtime | Template JavaScript/CSS, per-template/mobile/dark body classes, media, front/back rendering, typed answers using the backend comparer, cloze typing and native answer controls. | Offline MathJax 3.2.2, cached LaTeX images and the fork’s image-occlusion canvas runtime are integrated; browser checks pass, with new iOS fixtures pending. Desktop reviewer hooks and image-occlusion authoring remain unported. |
| Statistics and tools | Entire shared backend service surface is callable through the bridge. | Native statistics, scheduling analysis, optimizer/calibration and all collection maintenance workflows. Backend exposure alone does not count as a finished UI feature. |
| Desktop add-ons | Their collection data can remain in Anki's native formats. | Python/Qt add-ons do not execute unchanged on iOS. Their individual behaviors require native ports or supported template JavaScript. |

RWKV filtered-deck contexts, unknown desktop template filters and custom scheduling scripts are preserved but cannot execute in this build. Such a
collection pauses before reviewing, with a clear explanation; the app must not
silently ignore scheduling behavior that affects future reviews.

## Local collection testing

Keep personal fixtures outside the public repository. Never open a live desktop
profile with the mobile backend. `snapshot-anki.py` copies source database/WAL
bytes using read-only file access, checks for concurrent changes, then recovers
SQLite on the copy. It excludes preferences, sync credentials and cache DBs.
It rejects media symlinks. If the source changes during capture, close Anki
and retry. No source database connection or source checkpoint is performed.

```sh
python3 scripts/snapshot-anki.py /path/to/Anki2/Profile /private/path/new-snapshot
ANKI_COMPAT_COLLECTION_DIR=/private/path/new-snapshot \
  swift test --filter AnkiCompatibilityTests/testPrivateCollectionCopyRoundTrip
```

The test makes another disposable working copy. It logs aggregate counts only;
no note contents, deck names, credentials or private media enter public CI.
The snapshot manifest records source hashes so they can be checked afterwards.
The `.colpkg` import path deliberately does **not** call `CheckDatabase`:
that command can repair/rewrite notes and should be an explicit user action.

## Reproducible checks

```sh
scripts/build-native.sh
swift test
scripts/test-sync.sh
cargo test --release --locked --manifest-path NativeEngine/Cargo.toml --features validation --test parity
```

The public simulator workflow exercises synthetic fixtures only. Passing its
tests establishes the specific tested flows, not every row in this inventory.
See [verification](verification.md) for recorded revisions and results.

# AnkiMobile rebuild

An editable native iOS flashcard app reconstructed from static analysis of the supplied AnkiMobile 25.09 IPA with [REA](https://github.com/morluto/rea), Ghidra, and Apple's compiled resource metadata.

The default app uses the complete shared backend from [JSchoreels/anki](https://github.com/JSchoreels/anki) for real Anki SQLite collections, package import/export, scheduling, rendering and sync. The native UI is editable UIKit. **Full feature compatibility and exact original-app visual fidelity are not established.** See the [compatibility inventory](docs/compatibility.md) and [fidelity evidence](docs/analysis.md).

## Current status — 2026-10-27

- Backend pin: `96af4ca9d214e71743b1186fd2ceab1a7e7e3f32`, verified against fork main on 2026-10-27. All five bundled model hashes matched the fork.
- **840 synthetic desktop/Swift RWKV cases passed**, covering five models, four precisions, Instant/Curve/both and fourteen scenarios: 20,093 answers and 100,553 comparisons, including exact recurrent-state hashes.
- [Final code CI](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/runs/40565026742) passed at `db7314a`: 56 core tests (four optional skips), neural vectors, both server sync tests, the iOS build and all nine iPhone UI tests.
- Incoming sync changes and full downloads invalidate cached RWKV state; the regression verifies newly downloaded candidates and the retained FSRS-6 fallback.
- The **local test environment has been deleted**: private reference Python environment, generated reference/Rust/Swift builds, temporary test collections and logs. Source, test scripts, checked-in evidence and static-analysis tools remain. The installed Anki and its data were not modified.

These are recorded results, not tests rerun after cleanup. Reproduction commands below recreate generated environments only when deliberately invoked. Remaining gaps include filtered RWKV reviews, custom scheduling scripts, desktop add-ons, some refresh modes and broader device/live-AnkiWeb acceptance. [Verification and scope](docs/verification.md).

## Build for iPhone or iPad

On a Mac with Xcode 16.4 (or newer) and an iOS simulator runtime installed:

```sh
brew install xcodegen protobuf
scripts/prepare-backend.sh
# Install Rust via rustup if needed: https://rustup.rs
xcodegen generate
open Flashcards.xcodeproj
```

The checked-in project is generated from `project.yml`. After changing target settings or adding source files, regenerate it:

```sh
brew install xcodegen
xcodegen generate
```

Select the `Flashcards` scheme and an iPhone/iPad simulator, then Run. For a physical device, select your own development team in Signing & Capabilities. The minimum deployment target is iOS 15.2.

[GitHub Actions](https://github.com/Ivan-Melck/ankimobile-rebuild/actions) builds and runs the native app on a hosted iPhone simulator. Each run uploads an `ios-simulator-results` artifact with screenshots, the `.xcresult` test bundle, generated Xcode project, build log, and simulator `.app`. A simulator `.app` cannot be installed on a physical iPhone.

For a device IPA, manually run the [iOS Device IPA workflow](https://github.com/Ivan-Melck/ankimobile-rebuild/actions/workflows/ipa.yml) against the desired app commit. It archives a Release arm64 app for iPhone/iPad on a disposable hosted Mac, verifies its device platform and bundled models, and uploads `ios-device-ipa` for 30 days. The artifact includes the IPA, source/backend revisions, tool versions and SHA-256 checksum. **The IPA is unsigned and must be signed and provisioned before installation.** It cannot be installed directly or submitted to TestFlight as produced. This build uses the app's pinned backend; it does not update the Anki fork or rerun the simulator/compatibility suites.

To reproduce on a Mac after the setup above, run `scripts/build-ipa.sh`. Outputs go under `build/ipa/`; move that directory aside before repeating a build. This does not recreate the Linux desktop-reference environment.

## Current collection path

- Real Anki collections and `.colpkg` / `.apkg` imports into separate profiles, with a profile switcher and collection export including media.
- Native deck hierarchy, full backend search, arbitrary note fields and preserved note types/templates.
- Backend card rendering, typed/cloze answers, template JavaScript, offline MathJax, cached LaTeX, image-occlusion viewing and local media. Native answer controls remain outside the document.
- Anki scheduling states, answer history, undo, burying and suspension.
- RWKV Instant candidate scores and Curve interval integration using canonical fork replay rows. Model and precision are local per-profile settings; Instant retains the selected fallback due-date engine.
- Native deck options, login/sync, Keychain tokens, cancellation, full-sync direction choices and local backups before full sync.

The original JSON-based local reconstruction remains under Collection Tools → Original Local Collection. Its Study Plan, simulation, calibration and CSV workflows are separate from real Anki collections. They are not automatically applied to imported Anki data. No existing JSON collection is replaced or silently migrated.

A historical private collection test passed a round trip of 8,478 cards, 6,402 notes, 10 note types, 13,876 media files and 31,230 canonical history rows. That disposable fixture is not retained locally or published. This checks preservation; it does not certify every review interaction. [Verification details](docs/verification.md).

## Make changes

| What to change | Location |
| --- | --- |
| Native screens and navigation | `ios/Flashcards/Controllers/` |
| Card appearance | Existing Anki note-type CSS/templates; viewer defaults in `ios/Flashcards/Support/AnkiCardWebView.swift` |
| Native appearance, profiles and preferences | `ios/Flashcards/Support/AnkiAppState.swift` |
| Real Anki backend bridge and collection operations | `Sources/FlashcardsCore/AnkiBackend.swift`, `NativeEngine/src/full_backend.rs` |
| Offline math / image-occlusion assets | `tools/reviewer/`, `ios/Flashcards/Resources/anki-*.js` |
| Typed-answer presentation and comparison | `Sources/FlashcardsCore/AnkiTypedAnswer.swift` |
| Native RWKV replay/score coordination | `NativeEngine/src/collection_rwkv.rs` |
| Shared Anki implementation | `Vendor/anki/` (pinned submodule; keep adapter changes outside it) |
| Native profile/media/auth support | `ios/Flashcards/Support/Anki*.swift` |
| Legacy JSON reconstruction | `CollectionStore.swift`, `StudyPlanning.swift`, `NativeEngine/src/lib.rs` |
| Build settings and targets | `project.yml`, `scripts/build-native.sh` |

The portable core is a standalone Swift package with no UIKit dependency. On a dedicated Mac or the hosted CI runner:

```sh
scripts/build-native.sh
swift test
scripts/test-sync.sh
cargo test --release --locked --manifest-path NativeEngine/Cargo.toml --features validation --test parity
```

On this Linux workstation, use the [audited comparison and test workflow](tools/comparison/README.md), including its rebuild prerequisites. `scripts/test-sync.sh` automatically confines its Linux server/clients to a private namespace, but requires the reference Python environment to have been rebuilt first. Do not run the fork against the installed desktop profile.

See [architecture](docs/architecture.md), [compatibility](docs/compatibility.md), [analysis and fidelity](docs/analysis.md), [verification](docs/verification.md), and [local REA workflow](docs/reproduce-analysis.md). No supplied IPA, original executable, extracted assets, recovered proprietary code or personal collection data is published.

## Simulator captures

The native collection path includes real Anki deck options, typed answers and image-occlusion viewing. Captures use public synthetic fixtures; see [verification](docs/verification.md) for source revisions and limits.

<img src="docs/screenshots/native-options.png" width="230" alt="Native Anki deck options"> <img src="docs/screenshots/native-typed-answer.png" width="230" alt="Native Anki typed-answer review"> <img src="docs/screenshots/native-review.png" width="230" alt="Native Anki card review">

The separate legacy JSON collection provides these planning screens; they do not schedule imported Anki collections. [Verification and test results](docs/verification.md) identify the tested revisions and capture dates.

<img src="docs/screenshots/study-plan.png" width="230" alt="Study Plan"> <img src="docs/screenshots/retention-comparison.png" width="230" alt="Compare retention against workload"> <img src="docs/screenshots/retention-target.png" width="230" alt="Choose a retention target">


Captured from the rebuilt app on an iPhone 16 Pro simulator.

<img src="docs/screenshots/decks.png" width="240" alt="Deck list in the rebuilt iOS app"> <img src="docs/screenshots/answer.png" width="240" alt="Study answer with interval previews in the rebuilt iOS app">

This derivative is licensed under GNU AGPL-3.0-or-later. See [third-party notices](THIRD_PARTY_NOTICES.md) for fork/model provenance.

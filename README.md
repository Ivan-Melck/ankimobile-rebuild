# AnkiMobile rebuild

An editable native iOS flashcard app reconstructed from static analysis of the supplied AnkiMobile 25.09 IPA with [REA](https://github.com/morluto/rea), Ghidra, and Apple's compiled resource metadata.

**Full compatibility is still being validated.** The default app now uses the complete shared backend from [JSchoreels/anki](https://github.com/JSchoreels/anki) for real Anki SQLite collections, package import/export, scheduling, rendering and sync. The native UI is editable UIKit. See the [compatibility inventory and remaining gaps](docs/compatibility.md); backend support does not establish complete native UI or desktop add-on parity. See [fidelity and evidence](docs/analysis.md).

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

## Current collection path

- Real Anki collections and `.colpkg` / `.apkg` imports into separate profiles, with a profile switcher and collection export including media.
- Native deck hierarchy, full backend search, arbitrary note fields and preserved note types/templates.
- Backend card rendering, typed/cloze answers, template JavaScript, local media and native answer controls.
- Anki scheduling states, answer history, undo, burying and suspension.
- RWKV Instant candidate scores and Curve interval integration using canonical fork replay rows. Model and precision are local per-profile settings; Instant retains the selected fallback due-date engine.
- Native deck options, login/sync, Keychain tokens, cancellation, full-sync direction choices and local backups before full sync.

The original JSON-based local reconstruction remains under Collection Tools → Original Local Collection. Its Study Plan, simulation, calibration and CSV workflows are separate from real Anki collections. They are not automatically applied to imported Anki data. No existing JSON collection is replaced or silently migrated.

A private collection test passed a round trip of 8,478 cards, 6,402 notes, 10 note types, 13,876 media files and 31,230 canonical history rows. Personal data is excluded from the repository and public CI. This checks preservation; it does not certify every review interaction. [Verification details](docs/verification.md).

## Make changes

| What to change | Location |
| --- | --- |
| Native screens and navigation | `ios/Flashcards/Controllers/` |
| Card font, spacing, colors | `ios/Flashcards/Resources/reviewer.css` |
| Theme and preferences | `ios/Flashcards/Support/AppModel.swift` |
| Real Anki backend bridge and collection operations | `Sources/FlashcardsCore/AnkiBackend.swift`, `NativeEngine/src/full_backend.rs` |
| Typed-answer presentation and comparison | `Sources/FlashcardsCore/AnkiTypedAnswer.swift` |
| Native RWKV replay/score coordination | `NativeEngine/src/collection_rwkv.rs` |
| Shared Anki implementation | `Vendor/anki/` (pinned submodule; keep adapter changes outside it) |
| Native profile/media/auth support | `ios/Flashcards/Support/Anki*.swift` |
| Legacy JSON reconstruction | `CollectionStore.swift`, `StudyPlanning.swift`, `NativeEngine/src/lib.rs` |
| Build settings and targets | `project.yml`, `scripts/build-native.sh` |

The portable core is a standalone Swift package with no UIKit dependency:

```sh
scripts/build-native.sh
swift test
scripts/test-sync.sh
cargo test --release --locked --manifest-path NativeEngine/Cargo.toml --features validation --test parity
```

See [architecture](docs/architecture.md), [compatibility](docs/compatibility.md), [analysis and fidelity](docs/analysis.md), [verification](docs/verification.md), and [local REA workflow](docs/reproduce-analysis.md). No supplied IPA, original executable, extracted assets, recovered proprietary code or personal collection data is published.

## Simulator captures

The fork integration adds these native planning screens. [Verification and test results](docs/verification.md) include the exact tested revision and remaining runtime limits.

<img src="docs/screenshots/study-plan.png" width="230" alt="Study Plan"> <img src="docs/screenshots/retention-comparison.png" width="230" alt="Compare retention against workload"> <img src="docs/screenshots/retention-target.png" width="230" alt="Choose a retention target">


Captured from the rebuilt app on an iPhone 16 Pro simulator.

<img src="docs/screenshots/decks.png" width="240" alt="Deck list in the rebuilt iOS app"> <img src="docs/screenshots/answer.png" width="240" alt="Study answer with interval previews in the rebuilt iOS app">

This derivative is licensed under GNU AGPL-3.0-or-later. See [third-party notices](THIRD_PARTY_NOTICES.md) for fork/model provenance.

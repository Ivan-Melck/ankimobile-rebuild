# AnkiMobile rebuild

An editable native iOS flashcard app reconstructed from static analysis of the supplied AnkiMobile 25.09 IPA with [REA](https://github.com/morluto/rea), Ghidra, and Apple's compiled resource metadata.

**This is an initial functional reconstruction, not a complete or pixel-verified AnkiMobile replacement.** It implements the main local flashcard flows. AnkiWeb sync, APKG/SQLite compatibility, FSRS, media, and many advanced Anki features remain unimplemented. See [fidelity and evidence](docs/analysis.md).

## Build for iPhone or iPad

On a Mac with Xcode and its iOS simulator runtime installed:

```sh
brew install xcodegen
xcodegen generate
open Flashcards.xcodeproj
```

Select the `Flashcards` scheme and an iPhone/iPad simulator, then Run. For a physical device, select your own development team in Signing & Capabilities. The minimum deployment target is iOS 15.2.

[GitHub Actions](https://github.com/Ivan-Melck/ankimobile-rebuild/actions) builds and runs the native app on a hosted iPhone simulator. Each run uploads an `ios-simulator-results` artifact with screenshots, the `.xcresult` test bundle, generated Xcode project, build log, and simulator `.app`. A simulator `.app` cannot be installed on a physical iPhone.

## Implemented

- Native deck list with new/review counts; create, rename, configure limits, and delete decks.
- Add/edit Basic, reversed, and Cloze notes with tags and HTML fields.
- WebKit card rendering, tap-to-reveal, four answer ratings with interval previews, keyboard review, undo, bury, and suspend.
- Search by text, `deck:"French Verbs"`, `tag:verbs`, `flag:3`, `is:new`, `is:learn`, `is:review`, `is:due`, `is:suspended`, `is:buried`; combine with spaces and negate using `-`.
- Daily limits, local learning/review queues, review history, and statistics.
- CSV/TSV import with quoted fields and duplicate detection; CSV export; full JSON collection backup/restore.
- System/light/dark appearance and adjustable card text size.
- Atomic persistent storage and validation before backup replacement.

Scheduling uses a small documented local approximation. **It does not reproduce Anki/FSRS intervals.** JSON backups are specific to this rebuild. CSV imports create Basic notes; CSV exports preserve fields and tags, not note types or scheduling.

## Make changes

| What to change | Location |
| --- | --- |
| Native screens and navigation | `ios/Flashcards/Controllers/` |
| Card font, spacing, colors | `ios/Flashcards/Resources/reviewer.css` |
| Theme and preferences | `ios/Flashcards/Support/AppModel.swift` |
| Card templates and cloze rendering | `Sources/FlashcardsCore/Rendering.swift` |
| Scheduling engine | `Sources/FlashcardsCore/Scheduler.swift` |
| Models and collection format | `Sources/FlashcardsCore/Models.swift`, `CollectionStore.swift` |
| Search / CSV | `Search.swift`, `DelimitedText.swift` |
| Build settings and targets | `project.yml` |

`ReviewScheduler` is injected into `CollectionStore`, allowing a replacement scheduler without changing screens. The core is a standalone Swift package with no UIKit dependency:

```sh
swift test
```

See [architecture](docs/architecture.md), [analysis and fidelity](docs/analysis.md), and [local REA workflow](docs/reproduce-analysis.md). No supplied IPA, original executable, extracted assets, or decompiled original code is published in this repository.

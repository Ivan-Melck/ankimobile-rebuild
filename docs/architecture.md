# Architecture

The app uses native UIKit table/navigation controllers and a WKWebView for the card document. This matches the architecture visible in the binary's class metadata. There are no third-party runtime dependencies.

`AppDelegate` opens one collection in Application Support and creates a shared `AppModel`. Controllers call `CollectionStore` and refresh their views after changes. `AppModel` holds preferences in UserDefaults. `Theme` centralizes the recovered deck counter colors.

The Swift package contains notes, cards, decks, review logs, scheduling, rendering, CSV, and search. A note generates one Basic card, two reversed cards, or one card for each distinct cloze number. Template-preserving edits retain scheduling; switching between cloze and non-cloze creates fresh cards.

Collection mutations copy the current document, apply changes, validate all references and values, save atomically, then publish the new in-memory document. Failed validation or I/O leaves the live collection unchanged. A recursive lock serializes access within one instance. Use one store instance for a file; separate processes writing that same file are unsupported.

This repository is designed for small local collections. It validates and rewrites the whole JSON document for every edit, and currently builds search/queue projections in memory. Large-collection performance and multi-process access are not validated; an Anki-compatible database-backed repository is a separate parity task.

Backups use a versioned `flashcards-collection` JSON document. Dates use Foundation's native Codable Date representation (seconds since 2001-01-01), preserving Double precision without epoch conversion. References, unique identifiers, supported schemas, finite intervals, note templates, and undo records are checked during restore. Review history survives note/deck deletion for historical statistics; those logs may reference deleted objects. Any ordinary collection edit clears the single-answer undo record.

Queues prioritize due learning/relearning, then due review, then new cards. Daily limits apply per deck using the local calendar's midnight rollover. Learning cards bypass daily limits. There is no learning-ahead window, hierarchical limit aggregation, sibling burying, or Anki's 4am rollover.

`ApproximateLocalScheduler` implements a deliberately small local policy. Again/Hard/Good on a new card schedule 1/6/10 minutes; a second Good graduates to one day; Easy graduates to four days. Review intervals scale by ease and lapses return to learning. Replace the `ReviewScheduler` implementation for a production scheduling engine.

Card fields are rendered as authored HTML. JavaScript and external resources are disabled in the isolated card WKWebView; embedded `data:` images/media and inline CSS are allowed. This differs from Anki's custom JavaScript and media behavior. Native study buttons stay outside the web document so their actions are independent of a card template.

CSV import is one transaction. Rows have Front, Back, and optional space-separated Tags columns. Duplicate detection compares exact front strings within the destination deck. The parser supports a UTF-8 BOM, CRLF, quoted newlines, and doubled quotes. A malformed row aborts the whole import. Export writes each note once; it does not export card scheduling or note types.

Build settings live in `project.yml`. XcodeGen generates the Xcode project; the app links the local package. Linux/macOS `swift test` checks the portable core; the macOS GitHub runner builds UIKit code and runs XCUITest against an actual iOS simulator. UI tests use a separate test collection and only reset it on an explicit launch argument.

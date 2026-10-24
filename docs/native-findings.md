# Native metadata findings

The independent byte reader in `scripts/inspect_objc.py` decoded all 150 entries in the supplied binary's Objective-C class list without a class-level parsing error. It found 626 instance-method records. These are runtime-visible Objective-C/Swift bridge methods, not an inventory of every Swift or Rust function. The binary has additional native code outside this list.

The complete class/method address report is in [native-inventory.json](native-inventory.json). It contains factual metadata, not original executable bytes or pseudocode.

Selected mappings from that metadata:

| Class | Selector | Implementation VA |
| --- | --- | --- |
| DecksViewController | `launchPreferences` | `0x10017b618` |
| DecksViewController | `launchStudy` | `0x10017d858` |
| DecksViewController | `launchSync` | `0x10017d9dc` |
| DecksViewController | `launchStats` | `0x10017ee08` |
| DecksViewController | `viewDidLoad` | `0x1001800dc` |
| DecksViewController | `tableView:cellForRowAtIndexPath:` | `0x100181b94` |
| DeckCell | `toggleSectionShown` | `0x100101584` |
| DeckCell | `setSelected:animated:` | `0x100101614` |
| DeckCell | `layoutSubviews` | `0x1001016fc` |
| StudyViewController | `handleKeySpace` | `0x100099438` |
| StudyViewController | `onReturn` | `0x100099704` |
| StudyViewController | `handleKey1` | `0x10009a0f8` |
| StudyViewController | `handleUndo` | `0x10009a2e8` |

The study class also exposes handlers for keys 2–4, flags 1–7, voice recording/replay, card/note bury and suspend, marking, add/edit, browsing, deck navigation, and redo. The selectors demonstrate that those handlers exist; they do not establish every precondition or resulting behavior. Pure Swift actions can sit behind short Objective-C trampolines.

REA's default Ghidra analysis was interrupted after several minutes because the Objective-C message analyzer was decompiling many functions and reporting pointer/p-code errors. A focused pass disables `Objective-C Message Analyzer` and `Decompiler Switch Analysis`, retaining ordinary code analysis and explicit per-function decompilation. Raw replies and analysis logs are stored locally under `analysis/evidence/native-focused/`.

This file's address table comes from the supplemental reader, not a fabricated REA Evidence record. The focused pass completed successfully. Its overview identified 40341 procedures and 28821 defined strings; these are engine inventory counts rather than a claim of full semantic recovery. REA `analyze_function` returned pseudocode, assembly, call/reference data and explicit coverage information for eight bridge methods and six helpers. Selected conclusions:

- Deck selection calls the superclass `setSelected:animated:` implementation. The wrapper itself adds no custom selection behavior (local `deck-cell-selection.json`, evidence `ev_f1cee254484a8a8f1ee1f6bb3d248b550267d0c41543ad32b5314062bf0a4aa0`).
- Deck layout delegates to `0x100101668`, which updates the `leadingSpace` constraint from an indentation value. This supports the hierarchy/indentation interpretation; the exact multiplier remains uncertain due to decompiler calling-convention artifacts (`deck-layout-body.json`).
- The row helper loads `DeckCell` from a nib when it cannot dequeue one, attaches its delegate, hides the section button for leaves, chooses plus/minus for branches, sets text/count colors, and requests display (`deck-row-body.json`, evidence `ev_97337500969963cb2b0cadb53398649913cf784f005dbf3a03e9a025ada3f3d4`).
- The view-load helper installs a refresh control and two navigation items on each side, and REA recovers the Swift string literals `help`, `settings`, and `chart`. This independently corroborates the four-action header described in the official manual (`deck-load-body.json`, evidence `ev_276b2b9f41819a12656349d2b65253a2bd009594cdd50c150493b1342a7da2bb`).
- Collapse locates a deck from the cell's index path, updates the deck tree/sections, reloads the table and schedules a MainActor task. Persistence and async closure internals were not fully traced (`deck-collapse-body.json`).
- Space/Return handlers schedule work on Swift's MainActor. Return checks typed-answer mode first. `handleKey1` is a one-instruction branch to `0x1000aa40c`, so its entire behavior cannot be inferred from the wrapper alone (`study-space.json`, `study-return-body.json`, `study-answer1.json`).

REA's dispatch inventory is explicitly **partial**: at its 20,000-name bound it found 118 class symbols and 225 Swift symbol records, while declaring runtime ivar layouts, native relative pointers and Swift dispatch tables unsupported in that inventory. Its symbol-only dispatch result did not decode method implementations. The supplemental byte reader supplied method addresses; explicit Ghidra analysis then recognized the selected method entries. The 150/626 byte-reader counts and 118/225 symbol counts describe different coverage and must not be conflated.

No original pseudocode or extracted code is published here. Decompiler output contains unresolved Swift register conventions and warning annotations; high-level conclusions above are restricted to observable calls and metadata.

## Editor and browser pass

A second focused pass follows editor, browser, and web-message methods into their Swift helpers. Local evidence is under `analysis/evidence/native-editor-browser/`. The supplemental class inventory shows 44 bridge methods on `EditViewController` and 20 on `SearchViewController`.

| Flow | Bridge entry | Helper followed | Observation |
| --- | --- | --- | --- |
| Save note | `0x1001588a4` | `0x100158650` | Runs `anki.removeFocus()` through WKWebView's JavaScript completion API before the save completion path |
| Editor layout | `0x100151f30` | `0x100151448` | Builds a horizontally scrolling native editing toolbar and registers keyboard observers |
| New cloze number | `0x100155a60` | `0x1001551f4` | Constructs an `anki.wrap` call containing cloze delimiters and a number, then evaluates it in the editor web view |
| Change deck | `0x10016b0b8` | Async task boundary | Dispatches onto MainActor; selection internals remain outside this trace |
| Select browser row | `0x1000de480` | `0x1000e1588` | In selection mode, toggles the card ID in the selected set and reloads that row; otherwise schedules a per-card task |
| Browser row display | `0x1000dea00` | `0x1000e1a4c` | Reuses a custom SearchCell or creates one using database state, then asynchronously populates it by card ID |
| Submit browser search | `0x1000ded78` | `0x1000e1cd8` | Resigns the search field's first responder and schedules a search task |
| Browser actions | `0x1000dde18` | `0x1000ddb98` | Checks the selected-item count, takes an alert path for an empty selection, otherwise schedules the action task |
| Editor web message | `0x1002d70ac` | `0x1002da430` | Reads the WKScriptMessage body as a string, decodes UTF-8 JSON into a dictionary, and forwards it to the editor |

Selected evidence identifiers: save helper `ev_5172da2d54b370358a894271dea93dabd4ad7e29fe7060e74864b2dfcc343d70`; browser selection `ev_7cb181f5ce28821c455699dec4deb6353c10c340ddfbe28f04e99a58c6d9adfc`; JSON message handling `ev_9c07600eade2760599b94e62de96c70161b7825ad485b223cfc6d431419866af`.

This establishes that the original editor is a rich web-backed editing surface controlled by native actions. The rebuild's UITextView fields accept authored HTML and support the implemented note types, but do not reproduce that rich toolbar, DOM selection, media insertion, or JSON bridge. The current browser likewise implements ordinary single-card editing/search and swipe actions, while the original has a separate bulk-selection mode. These are specific behavioral gaps, not cosmetic differences.

The save completion at `0x10015876c` schedules another MainActor task. The storage commit itself was not traced through all async continuations, so the native save trace must not be treated as evidence of the original app's transaction guarantees.

The editor dictionary dispatcher at `0x10016190c` reads keys including `scheme` and `args`, and REA's literal recovery identifies messages and state keys for fields, tags, focus, bold/italic/underline, HTML mode, note type and deck changes. This corroborates the native-toolbar/web-editor bridge described above. Literal recovery also emits duplicates and some implausible register-derived strings; those were excluded from the report.

Across both passes, **35 selected functions** were analyzed. The expanded local evidence bundle contains **38 records**, including the overview/dispatch records and the earlier results loaded from the snapshot. The saved `anki-expanded.snapshot` retains the analyzed results for continuation. The 35-function count includes short bridges and helpers; it is not 35 complete end-to-end features.

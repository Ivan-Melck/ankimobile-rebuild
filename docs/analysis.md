# Analysis and fidelity

## Subject and method

The supplied app is AnkiMobile 25.09, bundle version `250900.1`, identifier `net.ichi2.anki`, minimum iOS 15.2. The native executable is a Mach-O arm64 binary with SHA-256 `591fcf587944031435c11cd977dd26b00306aaeb4854e1bfe17d54d233fdd459`. Its metadata identifies a device build against iOS 18.2 / Xcode 16.2.

Local analysis uses REA 6.7.0 with its artifact graph provider and Ghidra 12.1.4. Ghidra 12.2 was rejected by REA's version guard; the compatible version was installed locally. LLVM Mach-O headers, Objective-C metadata, and literal resource inspection supplement REA evidence. Decompiler output is an approximation, particularly for Swift runtime conventions and chained pointers, and does not recover the original Swift source project.

All evidence paths below are relative to the local `analysis/evidence/` folder, which is intentionally excluded from the public repository. This report publishes observations and implementation decisions, not original app code or assets.

## Recovered observations

| Observation | Evidence | Confidence / limits |
| --- | --- | --- |
| Native UIKit deck, study, search, editing, configuration controllers | `strings.txt`, supplemental `objc-methods-independent.json` | Strong class/outlet evidence; dynamic interactions still need device observation |
| Study screen contains remaining counts, answer stack, tool buttons, scratchpad and auto-advance state | `StudyViewController` stored-property and selector strings | Strong existence evidence; no claim that all are rebuilt |
| Card display uses HTML/JS plus native controls | Native `anki.showQuestion`, `bridgeCommand`, DOM-ready/state-mutation strings; shipped reviewer resources | Strong architectural evidence |
| Deck row uses two right-aligned review/new counters | REA `resource-interface-builder.json`, `DeckCell.nib` UILabels `Rev` and `New` | Exact labels, colors, 51pt design row height and font metadata recovered; runtime counts/grouping inferred |
| New counter RGB = (36, 111, 225) / 255 | Nib UIColor object 45 | Exact archived value |
| Review counter RGB = (0, 0.6520253057, 0.06549999957) | Nib UIColor object 41 | Exact archived value |
| Body font archive is SFUI Regular size 14; expand/collapse button uses SFUI Bold size 15 | Nib UIFont objects 38 and 23 | Exact archive values; dynamic-type behavior not verified |
| Deck rows have a disclosure accessory and a `toggleSectionShown` action | REA nib outlet/action graph | Exact archive relationships; initial rebuild does not implement hierarchy collapse |
| Web routes include card info, congrats, deck options, statistics, importing, note-type changes and more | REA Svelte active route evidence plus literal node inspection | Shipped route presence does not prove every route is reachable on iOS |
| Backend includes Rust/rslib and FSRS-related functionality | Backend-generated types and strings | Confirms backend complexity; local scheduler is an approximation |
| Original supports APKG/COLPKG/CSV/TSV/ZIP file associations, `anki:` URLs and home-screen shortcuts | REA plist evidence and `resource-observations.json` | Exact declared capabilities; rebuild only supports its own JSON and CSV/TSV through Tools |
| Apple asset catalog cannot be decoded here | `resource-asset-catalog.json` | REA reports macOS `assetutil` prerequisite; no icon or asset extraction claim |

The full native import and targeted decompilation results are recorded separately during the continuation pass. See `native-findings.md` for the outcome and any analysis limitations.

## Implemented fidelity

The rebuild follows the recovered native navigation/table + web card structure and uses the recovered counter colors. Deck listing, note editing, search, review/reveal/rating, undo, bury, suspend, local statistics and preferences have independent implementations. Source is organized for editing rather than following opaque decompiler output.

The official [deck-list manual](https://docs.ankimobile.net/deck-list.html) and [study-screen manual](https://docs.ankimobile.net/study-screen.html) supplement the binary evidence: the deck header has help/statistics/browser/preferences actions, and study counts are shown at the bottom with interval labels on rating buttons. Those behaviors are implemented, along with card tap reveal and Space/1–4 keyboard controls. The manuals may describe versions newer than the supplied IPA.

No original runtime screenshots were available. The original device IPA cannot be run in an iOS simulator simply by resigning it or changing arm64 architecture; its platform and dependencies target physical devices. GitHub's macOS runner can compile and run the rebuild in a simulator, capture screenshots, and verify flows. It cannot establish a direct visual match to this IPA. Layout, icon choices, screen transitions, and timing are therefore provisional.

## Outstanding parity work

- Compare every screen and gesture with the original on a physical iOS device; validate iPad/landscape/dynamic type/accessibility layouts.
- Integrate Anki-compatible collection storage, package/media import/export, production scheduler/FSRS, and custom note templates.
- Implement AnkiWeb synchronization, profile switching, automatic backups, media playback/recording, image occlusion and typed answers.
- Implement deck hierarchy/collapse/aggregate limits, filtered/custom study, card flags UI, browser bulk actions, richer stats, scratchpad, auto advance, gestures and gamepad shortcuts.
- Match all preferences, localization, error recovery, and background/rollover behavior.

These are material gaps. The current app should not be treated as a drop-in replacement for an existing Anki collection.

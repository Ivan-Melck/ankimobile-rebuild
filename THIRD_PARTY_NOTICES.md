# Scheduling engine provenance

The native inference integration is based on [JSchoreels/anki](https://github.com/JSchoreels/anki), commit `96af4ca9d214e71743b1186fd2ceab1a7e7e3f32` (24 October 2026). Anki and this derivative are distributed under **GNU AGPL version 3 or later**; see [LICENSE](LICENSE). Original copyright and license headers are retained.

- `NativeEngine/src/rwkv/` is the fork’s Rust inference implementation, including its original test and benchmark sources. The Anki host imports in `engine.rs` and `api.rs` are adapted to `NativeEngine/src/compat.rs`; the neural computation is retained. One simulator guard keeps new cards available for introduction, rather than postponing their first review using an untrained recall curve. An optional validation module checks the published small-model vectors. Benchmarks are not part of the iOS build.
- `Sources/FlashcardsCore/Resources/RWKV/` contains the fork’s F32 Legacy, SM40v2, SM36, SM55 and SM56 weights. SM56 SHA-256: `4388a5d11d4ebae5b29d63dc1b49eac3c537b1514673d89bd31ae944db226750`.
- FSRS is pinned to the fork’s exact `fsrs-rs` revision `0a5737406a0c5c7a5259b144738cbe4a0b649d76`, under BSD-3-Clause. Cargo fetches its source and license from [open-spaced-repetition/fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs/tree/0a5737406a0c5c7a5259b144738cbe4a0b649d76).
- Other Rust dependencies and their exact versions are recorded in `NativeEngine/Cargo.lock`. License texts and source for dependencies can be obtained from their Cargo package repositories.

The supplied proprietary AnkiMobile binary, extracted UI assets, and recovered proprietary source are not included. This integration vendors the public fork’s scheduling code, not its Qt UI or the supplied iOS binary.

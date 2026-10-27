# Protect the user's installed Anki

The user requires the experimental fork to remain isolated from local Anki.

- Never install this fork over system/user Anki, launch `just run` against the
  user's home, stop the installed Anki process, or change its preferences,
  profiles, credentials or collection files.
- Build the original reference with the vendor's `just build` recipe. Its
  Python environment belongs in `Vendor/anki/out/pyenv`; do not install its
  dependencies into the system/user Python environment.
- On this Linux workstation, execute desktop-reference comparisons through
  `tools/comparison/run.py`. It requires audited bubblewrap filesystem,
  process and network isolation. Never bypass a failed isolation audit.
  Built local test commands can use `tools/comparison/isolated_command.py`.
- The comparison harness uses generated synthetic collections only. Hosted
  iOS CI uses its disposable fixtures and simulator; it has no user profile.
- If private compatibility data is needed, use only a disposable copy made
  under the user's authorization. Never open the live source collection in
  SQLite or repair/export it in place. Never upload private collections,
  media, logs containing note contents, or credentials to the public repo/CI.

See `tools/comparison/README.md` for the isolation and verification workflow.

## Current validation and cleanup state

Recorded on 2026-10-27: the 840-case synthetic matrix passed; iOS source
`db7314a998b705db47f50c27184d8497751b39eb` passed core/vector checks, both
sync tests and nine UI tests. See `docs/verification.md` for exact scope and
remaining gaps; do not imply universal Anki/fork compatibility.

At the user's request, the private fork environment, generated builds and
temporary test collections/logs were deleted after validation. Source, scripts,
sanitized evidence and static-analysis tools remain. Documentation/review work
must not recreate the test environment or access the installed Anki. If future
implementation requires tests, explicitly describe the rebuild and retain the
mandatory runtime isolation; never assume prior binaries or fixtures exist.

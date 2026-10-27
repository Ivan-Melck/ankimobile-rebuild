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

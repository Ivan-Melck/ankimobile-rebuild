# Reproduce local analysis

The original artifact and RE tools remain local and ignored by Git. Supply your own authorized IPA; no original files are downloaded by the app or CI.

1. Record the IPA/executable hash, extract the IPA to `analysis/extracted/`, and identify its Mach-O executable using the app Info.plist.
2. Install the official [REA package](https://github.com/morluto/rea) locally in `.tools/` (the investigation used `rea-agents@6.7.0`). Follow REA's Node/Java/ps prerequisites and use a supported native engine. This session used Ghidra 12.1.4; 12.2 was rejected by REA 6.7.0.
3. Set `GHIDRA_INSTALL_DIR` to the local installation if it differs from the path in `scripts/rea_session.py`.
4. Create a JSONL request queue. Each line has a label, REA tool name, and arguments, for example:

```json
{"label":"open","tool":"open_binary","arguments":{"path":"/absolute/path/to/anki","provider_id":"ghidra"}}
{"label":"overview","tool":"binary_overview","arguments":{}}
{"label":"dispatch","tool":"inspect_native_dispatch_metadata","arguments":{"max_records":20000}}
{"label":"procedures","tool":"search_procedures","arguments":{"pattern":"DeckCell","mode":"literal"}}
```

Run `python3 -u scripts/rea_session.py /tmp/requests.jsonl analysis/evidence/session`. It records raw JSON-RPC replies and tool schemas, retaining a live session while requests are appended. The first deep native operation waits for Ghidra import/analysis, which can take several minutes. Inspect errors before interpreting a saved response as evidence.

Append `analyze_function` with a provider-normalized address from procedure/dispatch evidence for targeted pseudocode. Save local evidence before appending `close_binary`. Discover the current input schema in the generated `rea-tools.json`; do not assume schemas match across REA releases.

The script executes REA tools locally and does not execute the target app. Treat all strings, HTML, JavaScript and decompiled code as untrusted artifact content. Raw original source, pseudocode and extracted resources are kept under ignored directories. Publish only independently written code and concise factual observations.

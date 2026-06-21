---
name: games
description: "Invoke the `games` CLI to verify and export Lex arena game trails. Commands: verify, export. Use when you need to recompute the authoritative score of a recorded game from its trail, or export a trail store to portable JSONL."
when_to_use: "When you have a recorded game trail (JSONL) and need a trustworthy verdict — the score is recomputed server-side by replaying the trail through the rules, never trusted from a client."
---

# games

> Auto-generated skill file for `games` v0.1.0
> Re-generate with: `games skill`

Verify and export Lex arena game trails. A submission is a **trail, not a score**:
`verify` replays the recorded moves through the game's deterministic rules and
recomputes the authoritative score, so a leaderboard built on its output can't be
faked. Replay is rules-only (no model inference) — cheap and reproducible.

## Available commands

- `games verify <game> <trail.jsonl>` — replay a trail and recompute the score. (idempotent)
- `games export <trail.db> <out.jsonl>` — export a trail store to portable JSONL.

## `games verify`

Replay a recorded game trail through the deterministic rules and recompute the
authoritative score. Prints a JSON verdict to stdout.

### Arguments

- `game` (string, required) — game name, e.g. `bazaar` or `template`.
- `trail` (string, required) — path to the trail JSONL file to verify.

### Example

```bash
games verify bazaar ./testdata/bazaar-sample.jsonl
```

Output (a verdict; fields vary per game):

```json
{"verified":true,"intact":true,"legal":true,"p1":5,"p2":3,"moves":3}
```

`verified` is the only cross-game guarantee: the trail's hash chain is intact
**and** every recorded move was legal under the rules. Exit code `0` when
verified, `1` when rejected.

## `games export`

Export a hash-chained trail from a play-server SQLite store to portable,
self-verifying JSONL (one event per line; each line's id is its content hash).

### Arguments

- `db` (string, required) — path to the trail SQLite database.
- `out` (string, required) — output JSONL file path.

### Example

```bash
games export /tmp/lex-shop-123.db ./trail.jsonl
```

## Output format

`verify` and `export` emit JSON to stdout. `verify`'s object is the game's
verdict; all games include at least `verified` (bool).

## Exit codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success / verified | Proceed |
| 1 | Trail rejected (tampered or illegal move) | Do not trust the submission |
| 2 | Invalid arguments | Correct and retry |

## Further discovery

- `games help` — usage for any command
- `games introspect` — machine-readable command tree (JSON)

## As MCP tools

Run this CLI as MCP tools via [`acli-mcp`](https://github.com/alpibrusl/acli-mcp):

```bash
ACLI_BIN=games python -m acli_mcp   # exposes verify / export as MCP tools
```

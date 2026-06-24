---
name: games
description: "Invoke the `games` CLI to verify, export, and rank Lex arena game trails. Commands: verify, export, leaderboard, season. Use when you need to recompute the authoritative score of a recorded game from its trail, rank a field of policy rollouts, or update an ELO season — all from trails, never trusting a client-reported score."
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
- `games leaderboard <manifest.json>` — rank a field of robot-policy run trails by verified score. (idempotent)
- `games season <standings.json> <round.json>` — update head-to-head ELO ratings over a round; prints the new standings. (idempotent)

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

## `games leaderboard`

Rank a whole field of robot-policy run trails by their **verified** score (each
trail is replayed through the rules; a tampered or over-grant trail is
disqualified to the bottom, never trusted). Prints one ranked JSON object.

### Arguments

- `manifest` (string, required) — path to a JSON array of `{ "label":.., "trail":.. }` entries.

### Example

```bash
games leaderboard ./testdata/policy/leaderboard.json
```

## `games season`

Like `leaderboard`, but ratings **persist across rounds**: each round plays a
deterministic round-robin (the higher verified score wins each pairing) and
updates every policy's ELO. Reads the prior standings + this round's manifest and
prints the new standings — redirect stdout to persist, so a season is a chain.
A missing standings file starts everyone fresh at 1500.

### Arguments

- `standings` (string, required) — path to the prior standings JSON (missing/empty = fresh season).
- `manifest` (string, required) — path to this round's manifest (same shape as `leaderboard`).

### Example

```bash
games season standings.json round1.json > next.json   # round 1 (fresh)
games season next.json     round2.json > standings.json
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
ACLI_BIN=games python -m acli_mcp   # exposes verify / export / leaderboard / season as MCP tools
```

# Adding a game

A lex-game is **cheat-resistant by construction** and **verifiable**: a submission
is a *trail* (the recorded moves), not a score. The server replays the trail
through your deterministic rules and recomputes the score — it never trusts a
score from the client.

You implement a small amount; the framework gives you the rest.

| the framework provides (don't rewrite) | you implement per game |
|---|---|
| `gate()` — capability + turn enforcement | the **rules** (pure: legality, value/score) |
| match-bound signed tokens (`issue_match_token` / `match_token_side`) | a **replay** over the recorded trail |
| `record()` — hash-chained lex-trail | a **verdict** (verified? + the score) |
| `verify_log` / `all_events` — replay plumbing | the **play surface** (server skills, UI, bot) |
| the hosted arena: leaderboard, seasons, worker | — |

## 1. The verifier (this repo) — start from the template

Copy [`src/games/template.lex`](../src/games/template.lex) → `src/games/<yourgame>.lex`
and replace the rules. A game's verifier is **four pure pieces**:

1. **rules** — e.g. `value(i)`, what's legal. Pure + deterministic.
2. **replay state** + `step(state, line)` — apply one recorded trail line; track
   `legal` (rules held) and `intact` (`tf.line_intact` — the content-addressed id
   still recomputes, i.e. no tampering).
3. **`verdict(lines)`** — `verified = intact and legal`, plus `p1` (the
   contestant's score the leaderboard ranks) and `p2` (opponent).
4. **`verdict_json(v)`** — serialize it.

Then register it in [`src/arena/verify.lex`](../src/arena/verify.lex): add an
`if game == "<yourgame>"` branch (copy the `template` branch). Done — the verifier
is what the hosted worker runs over an uploaded trail.

**Determinism is the one hard rule.** The verifier must recompute the same result
every time from the same trail. So: record concrete moves (and any seed) in the
trail; no wall-clock, no randomness outside a recorded seed. Hidden information →
use commit-reveal (record a hash of the move, reveal later). This is what makes
the score *provable* rather than *claimed*.

## 2. The play surface (today in [lex-robot](https://github.com/alpibrusl/lex-robot))

Where the game is actually played and the trail is produced. Use **Bazaar Draft**
as the full reference (`sidecar/sim_sidecar.lex` shop_*, `examples/bazaar_game_web.html`,
`examples/bazaar_bot.lex`). Three parts:

- **Server skills** — `join` (issue a match-bound token via `game.issue_match_token`),
  `state`, `move` (gate via `game.match_token_side` + `game.gate`, apply rules,
  `game.record` the move). This is the authoritative game loop.
- **Web client** — a small page that calls the skills; players act in-browser.
- **A2A bot** (optional) — an independent agent that plays a side over A2A, so the
  capability gate is proven against an outside agent, not just the UI.

To enter the hosted arena, a player exports the recorded trail to JSONL
(`src/arena/export.lex`) and submits it; the worker runs your `verify.lex`.

## 3. Put it on the leaderboard

Seed an arena episode (see loom-cloud) with `verifier = '<yourgame>'` and
`scenario_id = '<yourgame>'` (the verifier picks the game by `scenario_id`). The
leaderboard renders a **Score** column for games episodes and ranks by the
verifier's recomputed score.

## 4. Test

```sh
# rules compile
lex check src/games/<yourgame>.lex

# verify a trail end-to-end (0 = verified, 1 = rejected)
lex run --allow-effects io src/arena/verify.lex verify '"<yourgame>"' '"trail.jsonl"'

# tamper any field → the content-addressed id breaks → rejected
sed 's/SomeValue/Tampered/' trail.jsonl > /tmp/bad.jsonl
lex run --allow-effects io src/arena/verify.lex verify '"<yourgame>"' '"/tmp/bad.jsonl"'
```

## What fits (and what doesn't)

✅ Turn-based, server-authoritative, deterministic: board / card / draft /
strategy / hidden-info (commit-reveal) / multi-player. Adding one is a few
hundred lines.

⚠️ Real-time / action / physics: **wrong tool.** lex-games is a governance +
verifiability layer, not a game engine (no rendering, physics, or tick loop). The
replay-verify model assumes discrete, deterministic moves. Lean "complex" toward
*strategic depth* and *AI-agent competition* — the parts only this makes provably
fair — not graphics.

Any client works (web, CLI, bot, or an AI assistant via MCP) — the verifiable
backend is client-agnostic.

# lex-games

[![CI](https://github.com/alpibrusl/lex-games/actions/workflows/ci.yml/badge.svg)](https://github.com/alpibrusl/lex-games/actions/workflows/ci.yml)

**Part of the [Lex](https://lexlang.org) project.** Capability-gated, verifiable
turn games — and the **arena verifier** that scores them.

A turn game in Lex is *cheat-resistant by construction* and *verifiable*:

- **`gate()`** — a connection holds a signed Ed25519 token for exactly one side;
  it cannot move as another side, nor out of turn. The illegal call is refused
  before any game logic runs.
- **match-bound tokens** (`issue_match_token`/`match_token_side`) — bound to a
  match id + expiry, so a token can't be replayed across matches.
- **`record()` + the arena verifier** — every move is appended to a hash-chained
  lex-trail; a submission is a **trail, not a score**. The verifier replays the
  recorded moves through the deterministic rules and **recomputes the
  authoritative score** — the score is never trusted from a client.

## Why a separate, lean repo

This is the **verifier** the hosted arena runs. A submission is a JSONL trail; the
arena's verify-worker clones a verifier repo and runs its `verify.lex` over the
upload. Keeping lex-games small (std + lex-trail only) means that image stays
small — it doesn't drag in the robot/physics tree of where the games are *played*.

## The model: a submission is a trail, not a score

```
play (local, your LLM/agent picks moves)  → records a lex-trail
        │  the only expensive step — inference is local, BYO-key
        ▼
export → portable JSONL trail  (src/arena/export.lex)
        ▼
upload the trail
        ▼
verify (server) → replay moves through the rules, recompute score
        rules-only — NO LLM — CPU-cents   (src/arena/verify.lex)
```

Replay re-runs only the deterministic referee, so it costs CPU-cents regardless of
how fancy the agent was. (Honest caveat: replay proves a *rule-legal result*, not
*who/what authored it* — model attribution is self-reported; overfitting is
defended with gated scoring seeds.)

## Try the verifier

```sh
# verify a submitted trail (the same binary the hosted worker runs):
lex run --allow-effects io src/arena/verify.lex verify '"bazaar"' '"testdata/bazaar-sample.jsonl"'
#   {"verified":true,"intact":true,"legal":true,"p1":35,"p2":30,"moves":4}   (exit 0)

# tamper any field → the content-addressed id breaks → rejected:
sed 's/Teapot/Teap0t/' testdata/bazaar-sample.jsonl > /tmp/bad.jsonl
lex run --allow-effects io src/arena/verify.lex verify '"bazaar"' '"/tmp/bad.jsonl"'
#   {"verified":false,"intact":false,...}   (exit 1)
```

Or via the launcher (JSON-quotes args for you): `cli/games verify bazaar testdata/bazaar-sample.jsonl`.

## Play / verify as MCP tools

The `cli/games` launcher is [ACLI](https://github.com/alpibrusl/acli)-compliant —
`games introspect` emits a machine-readable command tree and `games skill` emits a
[SKILL.md](SKILL.md). Point [`acli-mcp`](https://github.com/alpibrusl/acli-mcp) at
it and the commands become MCP tools an agent can call:

```sh
ACLI_BIN=games python -m acli_mcp      # exposes verify / export as MCP tools
```

`verify`'s stdout is the JSON verdict (the trailing exit-code line `lex run`
prints is stripped by the launcher), so the tool result is the verdict object and
the 0/1 verified/rejected signal is the process exit code.

## Layout

```
src/
  lex_games.lex          the framework: gate / match-bound tokens / record / verify_log / all_events
  games/bazaar.lex       Bazaar Draft rules + replay (the deterministic referee)
  games/robot_task.lex   Robot Task verifier — folds a lex-robot run trail → scored verdict
  games/template.lex     TEMPLATE — copy this to start a new game's verifier
  arena/trail_file.lex   portable JSONL trail format (self-verifying; matches the finance arena)
  arena/export.lex       sqlite lex-trail → JSONL (client side, after a local match)
  arena/verify.lex       JSONL trail → verdict (server side: integrity + replay + score)
cli/games                thin launcher
docs/ADDING_A_GAME.md    how to add your own game (the game contract + steps)
testdata/                a real sample trail (CI verifies it)
```

## Add your own game

See **[docs/ADDING_A_GAME.md](docs/ADDING_A_GAME.md)**. In short: copy
`src/games/template.lex`, implement four pure pieces (rules · replay · verdict ·
verdict_json), register a branch in `src/arena/verify.lex`. The framework handles
the capability gate, signed tokens, the hash-chained trail, and the leaderboard.

## Where the games are *played*

The interactive clients + the play server live in
[lex-robot](https://github.com/alpibrusl/lex-robot) (`examples/*_web.html`,
`sidecar/sim_sidecar.lex`) — tic-tac-toe, Bazaar Draft, Consent Match, Charger
Duel, Co-op Infiltration, Strategy Football, and the Robot Arena bridge. This repo
is the framework + the verifier those produce trails for. (Follow-up: lex-robot
will depend on this package instead of vendoring `lex_games.lex`.)

## Verifiable robot benchmarks

`games/robot_task.lex` extends the "trail, not score" model to **robots**. A
[lex-robot](https://github.com/alpibrusl/lex-robot) task runs as a supervised
guest (lex-os#47, *robot-in-box*) and emits a hash-chained lex-trail of its
Perceive→Plan→Execute→Verify loop plus any supervisor `killed` event. That trail
*is* a submission: the verifier re-derives every line's content id, checks the
chain links head-to-tail, and folds the recorded outcomes into an authoritative
score (goal reached · grant refusals · budget kills · actuation count). So a
robot run becomes a **cheat-resistant, replay-verifiable benchmark** — same
referee guarantee as the turn games.

```bash
# export a recorded run (sqlite lex-trail → JSONL), then verify it:
lex run --allow-effects io src/arena/verify.lex verify '"robot_task"' '"testdata/robot_task-sample.jsonl"'
# → {"verified":true,"intact":true,"linked":true,"goal_met":true,...,"score":148}
```

Depth note: today's lex-robot payloads carry a `detail` summary, so the verifier
checks tamper-integrity + chain linkage at full strength and scores from
outcomes. Re-deriving *grant legality* (that each move's `(skill, args)` sat
inside the granted workspace/force) needs lex-robot to record the structured
lex-os `SkillOutcome` in the payload — the natural next step; the verdict shape
already leaves room for it.

## Status

Verifier + Bazaar Draft + Robot Task, verified end-to-end. More games' replay
rules and a `verify.lex` dispatch per game land as each is wired into the hosted
arena.

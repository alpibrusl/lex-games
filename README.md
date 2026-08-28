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
  games/bazaar.lex       Bazaar Draft rules + replay (2-player deterministic referee)
  games/nbazaar.lex      N-player Bazaar — replay an N-seat match trail → per-seat scores
  games/gbazaar.lex      Governed Bazaar — replay a spend trail → compliance verdict (no overspend / rogue merchant)
  games/consent.lex      Consent — replay an a2p-style consent trail → compliance verdict (no leaked scope)
  games/ops.lex          Agent-ops — replay a tool-use run → compliance verdict (no rogue tool / over budget)
  games/capability.lex   Capability — one token over data AND money → unified verdict (no leaked scope / no overspend)
  games/notary.lex       Stamp of Destiny — replay a chit-stamping run → verdict (no unlicensed category stamped)
  games/wedding.lex      The Wedding Broker — replay a negotiation run → verdict (no over-budget / over-slot ruling)
  games/werewolf.lex     Werewolf — replay a social-deduction game → verdict (roles committed up front, no forged kill/inspect/lynch)
  games/conquest.lex     Conquest — deal and seed committed up front; re-derives every dice roll → verdict (no rigged deal)
  games/trading.lex      Trading — seed, bankroll and price-walk parameters committed up front → verdict (no rigged walk)
  games/robot_task.lex   Robot Task verifier — folds a lex-robot run trail → scored verdict
  games/stable_training.lex  Stable Training — idle/incremental economy → capped capability_level
  games/template.lex     TEMPLATE — copy this to start a new game's verifier
  arena/trail_file.lex   portable JSONL trail format (self-verifying; matches the finance arena)
  arena/export.lex       sqlite lex-trail → JSONL (client side, after a local match)
  arena/verify.lex       JSONL trail → verdict (server side: integrity + replay + score)
  arena/rank.lex         the canonical score-ranking rule (one source of truth, shared)
  arena/leaderboard.lex  many robot-policy run trails → ranked, cheat-resistant benchmark
  arena/elo.lex          pure, deterministic ELO math (logistic expected-score + update)
  arena/standings.lex    round-robin + ELO accumulation over a field (pure)
  arena/season.lex       prior standings + a round manifest → new ELO standings (head-to-head, persists)
  arena/nbazaar_season.lex  a manifest of N-player matches → ELO ratings per model (one match = one round)
  arena/bazaar_season.lex   a manifest of governed-bazaar sessions → seller reputation (revenue/deals, verified-only)
  arena/reputation.lex      a DID-anchored agent reputation registry — each session's trail is REPLAYED through its game's verifier; only recomputed, verified scores accumulate into per-did:lex trustMetrics
cli/games                thin launcher
docs/ADDING_A_GAME.md    how to add your own game (the game contract + steps)
docs/CAPABILITY_GRANTS.md how a fact earned on one trail (e.g. training) is
                          minted into a signed, cross-trail grant another
                          verifier can trust without re-replaying the source
testdata/                a real sample trail (CI verifies it)
```

## Add your own game

See **[docs/ADDING_A_GAME.md](docs/ADDING_A_GAME.md)**. In short: copy
`src/games/template.lex`, implement four pure pieces (rules · replay · verdict ·
verdict_json), register a branch in `src/arena/verify.lex`. The framework handles
the capability gate, signed tokens, the hash-chained trail, and the leaderboard.

## Where the games are *played*

The interactive clients live in
[lex-arena](https://github.com/alpibrusl/lex-arena) (`examples/*_web.html`) —
tic-tac-toe, Bazaar Draft, Consent Match, Charger Duel, Co-op Infiltration,
Strategy Football, N-player Bazaar, and the BYO-key AI-agent arena. The play
server itself (`sim_sidecar.lex`) lives in
[lex-robot](https://github.com/alpibrusl/lex-robot), a dependency lex-arena
builds on (see [lex-robot#75](https://github.com/alpibrusl/lex-robot/issues/75)
for why games/commerce and robot governance ended up in different repos). This
repo is the framework + the verifier both produce trails for (each consumes it
as a git dependency).

## N-player Bazaar — a model-vs-model arena

`games/nbazaar.lex` generalizes the head-to-head Bazaar Draft to **N seats**: N
agents take turns drafting from a shared pool under a per-seat budget, recorded
as one hash-chained trail. The live referee + LLM seats live in
[lex-arena](https://github.com/alpibrusl/lex-arena)
(`examples/nplayer_bazaar*.lex`) — point one open-weights model at each seat and
they play a free-for-all. The match trail is the submission; the verifier
replays it, enforcing turn order + affordability + ownership, and recomputes
every seat's score (never trusted from a client).

`arena/nbazaar_season.lex` turns a manifest of matches into an ELO leaderboard.
One match is itself a round-robin among the models at its table, so ratings
accumulate across matches the way an agent arena ranks models over many games:

```bash
# a 3-model match (glm-5.1 34, deepseek-v4-flash 32, kimi-k2.6 28) → ELO round
lex run --allow-effects io src/arena/nbazaar_season.lex run '"none.json"' '"testdata/nbazaar/season_r1.json"' | grep '^{' > s1.json
# chain a glm-vs-kimi rematch that kimi wins; deepseek sits out → carries forward
lex run --allow-effects io src/arena/nbazaar_season.lex run '"s1.json"' '"testdata/nbazaar/season_r2.json"'
# → glm 1512 (won r1, lost the rematch) · deepseek 1501 (unchanged) · kimi 1487 (clawed back)
```

A tampered match trail breaks its content ids → every seat in it is disqualified,
so a fabricated trail can never manufacture a win or a rating gain.

## Governed Bazaar — verifiable agent commerce

`games/gbazaar.lex` applies the same model to **money**. The Magentic Bazaar in
[lex-arena](https://github.com/alpibrusl/lex-arena) (`examples/bazaar_*`) is a
governed agent marketplace: agents buy from agents under a signed budget token,
each purchase authorized by `lex-guard`'s spend gate and settled over x402, all
attested to a hash-chained trail. `gbazaar` reads the budget *from the trail*
(`budget.opened`) and replays every settlement to recompute compliance:

- **integrity** — each line's content id recomputes (tamper-evident)
- **no rogue merchant** — every settlement is to an allow-listed seller
- **no over-cap transaction** / **no overspend** — within the per-tx and total caps

`verified = intact AND compliant`. The two-layer guarantee is the point: the hash
chain catches edits, *and* the compliance replay catches a perfectly-hashed trail
that pays a rogue merchant or overspends — you cannot forge a clean governed
session (see `tools/gen_gbazaar_forged.lex` + the CI checks).

`arena/bazaar_season.lex` turns a manifest of governed sessions into a **seller
reputation** board — revenue + deals per merchant, counting **only sessions that
verify**, so a tampered or non-compliant session earns its sellers nothing:

```bash
# 3-session field (2 honest + 1 forged) → the forged session's seller is absent
lex run --allow-effects io src/arena/bazaar_season.lex run '"testdata/gbazaar/reputation.json"'
# → textile 4800 (2 deals) · pottery 3300 · data 1200 · books 900 · rogue.seller ABSENT
```

It feeds the lobby's TOP SELLERS board in lex-arena.

## Verifiable robot benchmarks

`games/robot_task.lex` extends the "trail, not score" model to **robots**. A
[lex-robot](https://github.com/alpibrusl/lex-robot) task runs as a supervised
guest (lex-os#47, *robot-in-box*) and emits a hash-chained lex-trail of its
Perceive→Plan→Execute→Verify loop plus any supervisor `killed` event. That trail
*is* a submission. The verifier re-derives every line's content id, checks the
chain links head-to-tail, **re-derives that every successful actuation stayed
inside its recorded grant**, and folds the outcomes into an authoritative score
(goal reached · grant refusals · budget kills · actuation count). So a robot run
becomes a **cheat-resistant, replay-verifiable benchmark** — same referee
guarantee as the turn games.

```bash
# export a recorded run (sqlite lex-trail → JSONL), then verify it:
lex run --allow-effects io src/arena/verify.lex verify '"robot_task"' '"testdata/robot_task-sample.jsonl"'
# → {"verified":true,"intact":true,"linked":true,"legal":true,"legal_checked":1,"goal_met":true,...,"score":148}
```

### Authority is re-derived, not trusted

When a run records the **structured lex-os `SkillOutcome`** — the actuation plus
the grant it ran under — the verifier re-checks it: a `move_to` must land inside
the granted workspace box, a `grasp` must stay under the grip-force cap.
A trail that *claims* `reached` on an out-of-grant move is an **unauthorized
success**: it is `intact`, `linked`, and `goal_met`, yet `legal:false` →
`verified:false`. The vocabulary is strict — `move_to` and `move_base` are
checked against the recorded workspace box, `grasp` against the grip cap, and
a structured record with any *other* skill name that claims success is refused
outright (refuse, don't downgrade): an actuation the referee cannot re-derive
is not verifiable, so a cheat can't evade the check by inventing a name. The leaderboard disqualifies it even when its raw score ties
the honest winner. `legal_checked` reports how many actuations carried a grant we
could re-check (a legacy `detail`-only run verifies on integrity + linkage as
before, with `legal_checked:0`).

Wire format is **integer milli-units** (mm for position, mN for force), so the
grant caps should be **ISO/TS 15066-derived**: `max_grip` ≤ `140000` (140 N,
hands/fingers quasi-static), `max_force` ≤ `280000` (280 N transient). Then
*verified* means *every actuation stayed within standard biomechanical limits,
provable from the trail*. (Caveat: 15066 limits are ultimately about pressure =
force ÷ contact area, which the grant doesn't model — the force caps are a sound,
conservative proxy.)

## Stable Training — an idle economy that mints capability

`games/stable_training.lex` applies the "trail, not a score" model to
incremental-game mechanics: a stable's agent earns a budget passively over
real elapsed time, reinvests it into automation tiers (linear rate gain,
exponential cost), and may prestige — cash in accumulated budget for a
permanent rate bonus, resetting tier and budget to zero. Every idle-game
staple (compounding growth, automation, prestige) is recomputed, never
claimed: elapsed time is the delta between consecutive trail lines' own
server-stamped `ts_ms` (a client can't back-date a checkpoint — that breaks
`tf.line_intact`), and budget/tier/prestige are pure functions of that time
plus the recorded action sequence. There is nothing left for a forged trail
to lie about except the action names themselves.

```bash
lex run --allow-effects io tools/gen_stable_training_sample.lex gen '"testdata/stable_training-sample.jsonl"'
lex run --allow-effects io src/arena/verify.lex verify '"stable_training"' '"testdata/stable_training-sample.jsonl"'
#   {"verified":true,"intact":true,"legal":true,...,"capability_level":4,"score":15714}
```

The verdict's `capability_level` is a capped, monotonic function of tier +
prestige_count — not itself a usable grant. Minting a signed
`lex_games.issue_capability_grant()` token from it (so a *different* game's
match verifier can trust the level without re-replaying weeks of training
checkpoints) is a server-side step covered in
**[docs/CAPABILITY_GRANTS.md](docs/CAPABILITY_GRANTS.md)** — the same
signed-attestation trust model `issue_match_token` already uses, generalized
to carry a fact across trails instead of just a side across turns.

## Games as a safe RL/eval harness

`arena/leaderboard.lex` turns the robot referee into a **policy benchmark**. Each
learned policy runs once under a grant + budget (the lex-os box is the safety
envelope, so running an *untrusted* policy is safe) and its rollout trail is a
submission. The leaderboard ranks a whole field by their **recomputed** score —
never a number the client reported — so the benchmark is cheat-resistant and
auditable, and a policy that hits a guardrail (grant refusal / budget kill) ranks
*below* one that fails safely. A tampered or unreadable trail is disqualified to
the bottom, never trusted.

```bash
# rank a field of policies from a manifest (JSON array of {label, trail}):
cli/games leaderboard testdata/policy/leaderboard.json
# → {"game":"robot_task","winner":"diffusion_pusht","ranked":[
#      {"rank":1,"label":"diffusion_pusht","verified":true,"goal_met":true,"score":148,...},
#      {"rank":2,"label":"bc_retry",...,"score":144}, ... reckless_policy last ]}
```

The fixtures in `testdata/policy/` are authentic lex-robot run trails (built with
lex-trail's own `ev.make`); regenerate them with `tools/gen_policy_fixtures.lex`.

### ELO seasons (head-to-head, across rounds)

A single leaderboard ranks *one* field by absolute score. `arena/season.lex`
ranks the way agent arenas actually do — by **relative skill that accumulates**.
Each round is a manifest; we recompute every trail's verified score, play a
deterministic round-robin (the higher verified score wins each pairing), and
update each policy's **ELO** (logistic expected-score, K=32, seed 1500 — all pure
Lex, so the same image recomputes the same rating). Ratings persist across rounds
via a standings file, so a policy that keeps beating *strong* fields climbs and
one that only beat a weak field does not. Read-only by design: it prints the new
standings, and persistence is just stdout redirection.

```bash
# round 1 starts a fresh season (missing standings → everyone seeds at 1500):
cli/games season standings.json testdata/policy/leaderboard.json > next.json
# round 2 chains the standings forward; policies that sit out carry unchanged:
cli/games season next.json testdata/policy/season_round2.json > standings.json
# → {"game":"robot_task","round_entries":2,"players":5,"standings":[
#      {"rank":1,"label":"diffusion_pusht","rating":1531,"played":4,"wins":4,...}, ...]}
```

## Status

Verifier + Bazaar Draft + Robot Task + policy-eval leaderboard + ELO seasons,
verified end-to-end (incl. against a real `lex-robot` run trail). More games'
replay rules and a `verify.lex` dispatch per game land as each is wired into the
hosted arena.

## License

Copyright (c) 2026 lex-games contributors.

Licensed under the [EUPL-1.2](LICENSE) — the European Union Public Licence, as used across the `lex-*` ecosystem.

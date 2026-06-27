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
  games/robot_task.lex   Robot Task verifier — folds a lex-robot run trail → scored verdict
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

## N-player Bazaar — a model-vs-model arena

`games/nbazaar.lex` generalizes the head-to-head Bazaar Draft to **N seats**: N
agents take turns drafting from a shared pool under a per-seat budget, recorded
as one hash-chained trail. The live referee + LLM seats live in
[lex-robot](https://github.com/alpibrusl/lex-robot)
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
[lex-robot](https://github.com/alpibrusl/lex-robot) (`examples/bazaar_*`) is a
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

It feeds the lobby's TOP SELLERS board in lex-robot.

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
`verified:false`. The leaderboard disqualifies it even when its raw score ties
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

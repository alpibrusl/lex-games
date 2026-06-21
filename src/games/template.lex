# lex-games — TEMPLATE game (copy this to start a new game's verifier)
#
# This is the *verifier side* of a game: the deterministic rules + a replay that
# recomputes the authoritative score from a recorded trail. It's what the hosted
# arena runs over an uploaded trail — the score is never trusted from a client.
#
# A game's verifier implements just four things (everything else — the capability
# gate, signed tokens, the hash-chained trail, the leaderboard — is provided by
# the framework, src/lex_games.lex, and the arena):
#   1. the rules        (pure functions: what a move costs / is worth / is legal)
#   2. a replay state   + how to apply one recorded move to it (deterministic)
#   3. a verdict        (verified? + the score the leaderboard ranks)
#   4. verdict_json     (serialize the verdict for the worker)
#
# This template is "Token Pick": a shared pool of 6 numbered tokens, each worth
# some points. P1 and P2 alternate taking one free token; highest total wins.
# (It's Bazaar Draft minus the budget — deliberately tiny, so the *shape* is
# clear. Replace the rules with your game.)
#
# To wire it in: add a branch to src/arena/verify.lex (see docs/ADDING_A_GAME.md).
#
# Verify a trail:
#   lex run --allow-effects io src/arena/verify.lex verify '"template"' '"trail.jsonl"'
#
# Effects: pure.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "../arena/trail_file" as tf

# ── 1. RULES ──────────────────────────────────────────────────────────────────
# Replace these with your game's rules. Keep them PURE and DETERMINISTIC — the
# verifier must compute the same result every time from the same trail.
fn value(i :: Int) -> Int { if i == 0 { 5 } else { if i == 1 { 9 } else { if i == 2 { 3 } else { if i == 3 { 7 } else { if i == 4 { 2 } else { if i == 5 { 8 } else { 0 } } } } } } }
fn token_count() -> Int { 6 }

# The move payload recorded in the trail. Your move() in the play server writes
# this JSON (e.g. {"by":"P1","pick":3}); here we parse it back to score it.
type Move = { by :: Str, pick :: Int }

# ── 2. REPLAY STATE ───────────────────────────────────────────────────────────
# Whatever you need to re-derive the score by walking the recorded moves. Here:
# a 6-char ownership string ('.'=free, '1'=P1, '2'=P2), plus validity flags.
type RState = { own :: Str, legal :: Bool, intact :: Bool, moves :: Int }
fn owner_at(s :: Str, i :: Int) -> Str { str.slice(s, i, i + 1) }
fn owner_set(s :: Str, i :: Int, c :: Str) -> Str { str.concat(str.slice(s, 0, i), str.concat(c, str.slice(s, i + 1, token_count()))) }
fn score(own :: Str, ch :: Str) -> Int {
  list.fold([0,1,2,3,4,5], 0, fn (acc :: Int, i :: Int) -> Int { if owner_at(own, i) == ch { acc + value(i) } else { acc } })
}
fn init() -> RState { { own: "......", legal: true, intact: true, moves: 0 } }

# Apply one recorded trail line. Two checks every game should make:
#   intact — the line's content-addressed id still recomputes (no tampering)
#   legal  — the move was allowed by the rules at this point in the replay
fn step(st :: RState, l :: tf.Line) -> RState {
  let intact := st.intact and tf.line_intact(l)
  if l.kind != "move" { { own: st.own, legal: st.legal, intact: intact, moves: st.moves } } else {
    let parsed :: Result[Move, Str] := json.parse(l.payload_json)
    match parsed {
      Err(_) => { own: st.own, legal: false, intact: intact, moves: st.moves + 1 },
      Ok(m) => {
        let ch := if m.by == "P1" { "1" } else { "2" }
        # RULES CHECK: token must exist and be free. (Add your own legality here.)
        if m.pick < 0 or m.pick > 5 or owner_at(st.own, m.pick) != "." {
          { own: st.own, legal: false, intact: intact, moves: st.moves + 1 }
        } else {
          { own: owner_set(st.own, m.pick, ch), legal: st.legal, intact: intact, moves: st.moves + 1 }
        }
      },
    }
  }
}
fn replay(lines :: List[tf.Line]) -> RState { list.fold(lines, init(), step) }

# ── 3 & 4. VERDICT ────────────────────────────────────────────────────────────
# verified = the chain is intact AND every move was legal. p1 is the contestant's
# score (what the arena leaderboard ranks); p2 is the opponent's.
type Verdict = { verified :: Bool, intact :: Bool, legal :: Bool, p1 :: Int, p2 :: Int, moves :: Int }
fn verdict(lines :: List[tf.Line]) -> Verdict {
  let r := replay(lines)
  { verified: r.intact and r.legal, intact: r.intact, legal: r.legal, p1: score(r.own, "1"), p2: score(r.own, "2"), moves: r.moves }
}
fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"legal\":", b(v.legal), ",\"p1\":", int_str(v.p1), ",\"p2\":", int_str(v.p2), ",\"moves\":", int_str(v.moves), "}"], "")
}
fn int_str(n :: Int) -> Str { int.to_str(n) }

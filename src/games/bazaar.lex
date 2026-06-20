# lex-games — Bazaar Draft rules + replay (the deterministic referee)
#
# Pure game rules: the 6-item pool, and a REPLAY that re-runs the recorded moves
# from the initial state to recompute the authoritative score, checking each move
# was legal. The verifier (src/arena/verify.lex) folds a submitted trail through
# this — the score is computed here, by the rules, never trusted from a client.
#
# Move payloads in the trail look like: {"by":"P1","item":4,...}.
# Effects: pure.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "../arena/trail_file" as tf

fn value(i :: Int) -> Int { if i == 0 { 10 } else { if i == 1 { 14 } else { if i == 2 { 16 } else { if i == 3 { 6 } else { if i == 4 { 25 } else { if i == 5 { 8 } else { 0 } } } } } } }
fn price(i :: Int) -> Int { if i == 0 { 8 } else { if i == 1 { 12 } else { if i == 2 { 15 } else { if i == 3 { 5 } else { if i == 4 { 22 } else { if i == 5 { 7 } else { 999 } } } } } } }
fn name(i :: Int)  -> Str { if i == 0 { "Bowl" } else { if i == 1 { "Vase" } else { if i == 2 { "Scarf" } else { if i == 3 { "Saffron" } else { if i == 4 { "Teapot" } else { if i == 5 { "Ribbon" } else { "?" } } } } } } }

fn budget() -> Int { 30 }

# The move payload we care about for scoring.
type Move = { by :: Str, item :: Int }

# Replay state: 6-char ownership string ('.'/'1'/'2'), per-side budgets, validity.
type RState = { own :: Str, b1 :: Int, b2 :: Int, legal :: Bool, intact :: Bool, moves :: Int }
fn owner_at(s :: Str, i :: Int) -> Str { str.slice(s, i, i + 1) }
fn owner_set(s :: Str, i :: Int, c :: Str) -> Str { str.concat(str.slice(s, 0, i), str.concat(c, str.slice(s, i + 1, 6))) }
fn score(own :: Str, ch :: Str) -> Int {
  list.fold([0,1,2,3,4,5], 0, fn (acc :: Int, i :: Int) -> Int { if owner_at(own, i) == ch { acc + value(i) } else { acc } })
}

fn init() -> RState { { own: "......", b1: budget(), b2: budget(), legal: true, intact: true, moves: 0 } }

# Apply one trail line. Non-"move" lines only carry forward integrity; "move"
# lines must parse, be in range, target a free item, and be affordable.
fn step(st :: RState, l :: tf.Line) -> RState {
  let intact := st.intact and tf.line_intact(l)
  if l.kind != "move" { { own: st.own, b1: st.b1, b2: st.b2, legal: st.legal, intact: intact, moves: st.moves } } else {
    let parsed :: Result[Move, Str] := json.parse(l.payload_json)
    match parsed {
      Err(_) => { own: st.own, b1: st.b1, b2: st.b2, legal: false, intact: intact, moves: st.moves + 1 },
      Ok(m) => {
        let ch := if m.by == "P1" { "1" } else { "2" }
        let bud := if m.by == "P1" { st.b1 } else { st.b2 }
        if m.item < 0 or m.item > 5 or owner_at(st.own, m.item) != "." or price(m.item) > bud {
          { own: st.own, b1: st.b1, b2: st.b2, legal: false, intact: intact, moves: st.moves + 1 }
        } else {
          let nown := owner_set(st.own, m.item, ch)
          if m.by == "P1" { { own: nown, b1: st.b1 - price(m.item), b2: st.b2, legal: st.legal, intact: intact, moves: st.moves + 1 } }
          else { { own: nown, b1: st.b1, b2: st.b2 - price(m.item), legal: st.legal, intact: intact, moves: st.moves + 1 } }
        }
      },
    }
  }
}

fn replay(lines :: List[tf.Line]) -> RState { list.fold(lines, init(), step) }

# The verdict a verifier emits for a Bazaar trail.
type Verdict = { verified :: Bool, intact :: Bool, legal :: Bool, p1 :: Int, p2 :: Int, moves :: Int }
fn verdict(lines :: List[tf.Line]) -> Verdict {
  let r := replay(lines)
  { verified: r.intact and r.legal, intact: r.intact, legal: r.legal, p1: score(r.own, "1"), p2: score(r.own, "2"), moves: r.moves }
}
fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"legal\":", b(v.legal), ",\"p1\":", int.to_str(v.p1), ",\"p2\":", int.to_str(v.p2), ",\"moves\":", int.to_str(v.moves), "}"], "")
}

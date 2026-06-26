# lex-games — N-player Bazaar Draft rules + replay (the deterministic referee)
#
# The 2-player bazaar.lex scores a head-to-head draft. This is its N-seat
# generalization: the same shape of game (a shared item pool, per-seat budget,
# turn-ordered drafting) recorded as a trail and re-scored here by the rules. It
# matches the live referee in lex-robot/examples/nplayer_bazaar.lex (8-item pool,
# budget 30, seats 0..N-1) so a real multi-model match can be replayed and ranked.
#
# A submitted match trail is a sequence of recorded moves:
#   {"kind":"match_started","payload_json":"{\"seats\":3}", ...}   (optional header)
#   {"kind":"draft","payload_json":"{\"seat\":0,\"item\":1}", ...}
#   {"kind":"pass", "payload_json":"{\"seat\":1}", ...}
#
# Replay enforces, by the rules: turn order (round-robin 0,1,..,N-1), item in
# range + unowned, and affordability (per-seat spend ≤ budget). Any violation —
# or a tampered line whose id no longer recomputes — marks the verdict
# unverified. The per-seat scores are recomputed here, never trusted from a
# client.
#
# Effects: pure.

import "std.str"   as str
import "std.int"   as int
import "std.list"  as list
import "std.json"  as json
import "std.tuple" as tup

import "../arena/trail_file" as tf

# ── the pool (identical to the live referee) ─────────────────────────────────
fn price(i :: Int) -> Int {
  if i == 0 { 10 } else { if i == 1 { 15 } else { if i == 2 { 8 } else { if i == 3 { 20 } else {
  if i == 4 { 12 } else { if i == 5 { 18 } else { if i == 6 { 6 } else { if i == 7 { 25 } else { 999 } } } } } } } }
}
fn value(i :: Int) -> Int {
  if i == 0 { 8 } else { if i == 1 { 20 } else { if i == 2 { 5 } else { if i == 3 { 24 } else {
  if i == 4 { 10 } else { if i == 5 { 22 } else { if i == 6 { 9 } else { if i == 7 { 28 } else { 0 } } } } } } } }
}
fn n_items() -> Int { 8 }
fn budget() -> Int { 30 }

# ── move payloads ────────────────────────────────────────────────────────────
type Draft = { seat :: Int, item :: Int }
type Seat  = { seat :: Int }   # also parses a draft line (extra `item` ignored)
type Hdr   = { seats :: Int }

# ── list helpers (owners over items, spent over seats) ───────────────────────
fn nth_int(xs :: List[Int], i :: Int) -> Int {
  let r := list.fold(xs, (0, 0), fn (acc :: (Int, Int), v :: Int) -> (Int, Int) {
    if tup.fst(acc) == i { (tup.fst(acc) + 1, v) } else { (tup.fst(acc) + 1, tup.snd(acc)) }
  })
  tup.snd(r)
}
fn set_nth_int(xs :: List[Int], i :: Int, v :: Int) -> List[Int] {
  let r := list.fold(xs, (0, []), fn (acc :: (Int, List[Int]), x :: Int) -> (Int, List[Int]) {
    (tup.fst(acc) + 1, list.concat(tup.snd(acc), [if tup.fst(acc) == i { v } else { x }]))
  })
  tup.snd(r)
}
fn repeat_int(v :: Int, n :: Int) -> List[Int] {
  if n <= 0 { [] } else { list.concat([v], repeat_int(v, n - 1)) }
}

# ── replay state ─────────────────────────────────────────────────────────────
# owners[i] = seat index owning item i (-1 = unowned); spent[s] = seat s's spend.
type RState = { owners :: List[Int], spent :: List[Int], turn :: Int, n :: Int, legal :: Bool, intact :: Bool, moves :: Int }

fn init(n :: Int) -> RState {
  { owners: repeat_int(0 - 1, n_items()), spent: repeat_int(0, n), turn: 0, n: n, legal: true, intact: true, moves: 0 }
}

# How many seats does this trail describe? Prefer the header; else infer from the
# highest seat index that appears in a move. At least 1.
fn seat_in(l :: tf.Line) -> Int {
  let parsed :: Result[Seat, Str] := json.parse(l.payload_json)
  match parsed { Ok(s) => s.seat, Err(_) => 0 - 1 }
}
fn count_seats(lines :: List[tf.Line]) -> Int {
  let m := list.fold(lines, 1, fn (acc :: Int, l :: tf.Line) -> Int {
    if l.kind == "match_started" {
      let h :: Result[Hdr, Str] := json.parse(l.payload_json)
      match h { Ok(hd) => if hd.seats > acc { hd.seats } else { acc }, Err(_) => acc }
    } else {
      if l.kind == "draft" or l.kind == "pass" {
        let s := seat_in(l)
        if s + 1 > acc { s + 1 } else { acc }
      } else { acc }
    }
  })
  m
}

# carry integrity for a non-move line; moves count only draft/pass.
fn carry(st :: RState, intact :: Bool) -> RState {
  { owners: st.owners, spent: st.spent, turn: st.turn, n: st.n, legal: st.legal, intact: intact, moves: st.moves }
}
fn reject(st :: RState, intact :: Bool) -> RState {
  { owners: st.owners, spent: st.spent, turn: st.turn, n: st.n, legal: false, intact: intact, moves: st.moves + 1 }
}
fn advance(st :: RState, owners :: List[Int], spent :: List[Int], intact :: Bool) -> RState {
  { owners: owners, spent: spent, turn: mod_int(st.turn + 1, st.n), n: st.n, legal: st.legal, intact: intact, moves: st.moves + 1 }
}
fn mod_int(a :: Int, m :: Int) -> Int { if m <= 0 { 0 } else { a - a / m * m } }

fn step(st :: RState, l :: tf.Line) -> RState {
  let intact := st.intact and tf.line_intact(l)
  if l.kind == "draft" {
    let parsed :: Result[Draft, Str] := json.parse(l.payload_json)
    match parsed {
      Err(_) => reject(st, intact),
      Ok(m) => {
        let on_turn := m.seat == st.turn and m.seat >= 0 and m.seat < st.n
        let in_range := m.item >= 0 and m.item < n_items()
        let free := in_range and nth_int(st.owners, m.item) == 0 - 1
        let afford := on_turn and in_range and nth_int(st.spent, m.seat) + price(m.item) <= budget()
        if on_turn and in_range and free and afford {
          advance(st, set_nth_int(st.owners, m.item, m.seat), set_nth_int(st.spent, m.seat, nth_int(st.spent, m.seat) + price(m.item)), intact)
        } else {
          reject(st, intact)
        }
      },
    }
  } else {
    if l.kind == "pass" {
      let parsed :: Result[Seat, Str] := json.parse(l.payload_json)
      match parsed {
        Err(_) => reject(st, intact),
        Ok(m) => if m.seat == st.turn and m.seat >= 0 and m.seat < st.n { advance(st, st.owners, st.spent, intact) } else { reject(st, intact) },
      }
    } else {
      carry(st, intact)
    }
  }
}

fn replay(lines :: List[tf.Line]) -> RState { list.fold(lines, init(count_seats(lines)), step) }

# seat s's score = total worth of the items it owns.
fn score_for(owners :: List[Int], s :: Int) -> Int {
  list.fold([0, 1, 2, 3, 4, 5, 6, 7], 0, fn (acc :: Int, i :: Int) -> Int {
    if nth_int(owners, i) == s { acc + value(i) } else { acc }
  })
}
fn scores_from(owners :: List[Int], s :: Int, n :: Int) -> List[Int] {
  if s >= n { [] } else { list.concat([score_for(owners, s)], scores_from(owners, s + 1, n)) }
}

# ── verdict ──────────────────────────────────────────────────────────────────
type Verdict = { verified :: Bool, intact :: Bool, legal :: Bool, seats :: Int, scores :: List[Int], moves :: Int }
fn verdict(lines :: List[tf.Line]) -> Verdict {
  let r := replay(lines)
  { verified: r.intact and r.legal, intact: r.intact, legal: r.legal, seats: r.n, scores: scores_from(r.owners, 0, r.n), moves: r.moves }
}

# winning seat index (highest score; ties → lowest index). -1 if no seats.
type Best = { idx :: Int, best_i :: Int, best_s :: Int }
fn winner(v :: Verdict) -> Int {
  let r := list.fold(v.scores, { idx: 0, best_i: 0 - 1, best_s: 0 - 1 }, fn (acc :: Best, sc :: Int) -> Best {
    if sc > acc.best_s { { idx: acc.idx + 1, best_i: acc.idx, best_s: sc } } else { { idx: acc.idx + 1, best_i: acc.best_i, best_s: acc.best_s } }
  })
  r.best_i
}

fn scores_json(scores :: List[Int]) -> Str {
  str.join(["[", str.join(list.map(scores, fn (s :: Int) -> Str { int.to_str(s) }), ","), "]"], "")
}
fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"legal\":", b(v.legal),
            ",\"seats\":", int.to_str(v.seats), ",\"scores\":", scores_json(v.scores),
            ",\"winner\":", int.to_str(winner(v)), ",\"moves\":", int.to_str(v.moves), "}"], "")
}

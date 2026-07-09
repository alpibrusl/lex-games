# lex-games — Conquest verifier: was the game provably fair?
#
# The initial territory deal (and the match seed) is committed once, up
# front, as the trail's very first entry — a replay proves the deal was
# never rigged. From there this independently re-derives EVERY dice roll
# from (seed, a monotonic counter) rather than trusting the recorded
# values, and replays the board state (ownership + army counts) move by
# move, re-checking that every reinforce/attack/fortify was legal against
# the board state as it stood AT THAT POINT — not against a later claim.
# A forged trail claiming favorable dice, an attack from a territory the
# acting seat didn't actually own, or a fabricated winner is caught even
# if the hash-chain itself is intact — same unauthorized-success pattern
# as werewolf.lex.
#
# Effects: pure.

import "std.str"    as str
import "std.int"    as int
import "std.list"   as list
import "std.json"   as json
import "std.map"    as map
import "std.crypto" as crypto

import "../arena/trail_file" as tf

# ── the map — must match lex-conquest's src/conquest.lex exactly; the
# verifier never trusts the trail to tell it the map shape, only the
# DYNAMIC ownership/army state ─────────────────────────────────────────────
type Territory = { id :: Str, neighbors :: List[Str] }

fn territory_data() -> List[Territory] {
  [
    { id: "N1", neighbors: ["N2", "N4", "C1"] },
    { id: "N2", neighbors: ["N1", "N3"] },
    { id: "N3", neighbors: ["N2", "N4", "E4"] },
    { id: "N4", neighbors: ["N3", "N1", "W4"] },
    { id: "W1", neighbors: ["W2", "W4", "C2"] },
    { id: "W2", neighbors: ["W1", "W3"] },
    { id: "W3", neighbors: ["W2", "W4", "S4"] },
    { id: "W4", neighbors: ["W3", "W1", "N4"] },
    { id: "E1", neighbors: ["E2", "E4", "C3"] },
    { id: "E2", neighbors: ["E1", "E3"] },
    { id: "E3", neighbors: ["E2", "E4", "S2"] },
    { id: "E4", neighbors: ["E3", "E1", "N3"] },
    { id: "S1", neighbors: ["S2", "S4", "C4"] },
    { id: "S2", neighbors: ["S1", "S3", "E3"] },
    { id: "S3", neighbors: ["S2", "S4"] },
    { id: "S4", neighbors: ["S3", "S1", "W3"] },
    { id: "C1", neighbors: ["C2", "C4", "N1"] },
    { id: "C2", neighbors: ["C1", "C3", "W1"] },
    { id: "C3", neighbors: ["C2", "C4", "E1"] },
    { id: "C4", neighbors: ["C3", "C1", "S1"] },
  ]
}

fn territories() -> List[Str] {
  list.map(territory_data(), fn (t :: Territory) -> Str {
    t.id
  })
}

fn neighbors_of(id :: Str) -> List[Str] {
  list.fold(territory_data(), [], fn (acc :: List[Str], t :: Territory) -> List[Str] {
    if t.id == id {
      t.neighbors
    } else {
      acc
    }
  })
}

fn are_adjacent(a :: Str, b :: Str) -> Bool {
  list.fold(neighbors_of(a), false, fn (acc :: Bool, n :: Str) -> Bool {
    acc or n == b
  })
}

# ── dice re-derivation — must match src/conquest.lex's roll_die exactly ────
fn range(n :: Int) -> List[Int] {
  if n <= 0 {
    []
  } else {
    list.concat(range(n - 1), [n - 1])
  }
}

fn int_mod(a :: Int, b :: Int) -> Int {
  a - a / b * b
}

fn min_int(a :: Int, b :: Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

fn hex_digit_val(c :: Str) -> Int {
  if c == "1" {
    1
  } else {
    if c == "2" {
      2
    } else {
      if c == "3" {
        3
      } else {
        if c == "4" {
          4
        } else {
          if c == "5" {
            5
          } else {
            if c == "6" {
              6
            } else {
              if c == "7" {
                7
              } else {
                if c == "8" {
                  8
                } else {
                  if c == "9" {
                    9
                  } else {
                    if c == "a" {
                      10
                    } else {
                      if c == "b" {
                        11
                      } else {
                        if c == "c" {
                          12
                        } else {
                          if c == "d" {
                            13
                          } else {
                            if c == "e" {
                              14
                            } else {
                              if c == "f" {
                                15
                              } else {
                                0
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

fn hex_to_int(s :: Str, n :: Int) -> Int {
  list.fold(range(n), 0, fn (acc :: Int, i :: Int) -> Int {
    acc * 16 + hex_digit_val(str.char_at(s, i))
  })
}

fn roll_die(sd :: Int, counter :: Int) -> Int {
  let digest := crypto.sha256_str(str.join([int.to_str(sd), ":", int.to_str(counter)], ""))
  1 + int_mod(hex_to_int(digest, 6), 6)
}

fn rederive_dice(sd :: Int, start_counter :: Int, n :: Int) -> List[Int] {
  list.map(range(n), fn (i :: Int) -> Int {
    roll_die(sd, start_counter + i)
  })
}

fn insert_desc(x :: Int, xs :: List[Int]) -> List[Int] {
  let inserted := list.fold(xs, { done: false, acc: [] }, fn (state :: { done :: Bool, acc :: List[Int] }, y :: Int) -> { done :: Bool, acc :: List[Int] } {
    if state.done {
      { done: true, acc: list.concat(state.acc, [y]) }
    } else {
      if x >= y {
        { done: true, acc: list.concat(list.concat(state.acc, [x]), [y]) }
      } else {
        { done: false, acc: list.concat(state.acc, [y]) }
      }
    }
  })
  if inserted.done {
    inserted.acc
  } else {
    list.concat(inserted.acc, [x])
  }
}

fn sort_desc(xs :: List[Int]) -> List[Int] {
  list.fold(xs, [], fn (acc :: List[Int], x :: Int) -> List[Int] {
    insert_desc(x, acc)
  })
}

fn nth_int(xs :: List[Int], i :: Int) -> Int {
  if i <= 0 {
    match list.head(xs) {
      Some(x) => x,
      None => -1,
    }
  } else {
    nth_int(list.tail(xs), i - 1)
  }
}

fn dice_eq(a :: List[Int], b :: List[Int]) -> Bool {
  if list.len(a) != list.len(b) {
    false
  } else {
    dice_eq_step(a, b)
  }
}

fn dice_eq_step(a :: List[Int], b :: List[Int]) -> Bool {
  match list.head(a) {
    None => true,
    Some(ha) => match list.head(b) {
      None => false,
      Some(hb) => ha == hb and dice_eq_step(list.tail(a), list.tail(b)),
    },
  }
}

fn compare_dice(att :: List[Int], def :: List[Int], i :: Int, pairs :: Int, att_losses :: Int, def_losses :: Int) -> { att_losses :: Int, def_losses :: Int } {
  if i >= pairs {
    { att_losses: att_losses, def_losses: def_losses }
  } else {
    let a := nth_int(att, i)
    let d := nth_int(def, i)
    if a > d {
      compare_dice(att, def, i + 1, pairs, att_losses, def_losses + 1)
    } else {
      compare_dice(att, def, i + 1, pairs, att_losses + 1, def_losses)
    }
  }
}

# ── the setup commitment's `deal` object is keyed by territory id (a
# dynamic, non-fixed set of keys), so — same constraint werewolf.lex hit
# with its `roles.assign` object — this reads it by string manipulation
# rather than std.json's fixed-field record parse ──────────────────────────
fn get_seed(payload :: Str) -> Int {
  let parts := str.split(payload, "\"seed\":")
  match list.head(list.tail(parts)) {
    None => 0,
    Some(after) => match list.head(str.split(after, ",")) {
      Some(v) => match str.to_int(v) {
        Some(n) => n,
        None => 0,
      },
      None => 0,
    },
  }
}

fn deal_get_owner(payload :: Str, tid :: Str) -> Int {
  let marker := str.join(["\"", tid, "\":{\"owner\":"], "")
  let parts := str.split(payload, marker)
  match list.head(list.tail(parts)) {
    None => -1,
    Some(after) => match list.head(str.split(after, ",")) {
      Some(v) => match str.to_int(v) {
        Some(n) => n,
        None => -1,
      },
      None => -1,
    },
  }
}

fn deal_get_armies(payload :: Str, tid :: Str) -> Int {
  let marker := str.join(["\"", tid, "\":{\"owner\":"], "")
  let parts := str.split(payload, marker)
  match list.head(list.tail(parts)) {
    None => 0,
    Some(after) => {
      let parts2 := str.split(after, "\"armies\":")
      match list.head(list.tail(parts2)) {
        None => 0,
        Some(after2) => match list.head(str.split(after2, "}")) {
          Some(v) => match str.to_int(v) {
            Some(n) => n,
            None => 0,
          },
          None => 0,
        },
      }
    },
  }
}

# ── board replay ─────────────────────────────────────────────────────────
type TerrState = { owner :: Int, armies :: Int }
type Board = Map[Str, TerrState]

fn board_get(b :: Board, tid :: Str) -> TerrState {
  match map.get(b, tid) {
    Some(s) => s,
    None => { owner: -1, armies: 0 },
  }
}

fn distinct_owners(b :: Board) -> List[Int] {
  list.fold(territories(), [], fn (acc :: List[Int], tid :: Str) -> List[Int] {
    let o := board_get(b, tid).owner
    let seen := list.fold(acc, false, fn (found :: Bool, x :: Int) -> Bool {
      found or x == o
    })
    if seen {
      acc
    } else {
      list.concat(acc, [o])
    }
  })
}

fn owned_count(b :: Board, seat :: Int) -> Int {
  list.fold(territories(), 0, fn (acc :: Int, tid :: Str) -> Int {
    if board_get(b, tid).owner == seat {
      acc + 1
    } else {
      acc
    }
  })
}

fn best_by_territories(b :: Board, cands :: List[Int]) -> Int {
  list.fold(cands, -1, fn (best :: Int, s :: Int) -> Int {
    if best < 0 or owned_count(b, s) > owned_count(b, best) {
      s
    } else {
      best
    }
  })
}

# ── typed payload shapes for the moves that DON'T have dynamic keys
# (json.parse handles nested lists/records fine — only the setup deal's
# territory-id-keyed object needed the manual approach above) ──────────────
type Attack = { from :: Str, to :: Str, by :: Int, attacker_dice :: List[Int], defender_dice :: List[Int], att_losses :: Int, def_losses :: Int, captured :: Bool }
type ReinforceItem = { territory :: Str, n :: Int }
type Reinforce = { by :: Int, placements :: List[ReinforceItem] }
type Fortify = { by :: Int, from :: Str, to :: Str, n :: Int }
type GameOver = { winner :: Int, reason :: Str }

type Tally = { intact :: Bool, saw_setup :: Bool, seed :: Int, board :: Board, dice_counter :: Int, reinforces :: Int, attacks :: Int, fortifies :: Int, claimed_winner :: Int, claimed_reason :: Str, rogue :: List[Str] }

fn step(t :: Tally, l :: tf.Line) -> Tally {
  let intact := t.intact and tf.line_intact(l)
  if l.kind != "move" {
    { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: t.board, dice_counter: t.dice_counter, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: t.rogue }
  } else {
    if str.contains(l.payload_json, "\"kind\":\"setup\"") {
      if t.saw_setup {
        { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: t.board, dice_counter: t.dice_counter, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: list.concat(t.rogue, ["duplicate setup commitment"]) }
      } else {
        let sd := get_seed(l.payload_json)
        let b := list.fold(territories(), map.new(), fn (acc :: Board, tid :: Str) -> Board {
          map.set(acc, tid, { owner: deal_get_owner(l.payload_json, tid), armies: deal_get_armies(l.payload_json, tid) })
        })
        { intact: intact, saw_setup: true, seed: sd, board: b, dice_counter: 0, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: t.rogue }
      }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"attack\"") {
      match (json.parse(l.payload_json) :: Result[Attack, Str]) {
        Err(_) => { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: t.board, dice_counter: t.dice_counter, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: t.rogue },
        Ok(a) => {
          let from_st := board_get(t.board, a.from)
          let to_st := board_get(t.board, a.to)
          let owner_ok := t.saw_setup and from_st.owner == a.by and to_st.owner != a.by
          let adjacency_ok := are_adjacent(a.from, a.to)
          let att_n := list.len(a.attacker_dice)
          let def_n := list.len(a.defender_dice)
          let att_n_ok := att_n == min_int(3, from_st.armies - 1)
          let def_n_ok := def_n == min_int(2, to_st.armies)
          let rederived_att := sort_desc(rederive_dice(t.seed, t.dice_counter, att_n))
          let rederived_def := sort_desc(rederive_dice(t.seed, t.dice_counter + att_n, def_n))
          let dice_ok := dice_eq(rederived_att, a.attacker_dice) and dice_eq(rederived_def, a.defender_dice)
          let pairs := min_int(att_n, def_n)
          let expected := compare_dice(a.attacker_dice, a.defender_dice, 0, pairs, 0, 0)
          let losses_ok := expected.att_losses == a.att_losses and expected.def_losses == a.def_losses
          let new_from_armies := from_st.armies - a.att_losses
          let new_to_armies := to_st.armies - a.def_losses
          let expected_captured := new_to_armies <= 0
          let captured_ok := expected_captured == a.captured
          let legal := owner_ok and adjacency_ok and att_n_ok and def_n_ok and dice_ok and losses_ok and captured_ok
          let new_board := if a.captured {
            map.set(map.set(t.board, a.from, { owner: a.by, armies: 1 }), a.to, { owner: a.by, armies: new_from_armies - 1 })
          } else {
            map.set(map.set(t.board, a.from, { owner: from_st.owner, armies: new_from_armies }), a.to, { owner: to_st.owner, armies: new_to_armies })
          }
          let msg := str.join(["illegal or forged attack ", a.from, "->", a.to, " by seat ", int.to_str(a.by)], "")
          { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: new_board, dice_counter: t.dice_counter + att_n + def_n, reinforces: t.reinforces, attacks: t.attacks + 1, fortifies: t.fortifies, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: if legal {
            t.rogue
          } else {
            list.concat(t.rogue, [msg])
          } }
        },
      }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"reinforce\"") {
      match (json.parse(l.payload_json) :: Result[Reinforce, Str]) {
        Err(_) => { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: t.board, dice_counter: t.dice_counter, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: t.rogue },
        Ok(r) => {
          let applied := list.fold(r.placements, { board: t.board, ok: true }, fn (st2 :: { board :: Board, ok :: Bool }, item :: ReinforceItem) -> { board :: Board, ok :: Bool } {
            let cur := board_get(st2.board, item.territory)
            let legal := t.saw_setup and cur.owner == r.by and item.n > 0
            if legal {
              { board: map.set(st2.board, item.territory, { owner: cur.owner, armies: cur.armies + item.n }), ok: st2.ok }
            } else {
              { board: st2.board, ok: false }
            }
          })
          { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: applied.board, dice_counter: t.dice_counter, reinforces: t.reinforces + 1, attacks: t.attacks, fortifies: t.fortifies, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: if applied.ok {
            t.rogue
          } else {
            list.concat(t.rogue, [str.join(["illegal reinforcement by seat ", int.to_str(r.by)], "")])
          } }
        },
      }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"fortify\"") {
      match (json.parse(l.payload_json) :: Result[Fortify, Str]) {
        Err(_) => { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: t.board, dice_counter: t.dice_counter, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: t.rogue },
        Ok(f) => {
          let from_st := board_get(t.board, f.from)
          let to_st := board_get(t.board, f.to)
          let legal := t.saw_setup and from_st.owner == f.by and to_st.owner == f.by and are_adjacent(f.from, f.to) and f.n > 0 and from_st.armies - f.n >= 1
          let new_board := if legal {
            map.set(map.set(t.board, f.from, { owner: f.by, armies: from_st.armies - f.n }), f.to, { owner: f.by, armies: to_st.armies + f.n })
          } else {
            t.board
          }
          { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: new_board, dice_counter: t.dice_counter, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies + 1, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: if legal {
            t.rogue
          } else {
            list.concat(t.rogue, [str.join(["illegal fortify by seat ", int.to_str(f.by)], "")])
          } }
        },
      }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"game_over\"") {
      match (json.parse(l.payload_json) :: Result[GameOver, Str]) {
        Err(_) => { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: t.board, dice_counter: t.dice_counter, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: t.rogue },
        Ok(g) => { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: t.board, dice_counter: t.dice_counter, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies, claimed_winner: g.winner, claimed_reason: g.reason, rogue: t.rogue },
      }
    } else {
      { intact: intact, saw_setup: t.saw_setup, seed: t.seed, board: t.board, dice_counter: t.dice_counter, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: t.rogue }
    }}}}}
  }
}

type Verdict = { verified :: Bool, intact :: Bool, setup_committed :: Bool, reinforces :: Int, attacks :: Int, fortifies :: Int, winner_confirmed :: Bool, rogue :: List[Str] }

fn verdict(lines :: List[tf.Line]) -> Verdict {
  let t := list.fold(lines, { intact: true, saw_setup: false, seed: 0, board: map.new(), dice_counter: 0, reinforces: 0, attacks: 0, fortifies: 0, claimed_winner: -1, claimed_reason: "", rogue: [] }, step)
  let living := distinct_owners(t.board)
  # round_cap games aren't fully round-replayed here (the verifier doesn't
  # track round numbers independently) — the winner is instead re-checked
  # against "most territories among still-living seats in the final board",
  # a weaker but still meaningful check. Elimination games ARE fully
  # verified: exactly one owner must remain, and it must match the claim.
  let winner_ok := if str.is_empty(t.claimed_reason) {
    false
  } else {
    if t.claimed_reason == "elimination" {
      list.len(living) == 1 and list.fold(living, false, fn (acc :: Bool, s :: Int) -> Bool {
        acc or s == t.claimed_winner
      })
    } else {
      t.claimed_winner == best_by_territories(t.board, living)
    }
  }
  let all_rogue := if winner_ok {
    t.rogue
  } else {
    list.concat(t.rogue, ["claimed winner does not match the replayed final board state"])
  }
  { verified: t.intact and t.saw_setup and winner_ok and list.len(all_rogue) == 0, intact: t.intact, setup_committed: t.saw_setup, reinforces: t.reinforces, attacks: t.attacks, fortifies: t.fortifies, winner_confirmed: winner_ok, rogue: all_rogue }
}

fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str {
    if x {
      "true"
    } else {
      "false"
    }
  }
  let rogue := str.join(["[", str.join(list.map(v.rogue, fn (s :: Str) -> Str {
    str.join(["\"", s, "\""], "")
  }), ","), "]"], "")
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"setup_committed\":", b(v.setup_committed), ",\"reinforces\":", int.to_str(v.reinforces), ",\"attacks\":", int.to_str(v.attacks), ",\"fortifies\":", int.to_str(v.fortifies), ",\"winner_confirmed\":", b(v.winner_confirmed), ",\"rogue\":", rogue, "}"], "")
}

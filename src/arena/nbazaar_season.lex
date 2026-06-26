# lex-games arena — N-player Bazaar ELO season (model-vs-model ratings).
#
# season.lex ranks a field of single-policy trails (one label : one trail). An
# N-player Bazaar *match* is different: one trail holds N seats, so one match is
# itself a round-robin among the models that sat at its table. This season reads
# a manifest of matches, replays each trail through the nbazaar referee to
# recompute every seat's VERIFIED score (never trusted from a client), and folds
# each match as one ELO round — so ratings accumulate across matches the way an
# agent arena ranks models over many games.
#
# A match is a manifest row: the trail path + the seat→model labels in seat
# order. The recomputed scores decide the pairings; a tampered/unverifiable
# trail disqualifies every seat in that match (they can't win their pairings).
#
# Read-only (same effect profile as season.lex): reads prior standings + this
# manifest, prints the new standings as one JSON line. Persistence is stdout
# redirection, so a season chains:
#
#   lex run --allow-effects io src/arena/nbazaar_season.lex run '"none.json"' '"round1.json"' > s1.json
#   lex run --allow-effects io src/arena/nbazaar_season.lex run '"s1.json"'   '"round2.json"' > standings.json

import "std.io"   as io
import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "./trail_file"     as tf
import "../games/nbazaar" as nb
import "./standings"      as st

# One manifest row: a match trail + the model label per seat (seat order).
type Match = { trail :: Str, seats :: List[Str] }

fn nth_str(xs :: List[Str], i :: Int) -> Str {
  match list.head(xs) { None => "", Some(h) => if i <= 0 { h } else { nth_str(list.tail(xs), i - 1) } }
}
fn nth_int(xs :: List[Int], i :: Int) -> Int {
  match list.head(xs) { None => 0, Some(h) => if i <= 0 { h } else { nth_int(list.tail(xs), i - 1) } }
}

# Replay one match → one Scored row per seat. A missing/unverifiable trail makes
# every seat unverified (disqualified for that round).
fn score_match(m :: Match) -> [io] List[st.Scored] {
  let v := match tf.read_jsonl(m.trail) {
    Err(_)    => { verified: false, intact: false, legal: false, seats: 0, scores: [], moves: 0 },
    Ok(lines) => nb.verdict(lines),
  }
  let n := list.len(m.seats)
  build_rows(m.seats, v, 0, n, [])
}
fn build_rows(seats :: List[Str], v :: nb.Verdict, i :: Int, n :: Int, acc :: List[st.Scored]) -> List[st.Scored] {
  if i >= n {
    acc
  } else {
    let row :: st.Scored := { label: nth_str(seats, i), verified: v.verified, score: nth_int(v.scores, i) }
    build_rows(seats, v, i + 1, n, list.concat(acc, [row]))
  }
}

# ── standings JSON (matches season.lex's output shape) ───────────────────────
fn standing_json(rank :: Int, s :: st.Standing) -> Str {
  str.join(["{\"rank\":", int.to_str(rank), ",\"label\":\"", s.label, "\"",
            ",\"rating\":", int.to_str(s.rating), ",\"played\":", int.to_str(s.played),
            ",\"wins\":", int.to_str(s.wins), ",\"draws\":", int.to_str(s.draws),
            ",\"losses\":", int.to_str(s.losses), "}"], "")
}
type RankAcc = { rank :: Int, parts :: List[Str] }
fn standings_json(sorted :: List[st.Standing]) -> Str {
  let acc := list.fold(sorted, { rank: 1, parts: [] }, fn (a :: RankAcc, s :: st.Standing) -> RankAcc {
    { rank: a.rank + 1, parts: list.concat(a.parts, [standing_json(a.rank, s)]) }
  })
  str.join(acc.parts, ",")
}

type Prior = { standings :: List[st.Standing] }
fn load_prior(path :: Str) -> [io] Result[List[st.Standing], Str] {
  match io.read(path) {
    Err(_)      => Ok([]),
    Ok(content) => {
      let parsed :: Result[Prior, Str] := json.parse(content)
      match parsed { Err(e) => Err(e), Ok(p) => Ok(p.standings) }
    },
  }
}

fn err(msg :: Str) -> [io] Int { let _ := io.print(msg) 1 }

fn run(standings_path :: Str, manifest_path :: Str) -> [io] Int {
  match load_prior(standings_path) {
    Err(e) => err(str.concat("{\"error\":\"bad standings json: ", str.concat(e, "\"}"))),
    Ok(prior) => {
      match io.read(manifest_path) {
        Err(e) => err(str.concat("{\"error\":\"cannot read manifest: ", str.concat(e, "\"}"))),
        Ok(content) => {
          let parsed :: Result[List[Match], Str] := json.parse(content)
          match parsed {
            Err(e) => err(str.concat("{\"error\":\"bad manifest json: ", str.concat(e, "\"}"))),
            Ok(matches) => run_matches(prior, matches),
          }
        },
      }
    },
  }
}

# Fold every match as its own ELO round, in manifest order.
fn run_matches(prior :: List[st.Standing], matches :: List[Match]) -> [io] Int {
  let final := list.fold(matches, prior, fn (acc :: List[st.Standing], m :: Match) -> [io] List[st.Standing] {
    st.run_round(acc, score_match(m))
  })
  let ranked := st.ranked(final)
  let out := str.join(["{\"game\":\"nbazaar\",\"matches\":", int.to_str(list.len(matches)),
                       ",\"players\":", int.to_str(list.len(ranked)),
                       ",\"standings\":[", standings_json(ranked), "]}"], "")
  let _ := io.print(out)
  0
}

# lex-games arena — ELO season leaderboard (head-to-head ratings over rounds).
#
# leaderboard.lex ranks ONE field of policies by absolute verified score. A
# *season* ranks them the way agent arenas actually do — by relative skill that
# accumulates over time (UC Berkeley Agent Arena, CATArena, lmgame-Bench). Each
# round is a manifest of run trails; we recompute every trail's VERIFIED score
# (rules-only replay, never trusted from the client), play a deterministic
# round-robin where the higher verified score wins, and update each policy's ELO.
# Ratings persist across rounds via a standings file, so a policy that keeps
# beating strong fields climbs and one that only beat weak fields does not.
#
# Read-only by design (same effect profile as verify/leaderboard): it reads the
# prior standings + this round's manifest and PRINTS the new standings as one
# JSON line. Persistence is just stdout redirection, so a season is a chain:
#
#   lex run --allow-effects io src/arena/season.lex run '"standings.json"' '"round1.json"' > next.json
#   lex run --allow-effects io src/arena/season.lex run '"next.json"'      '"round2.json"' > standings.json
#
# A first round starts from an empty/missing standings file (everyone seeds at
# 1500). An unreadable/tampered trail is disqualified (verified:false) — it loses
# every pairing this round and sinks, but is never dropped silently.

import "std.io"   as io
import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "./trail_file"        as tf
import "../games/robot_task" as rt
import "./standings"         as st

# One manifest row: a human label for the policy + the path to its run trail.
type ManEntry = { label :: Str, trail :: Str }

# Replay one submission's trail through the robot_task referee → a scored row.
# A missing/unparseable trail is a disqualification (verified:false), not a crash.
fn score_one(e :: ManEntry) -> [io] st.Scored {
  match tf.read_jsonl(e.trail) {
    Err(_)    => { label: e.label, verified: false, score: 0 },
    Ok(lines) => {
      let v := rt.verdict(lines)
      { label: e.label, verified: v.verified, score: v.score }
    },
  }
}

fn standing_json(rank :: Int, s :: st.Standing) -> Str {
  str.join([
    "{\"rank\":", int.to_str(rank),
    ",\"label\":\"", s.label, "\"",
    ",\"rating\":", int.to_str(s.rating),
    ",\"played\":", int.to_str(s.played),
    ",\"wins\":", int.to_str(s.wins),
    ",\"draws\":", int.to_str(s.draws),
    ",\"losses\":", int.to_str(s.losses), "}"
  ], "")
}

# Render the ranked standings into a numbered JSON array (rank starts at 1).
fn standings_json(sorted :: List[st.Standing]) -> Str {
  let acc := list.fold(sorted, { rank: 1, parts: [] },
    fn (a :: { rank :: Int, parts :: List[Str] }, s :: st.Standing) -> { rank :: Int, parts :: List[Str] } {
      { rank: a.rank + 1, parts: list.concat(a.parts, [standing_json(a.rank, s)]) }
    })
  str.join(acc.parts, ",")
}

# The persisted standings file is exactly what `run` prints (a wrapper object
# with a `standings` array), so a season round-trips: `season prev round > next`.
type Prior = { standings :: List[st.Standing] }

# Load the prior standings. A missing file = a fresh season (empty standings); a
# present-but-malformed file is an error the caller should see, so it propagates.
# (json.parse ignores the wrapper's extra fields + each row's `rank`.)
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
          let parsed :: Result[List[ManEntry], Str] := json.parse(content)
          match parsed {
            Err(e) => err(str.concat("{\"error\":\"bad manifest json: ", str.concat(e, "\"}"))),
            Ok(entries) => {
              let scored := list.map(entries, score_one)
              let next   := st.ranked(st.run_round(prior, scored))
              let out := str.join([
                "{\"game\":\"robot_task\",\"round_entries\":", int.to_str(list.len(entries)),
                ",\"players\":", int.to_str(list.len(next)),
                ",\"standings\":[", standings_json(next), "]}"
              ], "")
              let _ := io.print(out)
              0
            },
          }
        },
      }
    },
  }
}

# lex-games arena — policy-eval leaderboard (direction #3: games as a safe
# RL/eval harness).
#
# Each robot policy's rollout is recorded as a lex-robot run trail (see
# games/robot_task.lex). A leaderboard is just *many* such submissions ranked by
# their VERIFIED score: we re-derive every trail's content id, re-run the
# rules-only referee on each, and sort by the recomputed score — never by a
# number the client reported. So benchmarking a learned policy is cheat-resistant
# and auditable by construction, and a policy that hits a guardrail (grant
# refusal / budget kill) is ranked below one that fails safely.
#
# Input is a manifest — a JSON array of { label, trail } — so one call scores a
# whole field of policies:
#   lex run --allow-effects io src/arena/leaderboard.lex run '"testdata/policy/leaderboard.json"'
#
# Prints one JSON line: the ranked table + the winner. An unreadable/tampered
# trail is disqualified (verified:false) and sorted to the bottom, never dropped
# silently.

import "std.io"   as io
import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "./trail_file"        as tf
import "../games/robot_task" as rt

# One manifest row: a human label for the policy + the path to its run trail.
type ManEntry = { label :: Str, trail :: Str }

# A scored row in the leaderboard.
type Row = {
  label    :: Str,
  verified :: Bool,
  goal_met :: Bool,
  score    :: Int,
  actions  :: Int,
  denials  :: Int,
  kills    :: Int,
}

# Score one submission by replaying its trail through the robot_task referee.
# A missing/unparseable trail is a disqualification, not a crash.
fn score_one(e :: ManEntry) -> [io] Row {
  match tf.read_jsonl(e.trail) {
    Err(_) => { label: e.label, verified: false, goal_met: false, score: 0, actions: 0, denials: 0, kills: 0 },
    Ok(lines) => {
      let v := rt.verdict(lines)
      { label: e.label, verified: v.verified, goal_met: v.goal_met, score: v.score,
        actions: v.actions, denials: v.denials, kills: v.kills }
    },
  }
}

# Sort key (ascending): verified rows first, highest score first; everything
# disqualified is pushed to the bottom.
fn rank_key(r :: Row) -> Int { if r.verified { 0 - r.score } else { 1000000 } }

fn b(x :: Bool) -> Str { if x { "true" } else { "false" } }

fn row_json(rank :: Int, r :: Row) -> Str {
  str.join([
    "{\"rank\":", int.to_str(rank),
    ",\"label\":\"", r.label, "\"",
    ",\"verified\":", b(r.verified),
    ",\"goal_met\":", b(r.goal_met),
    ",\"score\":", int.to_str(r.score),
    ",\"actions\":", int.to_str(r.actions),
    ",\"denials\":", int.to_str(r.denials),
    ",\"kills\":", int.to_str(r.kills), "}"
  ], "")
}

# Render the sorted rows into a numbered JSON array (rank starts at 1).
fn rows_json(sorted :: List[Row]) -> Str {
  let acc := list.fold(sorted, { rank: 1, parts: [] },
    fn (st :: { rank :: Int, parts :: List[Str] }, r :: Row) -> { rank :: Int, parts :: List[Str] } {
      { rank: st.rank + 1, parts: list.concat(st.parts, [row_json(st.rank, r)]) }
    })
  str.join(acc.parts, ",")
}

fn winner_of(sorted :: List[Row]) -> Str {
  match list.head(sorted) {
    Some(r) => if r.verified { r.label } else { "none" },
    None    => "none",
  }
}

fn run(manifest_path :: Str) -> [io] Int {
  match io.read(manifest_path) {
    Err(e) => { let _ := io.print(str.concat("{\"error\":\"cannot read manifest: ", str.concat(e, "\"}"))) 1 },
    Ok(content) => {
      let parsed :: Result[List[ManEntry], Str] := json.parse(content)
      match parsed {
        Err(e) => { let _ := io.print(str.concat("{\"error\":\"bad manifest json: ", str.concat(e, "\"}"))) 1 },
        Ok(entries) => {
          let rows := list.map(entries, score_one)
          let sorted := list.sort_by(rows, rank_key)
          let out := str.join([
            "{\"game\":\"robot_task\",\"entries\":", int.to_str(list.len(sorted)),
            ",\"winner\":\"", winner_of(sorted), "\"",
            ",\"ranked\":[", rows_json(sorted), "]}"
          ], "")
          let _ := io.print(out)
          0
        },
      }
    },
  }
}

# lex-games — Robot Task verifier (the deterministic referee for a robot run)
#
# This is direction #1 of the robot + games fusion: a lex-robot task emits a
# hash-chained lex-trail of its Perceive->Plan->Execute->Verify loop (and a
# supervisor `killed` event on budget breach). That trail IS a game submission.
# Here we replay it deterministically — re-derive every line's content id, check
# the chain links head-to-tail, and fold the recorded outcomes into an
# authoritative score. The score is computed here, by the rules, never trusted
# from the client.
#
# lex-robot trail kinds (see lex-robot/src/task.lex):
#   task_started  payload {}                      — root
#   perceive      payload {"detail":"..."}        — one per attempt
#   plan          payload {"detail":"target ..."}
#   execute       payload {"detail":"reached" | "denied: ..." | "killed: ..."
#                                   | "stalled: ..." | "timeout"}
#   verify        payload {"detail":"outcome reached" | "gate denied: ..."}
#   killed        payload {"detail":"... budget exhausted: ..."}  — supervisor
#
# Effects: pure.
#
# NOTE on depth: today's lex-robot payloads carry only a `detail` summary, so
# this verifier checks tamper-integrity + chain linkage at full strength and
# scores from the recorded outcomes. Re-deriving grant legality (that each
# move's (skill,args) was inside the granted workspace/force) needs lex-robot to
# record the structured lex-os SkillOutcome (skill + args + grant) in the
# payload — see lex-os#47. That is the natural follow-up; the verdict shape here
# already leaves room for it (a future `legal` that re-checks args).

import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "../arena/trail_file" as tf

# The summary payload shared by every non-root robot trail line.
type Rec = { detail :: Str }

# Pull the `detail` string out of a line's payload, or "" for the root / on
# parse failure (the root `task_started` carries "{}", which has no detail).
fn detail_of(l :: tf.Line) -> Str {
  if l.kind == "task_started" { "" } else {
    let parsed :: Result[Rec, Str] := json.parse(l.payload_json)
    match parsed {
      Ok(r)  => r.detail,
      Err(_) => "",
    }
  }
}

# Replay state. `intact` = every line's id recomputes from its content;
# `linked` = the trail is a single head-to-tail chain (first parent empty, each
# later parent == the previous line's id) — catches reorder/inject/splice.
# The rest are the outcome tallies we score from.
type RState = {
  goal     :: Bool,   # a `verify` line reported the goal reached
  attempts :: Int,    # `perceive` events (one per attempt)
  actions  :: Int,    # `execute` events (actuation attempts)
  reached  :: Int,    # `execute` outcomes that reached
  denials  :: Int,    # grant refusals (Denied)
  kills    :: Int,    # supervisor budget kills (Killed)
  intact   :: Bool,
  linked   :: Bool,
  seen     :: Int,    # lines folded so far
  prev     :: Str,    # previous line's id (for the linkage check)
}

fn init() -> RState {
  { goal: false, attempts: 0, actions: 0, reached: 0, denials: 0, kills: 0,
    intact: true, linked: true, seen: 0, prev: "" }
}

fn has(s :: Str, sub :: Str) -> Bool { str.contains(s, sub) }

# Fold one trail line.
fn step(st :: RState, l :: tf.Line) -> RState {
  let intact := st.intact and tf.line_intact(l)
  let parent_ok := if st.seen == 0 { l.parent == "" } else { l.parent == st.prev }
  let linked := st.linked and parent_ok
  let d := detail_of(l)

  let is_exec    := l.kind == "execute"
  let is_perceive := l.kind == "perceive"
  let is_verify  := l.kind == "verify"
  let is_killed  := l.kind == "killed"

  let reached_here := is_exec and has(d, "reached")
  let denied_here  := is_exec and has(d, "denied")
  let killed_here  := is_killed or (is_exec and has(d, "killed"))

  {
    goal:     st.goal or (is_verify and has(d, "reached")),
    attempts: st.attempts + (if is_perceive { 1 } else { 0 }),
    actions:  st.actions  + (if is_exec { 1 } else { 0 }),
    reached:  st.reached  + (if reached_here { 1 } else { 0 }),
    denials:  st.denials  + (if denied_here { 1 } else { 0 }),
    kills:    st.kills    + (if killed_here { 1 } else { 0 }),
    intact:   intact,
    linked:   linked,
    seen:     st.seen + 1,
    prev:     l.id,
  }
}

fn replay(lines :: List[tf.Line]) -> RState { list.fold(lines, init(), step) }

fn clamp0(n :: Int) -> Int { if n < 0 { 0 } else { n } }

# Authoritative score: goal completion dominates; a clean run (no grant refusal,
# no budget kill) earns integrity bonuses; each actuation costs a little, so the
# efficient solution outranks the wasteful one. Floored at 0.
fn score_of(r :: RState) -> Int {
  clamp0(
    (if r.goal { 100 } else { 0 })
    + (if r.denials == 0 { 25 } else { 0 })
    + (if r.kills == 0 { 25 } else { 0 })
    - (r.actions * 2)
  )
}

# Verdict. `verified` means the trail is a faithful, untampered, well-linked
# record — note a Denied or Killed run still *verifies* (it honestly recorded a
# refusal/kill); the score, not the verdict, reflects how well the run went.
type Verdict = {
  verified :: Bool,
  intact   :: Bool,
  linked   :: Bool,
  goal_met :: Bool,
  attempts :: Int,
  actions  :: Int,
  denials  :: Int,
  kills    :: Int,
  score    :: Int,
}

fn verdict(lines :: List[tf.Line]) -> Verdict {
  let r := replay(lines)
  {
    verified: r.intact and r.linked,
    intact:   r.intact,
    linked:   r.linked,
    goal_met: r.goal,
    attempts: r.attempts,
    actions:  r.actions,
    denials:  r.denials,
    kills:    r.kills,
    score:    score_of(r),
  }
}

fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  str.join([
    "{\"verified\":", b(v.verified),
    ",\"intact\":", b(v.intact),
    ",\"linked\":", b(v.linked),
    ",\"goal_met\":", b(v.goal_met),
    ",\"attempts\":", int.to_str(v.attempts),
    ",\"actions\":", int.to_str(v.actions),
    ",\"denials\":", int.to_str(v.denials),
    ",\"kills\":", int.to_str(v.kills),
    ",\"score\":", int.to_str(v.score), "}"
  ], "")
}

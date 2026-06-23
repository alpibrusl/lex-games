# lex-games — Robot Task verifier (the deterministic referee for a robot run)
#
# Direction #1 of the robot + games fusion: a lex-robot task emits a hash-chained
# lex-trail of its Perceive->Plan->Execute->Verify loop (and a supervisor
# `killed` event on budget breach). That trail IS a game submission. Here we
# replay it deterministically — re-derive every line's content id, check the
# chain links head-to-tail, RE-DERIVE that every successful actuation stayed
# inside its recorded grant, and fold the outcomes into an authoritative score.
# Everything is recomputed by the rules, never trusted from the client.
#
# lex-robot trail kinds (see lex-robot/src/task.lex):
#   task_started  payload {}                      — root
#   perceive      payload {"detail":"..."}        — one per attempt
#   plan          payload {"detail":"target ..."}
#   execute       LEGACY:     {"detail":"reached" | "denied: ..." | "timeout" | ...}
#                 STRUCTURED: {"skill":"move_to"|"grasp",
#                              "args":{"x","y","z","force"},          # integer milli-units
#                              "grant":{"ws_min","ws_max","max_force","max_grip"},
#                              "outcome":"reached" | "denied: ..." | ...}
#   verify        payload {"detail":"outcome reached" | "gate denied: ..."}
#   killed        payload {"detail":"... budget exhausted: ..."}  — supervisor
#
# Wire units are INTEGER milli-units (millimetres for position, milli-newtons for
# force): 0.5 m -> 500, 140 N -> 140000. Keeping the wire integral sidesteps Lex's
# Int/Float compare (a whole-valued float serializes without a decimal and decodes
# back as Int), and matches how robot stacks often encode anyway. The grant in the
# payload SHOULD carry ISO/TS 15066-derived caps — max_grip <= 140000 mN
# (hands/fingers quasi-static), max_force <= 280000 mN (transient) — so "legal"
# means "stayed within standard biomechanical limits, provable from the trail".
#
# Backward compatible: a legacy detail-only execute payload skips the legality
# re-check (legal_checked does not advance) but still verifies on integrity +
# linkage + outcome scoring, exactly as before.
#
# Effects: pure.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "../arena/trail_file" as tf

# --- payload shapes ----------------------------------------------------------

# The summary payload shared by every non-structured robot trail line.
type Rec = { detail :: Str }

# A structured execute payload: the actuation + the grant it ran under (the
# lex-os SkillOutcome shape), all in integer milli-units.
type Vec3i  = { x :: Int, y :: Int, z :: Int }
type ArgsI  = { x :: Int, y :: Int, z :: Int, force :: Int }
type GrantI = { ws_min :: Vec3i, ws_max :: Vec3i, max_force :: Int, max_grip :: Int }
type SkillRec = { skill :: Str, args :: ArgsI, grant :: GrantI, outcome :: Str }

fn has(s :: Str, sub :: Str) -> Bool { str.contains(s, sub) }

# Pull the `detail` string out of a (legacy / verify / killed) payload, or "" for
# the root and on parse failure.
fn detail_of(l :: tf.Line) -> Str {
  if l.kind == "task_started" { "" } else {
    let parsed :: Result[Rec, Str] := json.parse(l.payload_json)
    match parsed {
      Ok(r)  => r.detail,
      Err(_) => "",
    }
  }
}

# --- legality (grant re-derivation) ------------------------------------------

fn in_ws(a :: ArgsI, g :: GrantI) -> Bool {
  a.x >= g.ws_min.x and a.x <= g.ws_max.x and
  a.y >= g.ws_min.y and a.y <= g.ws_max.y and
  a.z >= g.ws_min.z and a.z <= g.ws_max.z
}

fn is_success(outcome :: Str) -> Bool { has(outcome, "reached") }

# Did this actuation stay inside its grant? move_to must land in the workspace
# box; grasp must not exceed the grip-force cap; anything else is unconstrained.
fn legal_rec(r :: SkillRec) -> Bool {
  if r.skill == "move_to" { in_ws(r.args, r.grant) }
  else { if r.skill == "grasp" { r.args.force <= r.grant.max_grip } else { true } }
}

# A violation is a trail that *claims success* on an out-of-grant actuation — an
# unauthorized win. (An out-of-grant move recorded as `denied` is consistent: the
# supervisor refused it correctly, so it is NOT a violation.)
fn violation_of(r :: SkillRec) -> Bool {
  if is_success(r.outcome) { if legal_rec(r) { false } else { true } } else { false }
}

# Normalized view of an execute line: its outcome string, whether it was a
# structured (legality-checkable) record, and whether it violated its grant.
type ExecInfo = { outcome :: Str, structured :: Bool, violation :: Bool }

fn exec_info(l :: tf.Line, legacy_detail :: Str) -> ExecInfo {
  if has(l.payload_json, "\"skill\"") {
    let p :: Result[SkillRec, Str] := json.parse(l.payload_json)
    match p {
      Ok(r)  => { outcome: r.outcome, structured: true, violation: violation_of(r) },
      Err(_) => { outcome: legacy_detail, structured: false, violation: false },
    }
  } else {
    { outcome: legacy_detail, structured: false, violation: false }
  }
}

# --- replay ------------------------------------------------------------------

# Replay state. `intact` = every line's id recomputes; `linked` = single
# head-to-tail chain; `legal` = no successful actuation broke its grant;
# `checked` = how many structured execute records we could legality-check.
type RState = {
  goal     :: Bool,
  attempts :: Int,
  actions  :: Int,
  reached  :: Int,
  denials  :: Int,
  kills    :: Int,
  intact   :: Bool,
  linked   :: Bool,
  legal    :: Bool,
  checked  :: Int,
  seen     :: Int,
  prev     :: Str,
}

fn init() -> RState {
  { goal: false, attempts: 0, actions: 0, reached: 0, denials: 0, kills: 0,
    intact: true, linked: true, legal: true, checked: 0, seen: 0, prev: "" }
}

fn step(st :: RState, l :: tf.Line) -> RState {
  let intact := st.intact and tf.line_intact(l)
  let parent_ok := if st.seen == 0 { l.parent == "" } else { l.parent == st.prev }
  let linked := st.linked and parent_ok
  let d := detail_of(l)

  let is_exec     := l.kind == "execute"
  let is_perceive := l.kind == "perceive"
  let is_verify   := l.kind == "verify"
  let is_killed   := l.kind == "killed"

  let eo := if is_exec { exec_info(l, d) } else { { outcome: "", structured: false, violation: false } }

  let reached_here := is_exec and has(eo.outcome, "reached")
  let denied_here  := is_exec and has(eo.outcome, "denied")
  let killed_here  := is_killed or (is_exec and has(eo.outcome, "killed"))

  {
    goal:     st.goal or (is_verify and has(d, "reached")),
    attempts: st.attempts + (if is_perceive { 1 } else { 0 }),
    actions:  st.actions  + (if is_exec { 1 } else { 0 }),
    reached:  st.reached  + (if reached_here { 1 } else { 0 }),
    denials:  st.denials  + (if denied_here { 1 } else { 0 }),
    kills:    st.kills    + (if killed_here { 1 } else { 0 }),
    intact:   intact,
    linked:   linked,
    legal:    if eo.violation { false } else { st.legal },
    checked:  st.checked + (if eo.structured { 1 } else { 0 }),
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

# Verdict. `verified` = the trail is untampered (`intact`), well-linked
# (`linked`), AND every successful actuation stayed inside its grant (`legal`). A
# Denied/Killed run still verifies (it honestly recorded a refusal/kill); the
# score, not the verdict, reflects how well the run went. `legal_checked` reports
# how many actuations carried a structured grant we could actually re-check.
type Verdict = {
  verified      :: Bool,
  intact        :: Bool,
  linked        :: Bool,
  legal         :: Bool,
  legal_checked :: Int,
  goal_met      :: Bool,
  attempts      :: Int,
  actions       :: Int,
  denials       :: Int,
  kills         :: Int,
  score         :: Int,
}

fn verdict(lines :: List[tf.Line]) -> Verdict {
  let r := replay(lines)
  {
    verified:      r.intact and r.linked and r.legal,
    intact:        r.intact,
    linked:        r.linked,
    legal:         r.legal,
    legal_checked: r.checked,
    goal_met:      r.goal,
    attempts:      r.attempts,
    actions:       r.actions,
    denials:       r.denials,
    kills:         r.kills,
    score:         score_of(r),
  }
}

fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  str.join([
    "{\"verified\":", b(v.verified),
    ",\"intact\":", b(v.intact),
    ",\"linked\":", b(v.linked),
    ",\"legal\":", b(v.legal),
    ",\"legal_checked\":", int.to_str(v.legal_checked),
    ",\"goal_met\":", b(v.goal_met),
    ",\"attempts\":", int.to_str(v.attempts),
    ",\"actions\":", int.to_str(v.actions),
    ",\"denials\":", int.to_str(v.denials),
    ",\"kills\":", int.to_str(v.kills),
    ",\"score\":", int.to_str(v.score), "}"
  ], "")
}

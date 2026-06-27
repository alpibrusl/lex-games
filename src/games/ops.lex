# lex-games — Agent-ops verifier (replay a tool-use trail → compliance verdict).
#
# The kernel applied to the universal agentic domain: agents calling tools/APIs.
# A Lex agent-ops gate (lex-robot examples/ops_gate.lex) records a run under a
# tool-use capability: a `policy.opened` snapshot (which tools the agent may call,
# under a call budget), then `op.requested` + (`op.ok` | `op.denied`) per call.
# This replays the run and recomputes — never trusted — that the agent stayed in
# its authority:
#
#   * integrity   — each line's content id recomputes (tamper-evident)
#   * no rogue tool — every EXECUTED op (op.ok) is allow-listed and not deny-listed
#   * within budget — the executed-op count does not exceed the call budget
#
# So an "audit-ready agent run" is provable: tamper an op and the id breaks; forge
# an op.ok for a forbidden tool and the rogue-tool check catches it with valid
# hashes. A clean verdict is what earns the agent operator reputation.
#
# Effects: pure.

import "std.str"   as str
import "std.int"   as int
import "std.list"  as list
import "std.json"  as json
import "std.tuple" as tup

import "../arena/trail_file" as tf

type Policy = { tools_allow :: List[Str], tools_deny :: List[Str], max_calls :: Int }
type Op     = { tool :: Str }

fn list_has(xs :: List[Str], x :: Str) -> Bool { list.fold(xs, false, fn (a :: Bool, s :: Str) -> Bool { a or s == x }) }
fn permitted(p :: Policy, tool :: Str) -> Bool { list_has(p.tools_allow, tool) and not list_has(p.tools_deny, tool) }

fn read_policy(lines :: List[tf.Line]) -> (Bool, Policy) {
  list.fold(lines, (false, { tools_allow: [], tools_deny: [], max_calls: 0 }), fn (acc :: (Bool, Policy), l :: tf.Line) -> (Bool, Policy) {
    if tup.fst(acc) or l.kind != "policy.opened" {
      acc
    } else {
      match (json.parse(l.payload_json) :: Result[Policy, Str]) { Err(_) => acc, Ok(p) => (true, p) }
    }
  })
}

type Tally = { intact :: Bool, ok :: Int, denied :: Int, rogue :: List[Str] }
fn step(p :: Policy, t :: Tally, l :: tf.Line) -> Tally {
  let intact := t.intact and tf.line_intact(l)
  if l.kind == "op.ok" {
    match (json.parse(l.payload_json) :: Result[Op, Str]) {
      Err(_) => { intact: intact, ok: t.ok, denied: t.denied, rogue: t.rogue },
      Ok(o) => {
        let rogue := if permitted(p, o.tool) { t.rogue } else { list.concat(t.rogue, [o.tool]) }
        { intact: intact, ok: t.ok + 1, denied: t.denied, rogue: rogue }
      },
    }
  } else {
    if l.kind == "op.denied" {
      { intact: intact, ok: t.ok, denied: t.denied + 1, rogue: t.rogue }
    } else {
      { intact: intact, ok: t.ok, denied: t.denied, rogue: t.rogue }
    }
  }
}

# ── verdict ──────────────────────────────────────────────────────────────────
# verified = intact AND no rogue tool executed AND within the call budget.
type Verdict = { verified :: Bool, intact :: Bool, compliant :: Bool, has_policy :: Bool, ok :: Int, denied :: Int, over_budget :: Bool, rogue :: List[Str] }
fn verdict(lines :: List[tf.Line]) -> Verdict {
  let pr := read_policy(lines)
  let has := tup.fst(pr)
  let p := tup.snd(pr)
  let t := list.fold(lines, { intact: true, ok: 0, denied: 0, rogue: [] }, fn (acc :: Tally, l :: tf.Line) -> Tally { step(p, acc, l) })
  let over := p.max_calls > 0 and t.ok > p.max_calls
  let compliant := has and list.len(t.rogue) == 0 and not over
  { verified: t.intact and compliant, intact: t.intact, compliant: compliant, has_policy: has, ok: t.ok, denied: t.denied, over_budget: over, rogue: t.rogue }
}

fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  let rogue := str.join(["[", str.join(list.map(v.rogue, fn (s :: Str) -> Str { str.join(["\"", s, "\""], "") }), ","), "]"], "")
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"compliant\":", b(v.compliant),
            ",\"has_policy\":", b(v.has_policy), ",\"ok\":", int.to_str(v.ok), ",\"denied\":", int.to_str(v.denied),
            ",\"over_budget\":", b(v.over_budget), ",\"rogue\":", rogue, "}"], "")
}

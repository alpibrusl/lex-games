# lex-games — Consent verifier (replay a consent trail → compliance verdict).
#
# The data-side twin of gbazaar. A Lex consent gate (lex-robot
# examples/consent_gate.lex) emits a hash-chained trail of an a2p-style session:
# a `policy.opened` snapshot (which scopes an agent pattern may read), then a
# `consent.requested` + (`consent.granted` | `consent.denied`) per access request.
# This replays that trail and recomputes — by the rules, never trusted — whether
# every GRANT respected the policy:
#
#   * integrity     — each line's content id recomputes (tamper-evident)
#   * no leaked scope — every granted scope is allow-listed and not deny-listed
#
# So a consent receipt is not merely *claimed* (as in plain a2p) but *provable*:
# tamper with a grant and the id breaks; forge a grant for a denied scope and the
# scope-leak check catches it even with valid hashes. The policy is read FROM the
# trail (policy.opened), so verification is self-contained.
#
# Effects: pure.

import "std.str"   as str
import "std.int"   as int
import "std.list"  as list
import "std.json"  as json
import "std.tuple" as tup

import "../arena/trail_file" as tf

type Policy = { allow :: List[Str], deny :: List[Str], require_purpose :: Bool }
type Grant  = { granted :: List[Str] }

fn list_has(xs :: List[Str], x :: Str) -> Bool {
  list.fold(xs, false, fn (a :: Bool, s :: Str) -> Bool { a or s == x })
}
fn permitted(p :: Policy, scope :: Str) -> Bool { list_has(p.allow, scope) and not list_has(p.deny, scope) }

# The policy this session committed to (first policy.opened); empty if absent.
fn read_policy(lines :: List[tf.Line]) -> (Bool, Policy) {
  list.fold(lines, (false, { allow: [], deny: [], require_purpose: false }), fn (acc :: (Bool, Policy), l :: tf.Line) -> (Bool, Policy) {
    if tup.fst(acc) or l.kind != "policy.opened" {
      acc
    } else {
      match (json.parse(l.payload_json) :: Result[Policy, Str]) { Err(_) => acc, Ok(p) => (true, p) }
    }
  })
}

# Running tally as we fold the trail.
type Tally = { intact :: Bool, grants :: Int, denials :: Int, leaked :: List[Str] }
fn add_leaks(p :: Policy, granted :: List[Str], acc :: List[Str]) -> List[Str] {
  list.fold(granted, acc, fn (a :: List[Str], s :: Str) -> List[Str] { if permitted(p, s) { a } else { list.concat(a, [s]) } })
}
fn step(p :: Policy, t :: Tally, l :: tf.Line) -> Tally {
  let intact := t.intact and tf.line_intact(l)
  if l.kind == "consent.granted" {
    match (json.parse(l.payload_json) :: Result[Grant, Str]) {
      Err(_) => { intact: intact, grants: t.grants, denials: t.denials, leaked: t.leaked },
      Ok(g) => { intact: intact, grants: t.grants + 1, denials: t.denials, leaked: add_leaks(p, g.granted, t.leaked) },
    }
  } else {
    if l.kind == "consent.denied" {
      { intact: intact, grants: t.grants, denials: t.denials + 1, leaked: t.leaked }
    } else {
      { intact: intact, grants: t.grants, denials: t.denials, leaked: t.leaked }
    }
  }
}

# ── verdict ──────────────────────────────────────────────────────────────────
# verified = the trail is intact AND no grant leaked a non-permitted scope.
type Verdict = { verified :: Bool, intact :: Bool, compliant :: Bool, has_policy :: Bool, grants :: Int, denials :: Int, leaked :: List[Str] }
fn verdict(lines :: List[tf.Line]) -> Verdict {
  let pr := read_policy(lines)
  let has_policy := tup.fst(pr)
  let p := tup.snd(pr)
  let t := list.fold(lines, { intact: true, grants: 0, denials: 0, leaked: [] }, fn (acc :: Tally, l :: tf.Line) -> Tally { step(p, acc, l) })
  let compliant := has_policy and list.len(t.leaked) == 0
  { verified: t.intact and compliant, intact: t.intact, compliant: compliant, has_policy: has_policy, grants: t.grants, denials: t.denials, leaked: t.leaked }
}

fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  let leaked := str.join(["[", str.join(list.map(v.leaked, fn (s :: Str) -> Str { str.join(["\"", s, "\""], "") }), ","), "]"], "")
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"compliant\":", b(v.compliant),
            ",\"has_policy\":", b(v.has_policy), ",\"grants\":", int.to_str(v.grants),
            ",\"denials\":", int.to_str(v.denials), ",\"leaked\":", leaked, "}"], "")
}

# lex-games — Capability verifier (one token, both domains, one verdict).
#
# The unified control-plane verifier. A Lex capability gate (lex-robot
# examples/capability_gate.lex) records a session in which ONE signed token bounds
# an agent's authority over BOTH data (which scopes it may read) and money (what
# it may spend), to ONE hash-chained trail: a single `policy.opened` snapshot,
# then interleaved consent.* (data) and spend.* (money) events. This replays the
# whole session and recomputes — never trusted — that EVERY action respected the
# one token:
#
#   * integrity      — each line's content id recomputes (tamper-evident)
#   * data_compliant — no granted scope is deny-listed / outside the allow set
#   * spend_compliant — no settlement over the per-tx cap, total cap, or to a
#                       non-allow-listed merchant
#
# It fuses the gbazaar (money) and consent (data) checks against a single policy —
# the verifiable form of "one capability for everything an agent may do or know."
#
# Effects: pure.

import "std.str"   as str
import "std.int"   as int
import "std.list"  as list
import "std.json"  as json
import "std.tuple" as tup

import "../arena/trail_file" as tf

# The unified capability, read from the trail's policy.opened.
type Cap = { data_allow :: List[Str], data_deny :: List[Str], spend_cap_total :: Int, spend_per_tx :: Int, merchants_allow :: List[Str] }
type Grant   = { granted :: List[Str] }
type Outcome = { amount :: Int, merchant :: Str }

fn list_has(xs :: List[Str], x :: Str) -> Bool { list.fold(xs, false, fn (a :: Bool, s :: Str) -> Bool { a or s == x }) }
fn permitted(c :: Cap, scope :: Str) -> Bool { list_has(c.data_allow, scope) and not list_has(c.data_deny, scope) }

fn read_cap(lines :: List[tf.Line]) -> (Bool, Cap) {
  list.fold(lines, (false, { data_allow: [], data_deny: [], spend_cap_total: 0, spend_per_tx: 0, merchants_allow: [] }), fn (acc :: (Bool, Cap), l :: tf.Line) -> (Bool, Cap) {
    if tup.fst(acc) or l.kind != "policy.opened" {
      acc
    } else {
      match (json.parse(l.payload_json) :: Result[Cap, Str]) { Err(_) => acc, Ok(c) => (true, c) }
    }
  })
}

# Running tally over the mixed trail.
type Tally = { intact :: Bool, grants :: Int, denials :: Int, settled :: Int, settlements :: Int, leaked :: List[Str], rogue :: Bool, over_tx :: Bool }
fn add_leaks(c :: Cap, granted :: List[Str], acc :: List[Str]) -> List[Str] {
  list.fold(granted, acc, fn (a :: List[Str], s :: Str) -> List[Str] { if permitted(c, s) { a } else { list.concat(a, [s]) } })
}
fn step(c :: Cap, t :: Tally, l :: tf.Line) -> Tally {
  let intact := t.intact and tf.line_intact(l)
  if l.kind == "consent.granted" {
    match (json.parse(l.payload_json) :: Result[Grant, Str]) {
      Err(_) => set_intact(t, intact),
      Ok(g) => { intact: intact, grants: t.grants + 1, denials: t.denials, settled: t.settled, settlements: t.settlements, leaked: add_leaks(c, g.granted, t.leaked), rogue: t.rogue, over_tx: t.over_tx },
    }
  } else {
    if l.kind == "consent.denied" {
      { intact: intact, grants: t.grants, denials: t.denials + 1, settled: t.settled, settlements: t.settlements, leaked: t.leaked, rogue: t.rogue, over_tx: t.over_tx }
    } else {
      if l.kind == "spend.outcome" {
        match (json.parse(l.payload_json) :: Result[Outcome, Str]) {
          Err(_) => set_intact(t, intact),
          Ok(o) => {
            let rogue := t.rogue or not list_has(c.merchants_allow, o.merchant)
            let over_tx := t.over_tx or (c.spend_per_tx > 0 and o.amount > c.spend_per_tx)
            { intact: intact, grants: t.grants, denials: t.denials, settled: t.settled + o.amount, settlements: t.settlements + 1, leaked: t.leaked, rogue: rogue, over_tx: over_tx }
          },
        }
      } else {
        set_intact(t, intact)
      }
    }
  }
}
fn set_intact(t :: Tally, intact :: Bool) -> Tally {
  { intact: intact, grants: t.grants, denials: t.denials, settled: t.settled, settlements: t.settlements, leaked: t.leaked, rogue: t.rogue, over_tx: t.over_tx }
}

# ── verdict ──────────────────────────────────────────────────────────────────
type Verdict = { verified :: Bool, intact :: Bool, has_policy :: Bool, data_compliant :: Bool, spend_compliant :: Bool, grants :: Int, denials :: Int, settlements :: Int, settled :: Int, leaked :: List[Str], rogue :: Bool, over_tx :: Bool, over_cap :: Bool }
fn verdict(lines :: List[tf.Line]) -> Verdict {
  let cr := read_cap(lines)
  let has := tup.fst(cr)
  let c := tup.snd(cr)
  let t := list.fold(lines, { intact: true, grants: 0, denials: 0, settled: 0, settlements: 0, leaked: [], rogue: false, over_tx: false }, fn (acc :: Tally, l :: tf.Line) -> Tally { step(c, acc, l) })
  let over_cap := c.spend_cap_total > 0 and t.settled > c.spend_cap_total
  let data_ok := has and list.len(t.leaked) == 0
  let spend_ok := has and not t.rogue and not t.over_tx and not over_cap
  { verified: t.intact and data_ok and spend_ok, intact: t.intact, has_policy: has, data_compliant: data_ok, spend_compliant: spend_ok, grants: t.grants, denials: t.denials, settlements: t.settlements, settled: t.settled, leaked: t.leaked, rogue: t.rogue, over_tx: t.over_tx, over_cap: over_cap }
}

fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  let leaked := str.join(["[", str.join(list.map(v.leaked, fn (s :: Str) -> Str { str.join(["\"", s, "\""], "") }), ","), "]"], "")
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"has_policy\":", b(v.has_policy),
            ",\"data_compliant\":", b(v.data_compliant), ",\"spend_compliant\":", b(v.spend_compliant),
            ",\"grants\":", int.to_str(v.grants), ",\"denials\":", int.to_str(v.denials),
            ",\"settlements\":", int.to_str(v.settlements), ",\"settled\":", int.to_str(v.settled),
            ",\"leaked\":", leaked, ",\"rogue\":", b(v.rogue), ",\"over_tx\":", b(v.over_tx), ",\"over_cap\":", b(v.over_cap), "}"], "")
}

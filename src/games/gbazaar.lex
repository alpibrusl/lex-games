# lex-games — Governed Bazaar verifier (replay a spend trail → compliance verdict)
#
# The Magentic Bazaar (lex-robot/examples/bazaar_market.lex) emits a hash-chained
# trail of governed transactions: a `budget.opened` policy snapshot, then a
# `spend.intent` + (`spend.outcome` | `spend.denied`) per purchase, written by
# lex-guard's spend gate. This replays that trail and recomputes — by the rules,
# never trusted from the client — whether EVERY settlement respected the budget:
#
#   * integrity — each line's content id recomputes (tamper-evident)
#   * no rogue merchant — every settlement is to an allow-listed seller
#   * no over-cap transaction — every settlement ≤ the per-transaction cap
#   * no overspend — cumulative settled ≤ the total cap
#
# The policy is read FROM the trail's budget.opened event, so verification is
# self-contained: tamper with a settlement (or the budget) and the id breaks; try
# to forge a compliant-looking rogue payment and the allow-list check catches it.
#
# Effects: pure.

import "std.str"   as str
import "std.int"   as int
import "std.list"  as list
import "std.json"  as json
import "std.tuple" as tup

import "../arena/trail_file" as tf

# ── payloads we parse out of the trail ───────────────────────────────────────
type Budget  = { cap_total :: Int, cap_per_transaction :: Int, merchants_allow :: List[Str] }
type Outcome = { amount :: Int, merchant :: Str }

fn list_has(xs :: List[Str], x :: Str) -> Bool {
  list.fold(xs, false, fn (acc :: Bool, m :: Str) -> Bool { acc or m == x })
}

# The budget the buyer committed to (first budget.opened event); empty if absent.
fn read_budget(lines :: List[tf.Line]) -> (Bool, Budget) {
  list.fold(lines, (false, { cap_total: 0, cap_per_transaction: 0, merchants_allow: [] }), fn (acc :: (Bool, Budget), l :: tf.Line) -> (Bool, Budget) {
    if tup.fst(acc) or l.kind != "budget.opened" {
      acc
    } else {
      match (json.parse(l.payload_json) :: Result[Budget, Str]) {
        Err(_) => acc,
        Ok(b) => (true, b),
      }
    }
  })
}

# Per-seller revenue (find-or-add fold accumulator).
type Rev = { merchant :: Str, revenue :: Int }
fn add_rev(rs :: List[Rev], merchant :: Str, amount :: Int) -> List[Rev] {
  let hit := list.fold(rs, false, fn (a :: Bool, r :: Rev) -> Bool { a or r.merchant == merchant })
  if hit {
    list.map(rs, fn (r :: Rev) -> Rev { if r.merchant == merchant { { merchant: r.merchant, revenue: r.revenue + amount } } else { r } })
  } else {
    list.concat(rs, [{ merchant: merchant, revenue: amount }])
  }
}

# Running tally as we fold the trail.
type Tally = { intact :: Bool, settled :: Int, approved :: Int, denied :: Int, rogue :: Bool, over_tx :: Bool, revs :: List[Rev] }

fn step(b :: Budget, t :: Tally, l :: tf.Line) -> Tally {
  let intact := t.intact and tf.line_intact(l)
  if l.kind == "spend.outcome" {
    match (json.parse(l.payload_json) :: Result[Outcome, Str]) {
      Err(_) => { intact: intact, settled: t.settled, approved: t.approved, denied: t.denied, rogue: t.rogue, over_tx: t.over_tx, revs: t.revs },
      Ok(o) => {
        let rogue := t.rogue or not list_has(b.merchants_allow, o.merchant)
        let over_tx := t.over_tx or (b.cap_per_transaction > 0 and o.amount > b.cap_per_transaction)
        { intact: intact, settled: t.settled + o.amount, approved: t.approved + 1, denied: t.denied, rogue: rogue, over_tx: over_tx, revs: add_rev(t.revs, o.merchant, o.amount) }
      },
    }
  } else {
    if l.kind == "spend.denied" {
      { intact: intact, settled: t.settled, approved: t.approved, denied: t.denied + 1, rogue: t.rogue, over_tx: t.over_tx, revs: t.revs }
    } else {
      { intact: intact, settled: t.settled, approved: t.approved, denied: t.denied, rogue: t.rogue, over_tx: t.over_tx, revs: t.revs }
    }
  }
}

# ── verdict ──────────────────────────────────────────────────────────────────
# verified = the trail is intact AND every settlement respected the budget.
type Verdict = { verified :: Bool, intact :: Bool, compliant :: Bool, has_budget :: Bool, settled :: Int, approved :: Int, denied :: Int, over_cap :: Bool, rogue :: Bool, over_tx :: Bool, revs :: List[Rev] }

fn verdict(lines :: List[tf.Line]) -> Verdict {
  let br := read_budget(lines)
  let has_budget := tup.fst(br)
  let b := tup.snd(br)
  let t := list.fold(lines, { intact: true, settled: 0, approved: 0, denied: 0, rogue: false, over_tx: false, revs: [] }, fn (acc :: Tally, l :: tf.Line) -> Tally { step(b, acc, l) })
  let over_cap := b.cap_total > 0 and t.settled > b.cap_total
  let compliant := has_budget and not t.rogue and not t.over_tx and not over_cap
  { verified: t.intact and compliant, intact: t.intact, compliant: compliant, has_budget: has_budget, settled: t.settled, approved: t.approved, denied: t.denied, over_cap: over_cap, rogue: t.rogue, over_tx: t.over_tx, revs: t.revs }
}

# top-earning seller (by recomputed revenue); "" if none.
fn top_seller(v :: Verdict) -> Str {
  let r := list.fold(v.revs, ("", 0 - 1), fn (acc :: (Str, Int), x :: Rev) -> (Str, Int) {
    if x.revenue > tup.snd(acc) { (x.merchant, x.revenue) } else { acc }
  })
  tup.fst(r)
}

fn revs_json(revs :: List[Rev]) -> Str {
  str.join(["[", str.join(list.map(revs, fn (r :: Rev) -> Str {
    str.join(["{\"merchant\":\"", r.merchant, "\",\"revenue\":", int.to_str(r.revenue), "}"], "")
  }), ","), "]"], "")
}

fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"compliant\":", b(v.compliant),
            ",\"has_budget\":", b(v.has_budget), ",\"settled\":", int.to_str(v.settled),
            ",\"approved\":", int.to_str(v.approved), ",\"denied\":", int.to_str(v.denied),
            ",\"over_cap\":", b(v.over_cap), ",\"rogue\":", b(v.rogue), ",\"over_tx\":", b(v.over_tx),
            ",\"top_seller\":\"", top_seller(v), "\",\"sellers\":", revs_json(v.revs), "}"], "")
}

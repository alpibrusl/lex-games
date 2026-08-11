# lex-games — Stable Training verifier (idle/incremental economy → capability)
#
# A "stable" (a manager's persistent agent) trains between matches: it earns a
# budget passively over real elapsed time, reinvests it into automation tiers
# (exponential cost, linear rate gain), and may PRESTIGE — cash in accumulated
# budget for a permanent rate bonus, resetting budget and tier back to zero.
# This is the classic incremental-game loop (accrue → reinvest → automate →
# prestige), replayed and recomputed exactly like every other lex-game:
#
#   * integrity — each line's content id recomputes (tamper-evident)
#   * legal     — every checkpoint names a known action
#   * elapsed time is NEVER a client claim — it's the delta between consecutive
#     recorded lines' own `ts_ms`, which `record()` stamps server-side (see
#     lex_games.record, effect [sql, time]). A trail cannot claim more idle
#     time than actually passed: tf.line_intact() ties ts_ms into the line's
#     content-addressed id, so back-dating a checkpoint breaks integrity.
#   * budget/tier/prestige are NEVER claimed either — every number here is
#     re-derived purely from (elapsed time, action sequence). There is nothing
#     for a forged trail to lie about except the action list itself.
#
# The verdict's `capability_level` is what a Stable earned — a monotonic,
# capped function of tier + prestige_count. It is NOT itself a usable grant:
# minting a signed lex_games.issue_capability_grant() token from it is a
# server-side step (same trust boundary as issue_match_token — see
# docs/CAPABILITY_GRANTS.md), done only after this verdict confirms
# verified=true. A match verifier elsewhere then trusts that signed token
# without re-replaying this trail.
#
# Effects: pure.

import "std.str"   as str
import "std.int"   as int
import "std.list"  as list
import "std.json"  as json
import "std.tuple" as tup

import "../arena/trail_file" as tf

# ── 1. RULES ──────────────────────────────────────────────────────────────────
# Pure, deterministic, replace-me constants — the whole economy is these five.
fn base_rate() -> Int { 10 }              # budget/sec earned at tier 0
fn max_tier() -> Int { 40 }               # hard cap: keeps tier_cost() in range
fn tier_cost(tier :: Int) -> Int { 100 * pow2_nonneg(tier) }
fn pow2_nonneg(n :: Int) -> Int { if n <= 0 { 1 } else { 2 * pow2_nonneg(n - 1) } }
fn prestige_threshold() -> Int { 5000 }   # budget-since-last-prestige per +1 permanent rate
fn prestige_gain(budget_since_prestige :: Int) -> Int { budget_since_prestige / prestige_threshold() }
fn rate(tier :: Int, prestige_mult :: Int) -> Int { base_rate() * (tier + 1) + prestige_mult }
fn capability_cap() -> Int { 10 }
fn capability_level(tier :: Int, prestige_count :: Int) -> Int {
  let raw := tier + prestige_count * 3
  if raw > capability_cap() { capability_cap() } else { raw }
}

# The opening commitment: which agent this training trail is for.
type Opened = { agent_id :: Str }
# The move payload: one decision per checkpoint. "idle" just anchors elapsed
# time without spending anything (a deliberate no-op, e.g. "wait and watch").
type Checkpoint = { action :: Str }

# ── 2. REPLAY STATE ───────────────────────────────────────────────────────────
type RState = {
  intact          :: Bool,
  legal           :: Bool,
  has_anchor      :: Bool,
  last_ts_ms      :: Int,
  budget          :: Int,
  tier            :: Int,
  prestige_mult   :: Int,
  prestige_count  :: Int,
  lifetime_budget :: Int,
  checkpoints     :: Int,
}

fn init() -> RState {
  { intact: true, legal: true, has_anchor: false, last_ts_ms: 0, budget: 0, tier: 0, prestige_mult: 0, prestige_count: 0, lifetime_budget: 0, checkpoints: 0 }
}

# Accrue budget for the real time between this line and the previous one. The
# FIRST line in a trail only sets the anchor (nothing has "elapsed" yet).
fn accrue(st :: RState, ts_ms :: Int) -> RState {
  if not st.has_anchor {
    { intact: st.intact, legal: st.legal, has_anchor: true, last_ts_ms: ts_ms, budget: st.budget, tier: st.tier, prestige_mult: st.prestige_mult, prestige_count: st.prestige_count, lifetime_budget: st.lifetime_budget, checkpoints: st.checkpoints }
  } else {
    let dt := ts_ms - st.last_ts_ms
    let dt_ok := if dt > 0 { dt } else { 0 }
    let earned := (rate(st.tier, st.prestige_mult) * dt_ok) / 1000
    { intact: st.intact, legal: st.legal, has_anchor: true, last_ts_ms: ts_ms, budget: st.budget + earned, tier: st.tier, prestige_mult: st.prestige_mult, prestige_count: st.prestige_count, lifetime_budget: st.lifetime_budget + earned, checkpoints: st.checkpoints }
  }
}

# "invest": buy the next tier if (recomputed, never claimed) budget covers its
# (fixed, deterministic) cost. Otherwise a harmless no-op — not enough saved
# yet, which is a strategy outcome, not an illegal move.
fn apply_invest(st :: RState) -> RState {
  if st.tier >= max_tier() {
    st
  } else {
    let cost := tier_cost(st.tier)
    if st.budget >= cost {
      { intact: st.intact, legal: st.legal, has_anchor: st.has_anchor, last_ts_ms: st.last_ts_ms, budget: st.budget - cost, tier: st.tier + 1, prestige_mult: st.prestige_mult, prestige_count: st.prestige_count, lifetime_budget: st.lifetime_budget, checkpoints: st.checkpoints }
    } else {
      st
    }
  }
}

# "prestige": cash in budget earned since the last prestige (NOT lifetime —
# lifetime never resets, so basing the gain on it would let repeated prestige
# checkpoints double-count the same earnings) for a permanent rate bonus.
fn apply_prestige(st :: RState) -> RState {
  let gain := prestige_gain(st.budget)
  if gain <= 0 {
    st
  } else {
    { intact: st.intact, legal: st.legal, has_anchor: st.has_anchor, last_ts_ms: st.last_ts_ms, budget: 0, tier: 0, prestige_mult: st.prestige_mult + gain, prestige_count: st.prestige_count + 1, lifetime_budget: st.lifetime_budget, checkpoints: st.checkpoints }
  }
}

fn mk(st :: RState, intact :: Bool, legal :: Bool, checkpoints :: Int) -> RState {
  { intact: intact, legal: legal, has_anchor: st.has_anchor, last_ts_ms: st.last_ts_ms, budget: st.budget, tier: st.tier, prestige_mult: st.prestige_mult, prestige_count: st.prestige_count, lifetime_budget: st.lifetime_budget, checkpoints: checkpoints }
}

# Apply one recorded trail line. `training.opened` only anchors the clock;
# every `checkpoint` accrues idle time first, then applies its action.
fn step(st :: RState, l :: tf.Line) -> RState {
  let intact := st.intact and tf.line_intact(l)
  let st0 := accrue(st, l.ts_ms)
  if l.kind != "checkpoint" {
    mk(st0, intact, st.legal, st0.checkpoints)
  } else {
    let parsed :: Result[Checkpoint, Str] := json.parse(l.payload_json)
    match parsed {
      Err(_) => mk(st0, intact, false, st0.checkpoints + 1),
      Ok(c) => {
        let known := c.action == "invest" or c.action == "prestige" or c.action == "idle"
        let st1 := if c.action == "invest" { apply_invest(st0) } else { if c.action == "prestige" { apply_prestige(st0) } else { st0 } }
        mk(st1, intact, st.legal and known, st1.checkpoints + 1)
      },
    }
  }
}
fn replay(lines :: List[tf.Line]) -> RState { list.fold(lines, init(), step) }

# The committed agent_id (first training.opened event); "" if absent.
fn read_agent(lines :: List[tf.Line]) -> (Bool, Str) {
  list.fold(lines, (false, ""), fn (acc :: (Bool, Str), l :: tf.Line) -> (Bool, Str) {
    if tup.fst(acc) or l.kind != "training.opened" {
      acc
    } else {
      match (json.parse(l.payload_json) :: Result[Opened, Str]) { Err(_) => acc, Ok(o) => (true, o.agent_id) }
    }
  })
}

# ── 3 & 4. VERDICT ────────────────────────────────────────────────────────────
# verified = intact AND every checkpoint action was known AND the trail
# committed to an agent. `score` is lifetime_budget (what the leaderboard
# ranks — total training output, prestige resets included). `capability_level`
# is the separate, capped number a match verifier's grant should be minted at.
type Verdict = {
  verified         :: Bool,
  intact           :: Bool,
  legal            :: Bool,
  has_agent        :: Bool,
  agent_id         :: Str,
  budget           :: Int,
  tier             :: Int,
  prestige_count   :: Int,
  lifetime_budget  :: Int,
  capability_level :: Int,
  checkpoints      :: Int,
  score            :: Int,
}

fn verdict(lines :: List[tf.Line]) -> Verdict {
  let ar := read_agent(lines)
  let has_agent := tup.fst(ar)
  let agent_id := tup.snd(ar)
  let r := replay(lines)
  let level := capability_level(r.tier, r.prestige_count)
  {
    verified:         r.intact and r.legal and has_agent,
    intact:           r.intact,
    legal:            r.legal,
    has_agent:        has_agent,
    agent_id:         agent_id,
    budget:           r.budget,
    tier:             r.tier,
    prestige_count:   r.prestige_count,
    lifetime_budget:  r.lifetime_budget,
    capability_level: level,
    checkpoints:      r.checkpoints,
    score:            r.lifetime_budget,
  }
}

fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"legal\":", b(v.legal),
            ",\"has_agent\":", b(v.has_agent), ",\"agent_id\":\"", v.agent_id, "\",\"budget\":", int.to_str(v.budget),
            ",\"tier\":", int.to_str(v.tier), ",\"prestige_count\":", int.to_str(v.prestige_count),
            ",\"lifetime_budget\":", int.to_str(v.lifetime_budget), ",\"capability_level\":", int.to_str(v.capability_level),
            ",\"checkpoints\":", int.to_str(v.checkpoints), ",\"score\":", int.to_str(v.score), "}"], "")
}

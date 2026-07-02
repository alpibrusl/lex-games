# lex-games arena — DID-anchored agent reputation registry (a2p trustMetrics,
# made persistent + verifiable).
#
# The seasons (nbazaar_season / bazaar_season) RECOMPUTE a ranking from one
# manifest. A platform needs reputation that an agent OWNS and that ACCUMULATES:
# keyed by its did:lex identity, carried forward across rounds. This registry is
# that store — and it holds the arena's core rule: **a submission is a trail,
# not a score**. A batch row names a session's TRAIL and the game it claims to
# be; the registry replays that trail through the game's own verifier and
# credits only the RECOMPUTED score, only when the replay verifies. Nothing in
# the batch is trusted: a forged, tampered, or non-compliant session contributes
# nothing regardless of what it claims to have earned. (Attribution — which DID
# played which seat — is claimed by the submitter, same caveat as model
# attribution everywhere in the arena.)
#
# Persistence is stdout → file, so a registry chains like a season:
#   lex run --allow-effects io src/arena/reputation.lex run '"none.json"'  '"round1.json"' > reg.json
#   lex run --allow-effects io src/arena/reputation.lex run '"reg.json"'   '"round2.json"' > reg2.json
#
# Effects: io (read prior + batch + trails, print).

import "std.io"   as io
import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "./trail_file"        as tf
import "../games/bazaar"     as bazaar
import "../games/nbazaar"    as nbazaar
import "../games/gbazaar"    as gbazaar
import "../games/consent"    as consent
import "../games/capability" as capability
import "../games/ops"        as ops
import "../games/template"   as template
import "../games/robot_task" as robot_task

# One batch row: a session attributed to an agent DID. `trail` is the
# submission; `game` picks the verifier that replays it; `seat` is the agent's
# side in multi-seat games (1-based; pass 0 for single-principal games);
# `won` marks a head-to-head win.
type Entry   = { did :: Str, game :: Str, trail :: Str, seat :: Int, won :: Bool }
# trustMetrics: the agent's accumulated, owned reputation.
type Profile = { did :: Str, reputation :: Int, sessions :: Int, wins :: Int }

# What a replay yields: the verdict + the recomputed score credited to the DID.
type Replayed = { verified :: Bool, score :: Int }

fn nth_int(xs :: List[Int], i :: Int) -> Int {
  match list.head(xs) { None => 0, Some(h) => if i <= 0 { h } else { nth_int(list.tail(xs), i - 1) } }
}

# The score per game is the verifier's own success measure:
#   bazaar/template: the seat's drafted value      nbazaar: the seat's score
#   robot_task: the referee score                  gbazaar/capability: settled amount
#   consent: grants honored within policy          ops: tool calls within policy
fn replay(game :: Str, lines :: List[tf.Line], seat :: Int) -> Replayed {
  if game == "bazaar" {
    let v := bazaar.verdict(lines)
    { verified: v.verified, score: if seat == 2 { v.p2 } else { v.p1 } }
  } else {
  if game == "template" {
    let v := template.verdict(lines)
    { verified: v.verified, score: if seat == 2 { v.p2 } else { v.p1 } }
  } else {
  if game == "nbazaar" {
    let v := nbazaar.verdict(lines)
    { verified: v.verified, score: nth_int(v.scores, seat - 1) }
  } else {
  if game == "gbazaar" {
    let v := gbazaar.verdict(lines)
    { verified: v.verified, score: v.settled }
  } else {
  if game == "consent" {
    let v := consent.verdict(lines)
    { verified: v.verified, score: v.grants }
  } else {
  if game == "capability" {
    let v := capability.verdict(lines)
    { verified: v.verified, score: v.settled }
  } else {
  if game == "ops" {
    let v := ops.verdict(lines)
    { verified: v.verified, score: v.ok }
  } else {
  if game == "robot_task" {
    let v := robot_task.verdict(lines)
    { verified: v.verified, score: v.score }
  } else {
    # unknown game → nothing to replay → contributes nothing
    { verified: false, score: 0 }
  }}}}}}}}
}

# Replay one entry's trail. Unreadable trail = unverified (void), like a season.
fn replay_entry(e :: Entry) -> [io] Replayed {
  match tf.read_jsonl(e.trail) {
    Err(_) => { verified: false, score: 0 },
    Ok(lines) => replay(e.game, lines, e.seat),
  }
}

fn upsert(ps :: List[Profile], e :: Entry, score :: Int) -> List[Profile] {
  let hit := list.fold(ps, false, fn (a :: Bool, p :: Profile) -> Bool { a or p.did == e.did })
  let w := if e.won { 1 } else { 0 }
  if hit {
    list.map(ps, fn (p :: Profile) -> Profile {
      if p.did == e.did { { did: p.did, reputation: p.reputation + score, sessions: p.sessions + 1, wins: p.wins + w } } else { p }
    })
  } else {
    list.concat(ps, [{ did: e.did, reputation: score, sessions: 1, wins: w }])
  }
}

type FoldAcc = { profiles :: List[Profile], verified :: Int, void :: Int }

# Fold one batch into the registry — each entry's trail is replayed and only a
# VERIFIED replay credits its recomputed score (the integrity rule: reputation
# accrues solely from sessions whose trail replays clean).
fn fold_entry(acc :: FoldAcc, e :: Entry) -> [io] FoldAcc {
  let r := replay_entry(e)
  if r.verified {
    { profiles: upsert(acc.profiles, e, r.score), verified: acc.verified + 1, void: acc.void }
  } else {
    { profiles: acc.profiles, verified: acc.verified, void: acc.void + 1 }
  }
}
fn apply_batch(prior :: List[Profile], batch :: List[Entry]) -> [io] FoldAcc {
  list.fold(batch, { profiles: prior, verified: 0, void: 0 }, fold_entry)
}

fn ranked(ps :: List[Profile]) -> List[Profile] { list.sort_by(ps, fn (p :: Profile) -> Int { 0 - p.reputation }) }

fn profile_json(rank :: Int, p :: Profile) -> Str {
  str.join(["{\"rank\":", int.to_str(rank), ",\"did\":\"", p.did, "\",\"reputation\":", int.to_str(p.reputation),
            ",\"sessions\":", int.to_str(p.sessions), ",\"wins\":", int.to_str(p.wins), "}"], "")
}
type RankAcc = { rank :: Int, parts :: List[Str] }
fn profiles_json(sorted :: List[Profile]) -> Str {
  let acc := list.fold(sorted, { rank: 1, parts: [] }, fn (a :: RankAcc, p :: Profile) -> RankAcc {
    { rank: a.rank + 1, parts: list.concat(a.parts, [profile_json(a.rank, p)]) }
  })
  str.join(acc.parts, ",")
}

# The persisted registry round-trips: `run` prints {profiles:[...]} so the next
# round can read it back. (json.parse ignores the wrapper's extra fields + rank.)
type Prior = { profiles :: List[Profile] }
fn load_prior(path :: Str) -> [io] Result[List[Profile], Str] {
  match io.read(path) {
    Err(_) => Ok([]),
    Ok(content) => {
      let parsed :: Result[Prior, Str] := json.parse(content)
      match parsed { Err(e) => Err(e), Ok(p) => Ok(p.profiles) }
    },
  }
}

fn err(msg :: Str) -> [io] Int { let _ := io.print(msg) 1 }

fn run(registry_path :: Str, batch_path :: Str) -> [io] Int {
  match load_prior(registry_path) {
    Err(e) => err(str.concat("{\"error\":\"bad registry json: ", str.concat(e, "\"}"))),
    Ok(prior) => {
      match io.read(batch_path) {
        Err(e) => err(str.concat("{\"error\":\"cannot read batch: ", str.concat(e, "\"}"))),
        Ok(content) => {
          let parsed :: Result[List[Entry], Str] := json.parse(content)
          match parsed {
            Err(e) => err(str.concat("{\"error\":\"bad batch json: ", str.concat(e, "\"}"))),
            Ok(batch) => {
              let acc := apply_batch(prior, batch)
              let next := ranked(acc.profiles)
              let out := str.join(["{\"kind\":\"reputation\",\"players\":", int.to_str(list.len(next)),
                                   ",\"verified\":", int.to_str(acc.verified),
                                   ",\"void\":", int.to_str(acc.void),
                                   ",\"profiles\":[", profiles_json(next), "]}"], "")
              let _ := io.print(out)
              0
            },
          }
        },
      }
    },
  }
}

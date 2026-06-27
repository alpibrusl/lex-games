# lex-games arena — DID-anchored agent reputation registry (a2p trustMetrics,
# made persistent + verifiable).
#
# The seasons (nbazaar_season / bazaar_season) RECOMPUTE a ranking from one
# manifest. A platform needs reputation that an agent OWNS and that ACCUMULATES:
# keyed by its did:lex identity, carried forward across rounds. This registry is
# that store. It folds a batch of session results — each attributed to an agent
# DID, each carrying the verdict from replaying its trail — into per-DID
# trustMetrics, counting ONLY sessions that verified. So an agent's reputation is
# always traceable to verified work: you cannot buy a rating with a forged or
# tampered session (its verdict is verified:false → it contributes nothing).
#
# Persistence is stdout → file, so a registry chains like a season:
#   lex run --allow-effects io src/arena/reputation.lex run '"none.json"'  '"round1.json"' > reg.json
#   lex run --allow-effects io src/arena/reputation.lex run '"reg.json"'   '"round2.json"' > reg2.json
#
# Effects: io (read prior + batch, print).

import "std.io"   as io
import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

# One batch row: a session result attributed to an agent DID. `verified` is the
# replay verdict (from gbazaar / capability / nbazaar / …); `score` is what the
# session earned; `won` marks a head-to-head win (optional, default false).
type Entry   = { did :: Str, score :: Int, verified :: Bool, won :: Bool }
# trustMetrics: the agent's accumulated, owned reputation.
type Profile = { did :: Str, reputation :: Int, sessions :: Int, wins :: Int }

fn upsert(ps :: List[Profile], e :: Entry) -> List[Profile] {
  let hit := list.fold(ps, false, fn (a :: Bool, p :: Profile) -> Bool { a or p.did == e.did })
  let w := if e.won { 1 } else { 0 }
  if hit {
    list.map(ps, fn (p :: Profile) -> Profile {
      if p.did == e.did { { did: p.did, reputation: p.reputation + e.score, sessions: p.sessions + 1, wins: p.wins + w } } else { p }
    })
  } else {
    list.concat(ps, [{ did: e.did, reputation: e.score, sessions: 1, wins: w }])
  }
}

# Fold one batch into the registry — VERIFIED entries only (the integrity rule:
# reputation accrues solely from sessions whose trail replays clean).
fn apply_batch(prior :: List[Profile], batch :: List[Entry]) -> List[Profile] {
  list.fold(batch, prior, fn (acc :: List[Profile], e :: Entry) -> List[Profile] {
    if e.verified { upsert(acc, e) } else { acc }
  })
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
              let next := ranked(apply_batch(prior, batch))
              let out := str.join(["{\"kind\":\"reputation\",\"players\":", int.to_str(list.len(next)),
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

# lex-games arena — Governed Bazaar seller reputation (revenue over many sessions).
#
# nbazaar_season ranks game models by ELO. A marketplace ranks SELLERS by the
# business they actually, verifiably did. This reads a manifest of governed
# bazaar sessions (each a spend trail), replays each through the gbazaar verifier,
# and — counting ONLY sessions that verify (intact + compliant) — accumulates per
# seller: total revenue, deals closed, and sessions appeared in. A tampered or
# non-compliant session is void: its sellers earn nothing from it, so you can't
# pad a reputation with a forged trail.
#
# Read-only; prints the reputation board as one JSON line (same wrapper shape the
# lobby leaderboard fetches):
#
#   lex run --allow-effects io src/arena/bazaar_season.lex run '"sessions.json"'

import "std.io"   as io
import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "./trail_file"     as tf
import "../games/gbazaar" as gb

# One manifest row: the path to a session's spend trail.
type Sess   = { trail :: Str }
type Seller = { merchant :: Str, revenue :: Int, deals :: Int, sessions :: Int }
type Acc    = { sellers :: List[Seller], verified :: Int, void :: Int }

# Fold one seller's session contribution (find-or-add).
fn add_seller(ss :: List[Seller], merchant :: Str, rev :: Int, deals :: Int) -> List[Seller] {
  let hit := list.fold(ss, false, fn (a :: Bool, s :: Seller) -> Bool { a or s.merchant == merchant })
  if hit {
    list.map(ss, fn (s :: Seller) -> Seller { if s.merchant == merchant { { merchant: s.merchant, revenue: s.revenue + rev, deals: s.deals + deals, sessions: s.sessions + 1 } } else { s } })
  } else {
    list.concat(ss, [{ merchant: merchant, revenue: rev, deals: deals, sessions: 1 }])
  }
}

# Replay one session; fold its sellers only if the session verifies.
fn fold_one(acc :: Acc, s :: Sess) -> [io] Acc {
  match tf.read_jsonl(s.trail) {
    Err(_) => { sellers: acc.sellers, verified: acc.verified, void: acc.void + 1 },
    Ok(lines) => {
      let v := gb.verdict(lines)
      if v.verified {
        let sellers2 := list.fold(v.revs, acc.sellers, fn (a :: List[Seller], r :: gb.Rev) -> List[Seller] { add_seller(a, r.merchant, r.revenue, r.deals) })
        { sellers: sellers2, verified: acc.verified + 1, void: acc.void }
      } else {
        { sellers: acc.sellers, verified: acc.verified, void: acc.void + 1 }
      }
    },
  }
}

fn ranked(ss :: List[Seller]) -> List[Seller] { list.sort_by(ss, fn (s :: Seller) -> Int { 0 - s.revenue }) }

fn seller_json(rank :: Int, s :: Seller) -> Str {
  str.join(["{\"rank\":", int.to_str(rank), ",\"merchant\":\"", s.merchant, "\"",
            ",\"revenue\":", int.to_str(s.revenue), ",\"deals\":", int.to_str(s.deals),
            ",\"sessions\":", int.to_str(s.sessions), "}"], "")
}
type RankAcc = { rank :: Int, parts :: List[Str] }
fn sellers_json(sorted :: List[Seller]) -> Str {
  let acc := list.fold(sorted, { rank: 1, parts: [] }, fn (a :: RankAcc, s :: Seller) -> RankAcc {
    { rank: a.rank + 1, parts: list.concat(a.parts, [seller_json(a.rank, s)]) }
  })
  str.join(acc.parts, ",")
}

fn err(msg :: Str) -> [io] Int { let _ := io.print(msg) 1 }

fn run(manifest_path :: Str) -> [io] Int {
  match io.read(manifest_path) {
    Err(e) => err(str.concat("{\"error\":\"cannot read manifest: ", str.concat(e, "\"}"))),
    Ok(content) => {
      let parsed :: Result[List[Sess], Str] := json.parse(content)
      match parsed {
        Err(e) => err(str.concat("{\"error\":\"bad manifest json: ", str.concat(e, "\"}"))),
        Ok(sessions) => {
          let acc := list.fold(sessions, { sellers: [], verified: 0, void: 0 }, fold_one)
          let board := ranked(acc.sellers)
          let out := str.join(["{\"game\":\"bazaar\",\"sessions\":", int.to_str(list.len(sessions)),
                               ",\"verified\":", int.to_str(acc.verified),
                               ",\"void\":", int.to_str(acc.void),
                               ",\"sellers\":[", sellers_json(board), "]}"], "")
          let _ := io.print(out)
          0
        },
      }
    },
  }
}

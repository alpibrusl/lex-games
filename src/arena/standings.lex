# lex-games arena — ELO standings & round-robin (pure; the season's referee math).
#
# Given a field of recomputed verified scores, play a deterministic round-robin
# (every i<j pairing once, decided ONLY by verified score) and fold the results
# into ELO ratings carried forward from the prior standings. No IO, no trail
# parsing — season.lex supplies the scored rows and persists the output. Pure +
# deterministic, so the same field always produces the same standings.
#
# Effects: pure.

import "std.int"  as int
import "std.list" as list
import "./elo"    as elo

type Scored   = { label :: Str, verified :: Bool, score :: Int }
type Standing = { label :: Str, rating :: Int, played :: Int, wins :: Int, draws :: Int, losses :: Int }
type Pair     = { a :: Scored, b :: Scored }

# A's result vs B as a milli-score (1000=win, 500=draw, 0=loss), decided ONLY by
# the recomputed verified scores. A disqualified (unverified) entry loses to any
# verified one; two DQs draw.
fn outcome_a(a :: Scored, b :: Scored) -> Int {
  if a.verified and b.verified {
    if a.score > b.score { 1000 } else { if a.score < b.score { 0 } else { 500 } }
  } else {
    if a.verified { 1000 } else { if b.verified { 0 } else { 500 } }
  }
}

# All i<j pairings in list order (deterministic round-robin schedule).
fn pairs_of(rows :: List[Scored]) -> List[Pair] {
  match list.head(rows) {
    None    => [],
    Some(h) => {
      let t := list.tail(rows)
      list.concat(list.map(t, fn (x :: Scored) -> Pair { { a: h, b: x } }), pairs_of(t))
    },
  }
}

fn lookup(sts :: List[Standing], label :: Str) -> Option[Standing] {
  list.fold(sts, None, fn (acc :: Option[Standing], s :: Standing) -> Option[Standing] {
    match acc { Some(_) => acc, None => if s.label == label { Some(s) } else { None } }
  })
}

fn has_standing(sts :: List[Standing], label :: Str) -> Bool {
  match lookup(sts, label) { Some(_) => true, None => false }
}

# Replace the standing with a matching label (no-op if absent).
fn set_standing(sts :: List[Standing], u :: Standing) -> List[Standing] {
  list.map(sts, fn (s :: Standing) -> Standing { if s.label == u.label { u } else { s } })
}

# Carry a participant's prior standing forward, or seed a newcomer at 1500.
fn seed_participant(prior :: List[Standing], s :: Scored) -> Standing {
  match lookup(prior, s.label) {
    Some(p) => p,
    None    => { label: s.label, rating: elo.seed(), played: 0, wins: 0, draws: 0, losses: 0 },
  }
}

fn tally(s :: Standing, new_rating :: Int, o_milli :: Int) -> Standing {
  { label: s.label, rating: new_rating, played: s.played + 1,
    wins:   s.wins   + (if o_milli == 1000 { 1 } else { 0 }),
    draws:  s.draws  + (if o_milli == 500  { 1 } else { 0 }),
    losses: s.losses + (if o_milli == 0    { 1 } else { 0 }) }
}

# Play one pairing: update both ratings & tallies in the working standings.
fn apply_pair(parts :: List[Standing], a :: Scored, b :: Scored) -> List[Standing] {
  match lookup(parts, a.label) { None => parts, Some(sa) =>
  match lookup(parts, b.label) { None => parts, Some(sb) => {
    let oa := outcome_a(a, b)
    let na := elo.update_one(sa.rating, sb.rating, oa)
    let nb := elo.update_one(sb.rating, sa.rating, 1000 - oa)
    set_standing(set_standing(parts, tally(sa, na, oa)), tally(sb, nb, 1000 - oa))
  } } }
}

# Run a full round: seed participants from prior standings, play the round-robin,
# then carry forward any prior entries that didn't compete this round.
fn run_round(prior :: List[Standing], scored :: List[Scored]) -> List[Standing] {
  let parts := list.map(scored, fn (s :: Scored) -> Standing { seed_participant(prior, s) })
  let played := list.fold(pairs_of(scored), parts,
    fn (acc :: List[Standing], p :: Pair) -> List[Standing] { apply_pair(acc, p.a, p.b) })
  let carried := list.filter(prior, fn (p :: Standing) -> Bool { not has_standing(played, p.label) })
  list.concat(played, carried)
}

# Standings sorted by rating, highest first.
fn ranked(sts :: List[Standing]) -> List[Standing] {
  list.sort_by(sts, fn (s :: Standing) -> Int { 0 - s.rating })
}

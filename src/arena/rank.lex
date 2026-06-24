# lex-games arena — the canonical leaderboard ordering rule (one source of truth).
#
# Every score-ranked arena surface orders the same way: verified rows by
# DESCENDING score, with disqualified (unverified) rows sunk to the bottom —
# never dropped. The rule depends only on (verified, score), so leaderboard.lex
# (the manifest CLI) and the live policy_eval demo (lex-robot) share THIS function
# instead of each re-deriving the sign and the DQ sentinel — which is exactly how
# two copies drift. Use it as a std.list.sort_by key (ascending):
#
#   list.sort_by(rows, fn (r :: Row) -> Int { rank.key(r.verified, r.score) })
#
# (The ELO season ranks by rating instead — a deliberately different rule, so it
# does not use this.)
#
# Effects: pure.

# A disqualified row sorts after every verified one (any real score < this).
fn dq_key() -> Int { 1000000 }

# Ascending sort key: verified → -score (higher score first); DQ → the sentinel.
fn key(verified :: Bool, score :: Int) -> Int { if verified { 0 - score } else { dq_key() } }

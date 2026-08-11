# Capability grants (cross-trail)

Every verifier in this repo replays ONE trail. A capability grant is the
mechanism for when a fact needs to travel from one already-verified trail
into a different one — e.g. a stable's training run (`stable_training.lex`)
should be able to make a match play stronger without the match verifier
having to re-replay the entire training history on every match.

## Why not just re-replay the source trail?

You could — a match verifier is free to import another game's `verdict()`
and fold its trail in directly (same pattern `capability.lex` uses to fuse
`gbazaar` + `consent` into one policy). That's the right call when the two
trails are genuinely part of one session. It's the wrong call when the
source trail is long-running and mostly irrelevant to the match itself (a
stable might train for weeks; nobody wants every match's verifier pulling
in weeks of checkpoint history just to learn one number).

## The mechanism

`src/lex_games.lex` provides a signed, expiring, cross-trail attestation —
the same trust shape as `issue_match_token`/`match_token_side`, generalized
from "grant a side for one match" to "grant a capability level, earned on
some other trail, to one agent":

```
issue_capability_grant(secret, agent_id, capability, level, source_root, expires_at_ms) -> Str
capability_grant_claim(pubkey_b64, token, agent_id, now_ms) -> GrantClaim
```

**Minting** happens server-side, in the arena worker — never inside a pure
verifier — and only after the worker has itself called the source game's
`verdict()` and seen `verified = true`:

```
if stable_training.verdict(training_lines).verified {
  let v := stable_training.verdict(training_lines)
  let grant := lex_games.issue_capability_grant(
    arena_secret, v.agent_id, "stable_training", v.capability_level,
    /* source_root = */ head_event_id_of(training_lines), expires_at_ms)
  # grant is handed to the play surface, which records it as the first
  # line of the MATCH trail (e.g. kind "capability.granted").
}
```

`source_root` — the training trail's own head event id — makes the grant
traceable back to the exact trail it was earned on, not just an asserted
number. It isn't re-verified by the match (that would defeat the point of
not re-replaying), but it makes the provenance auditable after the fact.

**Consuming** happens inside a match verifier, the same way `gbazaar.lex`
reads its `budget.opened` line — scan for the grant, then check every use
of the capability against it:

```
type Grant = { agent_id :: Str, capability :: Str, token :: Str }

fn read_grant(lines :: List[tf.Line]) -> (Bool, Grant) {
  list.fold(lines, (false, { agent_id: "", capability: "", token: "" }), fn (acc, l) {
    if tup.fst(acc) or l.kind != "capability.granted" { acc } else {
      match (json.parse(l.payload_json) :: Result[Grant, Str]) { Err(_) => acc, Ok(g) => (true, g) }
    }
  })
}

# then, once per replay:
let claim := lex_games.capability_grant_claim(arena_pubkey, g.token, g.agent_id, match_started_at_ms)
# claim.ok == false -> treat as capability_level = 0 (refuse, don't downgrade
# to "trust the claim" — an expired or forged grant is no grant at all).
```

A forged or expired grant fails `capability_grant_claim` (signature/agent/
expiry check), so a match verifier never has to trust a bare number sitting
in someone's trail — only a signature it can check with a public key.

## What this does and doesn't buy you

- It buys you: a match verifier that doesn't need the source repo's
  training-game module as a dependency, doesn't need the (possibly huge)
  training trail as part of the upload, and still can't be fooled by a
  claimed capability level.
- It does NOT buy you: proof that the capability level is *correct* beyond
  "the arena's signing key vouched for it once." If you don't trust the
  arena worker's own replay step, this mechanism doesn't help — same as
  `issue_match_token` already assumes the arena correctly authenticated the
  session before signing. Keep the minting step small, server-side, and
  itself covered by tests.

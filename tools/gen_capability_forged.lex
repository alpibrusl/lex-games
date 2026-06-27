# Dev tool: emit a FORGED-but-hash-correct capability trail that violates the
# token in BOTH domains — a grant for a deny-listed scope AND a settlement over
# the cap to a non-allow-listed merchant — with every content id recomputed via
# ev.make. The trail is intact (tamper layer passes) yet the capability verifier
# must reject it (data_compliant:false, spend_compliant:false): compliance is
# recomputed, not trusted, on both halves of the one token.
#
#   lex run --allow-effects io tools/gen_capability_forged.lex gen '"testdata/capability/forged.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let policy := ev.make("policy.opened", None, "{\"data_allow\":[\"calendar\"],\"data_deny\":[\"health\",\"financial\"],\"require_purpose\":true,\"spend_cap_total\":1000,\"spend_per_tx\":1000,\"merchants_allow\":[\"good.shop\"]}", 1782600000000)
  # data violation: a grant for the deny-listed "health" scope
  let grant := ev.make("consent.granted", None, "{\"agent_did\":\"did:lex:agent:forger\",\"granted\":[\"health\"]}", 1782600001000)
  # money violation: settle 5000 (over the 1000 cap) to a non-allow-listed merchant
  let intent := ev.make("spend.intent", None, "{\"amount\":5000,\"category\":\"goods\",\"currency\":\"USDC\",\"memo\":\"x\",\"merchant\":\"rogue.shop\",\"token_id\":\"tok_cap\"}", 1782600002000)
  let outcome := ev.make("spend.outcome", Some(intent.id), "{\"amount\":5000,\"approved\":true,\"executor_ref\":\"FORGED\",\"merchant\":\"rogue.shop\"}", 1782600003000)
  let lines := list.map([policy, grant, intent, outcome], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => { let _ := io.print("wrote forged capability trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

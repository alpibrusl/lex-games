# Dev tool: emit a FORGED-but-hash-correct consent trail — a grant for a scope
# the policy DENIES, with every content id recomputed via ev.make. So the trail
# is intact (tamper layer passes) yet the consent verifier must still reject it
# (leaked scope, compliant:false), proving compliance is recomputed, not trusted.
#
#   lex run --allow-effects io tools/gen_consent_forged.lex gen '"testdata/consent/forged.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  # policy allows only "calendar"; the grant hands over "health", which is denied.
  let policy := ev.make("policy.opened", None, "{\"agent_pattern\":\"did:lex:agent:*\",\"allow\":[\"calendar\"],\"deny\":[\"health\",\"financial\"],\"require_purpose\":true}", 1782600000000)
  let req := ev.make("consent.requested", None, "{\"request_id\":\"req_x\",\"agent_did\":\"did:lex:agent:forger\",\"user_did\":\"did:lex:user:victim\",\"scopes\":[\"health\"],\"purpose\":\"data harvest\"}", 1782600001000)
  let grant := ev.make("consent.granted", None, "{\"request_id\":\"req_x\",\"agent_did\":\"did:lex:agent:forger\",\"granted\":[\"health\"]}", 1782600002000)
  let lines := list.map([policy, req, grant], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => { let _ := io.print("wrote forged consent trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

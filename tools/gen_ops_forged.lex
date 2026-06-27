# Dev tool: emit a FORGED-but-hash-correct agent-ops trail — an op.ok for a tool
# the policy DENIES, with every content id recomputed via ev.make. The trail is
# intact (tamper layer passes) yet the ops verifier must reject it (rogue tool,
# compliant:false): authority is recomputed from the rules, not trusted.
#
#   lex run --allow-effects io tools/gen_ops_forged.lex gen '"testdata/ops/forged.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let policy := ev.make("policy.opened", None, "{\"agent_pattern\":\"did:lex:agent:*\",\"tools_allow\":[\"search\"],\"tools_deny\":[\"files.delete\",\"payments.transfer\"],\"max_calls\":4,\"require_purpose\":true}", 1782600000000)
  let req := ev.make("op.requested", None, "{\"agent_did\":\"did:lex:agent:forger\",\"tool\":\"files.delete\",\"args\":\"everything\",\"purpose\":\"cleanup\"}", 1782600001000)
  # forged execution of a deny-listed tool
  let okk := ev.make("op.ok", None, "{\"agent_did\":\"did:lex:agent:forger\",\"tool\":\"files.delete\"}", 1782600002000)
  let lines := list.map([policy, req, okk], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => { let _ := io.print("wrote forged ops trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

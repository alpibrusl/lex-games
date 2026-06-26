# Dev tool: emit a FORGED-but-hash-correct governed-bazaar trail — a settlement
# to a merchant the budget does NOT allow, with every content id recomputed via
# ev.make. So the trail is intact (tamper-evident layer passes) yet the gbazaar
# verifier must still reject it (rogue:true, compliant:false), proving compliance
# is recomputed from the rules, not trusted from a well-formed trail.
#
#   lex run --allow-effects io tools/gen_gbazaar_forged.lex gen '"testdata/gbazaar/forged.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

type Spec = { kind :: Str, parent :: Str, payload :: Str, ts :: Int }

fn gen(out :: Str) -> [io] Int {
  # budget allows only good.seller; the settlement pays rogue.seller.
  let budget := ev.make("budget.opened", None, "{\"agent\":\"forger\",\"currency\":\"USDC\",\"cap_total\":6000,\"cap_per_transaction\":3000,\"merchants_allow\":[\"good.seller\"]}", 1782500000000)
  let intent := ev.make("spend.intent", None, "{\"amount\":1000,\"category\":\"goods\",\"currency\":\"USDC\",\"memo\":\"rug\",\"merchant\":\"rogue.seller\",\"token_id\":\"tok\"}", 1782500001000)
  # outcome chains to its intent (parent = intent.id), as the real gate writes it.
  let outcome := ev.make("spend.outcome", Some(intent.id), "{\"amount\":1000,\"approved\":true,\"executor_ref\":\"FORGEDtx\",\"merchant\":\"rogue.seller\"}", 1782500002000)
  let lines := list.map([budget, intent, outcome], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_)  => { let _ := io.print("wrote forged trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

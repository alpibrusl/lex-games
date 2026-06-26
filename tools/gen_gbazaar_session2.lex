# Dev tool: emit a SECOND compliant governed-bazaar session trail (correct hashes
# via ev.make) so the reputation season has a multi-session field. Three deals
# within budget to textile/pottery/books — all allow-listed, all under cap.
#
#   lex run --allow-effects io tools/gen_gbazaar_session2.lex gen '"testdata/gbazaar/session2.jsonl"'

import "std.io"   as io
import "std.str"  as str
import "std.int"  as int
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

fn intent_payload(merchant :: Str, amount :: Int, item :: Str) -> Str {
  str.join(["{\"amount\":", int.to_str(amount), ",\"category\":\"goods\",\"currency\":\"USDC\",\"memo\":\"", item, "\",\"merchant\":\"", merchant, "\",\"token_id\":\"tok2\"}"], "")
}
fn outcome_payload(merchant :: Str, amount :: Int) -> Str {
  str.join(["{\"amount\":", int.to_str(amount), ",\"approved\":true,\"executor_ref\":\"tx_", merchant, "\",\"merchant\":\"", merchant, "\"}"], "")
}

# budget.opened is a root; each spend.intent is a root; each spend.outcome chains
# to its intent (parent = intent.id) — exactly as lex-guard's gate writes them.
fn pair(merchant :: Str, amount :: Int, item :: Str, ts :: Int) -> List[ev.Event] {
  let intent := ev.make("spend.intent", None, intent_payload(merchant, amount, item), ts)
  let outcome := ev.make("spend.outcome", Some(intent.id), outcome_payload(merchant, amount), ts + 1)
  [intent, outcome]
}

fn gen(out :: Str) -> [io] Int {
  let budget := ev.make("budget.opened", None, "{\"agent\":\"shopper2\",\"currency\":\"USDC\",\"cap_total\":6000,\"cap_per_transaction\":3000,\"merchants_allow\":[\"textile.bazaar\",\"pottery.bazaar\",\"books.bazaar\"]}", 1782600000000)
  let evs := list.concat([budget], list.concat(pair("textile.bazaar", 2200, "linen bolt", 1782600001000), list.concat(pair("pottery.bazaar", 1500, "glazed jug", 1782600003000), pair("books.bazaar", 900, "illuminated codex", 1782600005000))))
  let lines := list.map(evs, tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => { let _ := io.print("wrote session2") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

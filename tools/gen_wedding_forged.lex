# Dev tool: emit a FORGED-but-hash-correct Wedding Broker trail — Deb's
# request is recorded as approved for budget_cost:50 (lying — her real cost
# is 150), letting a forged trail claim all three guests fit under budget.
# Every content id is still recomputed via ev.make (hashes are intact); the
# wedding verifier must reject it because it re-derives Deb's cost from the
# fixed table, not the recorded claim.
#
#   lex run --allow-effects io tools/gen_wedding_forged.lex gen '"testdata/wedding/forged.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let deb    := ev.make("move", None, "{\"guest\":\"deb\",\"budget_cost\":50,\"slots_cost\":1,\"decision\":\"approve\"}", 1782600000000)
  let kamala := ev.make("move", Some(deb.id), "{\"guest\":\"kamala\",\"budget_cost\":0,\"slots_cost\":1,\"decision\":\"approve\"}", 1782600001000)
  let jonah  := ev.make("move", Some(kamala.id), "{\"guest\":\"jonah\",\"budget_cost\":50,\"slots_cost\":1,\"decision\":\"approve\"}", 1782600002000)
  let lines := list.map([deb, kamala, jonah], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => { let _ := io.print("wrote forged wedding trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

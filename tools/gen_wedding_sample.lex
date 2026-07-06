# Dev tool: emit an HONEST Wedding Broker trail — Deb and Jonah approved
# (150+50=200 budget, exactly the cap; 1+1=2 slots, exactly the cap), Kamala
# denied (the venue's slot limit, not the budget, is what runs out first).
# Every content id computed via ev.make.
#
#   lex run --allow-effects io tools/gen_wedding_sample.lex gen '"testdata/wedding/session1.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let deb    := ev.make("move", None, "{\"guest\":\"deb\",\"budget_cost\":150,\"slots_cost\":1,\"decision\":\"approve\"}", 1782600000000)
  let kamala := ev.make("move", Some(deb.id), "{\"guest\":\"kamala\",\"budget_cost\":0,\"slots_cost\":0,\"decision\":\"deny\"}", 1782600001000)
  let jonah  := ev.make("move", Some(kamala.id), "{\"guest\":\"jonah\",\"budget_cost\":50,\"slots_cost\":1,\"decision\":\"approve\"}", 1782600002000)
  let lines := list.map([deb, kamala, jonah], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => { let _ := io.print("wrote honest wedding trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

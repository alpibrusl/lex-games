# Dev tool: emit an HONEST Werewolf trail — 8 seats, roles committed (1:wolf,
# 2:seer, 5:doctor, rest villagers). The doctor protects seat 6 (not the
# wolf's target, so the kill lands), the seer correctly inspects the wolf,
# and the town lynches the wolf (game over, town wins). Every content id
# computed via ev.make.
#
#   lex run --allow-effects io tools/gen_werewolf_sample.lex gen '"testdata/werewolf/session1.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let roles   := ev.make("move", None, "{\"kind\":\"roles\",\"assign\":{\"0\":\"villager\",\"1\":\"wolf\",\"2\":\"seer\",\"3\":\"villager\",\"4\":\"villager\",\"5\":\"doctor\",\"6\":\"villager\",\"7\":\"villager\"}}", 1782600000000)
  let protect := ev.make("move", Some(roles.id), "{\"kind\":\"protect\",\"by\":5,\"target\":6}", 1782600000500)
  let kill    := ev.make("move", Some(protect.id), "{\"kind\":\"kill\",\"by\":1,\"target\":3}", 1782600001000)
  let insp    := ev.make("move", Some(kill.id), "{\"kind\":\"inspect\",\"by\":2,\"target\":1,\"saw\":\"wolf\"}", 1782600002000)
  let lynch   := ev.make("move", Some(insp.id), "{\"kind\":\"lynch\",\"target\":1,\"role\":\"wolf\",\"day\":1}", 1782600003000)
  let lines := list.map([roles, protect, kill, insp, lynch], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => { let _ := io.print("wrote honest werewolf trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

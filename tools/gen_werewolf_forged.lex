# Dev tool: emit a FORGED-but-hash-correct Werewolf trail — roles are
# committed honestly (1:wolf, 2:seer, rest villagers), but the recorded kill
# claims seat 3 (a villager) made the kill, which only the wolf may do. Every
# content id is still recomputed via ev.make (hashes are intact); the
# werewolf verifier must reject it because it re-derives who the wolf
# actually is from the FIRST roles commitment, not from the kill's own claim.
#
#   lex run --allow-effects io tools/gen_werewolf_forged.lex gen '"testdata/werewolf/forged.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let roles := ev.make("move", None, "{\"kind\":\"roles\",\"assign\":{\"0\":\"villager\",\"1\":\"wolf\",\"2\":\"seer\",\"3\":\"villager\",\"4\":\"villager\"}}", 1782600000000)
  let kill  := ev.make("move", Some(roles.id), "{\"kind\":\"kill\",\"by\":3,\"target\":4}", 1782600001000)
  let lines := list.map([roles, kill], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => { let _ := io.print("wrote forged werewolf trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

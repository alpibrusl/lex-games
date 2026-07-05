# Dev tool: emit an HONEST Stamp of Destiny trail — two legal stamps of the same
# goods_certification chit, one reversed (legal but doesn't solve Bosun's case)
# then one right-side up (the solve), every content id computed via ev.make.
#
#   lex run --allow-effects io tools/gen_notary_sample.lex gen '"testdata/notary/session1.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let reversed := ev.make("move", None, "{\"option\":1,\"category\":\"goods_certification\",\"orientation\":\"reversed\",\"claim\":\"Haddock is hereby declared eels\",\"legal\":true}", 1782600000000)
  let solve := ev.make("move", Some(reversed.id), "{\"option\":1,\"category\":\"goods_certification\",\"orientation\":\"normal\",\"claim\":\"This barrel is 100% haddock, filleted\",\"legal\":true}", 1782600001000)
  let lines := list.map([reversed, solve], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => { let _ := io.print("wrote honest notary trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

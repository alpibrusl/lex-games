# Dev tool: emit a FORGED-but-hash-correct Stamp of Destiny trail — a stamp
# claiming legal:true for "species_declaration" (a category the fixed Junior
# Notary license explicitly denies), every content id recomputed via ev.make.
# The trail is intact (tamper layer passes) yet the notary verifier must reject
# it: legality is re-derived from the category against the fixed license, not
# trusted from the recorded claim.
#
#   lex run --allow-effects io tools/gen_notary_forged.lex gen '"testdata/notary/forged.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let forged := ev.make("move", None, "{\"option\":0,\"category\":\"species_declaration\",\"orientation\":\"normal\",\"claim\":\"These eels are hereby a protected species\",\"legal\":true}", 1782600000000)
  let lines := list.map([forged], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => { let _ := io.print("wrote forged notary trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

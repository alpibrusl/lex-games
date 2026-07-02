# Dev tool: emit the committed Token-Pick sample trail for the TEMPLATE game
# (testdata/template-sample.jsonl), every content id computed via ev.make and
# each move chained to its parent — so CI can verify the template branch the
# same way it verifies bazaar: honest → verified, tampered → rejected.
#
#   lex run --allow-effects io tools/gen_template_sample.lex gen '"testdata/template-sample.jsonl"'
#
# P1 picks tokens 1 (9) + 3 (7) = 16; P2 picks 5 (8) + 0 (5) = 13 → P1 wins.

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"         as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let m1 := ev.make("move", None, "{\"by\":\"P1\",\"pick\":1}", 1782600000000)
  let m2 := ev.make("move", Some(m1.id), "{\"by\":\"P2\",\"pick\":5}", 1782600001000)
  let m3 := ev.make("move", Some(m2.id), "{\"by\":\"P1\",\"pick\":3}", 1782600002000)
  let m4 := ev.make("move", Some(m3.id), "{\"by\":\"P2\",\"pick\":0}", 1782600003000)
  let lines := list.map([m1, m2, m3, m4], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_)  => { let _ := io.print("wrote template sample trail") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

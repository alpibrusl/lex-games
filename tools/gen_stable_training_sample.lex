# Dev tool: emit a real, verified Stable Training trail — idle accrual, two
# rounds of automation investment, one prestige, then more accrual + a final
# investment — with every content id computed via ev.make (so it's genuinely
# tamper-evident, not hand-forged).
#
#   lex run --allow-effects io tools/gen_stable_training_sample.lex gen '"testdata/stable_training-sample.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"         as ev
import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let t0 := 1782500000000
  let opened     := ev.make("training.opened", None, "{\"agent_id\":\"stable-alpha\"}", t0)
  let c1_idle    := ev.make("checkpoint", None, "{\"action\":\"idle\"}",     t0 + 11000)  # +11s idle
  let c2_invest  := ev.make("checkpoint", None, "{\"action\":\"invest\"}",  t0 + 11100)  # +100ms -> tier 0->1
  let c3_idle    := ev.make("checkpoint", None, "{\"action\":\"idle\"}",    t0 + 61100)  # +50s idle
  let c4_invest  := ev.make("checkpoint", None, "{\"action\":\"invest\"}",  t0 + 61100)  # +0ms   -> tier 1->2
  let c5_invest  := ev.make("checkpoint", None, "{\"action\":\"invest\"}",  t0 + 61200)  # +100ms -> tier 2->3
  let c6_prestige := ev.make("checkpoint", None, "{\"action\":\"prestige\"}", t0 + 261200) # +200s -> prestige x1
  let c7_idle    := ev.make("checkpoint", None, "{\"action\":\"idle\"}",    t0 + 861200)  # +600s idle
  let c8_invest  := ev.make("checkpoint", None, "{\"action\":\"invest\"}",  t0 + 861200)  # +0ms   -> tier 0->1
  let lines := list.map([opened, c1_idle, c2_invest, c3_idle, c4_invest, c5_invest, c6_prestige, c7_idle, c8_invest], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_)  => { let _ := io.print("wrote stable_training sample") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

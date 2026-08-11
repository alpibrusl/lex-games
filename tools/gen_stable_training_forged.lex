# Dev tool: emit a hash-CORRECT but rule-violating Stable Training trail — one
# checkpoint claims an action the rules don't know ("cheat"), i.e. an attempt
# to sidestep invest/prestige/idle. Every content id still recomputes (intact),
# so this proves legality is recomputed from the rules, not inferred from a
# well-formed trail.
#
#   lex run --allow-effects io tools/gen_stable_training_forged.lex gen '"testdata/stable_training-forged.jsonl"'

import "std.io" as io

import "std.list" as list

import "lex-trail/event" as ev

import "../src/arena/trail_file" as tf

fn gen(out :: Str) -> [io] Int {
  let t0 := 1782500000000
  let opened := ev.make("training.opened", None, "{\"agent_id\":\"stable-alpha\"}", t0)
  let c1_idle := ev.make("checkpoint", None, "{\"action\":\"idle\"}", t0 + 11000)
  let c2_cheat := ev.make("checkpoint", None, "{\"action\":\"cheat\"}", t0 + 11100)
  let lines := list.map([opened, c1_idle, c2_cheat], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => {
      let __lex_discard_1 := io.print("wrote stable_training forged trail")
      0
    },
    Err(e) => {
      let __lex_discard_2 := io.print(e)
      1
    },
  }
}


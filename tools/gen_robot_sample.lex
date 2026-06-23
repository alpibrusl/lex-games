# Dev tool: emit a canonical robot-task sample trail with correct content ids.
# Builds a successful single-attempt pick-place run using lex-trail's own
# `ev.make` (so the ids hash exactly as the verifier recomputes them) and writes
# JSONL via the arena trail_file writer. Re-run to regenerate testdata.
#
#   lex run --allow-effects io tools/gen_robot_sample.lex gen '"testdata/robot_task-sample.jsonl"'

import "std.io"   as io
import "std.list" as list

import "lex-trail/event"  as ev
import "../src/arena/trail_file" as tf

# Build the chain: each event's parent is the previous event's id.
fn chain(specs :: List[{ kind :: Str, payload :: Str, ts :: Int }]) -> List[ev.Event] {
  let acc := list.fold(specs, { parent: "", evs: [] },
    fn (st :: { parent :: Str, evs :: List[ev.Event] }, s :: { kind :: Str, payload :: Str, ts :: Int })
        -> { parent :: Str, evs :: List[ev.Event] } {
      let p := if st.parent == "" { None } else { Some(st.parent) }
      let e := ev.make(s.kind, p, s.payload, s.ts)
      { parent: e.id, evs: list.concat(st.evs, [e]) }
    })
  acc.evs
}

fn gen(out :: Str) -> [io] Int {
  let specs := [
    { kind: "task_started", payload: "{}", ts: 1781955600000 },
    { kind: "perceive", payload: "{\"detail\":\"joints ok\"}", ts: 1781955601000 },
    { kind: "plan",     payload: "{\"detail\":\"target 0.5,0.5,0.2\"}", ts: 1781955602000 },
    { kind: "execute",  payload: "{\"detail\":\"reached\"}", ts: 1781955603000 },
    { kind: "verify",   payload: "{\"detail\":\"outcome reached\"}", ts: 1781955604000 },
  ]
  let lines := list.map(chain(specs), tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_)  => { let _ := io.print("wrote sample") 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

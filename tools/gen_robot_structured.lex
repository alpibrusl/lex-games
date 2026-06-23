# Dev tool: emit structured robot-task trails (the lex-os SkillOutcome shape)
# that exercise the verifier's grant-legality re-check. Two trails:
#   structured_legal.jsonl    — an in-workspace move recorded reached  -> legal
#   structured_illegal.jsonl  — an out-of-workspace move CLAIMING reached
#                               (an "unauthorized success") -> legal:false
# Grant caps are ISO/TS 15066-derived (mN): max_force 280000 (transient),
# max_grip 140000 (hands/fingers quasi-static). Ids hash via lex-trail ev.make.
#
#   lex run --allow-effects io tools/gen_robot_structured.lex gen '"testdata/policy"'

import "std.io"   as io
import "std.str"  as str
import "std.int"  as int
import "std.list" as list

import "lex-trail/event"  as ev
import "../src/arena/trail_file" as tf

type Spec = { kind :: Str, payload :: Str, ts :: Int }

fn d(detail :: Str) -> Str { str.join(["{\"detail\":\"", detail, "\"}"], "") }

fn grant_json() -> Str {
  str.concat(
    "\"grant\":{\"ws_min\":{\"x\":0,\"y\":0,\"z\":0},\"ws_max\":{\"x\":1000,\"y\":1000,\"z\":1000}",
    ",\"max_force\":280000,\"max_grip\":140000}")
}

# A structured move_to execute payload at (x,y,z) mm, recorded with `outcome`.
fn exec_move(x :: Int, y :: Int, z :: Int, outcome :: Str) -> Str {
  str.join([
    "{\"skill\":\"move_to\",\"args\":{\"x\":", int.to_str(x), ",\"y\":", int.to_str(y),
    ",\"z\":", int.to_str(z), ",\"force\":0},", grant_json(),
    ",\"outcome\":\"", outcome, "\"}"
  ], "")
}

fn chain(specs :: List[Spec]) -> List[ev.Event] {
  let acc := list.fold(specs, { parent: "", evs: [] },
    fn (st :: { parent :: Str, evs :: List[ev.Event] }, s :: Spec)
        -> { parent :: Str, evs :: List[ev.Event] } {
      let p := if st.parent == "" { None } else { Some(st.parent) }
      let e := ev.make(s.kind, p, s.payload, s.ts)
      { parent: e.id, evs: list.concat(st.evs, [e]) }
    })
  acc.evs
}

fn write(out :: Str, specs :: List[Spec]) -> [io] Bool {
  let lines := list.map(chain(specs), tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_)  => { let _ := io.print(str.concat("wrote ", out)) true },
    Err(e) => { let _ := io.print(str.concat("ERR ", e)) false },
  }
}

fn run_trail(dir :: Str, name :: Str, exec_payload :: Str) -> [io] Bool {
  let t := 1782200500000
  write(str.join([dir, "/", name], ""), [
    { kind: "task_started", payload: "{}", ts: t },
    { kind: "perceive", payload: d("joints ok"), ts: t + 1 },
    { kind: "plan",     payload: d("target 0.5,0.5,0.2"), ts: t + 2 },
    { kind: "execute",  payload: exec_payload, ts: t + 3 },
    { kind: "verify",   payload: d("outcome reached"), ts: t + 4 },
  ])
}

fn gen(dir :: Str) -> [io] Int {
  # in-workspace (x=500mm) reached -> authorized success -> legal
  let _a := run_trail(dir, "structured_legal.jsonl", exec_move(500, 500, 200, "reached"))
  # out-of-workspace (x=9900mm, ws_max 1000) but CLAIMS reached -> unauthorized -> illegal
  let _b := run_trail(dir, "structured_illegal.jsonl", exec_move(9900, 500, 200, "reached"))
  0
}

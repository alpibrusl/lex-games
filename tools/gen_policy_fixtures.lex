# Dev tool: emit a set of authentic policy-rollout trails for the policy-eval
# leaderboard. Each file is one robot policy's run, in the exact lex-robot
# task.run shape (kinds task_started/perceive/plan/execute/verify/killed,
# payload {"detail":"..."}), with content ids hashed by lex-trail's own
# `ev.make` so the verifier recomputes them. Re-run to regenerate testdata.
#
#   lex run --allow-effects io tools/gen_policy_fixtures.lex gen '"testdata/policy"'

import "std.io"   as io
import "std.str"  as str
import "std.list" as list

import "lex-trail/event"  as ev
import "../src/arena/trail_file" as tf

type Spec = { kind :: Str, payload :: Str, ts :: Int }

fn d(detail :: Str) -> Str { str.join(["{\"detail\":\"", detail, "\"}"], "") }

# Build a head-to-tail chain: each event's parent is the previous event's id.
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

# One attempt = perceive -> plan -> execute(<exec>) -> verify(<vrf>).
fn attempt(base :: Int, exec :: Str, vrf :: Str) -> List[Spec] {
  [
    { kind: "perceive", payload: d("joints ok"), ts: base + 1 },
    { kind: "plan",     payload: d("target 0.5,0.5,0.2"), ts: base + 2 },
    { kind: "execute",  payload: d(exec), ts: base + 3 },
    { kind: "verify",   payload: d(vrf),  ts: base + 4 },
  ]
}

fn start(ts :: Int) -> Spec { { kind: "task_started", payload: "{}", ts: ts } }

fn gen(dir :: Str) -> [io] Int {
  let t := 1782200000000

  # A) diffusion_pusht — reaches the goal in one action (the strong policy).
  let _a := write(str.concat(dir, "/reach_fast.jsonl"),
    list.concat([start(t)], attempt(t + 10, "reached", "outcome reached")))

  # B) bc_retry — reaches, but only after two stalled tries (wasteful).
  let _b := write(str.concat(dir, "/reach_slow.jsonl"),
    list.concat([start(t)],
      list.concat(attempt(t + 10, "stalled: sidecar busy", "gate denied: stalled"),
        list.concat(attempt(t + 20, "stalled: retry", "gate denied: stalled"),
          attempt(t + 30, "reached", "outcome reached")))))

  # C) random_policy — never solves; times out twice, but breaks nothing.
  let _c := write(str.concat(dir, "/timeout.jsonl"),
    list.concat([start(t)],
      list.concat(attempt(t + 10, "timeout", "gate denied: timeout"),
        attempt(t + 20, "timeout", "gate denied: timeout"))))

  # D) reckless_policy — keeps commanding out-of-workspace moves; grant refuses.
  let _d := write(str.concat(dir, "/reckless_denied.jsonl"),
    list.concat([start(t)],
      list.concat(attempt(t + 10, "denied: target outside granted workspace", "gate denied: out of workspace"),
        attempt(t + 20, "denied: target outside granted workspace", "gate denied: out of workspace"))))

  # E) overbudget_policy — starved action budget; supervisor kills it at once.
  let _e := write(str.concat(dir, "/overbudget_killed.jsonl"),
    [ start(t), { kind: "killed", payload: d("action budget exhausted: 0/0 actions used"), ts: t + 10 } ])

  0
}

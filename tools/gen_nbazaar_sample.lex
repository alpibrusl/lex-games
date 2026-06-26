# Dev tool: emit canonical N-player Bazaar match trails with correct content ids.
# Builds the move chain using lex-trail's own `ev.make` (so each id hashes exactly
# as nbazaar.verdict recomputes it) and writes JSONL via the arena trail_file
# writer. Re-run to regenerate testdata.
#
#   lex run --allow-effects io tools/gen_nbazaar_sample.lex match1 '"testdata/nbazaar/match1.jsonl"'
#   lex run --allow-effects io tools/gen_nbazaar_sample.lex match2 '"testdata/nbazaar/match2.jsonl"'

import "std.io"   as io
import "std.str"  as str
import "std.int"  as int
import "std.list" as list

import "lex-trail/event"        as ev
import "../src/arena/trail_file" as tf

type Spec = { kind :: Str, payload :: Str, ts :: Int }

fn draft(seat :: Int, item :: Int, ts :: Int) -> Spec {
  { kind: "draft", payload: str.join(["{\"seat\":", int.to_str(seat), ",\"item\":", int.to_str(item), "}"], ""), ts: ts }
}
fn pass(seat :: Int, ts :: Int) -> Spec {
  { kind: "pass", payload: str.join(["{\"seat\":", int.to_str(seat), "}"], ""), ts: ts }
}
fn header(seats :: Int, ts :: Int) -> Spec {
  { kind: "match_started", payload: str.join(["{\"seats\":", int.to_str(seats), "}"], ""), ts: ts }
}

# Build the chain: each event's parent is the previous event's id.
fn chain(specs :: List[Spec]) -> List[ev.Event] {
  let acc := list.fold(specs, { parent: "", evs: [] },
    fn (st :: { parent :: Str, evs :: List[ev.Event] }, s :: Spec) -> { parent :: Str, evs :: List[ev.Event] } {
      let p := if st.parent == "" { None } else { Some(st.parent) }
      let e := ev.make(s.kind, p, s.payload, s.ts)
      { parent: e.id, evs: list.concat(st.evs, [e]) }
    })
  acc.evs
}

fn write(out :: Str, specs :: List[Spec]) -> [io] Int {
  let lines := list.map(chain(specs), tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_)  => { let _ := io.print(str.concat("wrote ", out)) 0 },
    Err(e) => { let _ := io.print(e) 1 },
  }
}

# match1 — 3 seats; the real live result: seat0=34 (wins), seat2=32, seat1=28.
# Turn order is round-robin 0,1,2; every move is in-turn and affordable.
fn match1(out :: Str) -> [io] Int {
  write(out, [
    header(3, 1782000000000),
    draft(0, 1, 1782000001000),  # seat0: Vase  15/20   spent 15
    draft(1, 7, 1782000002000),  # seat1: 25/28         spent 25
    draft(2, 3, 1782000003000),  # seat2: 20/24         spent 20
    draft(0, 6, 1782000004000),  # seat0: 6/9           spent 21
    pass(1,     1782000005000),  # seat1: only 5 left
    draft(2, 0, 1782000006000),  # seat2: 10/8          spent 30
    draft(0, 2, 1782000007000),  # seat0: 8/5           spent 29
    pass(1,     1782000008000),
    pass(2,     1782000009000),
    pass(0,     1782000010000),  # → scores [34,28,32]
  ])
}

# match2 — 2-seat rematch; seat1 wins 28 to 22 (seat0 only nibbles cheap items).
fn match2(out :: Str) -> [io] Int {
  write(out, [
    header(2, 1782001000000),
    draft(0, 6, 1782001001000),  # seat0: 6/9    spent 6
    draft(1, 7, 1782001002000),  # seat1: 25/28  spent 25
    draft(0, 2, 1782001003000),  # seat0: 8/5    spent 14
    pass(1,     1782001004000),  # seat1: 5 left
    draft(0, 0, 1782001005000),  # seat0: 10/8   spent 24
    pass(1,     1782001006000),
    pass(0,     1782001007000),  # → scores [22,28]
  ])
}

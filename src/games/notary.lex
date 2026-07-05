# lex-games — Stamp of Destiny (Notary) verifier.
#
# The Guild Stamp is a capability grant wearing a costume: a Junior Notary's
# license covers a fixed set of chit CATEGORIES ("goods_certification",
# "harbor_permit", "minor_identity") and explicitly excludes others
# ("species_declaration", "title_of_nobility", "death_declaration"). Every
# notarization the sidecar allows is recorded as a "move" line carrying the
# category it claims to be, plus its own claimed `legal` flag; this verifier
# NEVER trusts that claim — it re-derives legality from the category against
# the same fixed license and flags any mismatch as a forged/unauthorized stamp
# (the same "unauthorized success" pattern as robot_task.lex/ops.lex).
#
# Effects: pure.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "../arena/trail_file" as tf

type License = { allow :: List[Str], deny :: List[Str] }

# The fixed Junior Notary License — same constant on both the sidecar (which
# enforces it before allowing a stamp) and here (which re-derives it
# independently from the recorded category, never trusting the sidecar's say-so).
fn license() -> License {
  { allow: ["goods_certification", "harbor_permit", "minor_identity"],
    deny: ["species_declaration", "title_of_nobility", "death_declaration"] }
}

type Stamp = { option :: Int, category :: Str, orientation :: Str, claim :: Str, legal :: Bool }

fn list_has(xs :: List[Str], x :: Str) -> Bool { list.fold(xs, false, fn (a :: Bool, s :: Str) -> Bool { a or s == x }) }
fn permitted(lic :: License, category :: Str) -> Bool { list_has(lic.allow, category) and not list_has(lic.deny, category) }

# The winning move: a goods_certification chit stamped right-side up (the
# reversed orientation is legal but useless — the puzzle's "legal ≠ optimal").
fn is_solve(s :: Stamp) -> Bool { s.option == 1 and s.orientation == "normal" and s.legal }

type Tally = { intact :: Bool, stamped :: Int, solved :: Bool, rogue :: List[Str] }
fn step(lic :: License, t :: Tally, l :: tf.Line) -> Tally {
  let intact := t.intact and tf.line_intact(l)
  if l.kind != "move" {
    { intact: intact, stamped: t.stamped, solved: t.solved, rogue: t.rogue }
  } else {
    match (json.parse(l.payload_json) :: Result[Stamp, Str]) {
      Err(_) => { intact: intact, stamped: t.stamped, solved: t.solved, rogue: t.rogue },
      Ok(s) => {
        let expected_legal := permitted(lic, s.category)
        let rogue := if s.legal == expected_legal { t.rogue } else { list.concat(t.rogue, [s.category]) }
        { intact: intact, stamped: t.stamped + 1, solved: t.solved or is_solve(s), rogue: rogue }
      },
    }
  }
}

# verified = every line content-intact AND every recorded stamp's claimed
# legality matches what the fixed license independently re-derives.
type Verdict = { verified :: Bool, intact :: Bool, stamped :: Int, solved :: Bool, rogue :: List[Str] }
fn verdict(lines :: List[tf.Line]) -> Verdict {
  let t := list.fold(lines, { intact: true, stamped: 0, solved: false, rogue: [] }, fn (acc :: Tally, l :: tf.Line) -> Tally { step(license(), acc, l) })
  { verified: t.intact and list.len(t.rogue) == 0, intact: t.intact, stamped: t.stamped, solved: t.solved, rogue: t.rogue }
}

fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  let rogue := str.join(["[", str.join(list.map(v.rogue, fn (s :: Str) -> Str { str.join(["\"", s, "\""], "") }), ","), "]"], "")
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"stamped\":", int.to_str(v.stamped),
            ",\"solved\":", b(v.solved), ",\"rogue\":", rogue, "}"], "")
}

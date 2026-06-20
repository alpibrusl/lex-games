# lex-games arena — trail file format (the submission artifact)
#
# One event per line, the canonical lex-trail fields with `parent` flattened to
# Str ("" = root) so a single record type parses every line:
#
#   {"id":"<sha256>","kind":"move","parent":"","payload_json":"{...}","ts_ms":1700000000000}
#
# The id is recomputable from the other fields (see lex-trail/event.compute_id),
# so a trail file is SELF-VERIFYING: tampering with any field breaks that line's
# id. The portable format matches the finance arena's trail_file, so one
# verifier-agnostic worker can score any vertical that emits lex-trails.
#
# Effects: pure parsers/builders; read/write carry [fs_read]/[fs_write] via std.io.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json
import "std.io"   as io

import "lex-trail/event" as ev

# A parsed trail-file line. Mirrors ev.Event with parent flattened to Str.
type Line = { id :: Str, kind :: Str, parent :: Str, payload_json :: Str, ts_ms :: Int }

fn line_parent(l :: Line) -> Option[Str] { if str.is_empty(l.parent) { None } else { Some(l.parent) } }

# A line is intact iff its id recomputes from its content (content-addressed).
fn line_intact(l :: Line) -> Bool { l.id == ev.compute_id(l.kind, line_parent(l), l.payload_json, l.ts_ms) }

# ---- export (client side: turn an event list into an uploadable trail) --------
fn esc(s :: Str) -> Str { str.replace(str.replace(s, "\\", "\\\\"), "\"", "\\\"") }
fn from_event(e :: ev.Event) -> Line {
  { id: e.id, kind: e.kind, parent: match e.parent { Some(p) => p, None => "" }, payload_json: e.payload_json, ts_ms: e.ts_ms }
}
fn line_json(l :: Line) -> Str {
  str.join(["{\"id\":\"", l.id, "\",\"kind\":\"", l.kind, "\",\"parent\":\"", l.parent, "\",\"payload_json\":\"", esc(l.payload_json), "\",\"ts_ms\":", int.to_str(l.ts_ms), "}"], "")
}
fn to_jsonl(lines :: List[Line]) -> Str { str.join(list.map(lines, line_json), "\n") }
fn write_jsonl(path :: Str, lines :: List[Line]) -> [io] Result[Unit, Str] { io.write(path, to_jsonl(lines)) }

# ---- parse (server side: load an uploaded trail) ------------------------------
fn parse_line(s :: Str) -> Result[Line, Str] {
  let parsed :: Result[Line, Str] := json.parse(s)
  parsed
}
fn parse_jsonl(content :: Str) -> Result[List[Line], Str] {
  let raw := str.split(content, "\n")
  let non_empty := list.filter(raw, fn (s :: Str) -> Bool { not str.is_empty(str.trim(s)) })
  list.fold(non_empty, Ok([]), fn (acc :: Result[List[Line], Str], s :: Str) -> Result[List[Line], Str] {
    match acc {
      Err(e) => Err(e),
      Ok(ls) => match parse_line(s) { Err(e) => Err(str.concat("bad trail line: ", e)), Ok(l) => Ok(list.concat(ls, [l])) },
    }
  })
}
fn read_jsonl(path :: Str) -> [io] Result[List[Line], Str] {
  match io.read(path) { Err(e) => Err(e), Ok(content) => parse_jsonl(content) }
}

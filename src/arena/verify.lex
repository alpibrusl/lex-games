# lex-games arena — replay verification (the core mechanism)
#
# A submission is a TRAIL, not a score. `verify(game, trail_path)` reads the
# uploaded JSONL trail, checks every line is content-intact (id recomputes), then
# re-runs the recorded moves through the game's deterministic rules to recompute
# the authoritative score. Replay is rules-only — no LLM — so it costs CPU-cents;
# the model inference happened once, locally, when the player produced the trail.
#
# Run (the same binary anyone runs locally; also what the hosted worker runs):
#   lex run --allow-effects fs_read,io src/arena/verify.lex verify bazaar trail.jsonl
#
# Prints a verdict JSON line; returns 0 = verified, 1 = rejected/error.

import "std.io"  as io
import "std.str" as str

import "./trail_file"   as tf
import "../games/bazaar" as bazaar

fn verify(game :: Str, trail_path :: Str) -> [io] Int {
  if game != "bazaar" {
    let _ := io.print(str.concat("{\"verified\":false,\"error\":\"unknown game: ", str.concat(game, "\"}")))
    1
  } else {
    match tf.read_jsonl(trail_path) {
      Err(e) => { let _ := io.print(str.concat("{\"verified\":false,\"error\":\"", str.concat(e, "\"}"))) 1 },
      Ok(lines) => {
        let v := bazaar.verdict(lines)
        let _ := io.print(bazaar.verdict_json(v))
        if v.verified { 0 } else { 1 }
      },
    }
  }
}

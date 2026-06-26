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

import "./trail_file"        as tf
import "../games/bazaar"     as bazaar
import "../games/nbazaar"    as nbazaar
import "../games/template"   as template
import "../games/robot_task" as robot_task

# Register a new game here: add an `if game == "<name>"` branch that reads the
# trail, calls your game's verdict/verdict_json, and returns 0 (verified) or 1.
# (See docs/ADDING_A_GAME.md.) The read+print+return shape is identical per game.
fn verify(game :: Str, trail_path :: Str) -> [io] Int {
  match tf.read_jsonl(trail_path) {
    Err(e) => { let _ := io.print(str.concat("{\"verified\":false,\"error\":\"", str.concat(e, "\"}"))) 1 },
    Ok(lines) => {
      if game == "bazaar" {
        let v := bazaar.verdict(lines)
        let _ := io.print(bazaar.verdict_json(v))
        if v.verified { 0 } else { 1 }
      } else {
      if game == "template" {
        let v := template.verdict(lines)
        let _ := io.print(template.verdict_json(v))
        if v.verified { 0 } else { 1 }
      } else {
      if game == "robot_task" {
        let v := robot_task.verdict(lines)
        let _ := io.print(robot_task.verdict_json(v))
        if v.verified { 0 } else { 1 }
      } else {
      if game == "nbazaar" {
        let v := nbazaar.verdict(lines)
        let _ := io.print(nbazaar.verdict_json(v))
        if v.verified { 0 } else { 1 }
      } else {
        let _ := io.print(str.concat("{\"verified\":false,\"error\":\"unknown game: ", str.concat(game, "\"}")))
        1
      }}}}
    },
  }
}

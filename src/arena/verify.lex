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

import "std.io" as io

import "std.str" as str

import "./trail_file" as tf

import "../games/bazaar" as bazaar

import "../games/nbazaar" as nbazaar

import "../games/gbazaar" as gbazaar

import "../games/consent" as consent

import "../games/capability" as capability

import "../games/ops" as ops

import "../games/notary" as notary

import "../games/wedding" as wedding

import "../games/werewolf" as werewolf

import "../games/conquest" as conquest

import "../games/trading" as trading

import "../games/template" as template

import "../games/robot_task" as robot_task

import "../games/stable_training" as stable_training

# Register a new game here: add an `if game == "<name>"` branch that reads the
# trail, calls your game's verdict/verdict_json, and returns 0 (verified) or 1.
# (See docs/ADDING_A_GAME.md.) The read+print+return shape is identical per game.
fn verify(game :: Str, trail_path :: Str) -> [io] Int {
  match tf.read_jsonl(trail_path) {
    Err(e) => {
      let __lex_discard_1 := io.print(str.concat("{\"verified\":false,\"error\":\"", str.concat(e, "\"}")))
      1
    },
    Ok(lines) => {
      if game == "bazaar" {
        let v := bazaar.verdict(lines)
        let __lex_discard_2 := io.print(bazaar.verdict_json(v))
        if v.verified {
          0
        } else {
          1
        }
      } else {
        if game == "template" {
          let v := template.verdict(lines)
          let __lex_discard_3 := io.print(template.verdict_json(v))
          if v.verified {
            0
          } else {
            1
          }
        } else {
          if game == "robot_task" {
            let v := robot_task.verdict(lines)
            let __lex_discard_4 := io.print(robot_task.verdict_json(v))
            if v.verified {
              0
            } else {
              1
            }
          } else {
            if game == "nbazaar" {
              let v := nbazaar.verdict(lines)
              let __lex_discard_5 := io.print(nbazaar.verdict_json(v))
              if v.verified {
                0
              } else {
                1
              }
            } else {
              if game == "gbazaar" {
                let v := gbazaar.verdict(lines)
                let __lex_discard_6 := io.print(gbazaar.verdict_json(v))
                if v.verified {
                  0
                } else {
                  1
                }
              } else {
                if game == "consent" {
                  let v := consent.verdict(lines)
                  let __lex_discard_7 := io.print(consent.verdict_json(v))
                  if v.verified {
                    0
                  } else {
                    1
                  }
                } else {
                  if game == "capability" {
                    let v := capability.verdict(lines)
                    let __lex_discard_8 := io.print(capability.verdict_json(v))
                    if v.verified {
                      0
                    } else {
                      1
                    }
                  } else {
                    if game == "ops" {
                      let v := ops.verdict(lines)
                      let __lex_discard_9 := io.print(ops.verdict_json(v))
                      if v.verified {
                        0
                      } else {
                        1
                      }
                    } else {
                      if game == "notary" {
                        let v := notary.verdict(lines)
                        let __lex_discard_10 := io.print(notary.verdict_json(v))
                        if v.verified {
                          0
                        } else {
                          1
                        }
                      } else {
                        if game == "wedding" {
                          let v := wedding.verdict(lines)
                          let __lex_discard_11 := io.print(wedding.verdict_json(v))
                          if v.verified {
                            0
                          } else {
                            1
                          }
                        } else {
                          if game == "werewolf" {
                            let v := werewolf.verdict(lines)
                            let __lex_discard_12 := io.print(werewolf.verdict_json(v))
                            if v.verified {
                              0
                            } else {
                              1
                            }
                          } else {
                            if game == "conquest" {
                              let v := conquest.verdict(lines)
                              let __lex_discard_13 := io.print(conquest.verdict_json(v))
                              if v.verified {
                                0
                              } else {
                                1
                              }
                            } else {
                              if game == "trading" {
                                let v := trading.verdict(lines)
                                let __lex_discard_14 := io.print(trading.verdict_json(v))
                                if v.verified {
                                  0
                                } else {
                                  1
                                }
                              } else {
                                if game == "stable_training" {
                                  let v := stable_training.verdict(lines)
                                  let __lex_discard_16 := io.print(stable_training.verdict_json(v))
                                  if v.verified {
                                    0
                                  } else {
                                    1
                                  }
                                } else {
                                  let __lex_discard_15 := io.print(str.concat("{\"verified\":false,\"error\":\"unknown game: ", str.concat(game, "\"}")))
                                  1
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    },
  }
}


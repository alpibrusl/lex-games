# lex-games arena — export a recorded trail to the uploadable JSONL format.
#
# Client side: after a local match the moves are recorded in a lex-trail (sqlite)
# log; `export(db_path, out_path)` reads that log and writes the portable JSONL
# trail the player uploads. The server then runs verify.lex over it.
#
#   lex run --allow-effects fs_read,fs_write,sql,io src/arena/export.lex \
#     export /tmp/lex-shop-123.db trail.jsonl

import "std.io"   as io
import "std.str"  as str
import "std.list" as list

import "lex-trail/log" as trail

import "./trail_file" as tf

fn export(db_path :: Str, out_path :: Str) -> [sql, fs_write, io] Int {
  match trail.open(db_path) {
    Err(e) => { let _ := io.print(str.concat("export error: ", e)) 1 },
    Ok(log) => {
      match trail.range(log, 0, 9999999999999) {
        Err(e) => { let _ := trail.close(log) let _ := io.print(str.concat("export error: ", e)) 1 },
        Ok(evs) => {
          let lines := list.map(evs, tf.from_event)
          let _ := trail.close(log)
          match tf.write_jsonl(out_path, lines) {
            Err(e) => { let _ := io.print(str.concat("write error: ", e)) 1 },
            Ok(_)  => { let _ := io.print(str.concat("exported ", str.concat(out_path, ""))) 0 },
          }
        },
      }
    },
  }
}

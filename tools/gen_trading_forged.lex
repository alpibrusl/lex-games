# Dev tool: emit a FORGED-but-hash-correct Trading trail — the rigged-tape cheat.
#
# Same setup as the honest sample (same seed, same opening prices), and every
# content id is still recomputed via ev.make, so the hash chain is INTACT and a
# chain check alone would pass this. What is forged is the tape itself: the
# round-2 price_tick claims AAPL at a price 500 cents above what the committed
# seed actually produces, and seat 2 — who bought at round 1 — is declared the
# winner on the strength of that invented rally.
#
# This is the cheat the game exists to catch: not a broken hash, but a
# plausible-looking price that never happened. The verifier must reject it
# because it re-derives every tick from (seed, symbol, counter) instead of
# trusting the recorded number:
#
#   "price tick at round 2 doesn't match the seed-derived tape"
#
# and, because the fill/equity replay then runs against the REAL tape, the
# claimed winner does not survive either.
#
#   lex run --allow-effects io,crypto tools/gen_trading_forged.lex gen '"testdata/trading/forged.jsonl"'

import "std.io"   as io
import "std.int"  as int
import "std.list" as list
import "std.str"  as str

import "lex-trail/event"         as ev
import "../src/arena/trail_file" as tf
import "../src/games/trading"    as trading

fn seed() -> Int { 42 }

fn bankroll() -> Int { 1000000 }

fn tick_max() -> Int { 50 }

fn open_price(s :: Str) -> Int {
  if s == "AAPL" { 19000 } else { if s == "MSFT" { 42000 } else { 25000 } }
}

fn stepped(prev :: Int, s :: Str, counter :: Int) -> [crypto] Int {
  let next := prev + trading.price_delta(seed(), s, counter, tick_max())
  if next < 100 { 100 } else { next }
}

fn price_json(a :: Int, m :: Int, t :: Int) -> Str {
  str.join(["\"AAPL\":", int.to_str(a), ",\"MSFT\":", int.to_str(m), ",\"TSLA\":", int.to_str(t)], "")
}

fn gen(out :: Str) -> [io, crypto] Int {
  let a0 := open_price("AAPL")
  let m0 := open_price("MSFT")
  let t0 := open_price("TSLA")
  let a1 := stepped(a0, "AAPL", 0)
  let m1 := stepped(m0, "MSFT", 1)
  let t1 := stepped(t0, "TSLA", 2)
  let a2_real := stepped(a1, "AAPL", 3)
  let m2 := stepped(m1, "MSFT", 4)
  let t2 := stepped(t1, "TSLA", 5)
  # THE FORGERY: AAPL marked 500 cents above the seed-derived price, turning
  # seat 2's round-1 buy into a winner it never was.
  let a2_forged := a2_real + 500

  let setup := ev.make("move", None, str.join(["{\"kind\":\"setup\",\"mode\":\"synthetic\",\"seed\":", int.to_str(seed()), ",\"starting_bankroll\":", int.to_str(bankroll()), ",\"tick_max_cents\":", int.to_str(tick_max()), ",\"round_cap\":2,\"prices\":{", price_json(a0, m0, t0), "}}"], ""), 1782600000000)
  let tick1 := ev.make("move", Some(setup.id), str.join(["{\"kind\":\"price_tick\",\"round\":1,\"prices\":{", price_json(a1, m1, t1), "}}"], ""), 1782600001000)
  let orders := ev.make("move", Some(tick1.id), str.join(["{\"kind\":\"orders\",\"by\":2,\"fills\":[{\"symbol\":\"AAPL\",\"side\":\"BUY\",\"qty\":10,\"price\":", int.to_str(a1), "}]}"], ""), 1782600002000)
  let tick2 := ev.make("move", Some(orders.id), str.join(["{\"kind\":\"price_tick\",\"round\":2,\"prices\":{", price_json(a2_forged, m2, t2), "}}"], ""), 1782600003000)
  let over := ev.make("move", Some(tick2.id), "{\"kind\":\"game_over\",\"winner\":2,\"reason\":\"round_cap\"}", 1782600004000)

  let lines := list.map([setup, tick1, orders, tick2, over], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => {
      let _ := io.print(str.join(["wrote forged trading trail — AAPL round 2 claimed ", int.to_str(a2_forged), ", seed says ", int.to_str(a2_real)], ""))
      0
    },
    Err(e) => {
      let _ := io.print(e)
      1
    },
  }
}

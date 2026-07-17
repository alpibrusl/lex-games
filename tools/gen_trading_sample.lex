# Dev tool: emit an HONEST Trading trail — 6 seats, synthetic mode.
#
# The setup commits (seed, starting_bankroll, tick_max_cents, round_cap) and the
# opening prices up front, so a replay can re-derive the whole price walk. Two
# rounds of ticks follow, each price taken from trading.price_delta at the same
# (seed, symbol, counter) the verifier will re-derive — this tool does NOT invent
# prices, it computes the same tape the verifier expects, which is what makes the
# trail honest rather than merely well-formed.
#
# Seat 2 buys AAPL at the round-1 tape price. Whether that trade wins is decided
# by the seed, not by this file: the generator re-derives the round-2 price and
# claims whichever seat the equity math actually favours (seat 2 if AAPL rose,
# else seat 0, which keeps its untouched bankroll and takes the tie on the lowest
# seat index). Claiming any other winner is what testdata/trading/forged.jsonl
# does deliberately.
#
# `side` MUST be the exact string "BUY". apply_fill_line does `f.side == "BUY"`,
# so ANY other spelling — "buy" included — is silently treated as a SELL: the
# seat is credited the notional instead of debited and ends up with the highest
# equity. Writing "buy" here made this honest trail fail its own winner check,
# which is how the casing was found. See lex-games#<this PR> — the emitter that
# produces real trails could not be located to confirm the contract.
#
#   lex run --allow-effects io,crypto tools/gen_trading_sample.lex gen '"testdata/trading/session1.jsonl"'

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

fn syms() -> List[Str] { ["AAPL", "MSFT", "TSLA"] }

fn open_price(s :: Str) -> Int {
  if s == "AAPL" { 19000 } else { if s == "MSFT" { 42000 } else { 25000 } }
}

# Re-derive one symbol's price after a tick, exactly as the verifier does:
# next = floor(prev + price_delta(seed, symbol, counter)), floored at 100.
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
  # round 1 — counters 0,1,2 (one per symbol, in symbols() order)
  let a1 := stepped(a0, "AAPL", 0)
  let m1 := stepped(m0, "MSFT", 1)
  let t1 := stepped(t0, "TSLA", 2)
  # round 2 — counters 3,4,5
  let a2 := stepped(a1, "AAPL", 3)
  let m2 := stepped(m1, "MSFT", 4)
  let t2 := stepped(t1, "TSLA", 5)

  let setup := ev.make("move", None, str.join(["{\"kind\":\"setup\",\"mode\":\"synthetic\",\"seed\":", int.to_str(seed()), ",\"starting_bankroll\":", int.to_str(bankroll()), ",\"tick_max_cents\":", int.to_str(tick_max()), ",\"round_cap\":2,\"prices\":{", price_json(a0, m0, t0), "}}"], ""), 1782600000000)
  let tick1 := ev.make("move", Some(setup.id), str.join(["{\"kind\":\"price_tick\",\"round\":1,\"prices\":{", price_json(a1, m1, t1), "}}"], ""), 1782600001000)
  # seat 2 buys 10 AAPL at the round-1 tape price — a fill the tape actually showed
  let orders := ev.make("move", Some(tick1.id), str.join(["{\"kind\":\"orders\",\"by\":2,\"fills\":[{\"symbol\":\"AAPL\",\"side\":\"BUY\",\"qty\":10,\"price\":", int.to_str(a1), "}]}"], ""), 1782600002000)
  let tick2 := ev.make("move", Some(orders.id), str.join(["{\"kind\":\"price_tick\",\"round\":2,\"prices\":{", price_json(a2, m2, t2), "}}"], ""), 1782600003000)
  # the seed decides the winner, not this file
  let winner := if a2 > a1 { 2 } else { 0 }
  let over := ev.make("move", Some(tick2.id), str.join(["{\"kind\":\"game_over\",\"winner\":", int.to_str(winner), ",\"reason\":\"round_cap\"}"], ""), 1782600004000)

  let lines := list.map([setup, tick1, orders, tick2, over], tf.from_event)
  match tf.write_jsonl(out, lines) {
    Ok(_) => {
      let _ := io.print(str.join(["wrote honest trading trail — AAPL ", int.to_str(a1), " -> ", int.to_str(a2), ", winner seat ", int.to_str(winner)], ""))
      0
    },
    Err(e) => {
      let _ := io.print(e)
      1
    },
  }
}

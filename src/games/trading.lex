# lex-games — Trading verifier: was the game provably fair?
#
# The seed, starting bankroll, and the price-walk parameters (tick_max_cents,
# round_cap) are committed once, up front, as the trail's very first entry —
# a replay proves the price walk was never rigged. From there this
# independently re-derives EVERY price tick from (seed, symbol, a monotonic
# counter) rather than trusting the recorded values, and replays every
# order fill through the REAL lex-positions WAAC/PnL logic (not a
# reimplementation of it) to recompute each seat's final equity — re-
# checking that every fill happened at the price the tape actually showed
# at that point, not against a later claim. A forged trail claiming
# favorable prices, a fill at a price that never occurred, or a fabricated
# winner is caught even if the hash-chain itself is intact — same
# unauthorized-success pattern as lex-conquest's/lex-werewolf's verifiers.
#
# Effects: pure.

import "std.str"    as str
import "std.int"    as int
import "std.list"   as list
import "std.json"   as json
import "std.crypto" as crypto

import "../arena/trail_file" as tf

import "lex-money/src/decimal" as d

import "lex-money/src/rounding" as r

import "lex-positions/src/position" as pos

import "lex-positions/src/position_update" as pu

import "lex-positions/src/pnl" as ppnl

fn symbols(mode :: Str) -> List[Str] {
  if mode == "crypto" { ["BTC-USD", "ETH-USD", "SOL-USD"] } else { ["AAPL", "MSFT", "TSLA"] }
}
fn seats() -> List[Int] { [0, 1, 2, 3, 4, 5] }

fn range(n :: Int) -> List[Int] {
  if n <= 0 { [] } else { list.concat(range(n - 1), [n - 1]) }
}

fn int_mod(a :: Int, b :: Int) -> Int {
  let m := a - (a / b) * b
  if m < 0 { m + b } else { m }
}

fn min_int(a :: Int, b :: Int) -> Int { if a < b { a } else { b } }

# ── seeded price walk — EXACT copy of market.lex's price_delta, so it
# re-derives byte-identical output from the same (seed, symbol, counter) ───
fn hex_digit_val(c :: Str) -> Int {
  if c == "1" { 1 } else { if c == "2" { 2 } else { if c == "3" { 3 } else { if c == "4" { 4 } else { if c == "5" { 5 } else { if c == "6" { 6 } else { if c == "7" { 7 } else { if c == "8" { 8 } else { if c == "9" { 9 } else { if c == "a" { 10 } else { if c == "b" { 11 } else { if c == "c" { 12 } else { if c == "d" { 13 } else { if c == "e" { 14 } else { if c == "f" { 15 } else { 0 } } } } } } } } } } } } } } }
}

fn hex_to_int(s :: Str, n :: Int) -> Int {
  list.fold(range(n), 0, fn (acc :: Int, i :: Int) -> Int {
    acc * 16 + hex_digit_val(str.char_at(s, i))
  })
}

fn price_delta(sd :: Int, symbol :: Str, counter :: Int, tick_max :: Int) -> Int {
  let digest := crypto.sha256_str(str.join([int.to_str(sd), ":", symbol, ":", int.to_str(counter)], ""))
  let span := 2 * tick_max + 1
  int_mod(hex_to_int(digest, 6), span) - tick_max
}

fn min_price_floor() -> Int { 100 }

# ── raw string extraction for the dynamic symbol-keyed "prices" object —
# json.parse only handles fixed-shape records, and the set of symbol keys
# here is fixed-but-external to the type system, same reason lex-conquest's
# verifier extracts its per-territory deal fields by string marker instead
# of json.parse. Fixed-shape payloads (orders/fills) DO go through
# json.parse below, same as lex-conquest's Reinforce/placements. ───────────
fn extract_int_after(payload :: Str, marker :: Str) -> Int {
  let parts := str.split(payload, marker)
  match list.head(list.tail(parts)) {
    None => 0,
    Some(after) => {
      let comma_cut := match list.head(str.split(after, ",")) {
        Some(v) => v,
        None => after,
      }
      let clean := match list.head(str.split(comma_cut, "}")) {
        Some(v) => v,
        None => comma_cut,
      }
      match str.to_int(clean) {
        Some(n) => n,
        None => 0,
      }
    },
  }
}

fn extract_str_after(payload :: Str, marker :: Str) -> Str {
  let parts := str.split(payload, marker)
  match list.head(list.tail(parts)) {
    None => "",
    Some(after) => match list.head(str.split(after, "\"")) {
      Some(v) => v,
      None => "",
    },
  }
}

# extract_str_after's marker must include the opening quote — it splits
# on the raw marker text, then takes everything up to the NEXT quote, so
# a marker ending right before the value's own opening quote (not
# including it) would just yield "" every time.
fn get_mode(payload :: Str) -> Str {
  let m := extract_str_after(payload, "\"mode\":\"")
  if str.is_empty(m) { "synthetic" } else { m }
}
fn get_seed(payload :: Str) -> Int { extract_int_after(payload, "\"seed\":") }
fn get_starting_bankroll(payload :: Str) -> Int { extract_int_after(payload, "\"starting_bankroll\":") }
fn get_tick_max(payload :: Str) -> Int { extract_int_after(payload, "\"tick_max_cents\":") }
fn get_round_cap(payload :: Str) -> Int { extract_int_after(payload, "\"round_cap\":") }
fn get_round(payload :: Str) -> Int { extract_int_after(payload, "\"round\":") }
fn get_price_of(payload :: Str, symbol :: Str) -> Int { extract_int_after(payload, str.join(["\"", symbol, "\":"], "")) }

# ── fixed-shape payloads (orders / game_over) via json.parse ───────────────
type Fill = { symbol :: Str, side :: Str, qty :: Int, price :: Int }
type Orders = { kind :: Str, by :: Int, fills :: List[Fill] }
type GameOver = { winner :: Int, reason :: Str }

# ── per-seat book: cash + one lex-positions Position per symbol, replayed
# through the REAL apply_fill/unrealized_pnl — not reimplemented here ──────
type BookEntry = { seat :: Int, symbol :: Str, position :: pos.Position }

fn position_key(seat :: Int, symbol :: Str) -> pos.PositionKey {
  { account: int.to_str(seat), symbol: symbol }
}

fn book_get(book :: List[BookEntry], seat :: Int, symbol :: Str) -> pos.Position {
  match list.fold(book, None, fn (acc :: Option[pos.Position], e :: BookEntry) -> Option[pos.Position] {
    match acc {
      Some(_) => acc,
      None => if e.seat == seat and e.symbol == symbol { Some(e.position) } else { None },
    }
  }) {
    Some(p) => p,
    None => pos.flat(position_key(seat, symbol)),
  }
}

fn book_set(book :: List[BookEntry], seat :: Int, symbol :: Str, p :: pos.Position) -> List[BookEntry] {
  let without := list.fold(book, [], fn (acc :: List[BookEntry], e :: BookEntry) -> List[BookEntry] {
    if e.seat == seat and e.symbol == symbol { acc } else { list.concat(acc, [e]) }
  })
  list.concat(without, [{ seat: seat, symbol: symbol, position: p }])
}

type CashEntry = { seat :: Int, cash :: Int }

fn cash_get(cash :: List[CashEntry], seat :: Int) -> Int {
  match list.fold(cash, None, fn (acc :: Option[Int], e :: CashEntry) -> Option[Int] {
    match acc {
      Some(_) => acc,
      None => if e.seat == seat { Some(e.cash) } else { None },
    }
  }) {
    Some(c) => c,
    None => 0,
  }
}

fn cash_set(cash :: List[CashEntry], seat :: Int, new_cash :: Int) -> List[CashEntry] {
  let without := list.fold(cash, [], fn (acc :: List[CashEntry], e :: CashEntry) -> List[CashEntry] {
    if e.seat == seat { acc } else { list.concat(acc, [e]) }
  })
  list.concat(without, [{ seat: seat, cash: new_cash }])
}

type PriceEntry = { symbol :: Str, price :: Int }

fn price_get(prices :: List[PriceEntry], symbol :: Str) -> Int {
  match list.fold(prices, None, fn (acc :: Option[Int], e :: PriceEntry) -> Option[Int] {
    match acc {
      Some(_) => acc,
      None => if e.symbol == symbol { Some(e.price) } else { None },
    }
  }) {
    Some(p) => p,
    None => 0,
  }
}

fn price_set(prices :: List[PriceEntry], symbol :: Str, new_price :: Int) -> List[PriceEntry] {
  let without := list.fold(prices, [], fn (acc :: List[PriceEntry], e :: PriceEntry) -> List[PriceEntry] {
    if e.symbol == symbol { acc } else { list.concat(acc, [e]) }
  })
  list.concat(without, [{ symbol: symbol, price: new_price }])
}

fn price_decimal(cents :: Int) -> d.Decimal { d.decimal(cents, 0 - 2) }

fn decimal_cents(dec :: d.Decimal) -> Int {
  let rounded := r.round_to(dec, 0 - 2, HalfEven(()))
  rounded.coefficient
}

fn equity_cents(mode :: Str, book :: List[BookEntry], cash :: List[CashEntry], prices :: List[PriceEntry], seat :: Int) -> Int {
  let c := cash_get(cash, seat)
  list.fold(symbols(mode), c, fn (acc :: Int, s :: Str) -> Int {
    let position := book_get(book, seat, s)
    let mark := price_decimal(price_get(prices, s))
    acc + decimal_cents(ppnl.unrealized_pnl(position, mark))
  })
}

type Tally = {
  intact :: Bool,
  saw_setup :: Bool,
  mode :: Str,
  seed :: Int,
  tick_max :: Int,
  round_cap :: Int,
  price_counter :: Int,
  prices :: List[PriceEntry],
  book :: List[BookEntry],
  cash :: List[CashEntry],
  round :: Int,
  price_ticks :: Int,
  orders_seen :: Int,
  claimed_winner :: Int,
  claimed_reason :: Str,
  rogue :: List[Str],
}

# `intact` is an explicit parameter, not copied off `t`: it used to read
# `intact: t.intact`, which silently discarded the freshly recomputed value from
# step. The setup/price_tick/game_over branches all rebuild the record inline and
# so kept their own `intact:`, but the ORDERS branch returns through here — so a
# tampered fill left intact untouched and the trail verified. Fills are the
# events that move money; they were the one kind the hash check did not reach.
fn re_tally(t :: Tally, intact :: Bool, seed :: Int, tick_max :: Int, round_cap :: Int, price_counter :: Int, prices :: List[PriceEntry], book :: List[BookEntry], cash :: List[CashEntry], round :: Int, price_ticks :: Int, orders_seen :: Int, claimed_winner :: Int, claimed_reason :: Str, rogue :: List[Str]) -> Tally {
  { intact: intact, saw_setup: t.saw_setup, mode: t.mode, seed: seed, tick_max: tick_max, round_cap: round_cap, price_counter: price_counter, prices: prices, book: book, cash: cash, round: round, price_ticks: price_ticks, orders_seen: orders_seen, claimed_winner: claimed_winner, claimed_reason: claimed_reason, rogue: rogue }
}

fn apply_fill_line(t :: Tally, by :: Int, f :: Fill) -> Tally {
  let is_buy := f.side == "BUY"
  let position := book_get(t.book, by, f.symbol)
  let fill := { exec_id: "", qty: f.qty, price: price_decimal(f.price), is_buy: is_buy }
  let notional := f.qty * f.price
  let cash_delta := if is_buy { 0 - notional } else { notional }
  let new_cash := cash_set(t.cash, by, cash_get(t.cash, by) + cash_delta)
  let new_book := book_set(t.book, by, f.symbol, pu.apply_fill(position, fill))
  # A fill's recorded price must match what the re-derived tape actually
  # showed at this point — not merely be internally consistent.
  let price_ok := price_get(t.prices, f.symbol) == f.price
  re_tally(t, t.intact, t.seed, t.tick_max, t.round_cap, t.price_counter, t.prices, new_book, new_cash, t.round, t.price_ticks, t.orders_seen + 1, t.claimed_winner, t.claimed_reason, if price_ok { t.rogue } else { list.concat(t.rogue, [str.join(["fill at a price the tape never showed: ", f.symbol, " @ ", int.to_str(f.price), " by seat ", int.to_str(by)], "")]) })
}

fn step(t :: Tally, l :: tf.Line) -> Tally {
  let intact := t.intact and tf.line_intact(l)
  let t2 := re_tally(t, intact, t.seed, t.tick_max, t.round_cap, t.price_counter, t.prices, t.book, t.cash, t.round, t.price_ticks, t.orders_seen, t.claimed_winner, t.claimed_reason, t.rogue)
  if l.kind != "move" {
    re_tally(t2, intact, t.seed, t.tick_max, t.round_cap, t.price_counter, t.prices, t.book, t.cash, t.round, t.price_ticks, t.orders_seen, t.claimed_winner, t.claimed_reason, t.rogue)
  } else {
    if str.contains(l.payload_json, "\"kind\":\"setup\"") {
      if t.saw_setup {
        { intact: intact, saw_setup: t.saw_setup, mode: t.mode, seed: t.seed, tick_max: t.tick_max, round_cap: t.round_cap, price_counter: t.price_counter, prices: t.prices, book: t.book, cash: t.cash, round: t.round, price_ticks: t.price_ticks, orders_seen: t.orders_seen, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: list.concat(t.rogue, ["duplicate setup commitment"]) }
      } else {
        let md := get_mode(l.payload_json)
        let sd := get_seed(l.payload_json)
        let bankroll := get_starting_bankroll(l.payload_json)
        let tick_max := get_tick_max(l.payload_json)
        let round_cap := get_round_cap(l.payload_json)
        let starting_prices := list.map(symbols(md), fn (s :: Str) -> PriceEntry {
          { symbol: s, price: get_price_of(l.payload_json, s) }
        })
        let starting_cash := list.map(seats(), fn (s :: Int) -> CashEntry {
          { seat: s, cash: bankroll }
        })
        { intact: intact, saw_setup: true, mode: md, seed: sd, tick_max: tick_max, round_cap: round_cap, price_counter: 0, prices: starting_prices, book: [], cash: starting_cash, round: 1, price_ticks: t.price_ticks, orders_seen: t.orders_seen, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: t.rogue }
      }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"orders\"") {
      match (json.parse(l.payload_json) :: Result[Orders, Str]) {
        Err(_) => t2,
        Ok(o) => {
          let applied := list.fold(o.fills, t2, fn (acc :: Tally, f :: Fill) -> Tally {
            apply_fill_line(acc, o.by, f)
          })
          applied
        },
      }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"price_tick\"") {
      let claimed_round := get_round(l.payload_json)
      if t.mode == "crypto" {
        # Crypto mode has no seed-derivable price walk (a real feed's
        # prices can't be recomputed from nothing) — this line's own
        # committed prices ARE the ground truth. Fairness instead comes
        # from the hash chain itself (checked via `intact` above): nobody
        # can rewrite a recorded tick after the fact without breaking it.
        # apply_fill_line's fill-price check still runs unmodified against
        # whatever lands in `prices` here, in both modes.
        let recorded := list.map(symbols(t.mode), fn (s :: Str) -> PriceEntry {
          { symbol: s, price: get_price_of(l.payload_json, s) }
        })
        { intact: intact, saw_setup: t.saw_setup, mode: t.mode, seed: t.seed, tick_max: t.tick_max, round_cap: t.round_cap, price_counter: t.price_counter, prices: recorded, book: t.book, cash: t.cash, round: claimed_round, price_ticks: t.price_ticks + 1, orders_seen: t.orders_seen, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: t.rogue }
      } else {
        let derived := list.fold(symbols(t.mode), { prices: t.prices, counter: t.price_counter, ok: true }, fn (acc :: { prices :: List[PriceEntry], counter :: Int, ok :: Bool }, s :: Str) -> { prices :: List[PriceEntry], counter :: Int, ok :: Bool } {
          let delta := price_delta(t.seed, s, acc.counter, t.tick_max)
          let cur := price_get(acc.prices, s)
          let next := cur + delta
          let floored := if next < min_price_floor() { min_price_floor() } else { next }
          let claimed := get_price_of(l.payload_json, s)
          { prices: price_set(acc.prices, s, floored), counter: acc.counter + 1, ok: acc.ok and floored == claimed }
        })
        let msg := str.join(["price tick at round ", int.to_str(claimed_round), " doesn't match the seed-derived tape"], "")
        { intact: intact, saw_setup: t.saw_setup, mode: t.mode, seed: t.seed, tick_max: t.tick_max, round_cap: t.round_cap, price_counter: derived.counter, prices: derived.prices, book: t.book, cash: t.cash, round: claimed_round, price_ticks: t.price_ticks + 1, orders_seen: t.orders_seen, claimed_winner: t.claimed_winner, claimed_reason: t.claimed_reason, rogue: if derived.ok { t.rogue } else { list.concat(t.rogue, [msg]) } }
      }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"game_over\"") {
      match (json.parse(l.payload_json) :: Result[GameOver, Str]) {
        Err(_) => t2,
        Ok(g) => { intact: intact, saw_setup: t.saw_setup, mode: t.mode, seed: t.seed, tick_max: t.tick_max, round_cap: t.round_cap, price_counter: t.price_counter, prices: t.prices, book: t.book, cash: t.cash, round: t.round, price_ticks: t.price_ticks, orders_seen: t.orders_seen, claimed_winner: g.winner, claimed_reason: g.reason, rogue: t.rogue },
      }
    } else {
      t2
    }}}}
  }
}

type Verdict = { verified :: Bool, intact :: Bool, setup_committed :: Bool, price_ticks :: Int, orders_seen :: Int, winner_confirmed :: Bool, rogue :: List[Str] }

fn living_seats(mode :: Str, book :: List[BookEntry], cash :: List[CashEntry], prices :: List[PriceEntry]) -> List[Int] {
  list.fold(seats(), [], fn (acc :: List[Int], s :: Int) -> List[Int] {
    if equity_cents(mode, book, cash, prices, s) > 0 { list.concat(acc, [s]) } else { acc }
  })
}

fn highest_equity_seat(mode :: Str, book :: List[BookEntry], cash :: List[CashEntry], prices :: List[PriceEntry], living :: List[Int]) -> Int {
  list.fold(living, -1, fn (best :: Int, s :: Int) -> Int {
    if best < 0 { s } else { if equity_cents(mode, book, cash, prices, s) > equity_cents(mode, book, cash, prices, best) { s } else { best } }
  })
}

fn verdict(lines :: List[tf.Line]) -> Verdict {
  let t := list.fold(lines, { intact: true, saw_setup: false, mode: "synthetic", seed: 0, tick_max: 0, round_cap: 0, price_counter: 0, prices: [], book: [], cash: [], round: 1, price_ticks: 0, orders_seen: 0, claimed_winner: -1, claimed_reason: "", rogue: [] }, step)
  let living := living_seats(t.mode, t.book, t.cash, t.prices)
  # bankrupt_out is fully re-checked (exactly one solvent seat must remain,
  # matching the claim). round_cap re-checks the winner against "highest
  # re-derived equity among still-solvent seats" — the same equity figures
  # this verifier independently computed from the replayed fills and the
  # re-derived price tape, not the server's own claimed numbers.
  let winner_ok := if str.is_empty(t.claimed_reason) {
    false
  } else {
    if t.claimed_reason == "bankrupt_out" {
      list.len(living) == 1 and list.fold(living, false, fn (acc :: Bool, s :: Int) -> Bool {
        acc or s == t.claimed_winner
      })
    } else {
      t.claimed_winner == highest_equity_seat(t.mode, t.book, t.cash, t.prices, living)
    }
  }
  let all_rogue := if winner_ok {
    t.rogue
  } else {
    list.concat(t.rogue, ["claimed winner does not match the replayed final equity"])
  }
  { verified: t.intact and t.saw_setup and winner_ok and list.len(all_rogue) == 0, intact: t.intact, setup_committed: t.saw_setup, price_ticks: t.price_ticks, orders_seen: t.orders_seen, winner_confirmed: winner_ok, rogue: all_rogue }
}

fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str {
    if x { "true" } else { "false" }
  }
  let rogue := str.join(["[", str.join(list.map(v.rogue, fn (s :: Str) -> Str {
    str.join(["\"", s, "\""], "")
  }), ","), "]"], "")
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"setup_committed\":", b(v.setup_committed), ",\"price_ticks\":", int.to_str(v.price_ticks), ",\"orders_seen\":", int.to_str(v.orders_seen), ",\"winner_confirmed\":", b(v.winner_confirmed), ",\"rogue\":", rogue, "}"], "")
}

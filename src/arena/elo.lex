# lex-games arena — ELO rating math (pure, deterministic).
#
# The season leaderboard (season.lex) turns a field of verified scores into
# head-to-head ELO ratings that persist across rounds. ELO's expected-score is
# the logistic E = 1 / (1 + 10^((Rb-Ra)/400)), which needs 10^x for fractional x.
# `std.float` has no pow/exp, so we implement exp() ourselves by range reduction:
# x = k*ln2 + r with |r| <= ln2/2, then exp(x) = 2^k * exp(r) with exp(r) a short
# Taylor series (fast convergence on the reduced range) and 2^k by exact doubling.
# Pure IEEE-754 doubles → the same image recomputes the same rating every time,
# which is the arena's one hard rule. Ratings themselves stay integers (the house
# style) by rounding each update.
#
# Effects: pure.

import "std.int"   as int
import "std.float" as flt

# Constants. K is the ELO update step; ratings start at SEED.
fn k_factor() -> Float { 32.0 }
fn seed() -> Int { 1500 }

fn ln2()  -> Float { 0.6931471805599453 }
fn ln10() -> Float { 2.302585092994046 }

# Round-half-away-from-zero of a float to the nearest Int.
fn round(x :: Float) -> Int {
  if x > 0.0 { flt.to_int(x + 0.5) } else { flt.to_int(x - 0.5) }
}

# 2^k for any integer k (k<0 allowed), by repeated multiply — exact for the
# small |k| the range-reduced exp produces.
fn pow2k(k :: Int) -> Float {
  if k == 0 { 1.0 } else {
    if k > 0 { 2.0 * pow2k(k - 1) } else { 0.5 * pow2k(k + 1) }
  }
}

# Taylor series for exp(r) accumulated to N terms. term_n = term_{n-1} * r/n.
fn exp_taylor(r :: Float, n :: Int, term :: Float, acc :: Float) -> Float {
  if n > 16 { acc } else {
    let t := term * r / int.to_float(n)
    exp_taylor(r, n + 1, t, acc + t)
  }
}

# exp(x) via range reduction x = k*ln2 + r, |r| <= ln2/2, exp(x)=2^k*exp(r).
fn exp(x :: Float) -> Float {
  let k := round(x / ln2())
  let r := x - int.to_float(k) * ln2()
  pow2k(k) * exp_taylor(r, 1, 1.0, 1.0)
}

# 10^d = exp(d*ln10).
fn pow10(d :: Float) -> Float { exp(d * ln10()) }

# Expected score of A vs B under the logistic ELO curve, in [0,1].
fn expected(ra :: Int, rb :: Int) -> Float {
  let d := (int.to_float(rb) - int.to_float(ra)) / 400.0
  1.0 / (1.0 + pow10(d))
}

# New rating for A after a game scored sa_milli (1000=win, 500=draw, 0=loss).
fn update_one(ra :: Int, rb :: Int, sa_milli :: Int) -> Int {
  let sa := int.to_float(sa_milli) / 1000.0
  let ea := expected(ra, rb)
  ra + round(k_factor() * (sa - ea))
}

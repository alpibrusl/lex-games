# lex-games — Werewolf verifier: was the game provably fair?
#
# Roles are assigned once, up front, and committed to the trail as the very
# first entry — a replay proves the setup was never rigged (no one secretly
# became the wolf mid-game). From there, every recorded action is re-checked
# against that FIRST commitment, never against a later claim:
#   * every kill was made by the seat that was actually the wolf
#   * every inspection was made by the seat that was actually the seer
#   * every lynch's revealed role matches that seat's committed role
# A forged trail claiming a villager killed someone, or revealing the wrong
# role at a lynch, is caught even if its hashes are otherwise intact — the
# same unauthorized-success pattern as robot_task.lex/notary.lex.
#
# Effects: pure.

import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.json" as json

import "../arena/trail_file" as tf

type RoleAssign = { assign :: { s0 :: Str, s1 :: Str, s2 :: Str, s3 :: Str, s4 :: Str, s5 :: Str, s6 :: Str, s7 :: Str } }
type Kill    = { by :: Int, target :: Int }
type Inspect = { by :: Int, target :: Int, saw :: Str }
type Protect = { by :: Int, target :: Int }
type Lynch   = { target :: Int, role :: Str, day :: Int }

fn ww_seats() -> List[Int] { [0, 1, 2, 3, 4, 5, 6, 7] }
fn role_of(a :: RoleAssign, seat :: Int) -> Str {
  if seat == 0 { a.assign.s0 } else { if seat == 1 { a.assign.s1 } else { if seat == 2 { a.assign.s2 } else { if seat == 3 { a.assign.s3 } else {
  if seat == 4 { a.assign.s4 } else { if seat == 5 { a.assign.s5 } else { if seat == 6 { a.assign.s6 } else { if seat == 7 { a.assign.s7 } else { "?" } } } } } } } }
}
fn count_role(a :: RoleAssign, role :: Str) -> Int {
  list.fold(ww_seats(), 0, fn (acc :: Int, s :: Int) -> Int { if role_of(a, s) == role { acc + 1 } else { acc } })
}
# 8 seats: 1 wolf, 1 seer, 1 doctor, 5 villagers.
fn valid_setup(a :: RoleAssign) -> Bool { count_role(a, "wolf") == 1 and count_role(a, "seer") == 1 and count_role(a, "doctor") == 1 and count_role(a, "villager") == 5 }
fn seat_of_role(a :: RoleAssign, role :: Str) -> Int {
  list.fold(ww_seats(), -1, fn (acc :: Int, s :: Int) -> Int { if acc >= 0 { acc } else { if role_of(a, s) == role { s } else { -1 } } })
}

# The parsed roles.assign shape is a nested object — pick each seat's role out
# of the raw JSON payload by splitting on its "<seat>":" marker, since the wire
# shape uses numeric-string keys that std.json's fixed-field record parse can't
# address directly.
fn assign_get(payload :: Str, seat :: Str) -> Str {
  let marker := str.concat(str.concat("\"", seat), "\":\"")
  let parts := str.split(payload, marker)
  match list.head(list.tail(parts)) {
    None => "?",
    Some(after) => match list.head(str.split(after, "\"")) { Some(v) => v, None => "?" },
  }
}
fn parse_assign(payload :: Str) -> (Bool, RoleAssign) {
  let a := { assign: {
    s0: assign_get(payload, "0"), s1: assign_get(payload, "1"), s2: assign_get(payload, "2"), s3: assign_get(payload, "3"),
    s4: assign_get(payload, "4"), s5: assign_get(payload, "5"), s6: assign_get(payload, "6"), s7: assign_get(payload, "7"),
  } }
  (str.contains(payload, "\"roles\""), a)
}

type Tally = { intact :: Bool, saw_roles :: Bool, roles :: RoleAssign, kills :: Int, inspects :: Int, protects :: Int, lynches :: Int, rogue :: List[Str] }
fn empty_assign() -> RoleAssign { { assign: { s0: "", s1: "", s2: "", s3: "", s4: "", s5: "", s6: "", s7: "" } } }

fn step(t :: Tally, l :: tf.Line) -> Tally {
  let intact := t.intact and tf.line_intact(l)
  if l.kind != "move" { { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills, inspects: t.inspects, protects: t.protects, lynches: t.lynches, rogue: t.rogue } } else {
    let pr := parse_assign(l.payload_json)
    if tup_fst(pr) {
      # the FIRST roles commitment is authoritative; later ones (there
      # shouldn't be any in an honest game) are ignored rather than trusted.
      if t.saw_roles { { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills, inspects: t.inspects, protects: t.protects, lynches: t.lynches, rogue: list.concat(t.rogue, ["duplicate roles commitment"]) } }
      else { { intact: intact, saw_roles: true, roles: tup_snd(pr), kills: t.kills, inspects: t.inspects, protects: t.protects, lynches: t.lynches, rogue: t.rogue } }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"kill\"") {
      match (json.parse(l.payload_json) :: Result[Kill, Str]) {
        Err(_) => { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills, inspects: t.inspects, protects: t.protects, lynches: t.lynches, rogue: t.rogue },
        Ok(k) => {
          let legal := t.saw_roles and role_of(t.roles, k.by) == "wolf"
          { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills + 1, inspects: t.inspects, protects: t.protects, lynches: t.lynches,
            rogue: if legal { t.rogue } else { list.concat(t.rogue, [str.join(["kill by non-wolf seat ", int.to_str(k.by)], "")]) } }
        },
      }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"inspect\"") {
      match (json.parse(l.payload_json) :: Result[Inspect, Str]) {
        Err(_) => { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills, inspects: t.inspects, protects: t.protects, lynches: t.lynches, rogue: t.rogue },
        Ok(ins) => {
          let by_seer := t.saw_roles and role_of(t.roles, ins.by) == "seer"
          let saw_true := ins.saw == role_of(t.roles, ins.target)
          let msg := if not by_seer { str.join(["inspect by non-seer seat ", int.to_str(ins.by)], "") } else { str.join(["inspection of seat ", int.to_str(ins.target), " reported the wrong role"], "") }
          { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills, inspects: t.inspects + 1, protects: t.protects, lynches: t.lynches,
            rogue: if by_seer and saw_true { t.rogue } else { list.concat(t.rogue, [msg]) } }
        },
      }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"protect\"") {
      match (json.parse(l.payload_json) :: Result[Protect, Str]) {
        Err(_) => { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills, inspects: t.inspects, protects: t.protects, lynches: t.lynches, rogue: t.rogue },
        Ok(p) => {
          let by_doctor := t.saw_roles and role_of(t.roles, p.by) == "doctor"
          { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills, inspects: t.inspects, protects: t.protects + 1, lynches: t.lynches,
            rogue: if by_doctor { t.rogue } else { list.concat(t.rogue, [str.join(["protect by non-doctor seat ", int.to_str(p.by)], "")]) } }
        },
      }
    } else {
    if str.contains(l.payload_json, "\"kind\":\"lynch\"") {
      match (json.parse(l.payload_json) :: Result[Lynch, Str]) {
        Err(_) => { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills, inspects: t.inspects, protects: t.protects, lynches: t.lynches, rogue: t.rogue },
        Ok(ly) => {
          let legal := t.saw_roles and ly.role == role_of(t.roles, ly.target)
          { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills, inspects: t.inspects, protects: t.protects, lynches: t.lynches + 1,
            rogue: if legal { t.rogue } else { list.concat(t.rogue, [str.join(["lynch revealed the wrong role for seat ", int.to_str(ly.target)], "")]) } }
        },
      }
    } else { { intact: intact, saw_roles: t.saw_roles, roles: t.roles, kills: t.kills, inspects: t.inspects, protects: t.protects, lynches: t.lynches, rogue: t.rogue } }}}}}
  }
}
fn tup_fst(p :: (Bool, RoleAssign)) -> Bool { match p { (a, _) => a } }
fn tup_snd(p :: (Bool, RoleAssign)) -> RoleAssign { match p { (_, b) => b } }

type Verdict = { verified :: Bool, intact :: Bool, roles_committed :: Bool, setup_valid :: Bool, kills :: Int, inspects :: Int, protects :: Int, lynches :: Int, rogue :: List[Str] }
fn verdict(lines :: List[tf.Line]) -> Verdict {
  let t := list.fold(lines, { intact: true, saw_roles: false, roles: empty_assign(), kills: 0, inspects: 0, protects: 0, lynches: 0, rogue: [] }, step)
  let setup_ok := t.saw_roles and valid_setup(t.roles)
  { verified: t.intact and setup_ok and list.len(t.rogue) == 0, intact: t.intact, roles_committed: t.saw_roles, setup_valid: setup_ok,
    kills: t.kills, inspects: t.inspects, protects: t.protects, lynches: t.lynches, rogue: t.rogue }
}
fn verdict_json(v :: Verdict) -> Str {
  let b := fn (x :: Bool) -> Str { if x { "true" } else { "false" } }
  let rogue := str.join(["[", str.join(list.map(v.rogue, fn (s :: Str) -> Str { str.join(["\"", s, "\""], "") }), ","), "]"], "")
  str.join(["{\"verified\":", b(v.verified), ",\"intact\":", b(v.intact), ",\"roles_committed\":", b(v.roles_committed), ",\"setup_valid\":", b(v.setup_valid),
            ",\"kills\":", int.to_str(v.kills), ",\"inspects\":", int.to_str(v.inspects), ",\"protects\":", int.to_str(v.protects), ",\"lynches\":", int.to_str(v.lynches), ",\"rogue\":", rogue, "}"], "")
}

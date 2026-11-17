# TASK-170a: Battalion battle groups – 7-company combined-arms templates (data)

- **Status**: done
- **Layers**: core
- **Depends on**: –
- **Sections**: GDD "Formations", GDD "Battle hand-off and auto-resolve" (Contact deployment), GDD "First rosters (TASK-039a)"
- **Model**: sonnet (data + tests + one table-driven rule; no tricky algorithm)
- **Topic**: Two-layer game

## Goal

Every operational formation is one balanced combined-arms battle force (tanks + infantry + own rocket artillery), so a contact battle is a 7 v 7 fight instead of 4 v 4 with artillery as separate counters. Part 1 of TASK-170 (AI and balance: TASK-170b).

## Decisions (2026-11-17, human)

- Rework the existing formation types; one formation = one battle force; no new template layer.
- No separate anti-tank unit (infantry squads carry RPGs); v1 roles = tanks + infantry + artillery. No new unit types or models.
- Each battalion has 1 organic MLRS company (Homar-K / 9K57 Uragan), deployed on the map like any company.
- 7 companies per battalion; mechanised = 4 infantry + 2 tank + 1 MLRS; armoured = 4 tank + 2 infantry + 1 MLRS; same shape for both factions.
- Standalone MLRS formations (`pl_mlrs_squadron`, `ru_mlrs_battalion`) are removed; order of battle rebalanced.

## Acceptance criteria (testable)

- [ ] `pl_mech_battalion` = 4 `pl_mech_infantry` + 2 `m1a2_sepv3` + 1 `homar_k` (7 companies, strength 66); `pl_tank_battalion` = 4 `m1a2_sepv3` + 2 `pl_mech_infantry` + 1 `homar_k` (7, 66).
- [ ] `ru_motor_rifle_battalion` = 4 `ru_motor_rifle` + 2 `t72b3` + 1 `bm27_uragan` (7, 62); `ru_tank_battalion` = 4 `t72b3` + 2 `ru_motor_rifle` + 1 `bm27_uragan` (7, 58).
- [ ] Every shipped formation type has exactly 7 companies and exactly 1 company of unit class `mlrs`; `formation_class` is `mechanised` or `armoured` only.
- [ ] `data/formations/pl_mlrs_squadron.tres` and `ru_mlrs_battalion.tres` are deleted; no `.tres` or test references their ids (grep clean).
- [ ] `suwalki_gap`: Poland 6 formations / strength 396 (4 mech + 2 tank); Russia 8 formations / 488 (6 motor rifle + 2 tank: 3+1 in Kaliningrad, 3+1 in Belarus); Russia/Poland strength ratio within 1.15–1.25 (488 / 396 = 1.232).
- [ ] Allies: Lithuania 198 (2 mech + 1 tank), Belarus 182 (2 motor rifle + 1 tank); off-map NATO allies 132; North Korea 124 (`kp_inf_1` + `kp_art_1` both `ru_motor_rifle_battalion`, `kp_art_1` renamed "North Korean Infantry Battalion (2nd)").
- [ ] The ≥ 3 hexes rule: every remaining formation still starts ≥ 3 hexes from each enemy formation, in a country open to its side (existing test stays green).
- [ ] `StrikeLaunch.SITES[&"launcher"]["formations"]` is `[&"mechanised", &"armoured"]` (every battalion now carries launchers); `test_strike_launch` uses a mech battalion instead of the removed squadron and still passes.
- [ ] Contact battle between two full battalions (7 v 7, both factions, both attacker/defender roles): `ContactMap.build` places all 14 companies with no push_error, `deploy_spacing` 2 kept (or relaxed per the existing ladder) and every tile distinct and passable.
- [ ] Auto-resolve of a full 7 v 7 contact battle completes, is deterministic for a fixed seed and `ResolveBattleCommand` accepts the result (no `auto_mismatch`).
- [ ] A played contact battle starts with 7 companies per side, each ref `<formation id>/<n>` with n = 1..7 in template order.
- [ ] Staff map: a mech or tank battalion shows its `mechanised` / `armoured` symbol; nothing crashes for lack of an `artillery` type (the symbol branch may stay, unused).
- [ ] Tests updated: `test_operational_data.gd` (tables of strengths / companies / counts), `test_outside_support.gd` (placement fixture no longer uses `ru_mlrs_battalion`), `test_strike_launch.gd`.

## Playtest (for the human)

1. Start the Suwałki Gap operation as NATO: 6 Polish and 8 Russian counters, no artillery counters; the strength bars read as full 66 / 62 / 58.
2. Move into contact and choose Play battle: each side fields 7 companies including one rocket-artillery company; the defender is clustered near the objective.
3. Choose Auto-resolve on another contact: the result is shown and the survivors' strengths carry over.
4. Trigger a deep strike with a launcher weapon: it launches from one of your battalion hexes.

## Player manual

docs/MANUAL.md (game-designer): replace the formation list with the four battalion types (7 companies, composition and strengths above); say that every battalion brings one rocket-artillery company into a battle and that there are no standalone artillery counters; update the order of battle counts (Poland 6 / 396, Russia 8 / 488), allies and outside-support sizes; battles are now 7 v 7.

## Out of scope

- Tactical AI use of artillery and balance tuning (TASK-170b).
- v2: air defence and helicopters; new unit models; a dedicated anti-tank unit; ammunition and morale; a separate template layer.
- New operational positions for the removed MLRS counters (the order of battle simply gets smaller).

## Implementation notes

- The four battalion `.tres` now hold 7 companies (4+2+1 template); `pl_mlrs_squadron` / `ru_mlrs_battalion` deleted; `suwalki_gap.tres` lost its four MLRS counters, `kp_art_1` is now a second `ru_motor_rifle_battalion` ("North Korean Infantry Battalion (2nd)").
- `StrikeLaunch.SITES[&"launcher"]["formations"]` = `[&"mechanised", &"armoured"]`.
- Tests updated for the new numbers (operational data, outside support, strike launch/command/rules, operation, staff map, contributions, match runner: seeds test also compares `strikes_intercepted`). New test: `test_a_contact_battle_is_seven_against_seven` (14 companies, distinct tiles, refs `<id>/1..7`, deterministic auto-resolve).
- Balance note for TASK-170b: an AI-vs-AI Suwałki match over 3 rounds ends 7 vs 34 in Russia's favour on every seed (round_limit, 2 auto battles); needs tuning.
- Not done: no visual check of staff-map symbols in the game window.

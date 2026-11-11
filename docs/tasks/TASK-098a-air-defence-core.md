# TASK-098a: Air defence and SEAD v1 (1/2, core) – three air-defence types with coverage zones per site, layered interception per weapon class, temporary suppression of a site by a hit

- **Status**: done
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data (`data/air_defence/`, `data/operations/suwalki_gap.tres`) + tests; one small presentation adaptation (`staff_map_strike_trail.gd` reads the new event field so its tests stay green)
- **Depends on**: TASK-141a, TASK-097a (soft: TASK-100, TASK-103)
- **Sections**: GDD "Deep strikes", "Escalation ladder"; ARCHITECTURE "Two layers", "Operational events"; TASK-097a and TASK-141a task files
- **Model**: sonnet (plain integer arithmetic on top of the existing, unchanged draw order; no new `rng` use, tests pin it – so no determinism design left to do)
- **Topic**: Two-layer game
- **Tags**: mvp

## Decisions (human, 2026-11-11)

Q1 air defence is **per-site data**: three types `short`, `medium`, `long` (`data/air_defence/<id>.tres`), each with a radius in hexes and an interception chance **per weapon class**; every `air_defence` installation has an `ad_type`; Q2 **SEAD = temporary suppression**: any hit on a non-destroyed site suppresses it for 2 rounds (data), a new hit refreshes (no stacking), a suppressed site intercepts 0 but still repairs and takes damage; destroyed sites never come back; Q3 layers combine **independently** (`1 − Π(1 − pᵢ)`, cap 90 %), still **one** interception draw per missile, draw order of TASK-097a unchanged; Q4 **deep strikes only** – no effect on battles, aircraft sorties (TASK-132) or airfield capability; reconnaissance stays a hook (TASK-100); Q5 view with coverage overlay, suppressed state and interception odds is TASK-098b (starts with `/design-ui`); core exposes `StrikeRules.interception_chance` and `coverage` for it; Q6 numbers are **[ASSUMPTION]** placeholders for TASK-103; Q7 split into 098a (this) and 098b.

## Goal

Replace TASK-097a's one-number "minimal built-in air defence" (radius 4, 40 % per site) by real layers: short-, medium- and long-range sites with different reach and different strengths against cruise missiles, ballistic missiles, drones and so on, and a way to prepare a strike by hitting the air defence first (suppression). Same rules for both sides; works on TASK-141a's named weapons (the `weapon_class` of a weapon picks the row of the table). The view is TASK-098b.

## Acceptance criteria (testable)

Data (`src/core/data/air_defence_definition.gd`, `data/air_defence/`):

- [ ] `AirDefenceDefinition` (Resource, `data/air_defence/<id>.tres`): `id`, `display_name` (English), `examples` (String, flavour: real systems), `radius_hexes` (≥ 1), `intercept_pct` (Dictionary `weapon_class → 0-100`). `SHIPPED` lists the ids; `shipped()` / `find()` like `StrikeMeansDefinition`. `problem() -> String` ("" when valid; one test per case: empty id, `radius_hexes` < 1, `intercept_pct` missing one of the six weapon classes, an unknown class key, a value outside 0-100).
- [ ] Shipped **[ASSUMPTION]** (a test reads the files; radius in hexes, 1 hex = 5 km; chance in % per weapon class cruise / ballistic / aeroballistic / rocket / drone / loitering): `short` (Pilica+, Pantsir-S1) radius 4 = 20 km: 50 / 0 / 0 / 40 / 60 / 60; `medium` (NASAMS / Narew, Buk-M3, Tor) radius 10 = 50 km: 60 / 20 / 10 / 50 / 60 / 50; `long` (Patriot / Wisła, S-400) radius 30 = 150 km: 55 / 50 / 30 / 50 / 40 / 30. A test asserts `problem() == ""` for each and unique ids.
- [ ] `InstallationPlacement` gains `ad_type: StringName` (default `&""`); `Installation` gains `ad_type` and `suppressed_rounds: int` (0 = active; `suppressed()` = > 0; never negative). `OperationDefinition` gains `suppression_rounds` (default 2) and **loses** `air_defence_radius` / `air_defence_intercept_pct` (no alias; `suwalki_gap.tres`, `OperationalState`, fixtures and tests that used them are rewritten). `OperationalState.air_defence_types` holds the types (like `strike_means`; tests may add made-up types in code, never in `data/air_defence/`).
- [ ] `Operation.from_definition` rejects (`push_error`, null – one test each): an `air_defence` installation with an empty or unknown `ad_type`; an `ad_type` on an installation of another class; `suppression_rounds` < 1. Existing rejections of TASK-097a stay.

State and snapshot:

- [ ] Snapshot gains per installation `ad_type` and `suppressed_rounds` (installations still sorted by id); the TASK-092b determinism test still passes; a snapshot with an unknown `ad_type` is rejected.

Rules (`StrikeRules`, static):

- [ ] `interception_chance(state, striker, weapon_id, target_coord) -> int` (percent, 0-90) replaces `intercept_chance`. For every installation owned by the **enemy of `striker`**, class `air_defence`, not destroyed, **not suppressed**, with `Hex.distance(site, target_coord)` ≤ its type's `radius_hexes` (exactly the radius counts): `pᵢ = intercept_pct[weapon_class] × integrity / 100` (integer, rounded down). Combined by integers in 1/10 000 units: `s = 10000; s = s × (100 − pᵢ) / 100` per site (setup order), `combined = (10000 − s) / 100`, `min(combined, 90)`, then `× interceptability_pct / 100` (integer, rounded down). Unknown weapon → 0. **[ASSUMPTION]** `interceptability_pct` stays as a multiplier on the combined chance (speed, stealth); the class table and the multiplier overlap (a ballistic weapon is low in both), so TASK-103 must tune them together and may drop one.
- [ ] Worked examples (shipped types, sites at integrity 100 unless stated, target in every radius): `short` vs `kalibr` (cruise, int. 100) 50; `medium` vs `iskander_m` (ballistic 20, int. 40) 8; `long` vs `geran_2` (drone 40, int. 150) 60; `medium` 100 + `long` 50 vs `jassm_er` (cruise, int. 70): 60 and 27 → combined 70 → **49**; `short` + `medium` + `long` vs `kalibr`: combined 91 → cap **90**, vs `jassm_er` 63; the same trio with `medium` suppressed vs `jassm_er`: 77 → **53**; `short` vs `kinzhal` (aeroballistic 0) 0; a target at radius + 1, a destroyed site and an own-side site contribute 0.
- [ ] Mirrored: every example with the sides swapped (sites of player 0 vs a Russian weapon and so on) gives the same number; no code reads a side id.
- [ ] `coverage(state, player) -> Array[Dictionary]`: the **non-destroyed** air-defence sites owned by `player`, setup order, `{id, coord, ad_type, radius_hexes, integrity, suppressed (bool), suppressed_rounds}`. Example: the shipped NATO side → 3 entries with radii 30 / 10 / 4 (view data for TASK-098b; no state is changed).
- [ ] `resolve` computes `p_intercept` **once before the salvo** with `interception_chance` (a hit inside the salvo does not change the chances of the remaining missiles); the draws are unchanged: per missile `randi_range(1, 100)` interception, then `randi_range(1, 100)` hit, so `rng_state` advances by exactly 2 × `count`. `strike_resolved` gains `interceptor_ids: Array[StringName]` (sites that were counted, i.e. covering, active, `pᵢ` > 0; setup order); `p_intercept` is the final percentage.

Suppression (SEAD):

- [ ] In `resolve`, when `hits` ≥ 1 on an `air_defence` installation that is **not destroyed by the salvo**: `suppressed_rounds = suppression_rounds` (a refresh, never added to: 2 stays 2) and event `installation_suppressed` (`id`, `before`, `after`, `cause` `strike`) after `installation_changed`; emitted on every such hit, also when `before` = `after` = 2. A salvo with 0 hits, or one that destroys the site, does not suppress it (a destroyed site has `suppressed_rounds` 0). Hits on any other class never suppress.
- [ ] A suppressed site intercepts 0 (see examples), still takes damage, still repairs (TASK-097a repair rule unchanged), keeps its zone in `coverage` with `suppressed` true, and is still a legal target.
- [ ] Round boundary (`StrikeRules.end_round`, inside `EndOperationalTurnCommand`, after resupply and repair): every installation with `suppressed_rounds` > 0 loses 1 (setup order), event `installation_suppressed` (`cause` `lapse`). Trace with `suppression_rounds` 2: a hit in round r → 2; boundary after r → 1; boundary after r + 1 → 0 (so the site is silent for the rest of round r and the whole of round r + 1, active again in r + 2). A hit in round r + 1 while at 1 refreshes to 2. No `rng` draws at the boundary.
- [ ] Sequence example (strip grid, player 0 level 3, enemy `medium` site integrity 100 next to an enemy airfield, a test weapon with `jassm_er`'s numbers but accuracy 100, damage 40): `p_intercept` on the airfield 42 (60 × 70 / 100); a strike on the site (1 hit, integrity 100 → 60, `suppressed_rounds` 2); a strike on the airfield in the same round has `p_intercept` 0 and `interceptor_ids` []; after two round boundaries the site shows `suppressed_rounds` 0 and integrity 70 (repair +5 twice) and `p_intercept` on the airfield is 29 (pᵢ = 60 × 70 / 100 = 42, × 70 / 100).
- [ ] Destroyed site: strike to integrity 0 → `suppressed_rounds` 0, `destroyed()` true, contributes 0 forever, repair does not revive it.

Scope fences:

- [ ] No effect outside deep strikes: tactical battles, `capability()` (it does not read suppression), aircraft sorties and the `strike_allowed` rules are untouched (a test: `capability(state, p, &"airfield")` is the same with every air-defence site suppressed).
- [ ] Determinism: same seed + same commands → same snapshot and events; `rng_state` advances 2 × `count` per accepted strike, 0 per rejected one, whatever the number of sites; a strike's draws are identical before and after this task for the same seed (only `p_intercept` differs).
- [ ] Codec / replay: `OperationalCommandCodec` is unchanged (no new command). The scripted `suwalki_gap` replay of TASK-097a (and any committed snapshot or replay fixture that carries `air_defence_radius` or lacks `ad_type`) is **regenerated** and re-pinned (the draws are the same, the interception percentages differ); list the files in the notes.
- [ ] `staff_map_strike_trail.gd` (`interceptors`, `interceptors_before`) reads `interceptor_ids` of the event instead of `state.air_defence_radius`; its tests keep passing (one case: 0 intercepted → no marks).

Shipped data (`suwalki_gap.tres`, **[ASSUMPTION]**; the agent picks the extra hexes on the real map, one installation per hex, on land in the right country, next to the named place, and lists them in the notes):

- [ ] Every side gets **three** air-defence sites, one of each type, so each side has **8 installations (16 in total)**; the 097a count test and every "7 per side" mention are updated. NATO: Białystok `nato_ad_bialystok` → `long` (Patriot / Wisła), Suwałki `nato_ad_suwalki` → `short` (Pilica+), new `nato_ad_olsztyn` `medium` (Narew) next to the Olsztyn-Mazury airfield. Russia: Kaliningrad `ru_ad_kaliningrad` → `long` (S-400), Grodno `ru_ad_grodno` → `medium` (Buk-M3 class), new `ru_ad_chernyakhovsk` `short` (Pantsir-S1) next to Chernyakhovsk airfield. A test checks the per-side type set {short, medium, long} and the owners.
- [ ] Effect check in the shipped operation (test): `interception_chance` of every NATO weapon on `ru_c2_kaliningrad` (inside the `long` zone of `ru_ad_kaliningrad`, whose chances are all > 0) is > 0; on `ru_airfield_lida` (outside every Russian zone) it is 0; mirrored: a Russian weapon on `nato_c2_bialystok` is > 0 and on `nato_depot_kaunas` is 0.
- [ ] Docs: ARCHITECTURE "Two layers" (`AirDefenceDefinition`, `ad_type`, coverage rule and formula, suppression and its countdown, `StrikeRules.interception_chance` / `coverage`, removal of `air_defence_radius` / `air_defence_intercept_pct`, draw order unchanged); "Operational events": new `installation_suppressed` (causes `strike`, `lapse`), `strike_resolved` field `interceptor_ids`, snapshot fields `ad_type` / `suppressed_rounds`.
- [ ] Docs: GDD "Deep strikes" bullets Resolution, Targets and Fog rewritten for air-defence types and SEAD (the designer has done it with this spec; the agent checks that the code and the numbers match and reports any difference); `docs/CODEMAP.md` is regenerated by `tools/check.sh`.

## Look (Claude Design)

None (core). The view is TASK-098b.

## Playtest (for the human)

1. `--debug` operation, F9 Strikes: NATO `jassm_er` ×2 on a Russian airfield inside the Kaliningrad zone (Open war): the toast shows an interception percentage above 0; the same on Lida (outside the zones): 0 %.
2. Strike a Russian air-defence site (hit): the next strike on a target it covered shows a lower (or 0 %) interception; End turn twice: the zone is active again. No marker or overlay change yet (TASK-098b); read the numbers in the toast / event log.
3. Destroy an air-defence site: it never intercepts again, also after several rounds.
4. Review the three types' radii and chances (see table), flag anything absurd for TASK-103.

## Player manual

Chapter **Deep strikes**: replace the "interception by air defence" paragraph. Three air-defence types (short / medium / long) with reach in hexes and kilometres and what each is good at (table of chances per weapon kind, in words and numbers from `data/air_defence/*.tres`); that every missile faces one interception roll made of all covering sites together (cap 90 %), scaled by the weapon's interceptability; damaged sites defend worse (integrity); a hit on a site silences it for the rest of the round and the whole next one (it still repairs and can be hit; destroyed sites never return); striking the air defence first is how a strike is prepared; battles and aircraft are not affected. The shipped sites per side (three each, with places). Controls and visuals come with TASK-098b.

## Out of scope

The coverage overlay, suppressed marker state and interception odds in the UI (TASK-098b); reconnaissance and fog of air-defence sites (TASK-100: hook only, all sites are known); aircraft sorties and battle effects (TASK-132, TASK-099); launcher platforms and shoot-down of the launcher; mobile or built air defence and replacements (TASK-105); the AI choosing SEAD targets (TASK-102); technology effects (TASK-104); limited interceptor stock (v1 has none); final balance (TASK-103).

## Implementation notes

- Done as specified: `AirDefenceDefinition` + `data/air_defence/{short,medium,long}.tres`; `ad_type` / `suppressed_rounds` on `InstallationPlacement` / `Installation` (snapshot too); `OperationDefinition.suppression_rounds` replaces `air_defence_radius` / `air_defence_intercept_pct`; `OperationalState.air_defence_types`; `StrikeRules.interception_chance`, `interceptors`, `coverage`; suppression in `resolve` and the countdown in `end_round`; `installation_suppressed` event and `interceptor_ids` on `strike_resolved`. Tests: `tests/unit/test_air_defence.gd` (new), plus the rewritten old ones.
- Extra hexes chosen on the real map (one installation per hex, land, right country): `nato_ad_olsztyn` (medium) at (-18, 50), Poland, next to the Olsztyn-Mazury airfield (-17, 50); `ru_ad_chernyakhovsk` (short) at (9, 22), Russia, next to the Chernyakhovsk airfield (8, 22). The four existing sites only got their `ad_type`.
- Presentation: `StaffMapStrikeTrail.interceptors_before` now reads the event's `interceptor_ids` (the old `interceptors` helper that read `state.air_defence_radius` is gone); the only presentation edit.
- Regenerated fixtures / replays: none were committed with `air_defence_radius` or without `ad_type` (the scripted replays build their state from `suwalki_gap.tres` at run time and assert behaviour, not pinned percentages); the only data file changed is `suwalki_gap.tres`.
- Test fixtures: `Fixtures.generic_strike_means()` now gives `ballistic` / `strike_drone` their weapon classes (`ballistic`, `drone`); staff-map tests that wanted "no interception" now clear `state.air_defence_types`.
- Known limitation: there is no snapshot loader in core, so "a snapshot with an unknown `ad_type` is rejected" is enforced where `ad_type` enters (`Operation.from_definition` rejects an unknown `ad_type`); nothing reads a snapshot back yet.
- GDD "Deep strikes": checked, numbers match the code.

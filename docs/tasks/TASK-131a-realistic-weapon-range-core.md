# TASK-131a: Realistic weapon range – core, AI, data, balance

- **Status**: done
- **Layers**: core / ai (+ data `.tres`, unit catalog)
- **Depends on**: TASK-089a (done), TASK-120 (done; auto-resolve recalibration)
- **Sections**: GDD "Combat" (incl. "Per-element rolls"), GDD "Stat derivation rules" → "Attack range", GDD "Balance of the default battle"; ARCHITECTURE "Commands" (via `tools/doc.py architecture`)
- **Model**: opus
- **Split**: 131a = this (rules, data, AI, balance); 131b = presentation and manual (TASK-131b, depends on this task).

## Goal

Every unit fires at its real range: a tank gun reaches 8 hexes instead of the adjacent hex, rifles 2, rocket artillery the whole map. Forests, buildings and hills block direct fire, distance weakens hits, and the AI plays it sensibly.

## Decisions (2026-11-10)

1. **Scale**: real metres / 250 m (hex size on the tactical map) = hexes. Ranges are stored in **metres** in `data/units/*.tres` (`effective_range_m`, `max_range_m`, `min_range_m`) and in the unit catalog; `attack_range` (hex count) is removed from data and replaced by derived hex values. Conversion: `effective_hexes = floor(effective_range_m / 250)`, `max_hexes = floor(max_range_m / 250)`, `min_hexes = ceil(min_range_m / 250)` (0 = none).
2. **Line of sight (LoS)**: direct fire needs it, indirect fire (artillery, MLRS, mortars) ignores it. Forests, buildings and hills (hex elevation) block; units do not block **[ASSUMPTION]** (companies are 250 m wide, a tank does not hide a target 1 km behind it).
3. **Distance effect**: full hit chance up to effective range, falling linearly to **50 %** at maximum range, inside the per-element roll of TASK-089a; no extra rng draws; the forecast uses the same maths.
4. **Counterattack** only if the defender can reach the attacker (distance within its min..max range) **and** (direct fire) sees it.
5. **Artillery**: real range, anything beyond the map covers the whole battlefield. New **minimum range 750 m (3 hexes)** **[ASSUMPTION]** (real MLRS minima are several km, but battle maps are 7.5 km; 750 m keeps the "cannot fire at an adjacent or next-but-one hex" meaning). This **replaces** the GDD rule "no minimum range".
6. **Split**: core/AI/balance here, UI in TASK-131b.
7. **Balance**: after the change re-balance with `tools/simulate.sh` (attack/defense may be tuned), regenerate the replay fixture, recheck spawn distance and auto-resolve calibration.
8. **AI**: stays at the longest range with clear LoS to the best target, closes in only to reach it, ranged units avoid standing in the enemy's range when possible, deterministic tie-breaks.

## Unit ranges (data; (?) = uncertain, confirm in the catalog with a source)

Fire mode `direct` or `indirect` is a new `UnitDefinition` field. Effective = full effect; maximum = last hex where the unit may fire. Hexes by the rule in Decision 1.

| Unit | Weapon | Mode | Effective m (hexes) | Maximum m (hexes) | Min m (hexes) |
|---|---|---|---|---|---|
| pl_mech_infantry | Grot 5.56, squad MG, RPG-7 / Carl Gustaf | direct | 500 (2) | 750 (3) (?) | – |
| ru_motor_rifle | AK-74M, PKM, RPG-7V2 | direct | 500 (2) | 750 (3) (?) | – |
| m1a2_sepv3 | 120 mm M256, M829A3 | direct | 2000 (8) | 3500 (14) (?) | – |
| t72b3 | 125 mm 2A46M-5, standard APFSDS (no Refleks missile) | direct | 2000 (8) | 3000 (12) (?) | – |
| bm27_uragan | 220 mm 9M27 | indirect | 30000 (120) (?) | 35000 (140) | 750 (3) [ASSUMPTION] |
| homar_k | 239 mm CGR-080 guided (not the 290 km CTM-290 missile) | indirect | 70000 (280) (?) | 80000 (320) | 750 (3) [ASSUMPTION] |

Notes: the catalog `fire_range_km` of Homar-K (290) is the ballistic missile, outside standard equipment (GDD principle 6); this task adds `effective_range_m` / `max_range_m` / `min_range_m` fields to every `unit.json` with a `source` and `verified` per field (the existing per-field source schema), marked `verified: false` for the (?) values. Direct-fire ranges: effective = practical engagement range of the weapon, maximum = longest range with a realistic hit chance (tank gun sight/fire control limit); they are design values with sources, not firing tables. Maps are about 30 x 24 hexes (diagonal about 38 hexes), so artillery effectively hits the whole map beyond its minimum.

## Rules

- **Distance** is hex distance. A shot is legal when `min_hexes <= d <= max_hexes` (and LoS, direct fire).
- **LoS function** (`src/core`, pure, `RefCounted`, static): `LineOfSight.visible(grid, from, to) -> bool`. The line is the hex line from `from` to `to` (cube lerp, ties nudged by a fixed epsilon so it is symmetric-deterministic); endpoints are not checked. Sight height at a line hex = linear interpolation between `ground(from) + 2 m` and `ground(to) + 2 m` (eye height 2 m **[ASSUMPTION]**). A middle hex blocks when `ground(h) + obstacle(h) > sight height`. `ground` = real elevation in metres (imported maps: `elevation_m`; otherwise `elevation * 1000`). `obstacle` = `los_obstacle_m` in the terrain `.tres`: forest 20, urban 12 **[ASSUMPTION]**, all others 0. Hills block through their ground elevation.
- **Hit chance with distance**: with `base = max(1, attack - (defense + tile bonus))`, `span = max_hexes - effective_hexes`, `over = max(0, d - effective_hexes)`: a shot hits when `roll * 2 * span <= base * (2 * span - over)`, `roll = rng.randi_range(1, max_hp)` (integer maths, no floats; `span = 0` means no falloff). One draw per shot as in TASK-089a.
- **Forecast** (`CombatForecast`) uses the same probability for attacker and counter, and reports distance, factor and LoS state.
- **AttackCommand.validate** order: existing checks, then `out_of_range` (`d > max_hexes`), `too_close` (`d < min_hexes`), `no_line_of_sight` (direct fire, no LoS).
- **Spawn**: scenario slot logic that sorted by `attack_range == 1` uses `fire mode`/effective range instead (direct units front column).

## Acceptance criteria (testable)

- [ ] Data: all six `.tres` hold the table's metres and fire mode; `attack_range` no longer exists; `UnitDefinition.effective_hexes()` etc. return 2/3, 8/14, 8/12, 120/140, 280/320 and `min_hexes()` 3 for the artillery.
- [ ] Catalog: each `unit.json` has effective/max (and min for artillery) range in metres with source; a test reads the catalog and compares with the `.tres` values.
- [ ] LoS: open plains line, a forest hex between attacker and target blocks (direct), a forest as the target or the attacker hex does not.
- [ ] LoS: a hill hex of 40 m between two 0 m plains units blocks; the same hill 3 m high does not; a unit on the hill (40 m) sees over a 15 m forest 4 hexes away.
- [ ] LoS: `visible(a, b) == visible(b, a)` on 100 random hex pairs of a fixed-seed map; adjacent hexes always visible.
- [ ] Attack: T-72B3 hits a target at distance 8 (full chance), at 12 (50 % factor), `out_of_range` at 13.
- [ ] Attack: infantry at distance 3 shoots with factor 1/2, at 4 gets `out_of_range`.
- [ ] Attack: tank behind a forest hex returns `no_line_of_sight`; Homar-K at the same geometry is allowed (indirect).
- [ ] Attack: artillery at distance 1 and 2 returns `too_close`, at 3 is allowed.
- [ ] Roll maths: base 4, max_hp 10, span 4, over 2 hits exactly on rolls 1-3 (`roll * 8 <= 4 * 6`); over 4 on rolls 1-2; over 0 on rolls 1-4 (table-driven for span 0, 1, 4); the rng is consumed exactly `hp` times per strike as before (draw counter test).
- [ ] Counter: Abrams hit by a squad from 3 hexes counters (range 14, LoS); a squad hit by an Abrams from 6 hexes does not (range 3).
- [ ] Counter: defender behind a forest hex (no LoS, direct fire) does not counter; an artillery defender counters at 4 hexes without LoS, not at 2 (`min_hexes`).
- [ ] Forecast: `forecast()` expected damage at max range = 50 % of the damage at effective range for the same pair; `validate` reasons mirror the command's.
- [ ] Determinism: same seed and orders give identical event logs twice; replay fixture regenerated and its test passes.
- [ ] AI: a T-72B3 with a target in LoS ends its move at the largest distance up to its effective range from which it sees the target (not adjacent); ties broken by lowest (y, x).
- [ ] AI: no LoS from any reachable hex within range, it moves toward the nearest hex that gives LoS and range; a squad closes in only until `max_hexes` is reached.
- [ ] AI: Homar-K prefers a firing hex outside every enemy `max_hexes` (with LoS for direct units) over one inside, when both reach the target; if none exist it still fires.
- [ ] Spawn: default and suwalki_battle scenarios have no enemy pair within direct-fire effective range of 8 hexes at turn 1 (test on spawn distance), else slot distance is adjusted.
- [ ] Balance: `tools/simulate.sh 200` for `poland,russia`, `russia,poland`, `poland,poland`, `russia,russia`: Poland 40-60 % of decided matches over the first two, draws <= 15 %, errors 0; numbers recorded in GDD "Balance of the default battle".
- [ ] Auto-resolve: `data/battle/auto_resolve.tres` recalibrated (win shares of auto-resolve vs played battles on the default battle differ by <= 20 points; TASK-120 calibration test passes).
- [ ] Rejection reasons exist and are unit-tested: `out_of_range`, `too_close`, `no_line_of_sight`.

## GDD changes (designer, done with this refinement)

"Attack range" band table replaced by the metres rule; "Combat": Attack bullet (range, LoS, new codes), Counterattack bullet (reach and sight), Ranged units bullet (minimum range, whole-map reach).

## Playtest (for the human)

Presentation comes in TASK-131b. After this task only check with the existing UI that: a tank can be ordered to attack an enemy 6 hexes away in the open; an attack through a forest is refused (no feedback beyond the existing rejection); watch an AI-vs-AI game (`tools/simulate.sh 5 --verbose` or the AI turn): tanks stop several hexes away and fire, squads stay out of tank range if they can.

## Player manual

Done in TASK-131b (the manual describes behaviour together with its overlay); until then docs/MANUAL.md says nothing new.

## Out of scope

- Operational-map strike ranges (GDD "Means"); fog of war (TASK-007); vision range; ammunition; several weapons per unit (a unit has one weapon profile); units blocking LoS; range/LoS UI (TASK-131b).

## Implementation notes

- **Data**: `UnitDefinition` loses `attack_range`; new `effective_range_m` / `max_range_m` / `min_range_m` (defaults 250 / 250 / 0 = adjacent hex only, so generic test units keep their old reach), `fire_mode` (`direct` / `indirect`, StringName consts `FIRE_DIRECT` / `FIRE_INDIRECT`), `HEX_METRES = 250`, helpers `effective_hexes()`, `max_hexes()`, `min_hexes()`, `is_indirect()`. The six `data/units/*.tres` hold the table's values. `TerrainDefinition.los_obstacle_m` (forest 20, urban 12).
- **Catalog**: every `unit.json` has `effective_range_m` / `max_range_m` (+ `min_range_m` for the MLRS) with a provenance `source` and `verified` (false for the (?) values; the 750 m minimum is the human decision of 2026-11-10). The catalog tool knows the fields (`catalog.py` `RANGE_FIELDS` in key order / numeric / research fields, `unit.schema.json`, three number inputs in `app.js`). `test_unit_catalog_consistency.gd` compares them with the `.tres`.
- **Rules**: `LineOfSight` (`src/core/line_of_sight.gd`, static) on `Hex.line` (cube lerp with a fixed nudge `Hex.LINE_NUDGE`; `visible` traces from the endpoint with the lower (y, x) so it is symmetric). `AttackCommand.fire_problem(state, definition, from, to)` (`out_of_range`, `too_close`, `no_line_of_sight`) is the one range/sight check: validate (after the old checks), the counter, `tiles_in_range`, `CombatForecast` and the AI. `AttackCommand.hit_faces(base, max_hp, span, over)` is the integer falloff; `hit_on` = `hit_on_at(distance)`; `range_factor` for the forecast. Still one rng draw per shot. `CombatForecast.compute_at(state, attacker, defender, from)` plus fields `distance`, `range_factor`, `line_of_sight`, `problem`; the counter uses the falloff of the defender at the same distance.
- **AI** (`AiPlayer._firing_destination`): firing hexes = reachable hexes (and the own) from which it can hit an enemy with a non-zero chance; ranked by (outside every enemy's reach, best `target_score` from there – forecasts cached per enemy/distance/counter, distance to the nearest enemy (larger), current hex, lowest (y, x)). With no firing hex in reach it heads for the nearest firing hex on the map (hex distance, ties (y, x)). `_best_target` skips targets with zero hit faces; `_action_score` uses `fire_problem` from the destination.
- **Spawn**: front/back slots by fire mode (same split as range 1). No slot change needed: closest enemy pair at turn 1 is > 8 hexes on default (both assignments) and suwalki_battle (`test_spawn_distance.gd`).
- **Balance** (seeds 1..200): shipped composition gave Poland 33.1 %; tuning ladder → Russian `default_force` now 4 × Motor Rifle Squad, 1 × T-72B3, 1 × Uragan: poland,russia 154 / 44 / 0 draws / 2 cuts, russia,poland 147 / 53 / 0 / 0 → Poland **52.0 %**, errors 0, draws ≤ 1.5 %; mirrors P0 72.0 % / 80.2 % (strong first-mover bias, flagged in GDD "Balance of the default battle"). Stats untouched.
- **Auto-resolve**: NOT recalibrated – `auto_resolve.tres` stays 8 / 50. On the default battle (100 seeds) auto-resolve gives Russia 91–94 % of the matches (Poland ~3 % of the decided) vs played ~50 %; a sweep of `default_rounds` 1–20 × `break_share` 10–100 never brings Poland's share above ~5 % (Russia always wins when decided). Even with the old composition auto gave Russia ~92 % of the decided. The resolver has no range / first-strike model, so the ≤ 20-point criterion cannot be met with its two numbers – needs a human decision (an auto-resolve rule change, a follow-up task). TASK-120 tests pass unchanged.
- **Replay fixture** regenerated (`tools/make_replay_fixture.sh`: 79 commands, turn 8, winner 0).
- **Deviations / assumptions**: (1) the LoS criterion "a 3 m hill does not block" contradicts the rule (eye 2 m, ground 3 m > 2 m blocks); the rule was kept and the test uses a 1.5 m rise (and asserts 3 m blocks). (2) The "unit on a 40 m hill sees over a forest" test uses the forest's 20 m obstacle 2 hexes out. (3) With base 1 the falloff floors to 0 faces at maximum range (squad vs tank / squad at 3 hexes): legal but harmless; the AI skips such targets/hexes. (4) Hand-made / generated maps use `elevation × 1000` m (generated land spans 120–700 m, hills to 2200 m), so their relief blocks a lot of sight. (5) The squad AI criterion is tested as "starts 6 hexes away, ends at 3" – when it can reach its effective range it prefers that (full chance) over the maximum.
- **For TASK-131b (presentation)**: `TargetRingModel.REASON_TEXTS` has no text for `too_close` / `no_line_of_sight` (falls back to the code); `battle_controller` range overlay now shows for every unit with `max_hexes() >= 2` and uses `tiles_in_range` (LoS-aware); ground-mark craters pass range 1 for direct fire to keep tank shots from cratering; unit popup / catalog "Range" show maximum hexes.

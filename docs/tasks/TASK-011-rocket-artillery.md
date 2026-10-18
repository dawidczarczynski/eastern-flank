# TASK-011: Ranged unit (self-propelled rocket artillery)

- **Status**: done
- **Layers**: core / ai / presentation (+ data)
- **Depends on**: **TASK-010** (counterattack – the archer's advantage is that melee units can't hit back at range 2). Soft: TASK-009 (`valid_targets` already handles range).
- **Model**: sonnet

## Goal

A third unit type with a distinct role: a fragile, long-range damage dealer that fires from up to 5 hexes away without taking counter damage from melee units, and must be protected by infantry. Also moves the starting army setup from the view into core, so replays (TASK-005) and AI-vs-AI simulations (TASK-012) can build the same battle headless.

> **Revision (2026-10-18, human feedback):** the first version was a literal archer (range 2), which doesn't fit the setting (rifle squads, tanks). The unit is now **self-propelled rocket artillery** with **range 5**, a rocket-volley attack animation and a visible attack range on the map. The `Scenario` and AI parts stay as implemented.

## Acceptance criteria (testable)

- [x] `data/units/archer.tres` is replaced by `data/units/rocket_artillery.tres` (proposed balance, to be tuned with TASK-012): `id = &"rocket_artillery"`, `display_name = "Rocket Artillery"`, `short_name = "ART"`, `max_hp = 6`, `move_points = 3`, `attack = 5`, `defense = 1`, `attack_range = 5`. Test loads the file and checks the values. No `archer` references remain in code, data, tests or i18n.
- [x] Combat numbers with the real data files on plains (tests in `tests/unit/test_rocket_artillery.gd`):
  - artillery attacks infantry at distance 2 and at distance 5 → infantry **10 → 8**, no counter, artillery stays **6**.
  - artillery attacks infantry at distance 1 → infantry **8**, counter `max(1, 4 − 1) = 3` → artillery **3**.
  - cavalry attacks artillery (distance 1) → artillery **6 → 2**; artillery counters (no minimum range yet) `max(1, 5 − 2) = 3` → cavalry **8 → 5**.
  - artillery attacks artillery at distance 5 → target **6 → 2**, counter `4` → attacker **2**.
  - artillery attacks at distance 6 → rejected with `out_of_range`.
- [x] Range query in core: `AttackCommand.tiles_in_range(state, unit) -> Array[Vector2i]` returns every grid coordinate with `1 ≤ distance ≤ unit.definition.attack_range` from the unit (own tile excluded, only tiles that exist in the grid). Tests: range 1 in the middle of `Fixtures.plains_grid(3)` → 6 tiles; range 2 → 18; range 5 near the grid edge → only in-grid tiles. The view uses this query (future line-of-sight rules go here, not in the view).
- [x] Starting setup in core: `Scenario.default_battle(seed_value: int) -> GameState` in `src/core/scenario.gd` (pure; preloads the unit `.tres` files). It generates a 12×10 map with `MapGenerator.generate` from a separate `RandomNumberGenerator` seeded with `seed_value`, creates `GameState(grid, 2, seed_value)`, forces every spawn tile to PLAINS (`MapGenerator.force_terrain`) and adds units in this order (offset `(col, row)` → `MapGenerator.offset_to_axial`), so ids are 1–8:
  - player 0: infantry (1, 3), cavalry (1, 5), infantry (1, 7), **rocket artillery (0, 5)**;
  - player 1: infantry (10, 2), cavalry (10, 4), infantry (10, 6), **rocket artillery (11, 4)**.
- [x] Tests for `Scenario`: 8 units, 4 per player, exactly one rocket artillery per player, all units on PLAINS tiles, no two units on the same tile; two calls with seed `12345` give identical terrain and unit lists; terrain for seed `12345` equals `MapGenerator.generate(12, 10, rng seeded 12345)` apart from spawn tiles.
- [x] `BattleController` builds its state with `Scenario.default_battle(MAP_SEED)`; no spawn list or unit preloads in presentation.
- [x] AI positioning for ranged units: `AiPlayer` picks the reachable tile whose distance `d` to the nearest enemy minimises `|d − attack_range|`; ties prefer `d ≤ attack_range`, then staying on the current tile, then iteration order. Melee behaviour unchanged.
  - Tests (fixture units, range 2): archer-style unit at `(0,0)`, enemy `Fixtures.fighter(4, 3)` at `(4,0)` → ends at distance 2, enemy 8 HP, no counter; a ranged unit already at its preferred distance doesn't move and attacks.
  - Test (real `rocket_artillery.tres`, range 5): enemy infantry adjacent on `Fixtures.plains_grid(6)` → the artillery moves away (ends at distance > 1, ideally the best reachable distance towards 5), attacks, and takes no counter.
- [x] View – model: rocket artillery is a procedural vehicle (e.g. wheeled or tracked chassis with a cab and a tilted multi-tube rocket pod on the back, faction colours), clearly distinct from the tank and the infantry squad; chosen by `definition.id`. Uses vehicle locomotion like the tank where that fits.
- [x] View – volley animation: when rocket artillery attacks (also when it counterattacks), the pod fires a salvo of several rockets in quick succession; each rocket flies on a ballistic arc from the pod to the target tile with a small trail/flash, then impacts (flash/puff), followed by the existing hit/HP reaction. The event queue waits for the volley so later events don't overlap. Purely presentational (no rules, no `GameState.rng` – use a view-local RNG if any randomness is needed).
- [x] View – attack range on the map: when a unit with `attack_range ≥ 2` is selected, the tiles from `AttackCommand.tiles_in_range` (from its current position) are marked in a way distinct from the reach wash and the attackable-enemy markers (e.g. a thin outline of the range boundary or a faint tint). Hovering any unit with `attack_range ≥ 2` (own or enemy) while nothing is selected shows its range too, so the player can read the threat zone.
- [x] i18n: `Rocket Artillery` / `ART` rows (pl: `Artyleria rakietowa` / `ART`); the archer rows are removed.
- [x] GDD: units table row is "Rocket Artillery … 5 … implemented"; archer wording in GDD updated.

## Playtest (for the human)

1. `tools/run.sh` – each side has 4 units; the rocket artillery stands behind the cavalry and looks like a rocket launcher vehicle.
2. Select your artillery – movement works (3 points) and its attack range (5 hexes) is marked on the map, distinct from the movement wash.
3. Hover the enemy artillery with nothing selected – its threat range is shown.
4. Attack an enemy up to 5 hexes away – a rocket salvo flies to the target, it loses HP, no counterattack.
5. Drive the artillery next to an enemy and attack – the enemy counterattacks.
6. During AI turns, the AI artillery keeps its distance and fires salvos.

## Out of scope

- Line of sight / obstacles blocking shots, minimum range, terrain affecting range (e.g. hills +1).
- Separate melee/ranged attack values (Wesnoth-style weapons).
- 3D models (procedural primitives only).
- Moving the scenario definition itself to a `.tres` resource (follow-up when there is more than one battle).

## Implementation notes

- **History**: first implemented as a literal archer (range 2); reworked on human feedback into rocket artillery (range 5) with a volley animation and a range overlay. The `Scenario` and AI positioning parts carried over unchanged.
- **Data / i18n**: `data/units/rocket_artillery.tres` (hp 6, mp 3, atk 5, def 1, range 5, short name `ART`); `Rocket Artillery`/`ART` rows (pl: `Artyleria rakietowa`/`ART`).
- **Core**: `Scenario.default_battle(seed)` in `src/core/scenario.gd` owns the map size, unit preloads and spawn list (ADR 0004). `AttackCommand.tiles_in_range(state, unit)` is the single source for "which tiles can this unit shoot at" (future line of sight goes there).
- **AI**: `AiPlayer._best_destination` / `_is_better` minimise `|d − attack_range|`; ties prefer `d ≤ range`, then the current tile. For range 1 this is the old "closest tile" rule.
- **Model**: `UnitModels._make_rocket_artillery` – 6-wheel truck with a cab and a tilted `Pod` holding six tubes (`Mouth0..5`). `UnitModels.is_vehicle(id)` replaces the cavalry-only check, so the truck gets the tank locomotion (wheel spin, hull rock, slope tilt).
- **Volley**: `src/presentation/rocket_volley.gd` (pure arc/timing math + the effect node, view-local RNG for landing scatter). `BattleController` annotates its queued copy of an artillery `unit_attacked` event with `view_duration` and `view_fx` (decided once at queue time, see ARCHITECTURE "View-only annotations"); `EventQueue.base_duration` honours `view_duration`, so the queue and burst speed wait for the salvo. Sequence: turn towards the target (0.2 s), 6 rockets 0.08 s apart, `play_hit` at the last impact. Works for counterattacks and AI attacks too.
- **Range overlay**: `MapView.show_attack_range` – amber outline of the range boundary (`OverlayGeometry.boundary_edges` / `edge_ribbons`) plus a faint tint. Shown for the selected unit with range ≥ 2, or for the hovered unit (own or enemy) when nothing is selected; hidden during event playback; hover is re-picked after playback.
- **Tests**: `test_rocket_artillery.gd`, `test_scenario.gd`, `tiles_in_range` in `test_attack.gd`, AI tests (fixture ranged unit, tie-break, real artillery backing off), `test_rocket_volley.gd`, boundary edges in `test_overlay_geometry.gd`, duration annotation in `test_event_queue.gd`, artillery model in `test_unit_models.gd`.
- **Limitations / unverified**: the agent saw the truck and the range outline only in static screenshots; the salvo in motion has not been seen. Timings, apex heights and proportions are first guesses (constants at the top of `rocket_volley.gd` and `unit_models.gd`). Rocket noses stay in the tubes after firing. Artillery still counters at distance 1 (no minimum range – out of scope).

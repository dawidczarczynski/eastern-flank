# TASK-011: Ranged unit (archer)

- **Status**: ready
- **Layers**: core / ai / presentation (+ data)
- **Depends on**: **TASK-010** (counterattack – the archer's advantage is that melee units can't hit back at range 2). Soft: TASK-009 (`valid_targets` already handles range).

## Goal

A third unit type with a distinct role: a fragile damage dealer that attacks from 2 hexes away without taking counter damage, which must be protected by infantry. Also moves the starting army setup from the view into core, so replays (TASK-005) and AI-vs-AI simulations (TASK-012) can build the same battle headless.

## Acceptance criteria (testable)

- [ ] New `data/units/archer.tres` (proposed balance, to be tuned with TASK-012): `id = &"archer"`, `display_name = "Archer"`, `max_hp = 6`, `move_points = 3`, `attack = 5`, `defense = 1`, `attack_range = 2`. Test loads the file and checks all seven values.
- [ ] Combat numbers with the real data files on plains (tests in `tests/unit/test_archer.gd`):
  - archer attacks infantry at distance 2 → infantry **10 → 8**, no counter event, archer stays **6**.
  - archer attacks infantry at distance 1 → infantry **8**, counter `max(1, 4 − 1) = 3` → archer **3**.
  - cavalry attacks archer (distance 1) → archer **6 → 2**; archer counters (its range 2 covers distance 1) `max(1, 5 − 2) = 3` → cavalry **8 → 5**.
  - archer attacks archer at distance 2 → target **6 → 2**, counter `4` → attacker **2** (both have range 2).
  - archer attacks at distance 3 → rejected with `out_of_range`.
- [ ] Starting setup moved to core: `Scenario.default_battle(seed_value: int) -> GameState` in `src/core/scenario.gd` (pure; preloads the unit `.tres` files). It generates a 12×10 map with `MapGenerator.generate` from a separate `RandomNumberGenerator` seeded with `seed_value`, creates `GameState(grid, 2, seed_value)`, forces every spawn tile to PLAINS and adds units in this order (offset `(col, row)` → `MapGenerator.offset_to_axial`), so ids are 1–8:
  - player 0: infantry (1, 3), cavalry (1, 5), infantry (1, 7), **archer (0, 5)**;
  - player 1: infantry (10, 2), cavalry (10, 4), infantry (10, 6), **archer (11, 4)**.
- [ ] Tests for `Scenario`: 8 units, 4 per player, exactly one archer per player, all units on PLAINS tiles, no two units on the same tile; two calls with seed `12345` give identical terrain on every coordinate and identical unit lists; terrain for seed `12345` equals what `MapGenerator.generate(12, 10, rng seeded 12345)` produces (same map as before this task, apart from spawn tiles).
- [ ] `BattleController` builds its state with `Scenario.default_battle(MAP_SEED)`; the spawn list and `INFANTRY`/`CAVALRY` preloads are removed from presentation.
- [ ] AI positioning for ranged units: when choosing a destination, `AiPlayer` picks the reachable tile whose distance `d` to the nearest enemy minimises `|d − attack_range|`; ties prefer `d ≤ attack_range`, then staying on the current tile, then the existing iteration order. For melee units (range 1) behaviour is unchanged – all existing `test_ai_player.gd` tests pass.
  - Test: AI archer at `(0,0)`, single enemy `Fixtures.fighter(4, 3)` at `(4,0)`, `Fixtures.plains_grid(5)` → after `take_turn` the archer is at distance **2** from the enemy, the enemy has **8** HP and the archer still has **6** (no counter).
  - Test: AI archer already at distance 2 from the enemy doesn't move (no `unit_moved` event) and attacks.
- [ ] View: archers are visually distinguishable from infantry/cavalry (e.g. a thinner/shorter capsule or a small marker on top – keep it procedural, chosen by `definition.id`, no rules in the view).
- [ ] GDD units table: Archer row marked as implemented.

## Playtest (for the human)

1. `tools/run.sh` – each side has 4 units; the archer stands behind the cavalry and looks different from the other units.
2. Select your archer – movement works as for infantry (3 points).
3. Attack an enemy two hexes away – it loses HP and your archer is not hit back.
4. Walk the archer next to an enemy and attack – this time the enemy counterattacks.
5. During AI turns, the AI archer stays at two hexes from your units when it can and shoots.

## Out of scope

- Line of sight / obstacles blocking shots, minimum range, terrain affecting range (e.g. hills +1).
- Separate melee/ranged attack values (Wesnoth-style weapons).
- 3D models (procedural primitives only).
- Moving the scenario definition itself to a `.tres` resource (follow-up when there is more than one battle).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

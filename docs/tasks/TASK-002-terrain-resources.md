# TASK-002: Terrain types as `.tres` resources with a defense bonus

- **Status**: ready
- **Layers**: core / presentation (+ data)
- **Depends on**: TASK-001. TASK-010 (counterattack) will reuse the damage function introduced here.
- **Model**: sonnet

## Goal

Terrain becomes a tactical choice: standing in a forest or on a hill makes a unit harder to hurt. Terrain numbers move out of code (`src/core/terrain.gd`, `MapView` constants) into data files that the designer can tune.

## Design decisions

- **Visual properties live in the same resource**, in an `@export_group("Presentation")` (`color`, `height`). Reason: one file per terrain type is the single place to add/tune a terrain; `Color`/`float` add no dependency on nodes, so `src/core` stays pure. Rule: **core never reads the presentation group**. Record this as an ADR (`docs/adr/0002-terrain-definitions.md`).
- `Terrain.Type` enum stays as the key stored in `HexGrid` (minimal change for `MapGenerator` and tests); each enum value maps to one `.tres`.
- Defense bonus is a flat number added to the defender's defense (consistent with the deterministic TASK-001 formula). **[ASSUMPTION]** pending the randomness open question in the GDD.

## Acceptance criteria (testable)

- [ ] New resource class `TerrainDefinition` (`src/core/data/terrain_definition.gd`, `extends Resource`): `id: StringName`, `display_name: String`, `move_cost: int`, `impassable: bool`, `defense_bonus: int`; presentation group: `color: Color`, `height: float`.
- [ ] Data files in `data/terrain/` (proposed numbers; colors/heights copied from the current `MapView` constants so the map looks the same):

  | file | id | move_cost | impassable | defense_bonus | color | height |
  |---|---|---|---|---|---|---|
  | plains.tres | `plains` | 1 | false | 0 | (0.56, 0.71, 0.36) | 0.2 |
  | forest.tres | `forest` | 2 | false | 1 | (0.24, 0.45, 0.22) | 0.25 |
  | hills.tres | `hills` | 2 | false | 2 | (0.6, 0.53, 0.38) | 0.45 |
  | water.tres | `water` | 1 | **true** | 0 | (0.2, 0.42, 0.7) | 0.08 |

- [ ] `static func Terrain.definition(t: Terrain.Type) -> TerrainDefinition` returns the preloaded resource for every enum value. `Terrain.move_cost(t)` returns `Terrain.IMPASSABLE` when `impassable`, otherwise `definition.move_cost` (no hardcoded numbers left in `terrain.gd`).
- [ ] `HexGrid.defense_bonus(c: Vector2i) -> int` – the bonus of the tile's terrain; `0` for coordinates off the map.
- [ ] Single damage function `static func AttackCommand.compute_damage(state: GameState, attacker: Unit, defender: Unit) -> int` = `max(1, attacker.attack − (defender.defense + state.grid.defense_bonus(defender.coord)))`; `apply()` uses it. The attacker's own tile does not matter.
- [ ] Tests (`tests/unit/test_terrain.gd`, `tests/unit/test_attack.gd`):
  - Loaded data: forest `defense_bonus == 1`, hills `== 2`, plains `== 0`; water `impassable == true`; `HexGrid.move_cost` is 1 / 2 / 2 / `IMPASSABLE` for plains / forest / hills / water (existing movement tests unchanged).
  - Attacker `Fixtures.fighter(4, 2)` vs defender with defense 2: defender on plains → **2** damage, on forest → **1**, on hills → **1** (`max(1, 4 − 4)`).
  - Attacker `Fixtures.fighter(7, 2)` vs defense 2: plains **5**, forest **4**, hills **3**.
  - Attacker standing on hills, defender on plains, attack 7 vs defense 2 → **5** (attacker's tile ignored).
  - `defense_bonus` of an off-map coordinate → `0`.
- [ ] `MapView` reads `color` and `height` from `Terrain.definition(t)`; `TERRAIN_COLORS` and `TERRAIN_HEIGHTS` constants are removed. Trees are still drawn on forest tiles.
- [ ] GDD "Map" and "Combat" sections updated from "planned" to implemented; ADR added.

## Playtest (for the human)

1. `tools/run.sh` – the map looks exactly as before (same colors, heights, trees on forests).
2. Attack an enemy standing on plains with cavalry (attack 5 vs infantry defense 3): it loses 2 HP.
3. Attack an infantry standing in a forest with cavalry: it loses only 1 HP; on a hill: also 1 HP.
4. Edit `data/terrain/forest.tres` (e.g. `color`) in the editor and run again – the change is visible without touching code.

## Out of scope

- Data-driven terrain list without the enum (adding a terrain still needs an enum value).
- Showing the terrain/bonus in the UI (follow-up for TASK-003), AI preferring defensive terrain, per-unit-type terrain modifiers (Wesnoth-style).
- Changing the map generator's terrain distribution.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

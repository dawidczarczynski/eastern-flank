# TASK-022: Unit movement along the path with turning

- **Status**: ready
- **Layers**: core (path in the `unit_moved` event) / presentation (pure helpers tested in `tests/unit/`)
- **Depends on**: **TASK-008** (event queue – movement duration now depends on the path length), TASK-016b (ground height), TASK-019 (models with a facing). Reference: `docs/design/game_screen.scene.js` lines 475–480 and 616–625.

## Goal

A moving unit walks tile by tile along the route the player saw in the preview, turning to face where it is going, instead of sliding in a straight line through forests and over hills.

## Design values

- **0.26 s per tile**, linear interpolation between consecutive tile centres (no easing) in XZ; `y = ground_height(x, z)` sampled every frame so the unit follows the terrain.
- Turning: target yaw `atan2(−dz, dx)` of the current segment (models face +X at yaw 0, TASK-019); every frame `yaw += wrap(target − yaw) · min(1, dt · 14)` with `wrap` to `(−π, π]` (shortest arc). The unit keeps its last facing after arriving.
- The unit's ring/fill marker is hidden while moving and shown at the destination when the move ends (label follows the unit all the time).

## Acceptance criteria (testable)

- [ ] Core: `unit_moved` gets a `path: Array[Vector2i]` field – `grid.path_to(from, to, moves_left_before, occupied)` computed in `MoveUnitCommand.apply` **before** the state changes; excludes `from`, ends with `to`. `docs/ARCHITECTURE.md` event table updated.
- [ ] Core tests (`tests/unit/test_commands.gd` or a new file), `Fixtures.plains_grid(2)`:
  - move `(0,0) → (2,0)` → `path == [(1,0), (2,0)]`;
  - with `(1,0)` FOREST, move `(0,0) → (1,1)` with 3 moves → `path == [(0,1), (1,1)]`;
  - for every move: consecutive tiles adjacent, `path.back() == to`, and the summed `move_cost` over `path` == `moves_left` before − after.
- [ ] `EventQueue.base_duration` (TASK-008): `unit_moved` with a `path` → **0.26 × path.size()**; without `path` → 0.25 (old events / tests unchanged). Tests: path of 3 tiles → 0.78; existing `test_event_queue.gd` cases still pass.
- [ ] Pure helper `src/presentation/move_animation.gd` (`class_name MoveAnimation`, static): `facing_yaw(from: Vector3, to: Vector3) -> float`, `turn_towards(current: float, target: float, dt: float, rate := 14.0) -> float`, `sample(points: PackedVector3Array, elapsed: float, seconds_per_tile := 0.26) -> Vector3` (XZ position along the polyline; clamps to the last point). Tests `tests/unit/test_move_animation.gd` (tolerance 0.001):
  - `facing_yaw` east `(1,0,0)` → 0; north `(0,0,−1)` → `π/2`; south → `−π/2`; west → `±π`.
  - `turn_towards(3.0, −3.0, 1.0)` == `−3.0` wrapped equivalent (`3.0 + 0.283…`, i.e. it turns through `π`, not back through 0); `turn_towards(0, 1, 0.05)` == 0.7; `turn_towards(0, 1, 1.0)` == 1.
  - `sample([(0,0,0), (1,0,0), (1,0,2)], 0.13)` → `(0.5, 0, 0)`; at 0.39 → `(1, 0, 1)`; at 10 → `(1, 0, 2)`; single point → that point.
- [ ] `UnitView.move_along(world_points: PackedVector3Array, surface: TerrainSurface)` animates with `MoveAnimation` (in `_process` or a tween driving `elapsed`); the duration equals `EventQueue.base_duration` of the event, and it respects the TASK-008 burst speed scale. `BattleController` passes the tile centres of `[from] + path`.
- [ ] Handlers still use only event fields (`from`, `path`, `to`) – never `Unit.coord` from the state (TASK-008 rule).
- [ ] AI units move along their paths too (same event).
- [ ] Agent visual check: the default screenshot is static – verify only that units still stand at their tiles with the expected facing; motion is checked by the human.

## Playtest (for the human)

1. Move infantry 3 tiles around a forest – it walks tile by tile along the dotted route (about a quarter second per tile), not straight through the trees.
2. The unit turns smoothly to face each new direction; at the end it keeps facing the way it walked.
3. Moving up/down a hill, the unit follows the ground (no floating, no clipping into the slope).
4. End the turn – AI units also walk their routes one after another; a long AI turn still finishes in about 3 s (burst speed-up from TASK-008).
5. Attack right after moving – the hit plays only after the unit arrives.

## Out of scope

- Walk cycles / soldier animation, vehicle track animation, dust effects.
- Camera following the moving unit.
- Turning towards the target when attacking (follow-up, same `facing_yaw`).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

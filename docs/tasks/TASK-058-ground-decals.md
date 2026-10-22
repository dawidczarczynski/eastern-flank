# TASK-058: Ground decals from events – track marks, shell craters, scorched ground

- **Status**: ready
- **Layers**: presentation (pure `GroundMarks` planner, procedural `DecalTextures`, a `GroundMarksView` reacting to events), tests
- **Depends on**: soft **TASK-050** (`decals_max`), soft **TASK-055** (judged on the new ground), soft **TASK-065** (shares the scorch decal under wrecks)
- **Model**: sonnet

## Goal

The battlefield remembers what happened: vehicles leave tracks behind them, artillery strikes leave craters, and destroyed units leave scorched earth. Purely visual – the map rules don't change.

## Design

- **Presentation-only reaction to events** (`GameSimulation.event_emitted`, played through the event queue at the moment the matching animation plays): no state, no rules; the view reads the unit's definition (`unit_class`) and positions from the existing views.
  - `unit_moved`: for `unit_class == &"tank"` **track marks** (two parallel tread strips), for `&"mlrs"` **tyre marks** (two narrower, smoother strips), for `&"infantry"` nothing. One decal per path segment (tile centre → next tile centre), oriented along the segment, length = segment length, width 0.42 (tank) / 0.34 (mlrs) world units at the `current` scale preset – the code multiplies them by `VisualScale.unit_model_scale / 1.3` (TASK-059), so the marks follow the chosen unit size, alpha 0.55. Spawned progressively as the unit passes (at segment end), not all at once.
  - `unit_attacked` where the attacker's `attack_range ≥ 2` and the hex distance between attacker and target ≥ 2 (indirect/rocket fire) and `counter == false`: **2–3 craters** (count from a view-local hash of the event index) within 0.35 of the target tile centre, radius 0.10–0.16, plus one scorch blob radius 0.25. Direct fire leaves nothing.
  - `unit_died`: one **scorch** blob radius 0.35 at the unit's tile.
- **Pool**: at most `decals_max` decals (TASK-050: 16 LOW, 64 HIGH); when full, the oldest **track** decal is removed first, then the oldest crater; scorch marks under living wrecks are removed last.
- **Placement**: `Decal` nodes, box height 0.6 centred on the ground height, `cull_mask` so decals project **only onto the terrain layer** (put terrain on its own visual layer; units, foliage and grass not affected). Slight random yaw for craters/scorch. Fade in over 0.3 s.
- **Textures** – pure `DecalTextures` (static, cached): `tread(size)` (repeating chevron/grouser pattern along v, dark brown `#3a2f22`, soft edges), `tyre(size)` (fine lines), `crater(size)` (dark centre, lighter raised rim ring, soil splatter), `scorch(size)` (black-brown blob, noisy edge). Albedo with alpha; normal maps optional (crater rim normal is a plus). If TASK-053 allows textures, a CC0 decal may replace the procedural one (credited).
- **Determinism**: view-local hash only (never `GameState.rng`), so replays look the same.

## Acceptance criteria (testable)

- [ ] `tests/unit/test_ground_marks.gd` (pure planner):
  - `track_segments(path_world, &"tank")` for a 3-tile path (4 centres incl. start) returns 3 segments; each has its midpoint at the segment midpoint, yaw along the segment (±0.01 rad), length = segment length, width 0.42; `&"mlrs"` width 0.34; `&"infantry"` → empty;
  - `craters(event_index, target_center, attacker_range, distance, counter)` → 2–3 craters within 0.35 of the centre for `(range 5, distance 3, counter false)`; empty for `distance 1`, for `range 1` and for `counter true`; deterministic for the same event index;
  - `Pool`: with max 4, adding 3 tracks + 2 craters evicts the oldest track; scorch marks are evicted last.
- [ ] `DecalTextures`: each texture has the requested size, alpha 0 on the border pixels (no hard box edge), deterministic.
- [ ] Decal nodes' `cull_mask` excludes the unit, foliage and grass layers (test on the created nodes).
- [ ] With `decals_max = 0` no decals are created.
- [ ] Agent visual check (Windows build): a scripted move + rocket attack in the screenshot hook (or a debug env var) shows tracks behind the tank, craters near the target; decals do not appear on unit models or trees.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it (the default shot has no events – it should be unchanged), commit only if changed.

## Playtest (for the human)

1. Move a tank across plains: dark tread marks appear behind it, following its path; the rocket artillery truck leaves thinner tyre marks; infantry leaves none.
2. Fire the rocket artillery at a distant enemy: a few craters and a scorched patch appear around the target as the hit plays.
3. Destroy a unit: a scorched patch remains on its tile.
4. Play many turns: the oldest tracks disappear first; nothing ever covers a unit or a tree.
5. Marks on slopes follow the ground, no floating rectangles.

## Player manual

Short note in section 10 (Screen): "Tracks, craters and scorch marks on the ground are only decoration – they don't change movement or defense."

## Out of scope

- Terrain deformation, persistent marks across saves/replays (they are re-created by replaying events), footprints, blood.

## Implementation notes

_Filled in by the agent when done._

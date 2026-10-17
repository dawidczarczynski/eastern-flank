# TASK-019: Unit models from primitives, faction markers, unit labels

- **Status**: ready
- **Layers**: presentation (pure helpers tested in `tests/unit/`) + data (`short_name` in unit definitions)
- **Depends on**: **TASK-016b** (units stand on the surface), **TASK-017** (`OverlayGeometry` for the markers), TASK-014 (fonts/palette). Soft: TASK-008 (removes the hit `delay`; do 008 first so the new hit animation is written once), TASK-009 (`valid_targets` for the "done" state), TASK-023 (abbreviations through `tr()`). Reference: `docs/design/game_screen.scene.js` lines 161–215 (`makeTank`, `soldier`, `makeInf`), 398–428 (markers, labels), 626–627 (label position/opacity).
- **Model**: sonnet

## Goal

Units look like small miniatures instead of capsules: a squad of five soldiers for infantry and a compact armoured vehicle for the fast unit, standing on a faction-coloured hex ring, with a compact label (colour tab, abbreviation, HP bar) floating above them.

## Known bug to check (from the first agent screenshot)

The first `tools/screenshot.sh` image (`.screenshots/battle.png`) shows the current capsule units **lying on their side** instead of standing upright (`UnitView.setup` builds a `CapsuleMesh` in a `MeshInstance3D`). Not fixed yet on purpose – this task replaces the capsule, but the agent must **find the cause** (mesh orientation, a parent node's basis, the camera, or a misleading camera angle) so the new models don't inherit it, and describe it in the implementation notes.

## Design decisions

- **Infantry** = port of `makeInf` (5 soldiers, two kneeling, one with a heavier weapon).
- **Cavalry** = port of `makeTank` as an **interim** model: the tank is the mock-up's fast unit (5 move, same as our cavalry). The name stays "Cavalry" until the setting/roster question in the GDD is decided. **[ASSUMPTION – human to confirm]**
- Faction body colours: player 0 uniform `#4f5934`, vest `#3d4529`; player 1 uniform `#7a7354`, vest `#5d5840`; accent = `UiPalette.FACTION[owner]`. Shared: skin `#b98d6c`, soldier dark `#1f201c` (roughness 0.7, metal 0.3), tank dark `#22231f` (0.95/0.05), tank metal `#3c3e38` (0.55/0.45), tank body roughness 0.8 / metal 0.15, uniforms 0.9 / 0.
- three.js → Godot primitives: `BoxGeometry(w,h,d)` → `BoxMesh.size = (w,h,d)`; `CylinderGeometry(rt, rb, h, seg)` → `CylinderMesh(top_radius, bottom_radius, height, radial_segments)`; half-sphere helmet → `SphereMesh.is_hemisphere`; the extruded turret outline → a prism `ArrayMesh` from the 8-point polygon, depth 0.085 (bevel skipped). Positions/rotations copied 1:1 (both engines are right-handed, Y up). Model scale: soldier ×1.5 inside the squad, whole model ×1.3.
- **Facing**: models are built facing **+X**; `yaw = 0` for player 0 (spawns west, faces east), `PI` for player 1. TASK-022 rotates units while moving.
- Meshes and materials are created once per (unit type, owner) and shared between instances. All parts cast shadows.
- **Done state** (dims ring and label): a unit is "done" when `moves_left == 0` and (`has_attacked` or it has no valid attack target). Shared pure helper so TASK-020 counts "ready units" with the same rule.

## Acceptance criteria (testable)

- [ ] `UnitDefinition` gets `@export var short_name: String`; `infantry.tres` = `"INF"`, `cavalry.tres` = `"CAV"` (Polish via CSV: `PIECH`, `KAW`). A test loads both files and checks the values.
- [ ] Pure helper `src/presentation/unit_status.gd` (`class_name UnitStatus`, static): `is_done(state: GameState, unit: Unit) -> bool` (rule above; uses `AttackCommand.valid_targets` if TASK-009 is done, otherwise only `has_attacked`), `hp_fill_width(hp: int, max_hp: int, width: int) -> int` (`roundi(width · clamp(hp / max_hp, 0, 1))`). Tests `tests/unit/test_unit_status.gd`:
  - fresh unit → not done; `moves_left = 0, has_attacked = true` → done; `moves_left = 0, has_attacked = false`, enemy adjacent → not done; same with no enemy in range → done (only if TASK-009 is done); `moves_left = 1, has_attacked = true` → not done.
  - `hp_fill_width(10, 10, 26) == 26`, `(5, 10, 26) == 13`, `(1, 8, 26) == 3`, `(0, 10, 26) == 0`, `(12, 10, 26) == 26`.
- [ ] `src/presentation/unit_models.gd` (`class_name UnitModels`): `static func build(definition_id: StringName, owner_id: int) -> Node3D`; infantry → 5 soldiers at `(0.13, 0)`, `(−0.02, 0.15)` kneeling + heavy weapon, `(−0.03, −0.15)`, `(−0.18, 0.06)`, `(−0.15, −0.12)` kneeling (XZ), each with a small fixed yaw jitter (`(hash(i, 3, 1) − 0.5)·0.6` via `TerrainNoise.hash` – deterministic); cavalry → tank; unknown id → a fallback box with a `push_warning`.
- [ ] Marker under each unit (built with `OverlayGeometry`, draped on the surface): ring radii **0.6–0.72** (selected: **0.6–0.8**), lift 0.035, faction colour, alpha **0.95** (**0.45** when the unit is done on its owner's turn); fill patch scale **0.6**, lift 0.03, alpha **0.1** / hovered **0.2** / selected **0.32**. The old `scale × 1.25` selection effect is removed.
- [ ] Unit label (replaces the HP `Label3D`): a `Control` in the HUD (under the other HUD panels, `MOUSE_FILTER_IGNORE`) positioned every frame at `camera.unproject_position(unit_position + (0, h, 0))` with `h = 0.5` (infantry) / `0.62` (cavalry), anchored bottom-centre; hidden when `camera.is_position_behind(...)`. Style: background `rgba(14,16,13,0.82)`, 1 px border `rgba(255,255,255,0.14)`, padding 2/5/2/2 px (top/right/bottom/left), 5 px gaps; faction tab 4×15 px; `short_name` in Mono SemiBold 9 px, colour `#ebe8df`, glyph spacing 1 px; HP bar 26×4 px, track `rgba(255,255,255,0.15)`, fill width `hp_fill_width(hp, max, 26)` in `UiPalette.hp_color`. Opacity **0.55** when the unit is done on its owner's turn, else 1.
- [ ] Hit reaction works with multi-mesh models: the model shakes ±0.12 sideways and flashes white through a shared `material_overlay` (unshaded white, alpha tweened 0 → 0.8 → 0) on all its meshes; the label's HP bar updates. Death: overlay goes to black alpha 0.6, model shrinks as before, marker and label are removed.
- [ ] Upright check: a test builds both models with `UnitModels.build` and asserts the combined AABB of their `MeshInstance3D`s is taller (Y) than 0.15 and its bottom is within 0.02 of `y = 0` (models stand on their origin, not lying/sunk).
- [ ] Agent visual check: take a screenshot with `tools/screenshot.sh` and compare with `docs/design/reference.png`: **units stand upright** (soldiers and the vehicle are vertical, wheels/tracks on the ground), blue-ringed units on the left face right, red-ringed on the right face left, labels show `INF`/`CAV` with full green HP bars and don't cover each other at the default zoom.

## Playtest (for the human)

1. `tools/run.sh` – your infantry is a group of five small soldiers, your cavalry a small armoured vehicle, all standing upright on blue hex rings; the enemy's are olive-tan on red rings, facing your side.
2. Labels above units: coloured tab, `INF`/`CAV`, a green bar. Hit an enemy – it flashes white, shakes, and the bar shrinks and turns yellow/red at low HP.
3. Select a unit – its ring gets thicker and the fill under it brighter; hovering a unit brightens its fill a little.
4. Use up a unit's move and attack – its ring and label fade to about half opacity until your next turn.
5. Kill a unit – it darkens and shrinks; its ring and label disappear.
6. Rotate the camera (Q/E or RMB drag) – labels stay above their units and disappear when the unit is behind the camera.

## Out of scope

- Walking animation along the path and turning towards travel direction (TASK-022).
- MLRS/artillery model, portraits (TASK-021 follow-up), unit names/designations, rank pips (GDD ideas).
- A dedicated cavalry (horse) model – pending the setting decision.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

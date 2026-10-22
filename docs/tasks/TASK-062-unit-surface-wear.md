# TASK-062: Unit surface v2 – bevelled part edges, edge wear, dust and streaks in the camo shader

- **Status**: ready (revised 2026-10-22: based on the model detail study – three vertex masks instead of one, paint from `docs/design/showcase/showcase_paint.gdshader.txt`; geometry primitives come from the rewritten TASK-030)
- **Layers**: presentation (`models/model_parts.gd`, `models/parts/vehicle_frame.gd`, `assets/shaders/camo.gdshader`, `unit_models.gd`), tests (`test_unit_model_contract.gd`, model part tests). Roles: **presentation-engineer** (shader, helpers), **unit-modeler** (re-render and check every model with `tools/render_unit.sh`).
- **Depends on**: **TASK-030** (mesh kit v2: chamfers and the RGB vertex-mask convention). Blocks TASK-067 and TASK-069 (they build on this paint). Soft: TASK-065 (adds `burnt` to the same shader – do this first).
- **Model**: sonnet

## Goal

Vehicles look like used steel, not freshly painted plastic boxes: edges catch the light, paint is worn on corners, cavities are darker, the lower hull is dusty and muddy, rain has left faint vertical streaks – different on every vehicle. Existing models get it without a rework.

## Current state

`ModelParts` / `VehicleFrame` build boxes and extrusions with flat normals and sharp edges, no vertex colours. `camo.gdshader` has three camo colours, `pattern_mode`, `dirt_color` + `dirt_height` (a mud band at the bottom), roughness/metallic and an `instance uniform part_origin`. The study's `showcase_paint.gdshader.txt` shows the target: hard-edged camo, wear on chamfers (`COLOR.r`), cavity darkening (`COLOR.g`), per-part tint (`COLOR.b`), dust on up-facing faces, streaks, mud, fade.

## Design

- **Chamfers in the existing helpers**: `ModelParts` box / prism / extrusion helpers and `VehicleFrame.slab` / `pair` / `profile` build through `MeshKit` (TASK-030) with a default chamfer of **0.004 model units** (≈ 4 cm), optional per call (`bevel := …`, 0 = sharp), and write the RGB masks. Lathes and drums write `r` on their rims. So all six models gain chamfers and masks without being remodelled. Triangle budget: ≤ **+60 %** per model and within ADR 0010 (40k per vehicle, cold build ≤ 500 ms) – check `Stats` from `tools/render_unit.sh`; reduce chamfer segments where a model would exceed it.
- **Camo shader** – port the study's paint into `camo.gdshader` (keep today's uniforms and `pattern_mode`; all view-only):
  - `wear_amount`, `wear_color`: chipped paint on `COLOR.r`, broken by fine object-space noise; lower roughness, a little metallic.
  - cavity darkening by `COLOR.g`; per-part tint by `COLOR.b` (`tint_amount`).
  - `dust_amount`, `dust_color`: up-facing surfaces (`normal.y > 0.6` in object space); `mud_color`, `mud_height`, `mud_amount`: the lower hull (replaces / extends `dirt_*`).
  - `streak_amount`: vertical streaks on vertical faces; `fade`: sun-faded paint.
  - Models without vertex colours (or helpers called with `bevel = 0`) render as today: mask defaults `r = 0, g = 1, b = 0.5`.
  - `instance uniform float wear_seed`: offsets the noises so every unit differs; set by `UnitModels` from the unit id (view-local hash).
- No per-faction values yet (FactionDefinition unchanged); defaults chosen so both factions' camo still read. Start from the study's defaults and tune on render sheets.

## Acceptance criteria (testable)

- [ ] `ModelParts` box with default bevel: mesh AABB equals the requested size (±0.0005); every normal is unit length; the mesh has `ARRAY_COLOR` with `r == 1` on ≥ 1 and `r == 0` on ≥ 1 vertex and `g`/`b` in [0, 1]; with `bevel = 0` the result equals today's box (vertex count and AABB).
- [ ] `camo.gdshader` declares `wear_amount`, `wear_color`, `tint_amount`, `dust_amount`, `dust_color`, `mud_color`, `mud_height`, `mud_amount`, `streak_amount`, `fade` and `instance uniform wear_seed` (`Shader.get_shader_uniform_list()`); defaults recorded in the notes.
- [ ] Two units with different ids get different `wear_seed` values; the same id always the same value.
- [ ] `test_unit_model_contract.gd` passes for every model (budgets incl. build time); triangle counts and cold build times recorded before/after in the notes (≤ +60 %).
- [ ] unit-modeler check: `tools/render_unit.sh <id>` for every model in `src/presentation/models/` – sheets read (paths in the notes): chamfered edges visible, worn edges lighter, cavities darker, dusty lower hull; compare with `docs/design/showcase/m1a2_cut_hero.jpg`.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. Zoom in on a tank: edges are rounded and catch highlights; corners show worn paint; the lower hull and wheels are dusty/muddy; faint streaks on the sides.
2. Compare two tanks of the same type: their dirt and wear patterns differ.
3. Rotate the camera: no flickering noise patterns, no shimmering on edges.
4. Camouflage patterns of both factions are still recognisable.
5. Frame rate with all units on screen unchanged.

## Player manual

None (presentation only).

## Out of scope

- Markings and numbers (TASK-063), damage states/burnt wrecks (TASK-065), per-faction weathering presets.

## Implementation notes

_Filled in by the agent when done._

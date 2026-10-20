# TASK-062: Unit surface v2 – bevelled part edges, edge wear, dust and streaks in the camo shader

- **Status**: ready
- **Layers**: presentation (`models/model_parts.gd`, `assets/shaders/camo.gdshader`, `unit_models.gd`), tests (`test_unit_model_contract.gd`, model part tests). Roles: **presentation-engineer** (shader, `ModelParts`), **unit-modeler** (re-render and check every model with `tools/render_unit.sh`).
- **Depends on**: **TASK-030** (`MeshKit.rounded_box` / bevelled extrusion), soft TASK-031 … TASK-033 (new detailed models get it for free)
- **Model**: sonnet

## Goal

Vehicles look like used steel, not freshly painted plastic boxes: edges catch the light, paint is worn on corners, the lower hull is dusty and muddy, rain has left faint vertical streaks – different on every vehicle.

## Current state

`ModelParts` builds boxes and extrusions with flat normals and sharp edges. `camo.gdshader` has three camo colours, `pattern_mode`, `dirt_color` + `dirt_height` (a mud band at the bottom), roughness/metallic and an `instance uniform part_origin`.

## Design

- **Bevels**: `ModelParts` box/extrusion helpers use `MeshKit.rounded_box` / `extrude_profile` with a bevel of **0.004 model units** (≈ 4 cm) by default, optional per call (`bevel := …`, 0 = sharp); 2 bevel segments. Bevel vertices are flagged in **`COLOR.r`** (1 on bevel/edge vertices, 0 on faces) – the edge mask the shader uses for wear. Triangle budget: ≤ **+60 %** per model (check `Stats` from `tools/render_unit.sh`).
- **Camo shader** additions (uniforms with defaults; all view-only):
  - `wear_amount` (0.35): on edge-mask areas, broken by a fine world/object-space noise, blend albedo toward `wear_color` (`#5d5a52`, worn primer/steel), lower roughness by 0.25, metallic +0.3.
  - `dust_amount` (0.4): on up-facing surfaces (`normal.y > 0.6` in object space) and the lower hull (existing `dirt_height` band, extended with a soft noisy gradient up to 2× `dirt_height`), blend toward `dust_color` (`#8a7b62`), roughness → 0.95.
  - `streak_amount` (0.25): on vertical faces, vertical streaks = noise stretched ×12 along object y, darkening albedo by ≤ 15 %.
  - `instance uniform float wear_seed`: offsets the noises so every unit differs; set by `UnitModels` from the unit id (view-local hash).
- No per-faction values yet (FactionDefinition unchanged); defaults chosen so both factions' camo still read.

## Acceptance criteria (testable)

- [ ] `ModelParts` box with default bevel: mesh AABB equals the requested size (±0.0005); every normal is unit length; the mesh has `ARRAY_COLOR` with `r == 1` on ≥ 1 and `r == 0` on ≥ 1 vertex; with `bevel = 0` the result equals today's box (vertex count and AABB).
- [ ] `camo.gdshader` declares `wear_amount`, `wear_color`, `dust_amount`, `dust_color`, `streak_amount` and `instance uniform wear_seed` (`Shader.get_shader_uniform_list()`); defaults as above.
- [ ] Two units with different ids get different `wear_seed` values; the same id always the same value.
- [ ] `test_unit_model_contract.gd` passes for every model; triangle counts recorded before/after in the notes (≤ +60 %).
- [ ] unit-modeler check: `tools/render_unit.sh <id>` for every model in `src/presentation/models/` – sheets read (paths in the notes): rounded edges visible, worn edges lighter, dusty lower hull.
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

# TASK-062: Unit surface v2 – bevelled part edges, edge wear, dust and streaks in the camo shader

- **Status**: done (revised 2026-10-22: based on the model detail study – three vertex masks instead of one, paint from `docs/design/showcase/showcase_paint.gdshader.txt`; geometry primitives come from the rewritten TASK-030)
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

- [x] `ModelParts` box with default bevel: mesh AABB equals the requested size (±0.0005); every normal is unit length; the mesh has `ARRAY_COLOR` with `r == 1` on ≥ 1 and `r == 0` on ≥ 1 vertex and `g`/`b` in [0, 1]; with `bevel = 0` the result equals today's box (vertex count and AABB).
- [x] `camo.gdshader` declares `wear_amount`, `wear_color`, `tint_amount`, `dust_amount`, `dust_color`, `mud_color`, `mud_height`, `mud_amount`, `streak_amount`, `fade` and `instance uniform wear_seed` (`Shader.get_shader_uniform_list()`); defaults recorded in the notes.
- [x] Two units with different ids get different `wear_seed` values; the same id always the same value.
- [x] `test_unit_model_contract.gd` passes for every model (budgets incl. build time); triangle counts and cold build times recorded before/after in the notes (≤ +60 %).
- [x] unit-modeler check: `tools/render_unit.sh <id>` for every model in `src/presentation/models/` – sheets read (paths in the notes): chamfered edges visible, worn edges lighter, cavities darker, dusty lower hull; compare with `docs/design/showcase/m1a2_cut_hero.jpg`.
- [x] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

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

Implemented 2026-10-23 (presentation-engineer).

- **Helpers** (`models/model_parts.gd`, `parts/vehicle_frame.gd`): `box_mesh`, `cyl_mesh`, `prism_mesh`, `loft_mesh`, `lathe_mesh` now build through `MeshKit` (cbox / lathe / plate / loft / stack, indexed commit via the new `MeshKit.commit(indexed)`) and write the ADR 0012 vertex masks; `sphere_mesh`, `band_mesh`, `turret_mesh` write the plain mask `(0, 1, 0.5)`. `bevel := ModelParts.DEFAULT_BEVEL` (0.004 model units) is an optional last argument everywhere (`VehicleFrame.slab/pair/drum/profile/loft`); 0 = sharp (box: 24 vertices, same AABB as the old BoxMesh, `r = 0`). The bevel is limited to a fifth of the thinnest box side (a quarter of the depth/height for prisms and lofts, 40 % of the outline's inradius, a lathe corner's neighbouring segments) and becomes 0 below `MIN_BEVEL = 0.0015`, so small parts stay 12-triangle boxes (this is what keeps the triangle budget). Lathe corners over ~30 degrees get a chamfer (rims, `r = 1`). Mesh caches keep working (bevel is part of the key).
- **Merging**: `merged_mesh` still uses `SurfaceTool.append_from` (colours survive) and then writes the per-part tint seed into `b` (hash of the part's position), so every placed part has its own tint although the base meshes are shared.
- **Shader** `assets/shaders/camo.gdshader`: port of the study paint (hard-edged domain-warped camo with fwidth AA, wear on `COLOR.r`, cavities on `COLOR.g`, tint `COLOR.b`, dust on up-facing object-space normals, streaks, mud, fade, ground AO). Kept `color_a/b/c`, `pattern_scale`, `pattern_mode` (digital mode 1 unchanged, quantised cells), `digital_cells`, `base_roughness`, `metallic`, `part_origin`; `dirt_height` became `mud_height` (`dirt_color` -> `mud_color`). Every noise term fades to its mean once its cell is smaller than ~1 px and is skipped entirely then (no shimmer, cheaper with distance). Meshes without `ARRAY_COLOR` render white (r = 1, fully worn) - all helpers write colours, so nothing in the game is affected; custom meshes using this shader must write colours.
- **Defaults** (uniform = value): `wear_amount 0.7`, `wear_color (0.38, 0.36, 0.32)`, `tint_amount 0.1`, `dust_amount 0.5`, `dust_color (0.56, 0.51, 0.42)`, `mud_color (0.357, 0.290, 0.208)`, `mud_height` = preset `dirt` (0.12 vehicle, 0.11 truck, 0.03 uniform), `mud_amount 0.8`, `ground_ao_height 0.03`, `streak_amount 0.12`, `fade 0.15` (study: 0.22), `wear_seed 0` (instance). Study colours kept except `wear_color` (lighter so worn edges read as bare steel) and `fade`.
- **wear_seed**: `UnitModels.wear_seed(unit_id)` = `hash(str(id)) % 4096 / 4096 * 64`; `UnitModels.build(definition_id, owner_id, faction, unit_id = null)` applies it per unit **instance** (`UnitView` passes `unit.id`; without an id the definition id is used, e.g. portraits), through `ModelParts.cached(key, builder, wear_seed)` -> `_restore_camo` (set on the copies, prototypes still hold no instance-uniform slots). Only the weathering noises are offset; the camo pattern stays the same for a faction.
- **Triangles / cold build (ms, `tools/test.sh --verbose test_unit_model_contract`)**:

| model | tris before | tris after | change | build before | build after |
|---|---|---|---|---|---|
| m1a2_sepv3 | 14184 | 21460 | +51 % | 15.0 | 30.9 |
| t72b3 | 15544 | 20988 | +35 % | 20.9 | 38.4 |
| homar_k | 5328 | 6144 | +15 % | 4.9 | 14.5 |
| bm27_uragan | 7296 | 8552 | +17 % | 8.2 | 19.8 |
| pl_mech_infantry | 12880 | 15360 | +19 % | 14.6 | 30.4 |
| ru_motor_rifle | 14296 | 17068 | +19 % | 15.2 | 34.1 |

  (With the first, smaller `MIN_BEVEL` 0.0008 the wheeled launchers doubled, +104 %; hence the threshold.)
- **Sheets** (`tools/render_unit.sh`, `.screenshots/units/`): `before_<id>*.png` / `after_<id>*.png` for all six models (before = old helpers and shader); chamfered edges, lighter worn edges, dusty roofs and a darker lower hull are visible on the three-quarter views. Not seen: shimmer under camera rotation and the real FPS (software renderer) - see playtest.
- **Tests**: `tests/unit/test_surface_wear.gd` (box AABB / normals / masks, `bevel = 0` equals the old box, helper masks, merge keeps masks and varies tint, shader uniforms, `wear_seed`, per-unit seed on a built model); `test_unit_model_contract.gd` unchanged and green. `tools/check.sh` passes.
- `docs/images/gameplay.png` re-rendered with `tools/readme_screenshot.sh`; framing still fine.


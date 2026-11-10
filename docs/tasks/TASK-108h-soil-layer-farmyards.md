# TASK-108h: Real-terrain look v2 – `soil` ground layer and URBAN farmyards

- **Status**: ready
- **Layers**: presentation (`TerrainSplat`, `TerrainTextures`, `TerrainGround`, `assets/shaders/terrain.gdshader`) + assets (one CC0 ground set, `credits.json`) + docs (MANUAL)
- **Depends on**: TASK-108 (done) (split from TASK-108b, 2026-11-10)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Villages look like farmyards: gravel, bare soil and grass mixed. Needs a new ground layer 6 `soil` (ploughed / bare farm soil).

## Design

- CC0 PBR set (ambientCG / Poly Haven; albedo, normal_gl, roughness, ao, height; 1024² JPG like the others) at `assets/third_party/textures/ground/soil/`, manifest id `ground_soil` in `credits.json` (ADR 0011). No strong rows.
- `TerrainTextures.LAYERS` gets `"soil"` appended (0–5 unchanged); `SOURCE_METRES`, `TerrainGround.LAYER_TINTS` and the shader arrays grow to 7; `TerrainSplat.LAYER_COUNT` = 7, `SOIL := 6`. Splat channel `CUSTOM0.z` carries the soil weight (`.w` stays free); document in `TerrainGround.add_surface`.
- `TerrainSplat` URBAN base: gravel 0.40, soil 0.30, grass 0.30. All other terrain types: soil 0.
- Shader: skip layers below weight 0.004. LOW: same layers at 512².
- Budget: Suwałki ≤ +0.3 ms GPU, default battle ≤ +0.2 ms.

## Acceptance criteria

- [ ] `LAYER_COUNT` = 7; `LAYERS` ends with `"soil"`; set exists and is credited (`test_third_party_assets.gd`).
- [ ] `weights()` for every `Terrain.Type` returns 7 values ≥ 0 summing to 1 (± 1e-4); flat URBAN → gravel ≥ 0.35 and soil ≥ 0.25; other types: layer 6 exactly 0 and layers 0–5 equal to today's values.
- [ ] `TerrainGround.add_surface` stores soil in `CUSTOM0.z` (± 1e-6); layers 4–5 still in `.x` / `.y`.
- [ ] Screenshot of a village on `suwalki_battle` Read by the agent; before/after frame times in the notes.

## Playtest

1. `tools/run.sh --scenario=suwalki_battle`: villages read as farmyards (gravel + bare soil + grass). 2. Default battle unchanged. 3. `--quality=low` still shows it.

## Player manual

§10 "Screen": villages look like farmyards of gravel and soil.

## Implementation notes

_Filled in by the agent when done._

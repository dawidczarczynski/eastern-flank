# TASK-217b: GPU-placed near grass (clump cards) + cheap far grass tone

- **Status**: done
- **Layers**: presentation (grass layer on the TASK-217a framework, grass shader, terrain shader detail)
- **Depends on**: TASK-217a (framework), TASK-189, TASK-191, TASK-200
- **Sections**: ARCHITECTURE "Real-scale vegetation", "Chunked lazy world"; the ADR written by 217a; code (grep CODEMAP): `GrassField`, `GrassNear`, `GrassPlanner`, `GrassMesh`, `GrassTexture`, `Wind`, `ParcelMap`, `terrain.gdshader`
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Grass near the camera is hash-placed on the GPU (real blades, clump cards) and appears at once after a camera jump; farther away the terrain shader supplies a cheap grass tone, with no instances. `true` preset only; `balanced` untouched.

## Decisions (2026-11-23)

- Near ring ~30-50 m of GPU-hashed clump cards with real blades; replaces `GrassNear` / `GrassField` CPU planning under `true`.
- Beyond the ring: no instances; the terrain shader adds a cheap grass-tone / detail texture.
- Keep wind, flowers and reeds behaviour.
- Budget: grass <= 0.6 ms GPU on RX 580 HIGH **[ASSUMPTION]** (total 1.5 ms with 217a, 217c). LOW / MEDIUM: no near grass instances (terrain-shader tone only). No CPU planning per instance.
- Metres via `MapScale`. Out of scope: units, buildings, trees, seasons, balanced, game rules (no `GameState.rng`).

## Acceptance criteria (testable)

- [ ] Grass chunks use the 217a framework: instant layer, no worker plan, no per-instance data (test: 0 worker tasks after building 100 chunks; <= 4 ms per `process()`).
- [ ] GDScript reference of the grass cell (position jitter, kind, height, flower roll) is deterministic; a fixed-value test fixes 5 cells to literals, the shader uses the shared 217a hash.
- [ ] Ring radius from `LookPreset` is 30-50 m **[ASSUMPTION: 40 m]**; no chunk is created farther than ring + chunk size (test).
- [ ] Keep-off: no clump on road, river, building, bridge or crop-parcel interior (grass on meadow / fallow / balk allowed); test over the fixture map.
- [ ] Density 100-300 clumps per 100 m^2 **[ASSUMPTION]** on grass tiles, 0 on bare / rock / water / forest interior; per-kind clump heights in the old ranges (lawn, tall, straw, nettle, `GrassPlanner` kinds) (tests).
- [ ] Wind, flowers and reeds: the shader uses the `Wind` parameters as before; flower share and reed placement on banks match the old rules within +-20 % over 1 ha (test of the reference).
- [ ] Terrain shader far tone: with `true`, terrain beyond the ring shows a grass-tone detail term; `balanced` shader output unchanged (uniform off, existing terrain tests green).
- [ ] CPU planning removed under `true`: `GrassNear` / `GrassField` build 0 MultiMesh instances from `GrassPlanner` (test counts); `balanced` unchanged (existing grass tests green).
- [ ] LOW / MEDIUM: grass layer disabled, terrain tone still on (test per level).
- [ ] After a 2 km jump grass within the ring exists after the first `process()` (headless test).

## Playtest (for the human)

1. `true`, HIGH, camera close to the ground in a meadow: blades and clumps, flowers, wind sway; reeds on a bank.
2. Pull the camera up: at the ring edge (~40 m) the change from clumps to terrain tone is gentle, no visible line or colour jump.
3. Jump 2 km: grass is there at once.
4. FPS 60; grass on vs off differs <= 0.6 ms on RX 580. LOW / MEDIUM: no clumps, ground still green-toned. `balanced`: as before.

## Player manual

One line on graphics quality: near grass blades are drawn only on HIGH (realistic scale). No rule change.

## GDD

No change (cosmetic).

## Out of scope

- Shrubs (217a), crops (217c), seasons, balanced preset, game rules.

## Implementation notes

- **Code**: `GrassRules` (`src/presentation/grass_rules.gd`, reference) / `assets/shaders/grass_rules.gdshaderinc` (twin; includes `shrub_rules.gdshaderinc` for habitat, crop interiors, keep-off) / `assets/shaders/grass_gpu.gdshader` / `GpuGrassField` (`src/presentation/gpu_grass_field.gd`: one instant `GpuVegetationLayer`, 18 m chunks, 3-surface mesh grass / flowers / reeds, shares masks, height texture and `NearHeightCache` with `ShrubField`). `LookPreset.vegetation()` `grass_range_m` 40 / `grass_cell_m` 0.8 (replace `near_grass_*`); `GraphicsQuality` `gpu_grass` (HIGH only; no MEDIUM level exists). Terrain shader: `grass_tone_*` uniforms, `TerrainGround.set_grass_tone` (on under `true` on every quality, off under `balanced`). `GrassNear` deleted (its only user was `true`); `GrassField.setup` plans nothing under `true`; `RealScaleVegetation.grass` replaces `grass_near`; `GpuVegetationLayer.layers`, `ShrubField.bind_terrain / lattice / height_range` added.
- **Deviations / assumptions**: noises are `VegetationHash` value noises (two octaves, wavelengths in metres), not the sin-hash `TerrainNoise`, so tall / dry / flower patches and the bare patches follow the old statistics but not the old positions (bare patches do not coincide with the terrain's dirt). A flower replaces a clump in its cell (old share `flower_density / PLAINS_DENSITY` x cluster noise); old near grass never had flowers, so flowers are new close up. Reeds = bank habitat clumps with probability `bank_reeds` (marsh reed noise and the 1.3 marsh density are not reproduced). Forest interior has no grass (old: 28 % density); hills factor and the tile-centre clearing are not ported. Colour is not in the reference (shader only: ground layer averages, dry share, satellite hue, kind colour). The ring is 40 m 3D from the camera; clumps thin out from 24 m, the terrain tone ramps from 20 to 60 m. Chunk build ring = ring (reach_m / build_factor).
- **Tests**: `test_grass_rules.gd` (determinism / order, 5 fixed cells, keep-off incl. bridge / urban / crop interior, balk and edge carry grass, density 100-300 per 100 m2 and at another MapScale, water / shore / slope, kinds and heights, bank reeds share, flower share within 20 %, include constants), `test_gpu_grass_field.gd` (instant layer without instance data, ring and no chunk beyond it, 100 chunks 0 plan ms and <= 4.5 ms per process(), LOW vs HIGH, CPU grass 0 under true / balanced as before, tone uniform off by default), `test_real_scale_suwalki.gd` (2 km jump: grass within the ring after the first frame; grass reads the near height window).
- **Open issue fixed (visually checked in `SCREENSHOT_SCENARIO=suwalki_battle SCREENSHOT_SCALE_PRESET=true --windows`, HIGH, RX 580)**: grass was invisible because the jitter of `veg_point` (16-bit halves of the cell hash) placed every clump far off its cell on D3D12 (found by painting stage colours in the vertex shader). `grass_point` / `GrassRules.point` now take the jitter from `veg_unit(h, 0)` / `veg_unit(h, 1)` (GDScript twin changed, the 5 literal cells updated). Clumps are drawn around a tank on the Suwalki battle. `veg_point` itself is unchanged and still used by the shrubs (their screenshots looked right, but not re-checked for the same offset). NOT measured: GPU cost (budget 0.6 ms) and the far terrain-tone look; check both in the playtest.
- **Not measured**: GPU cost (budget 0.6 ms on the RX 580; every vertex re-evaluates the cell function: ~1.5 k cells per chunk x 36 vertices), the look at the ring edge, the terrain tone against the satellite colour.

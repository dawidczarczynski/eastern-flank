# TASK-217b: GPU-placed near grass (clump cards) + cheap far grass tone

- **Status**: blocked
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

_Filled in by the agent when done._

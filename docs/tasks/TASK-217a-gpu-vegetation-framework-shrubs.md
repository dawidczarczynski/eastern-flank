# TASK-217a: GPU vegetation framework (generalised from the forest) + GPU shrub layer

- **Status**: ready
- **Layers**: presentation (new shader include, layer base, shrub layer, masks) + docs (new ADR, ARCHITECTURE)
- **Depends on**: TASK-189, TASK-191, TASK-200, TASK-199b (all done); soft: TASK-108c (in progress – its riparian shrubs are migrated; if 108c is not done yet, migrate what exists then and leave a note in 108c)
- **Sections**: ARCHITECTURE "Real-scale vegetation", "Chunked lazy world"; ADR 0026, ADR 0027; look reference (TASK-190). Code (grep CODEMAP): `ForestFill`, `forest_hash.gdshaderinc`, `TreeImpostors`, `ChunkLayer`, `ForestMaskSource`, `ParcelMap`, `RiparianPlanner`, `ScatterChunks`, `TreeFeatures`, `FoliageChunks`, `LookPreset.vegetation()`, `GraphicsQuality`
- **Model**: opus
- **Tags**: battle-look

## Goal

Every bush and shrub of a real-scale map is placed on the GPU from a cell hash, exactly like the forest impostors, so the countryside has forest edges, hedges, bank scrub and heath juniper that appear the frame a chunk node exists, and the framework is reusable by grass (217b). `true` VisualScale preset only; `balanced` and its tests stay untouched.

## Decisions (2026-11-23)

- Split 217a framework + shrubs, 217b grass, 217c crops; 217b and 217c depend on 217a.
- Framework = ADR 0027 generalised: cell hash in the vertex shader, `instance_count` = cells of the chunk, no per-instance data, one GDScript reference + one GLSL hash with a fixed-value test, `instant` ChunkLayer, masks as textures.
- Shrubs grow at: forest edges and clearings, field edges + hedges + roadsides, river and marsh banks, scrub on wasteland / heath / meadow patches (noise-driven density). All sizes and distances in metres via `MapScale`.
- 4 kinds, each own colour + silhouette, chosen by habitat: low bush 0.5-1 m, hazel / blackthorn 1.5-3 m, juniper (heath) 0.8-1.5 m, willow (banks) 2-3 m.
- LOD: real mesh hash-placed below ~60 m; impostor quads (baked albedo + normal atlas path of TASK-191, sun-lit) from there to ~600 m; nothing farther (canopy shell / backdrop covers).
- Existing CPU shrubs migrate: `RiparianPlanner`, hedge / tree-feature shrubs (TASK-199b / 215b) where they exist, `ScatterChunks` bushes under `true`.
- Budget: shrubs <= 0.7 ms GPU on RX 580 HIGH **[ASSUMPTION]** (of 1.5 ms for 217a+b+c: grass 0.6, crops 0.2). LOW and MEDIUM: no shrubs beyond 150 m. No CPU planning per instance.
- Out of scope: units, buildings, trees, seasons, balanced preset, game rules (cosmetic, no `GameState.rng`).

## Acceptance criteria (testable)

Framework
- [ ] A shared shader include (`assets/shaders/vegetation_hash.gdshaderinc` **[ASSUMPTION]**, reusing / including `forest_hash.gdshaderinc` constants) and a GDScript reference class give identical 32-bit hash results; a test fixes the hash of 5 (seed, cell) pairs to literal values and checks the include text contains the same constants.
- [ ] A generic vegetation chunk layer (instant `ChunkLayer`, instances = cells of the chunk, no per-instance data) is built without any worker plan: a test builds 200 chunks and asserts zero worker tasks and <= 4 ms per `process()` call (`instant_budget_usec`).
- [ ] Masks (habitat, keep-off) are handed over as textures built once per map; a test checks size and texel scale (<= 4.5 m per texel) and that rebuilding twice gives identical bytes.
- [ ] The forest impostor layer still gives its previous fixed-value cells (existing TASK-189 tests unchanged and green).

Shrub rules (GDScript reference, headless)
- [ ] The reference gives the same cell result in 2 runs and for any chunk order (determinism); no `GameState.rng` use.
- [ ] No shrub centre on a road, river or bridge ribbon, building footprint, or inside a crop parcel interior (test over a fixture map with each).
- [ ] Shrubs on a parcel edge strip (<= 3 m from the boundary) are allowed; density there is >= 3x the parcel interior density (which is 0).
- [ ] Habitat density (shrubs per ha, test over 1 ha of each fixture habitat, tolerance +-25 %): forest edge band (<= 10 m inside / outside) 150-300 **[ASSUMPTION]**; hedge line 1 per 2 m of line; bank band 80-200; heath 40-120; open meadow 0-10; forest interior 0.
- [ ] Kind by habitat: banks -> willow only share >= 70 %; heath -> juniper share >= 60 %; hedges / forest edge -> hazel / blackthorn share >= 60 %; every placed shrub's height lies in its kind's range (0.5-1, 1.5-3, 0.8-1.5, 2-3 m).
- [ ] Heights come from `MapScale` metres: the same cell at two `MapScale` values has the same metre height (test).
- [ ] Noise-driven scrub: density over a heath patch varies (std dev of per-10 m-cell counts > 0).

LOD and quality
- [ ] LOD ranges are `LookPreset.vegetation()` values: mesh < 60 m, impostor 60-600 m, none beyond (test reads the values and the chunk layer radius).
- [ ] LOW / MEDIUM `GraphicsQuality`: shrub radius <= 150 m, shrub layer count of instances per chunk <= HIGH value (test per level); `balanced` preset builds no shrub layer (test).
- [ ] After a simulated 2 km camera jump every shrub chunk within 600 m exists after the first `process()` (headless test with the instant budget).

Migration
- [ ] Under `true`, `RiparianPlanner`, `ScatterChunks` bushes and hedge / tree-feature shrubs add 0 CPU-planned shrub instances (test counts MultiMesh instances of the old layers = 0 for shrubs); under `balanced` they are unchanged (existing tests green).
- [ ] No two shrubs of the migrated sources are doubled: the old and new layers never both draw (test: old layer disabled under `true`).

Docs
- [ ] New ADR in docs/adr/ ("GPU-placed vegetation layers", extends 0027) states the generic framework, the 4 shrub kinds' rules and the LOD split; ARCHITECTURE "Real-scale vegetation" updated; the new event/table rows if any.

## Playtest (for the human)

1. Suwalki on `true`, HIGH: fly along a forest edge, a hedge, a river and a heath; check shrubs stand where listed and not on roads / rivers / fields' interiors; 4 kinds look distinct.
2. Zoom from 5 m to 600 m: the mesh -> impostor change at ~60 m shows no visible pop in colour / lighting / position (compare with the full-tree hand-over).
3. Jump the camera ~2 km with a hotkey / minimap: shrubs are there at once, no fill-in over seconds.
4. FPS: 60 on the target GPU in a dense edge scene; frame time with shrubs off vs on differs by <= 0.7 ms (RX 580).
5. LOW and MEDIUM: shrubs vanish beyond ~150 m; frame time lower than HIGH. Switch to `balanced`: nothing changes.

## Player manual

One line in the graphics-quality section of docs/MANUAL.md: on the realistic scale, LOW / MEDIUM show shrubs only up close (150 m). No rules change.

## GDD

No change (cosmetic only; no game rule added).

## Out of scope

- Grass (217b), crops (217c), trees, units, buildings, seasons, balanced preset, game rules.

## Implementation notes

_Filled in by the agent when done._

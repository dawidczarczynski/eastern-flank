# TASK-135: Vegetation at real scale – real density, impostors / canopy shells, distance budgets

- **Status**: to playtest
- **Layers**: presentation (`TreeField`, `ScatterPlanner`, `BackdropCanopy`, grass / bush layers, `VisualScale`)
- **Depends on**: – (soft: TASK-072a, TASK-072b, TASK-134, TASK-110)
- **Sections**: GDD "Visual direction", "Open questions" (Realistic scale); ADR 0021
- **Model**: opus (performance budgets, LOD, determinism of scatter)

## Goal

With trees at real size (`true` preset) forests still read as forests: real density (~2 000 trees per forest hex) through impostors and canopy shells, with distance budgets so Suwałki keeps its frame time. TASK-072 is split: TASK-072a (benchmark) and TASK-072b (chunk manager with metre-based rings). If 072b lands first, the vegetation layers (impostors, shells, budgets) plug into its chunk interface; otherwise this task adds its budgets per chunk in `TreeField`/`GrassField` and 072b absorbs them. 072b does not implement impostors, shells or real density.

## Acceptance criteria (testable)

- [x] Forest hex density at the `true` preset ≈ 2 000 trees (± 10 %) as a *visual* count (full trees + impostors + shell), derived from `MapScale`; `balanced` is unchanged.
- [x] Full 3D trees only within a range given in metres (default 250 m), impostors to ~1 km, beyond that canopy shell; ranges scale with tree size (a test with two tree sizes).
- [x] Per-frame budget: full-tree instance count ≤ a data-driven cap (`LookPreset`); exceeding it drops the farthest first (test with a synthetic camera).
- [x] Scatter stays deterministic: same seed → same tree positions (no new RNG outside the existing streams); the `true` preset adds no extra simulation draws.
- [x] Grass and ground cover at real size (0.3–1.5 m) and real density only within ~100 m of the camera.
- [x] Follow-up from TASK-134 (ADR 0025): grass, ground cover and full trees within the near-terrain reach (≤ 3 units) sit on the drawn near surface (`TerrainNear.drawn_height_at`), not on the 36 m lattice (`MapView.mesh_height_at`), which is off by 0.2 m on average and a few metres on steep slopes; test: mean and max offset to the near surface on Suwałki ≤ 0.1 m.
- [x] Frame time on Suwałki at distances 46 / 24 / 7 with `SCREENSHOT_SCALE_PRESET=true` ≤ 16.7 ms avg on the RX 580 (or the shortfall is recorded for the human); numbers in the implementation notes.
- [ ] Screenshots Read by the agent: a forest hex at 46, 24, 7 and 1.2 reads as a closed forest, no visible pop between levels.

## Playtest (for the human)

1. Suwałki at all zoom levels with the `true` preset: forests look dense, no flicker when zooming.
2. Frame rate stays smooth while panning across forests.

## Player manual

None (look only).

## Out of scope

- Terrain mesh and textures (TASK-134); making `true` the default (TASK-138).

## Implementation notes

Everything applies only under the `true` VisualScale preset; `balanced` builds and draws what it did (tested). ADR [0026](../adr/0026-real-scale-vegetation.md); ARCHITECTURE "Real-scale vegetation".

- **Data**: `LookPreset.VEGETATION_DEFAULT` / `LookPreset.vegetation()` (trees per ha 370 ≈ 2 000 per hex, clearing 15 m, fill crown width 7 m, ranges 250 m / 1 km at a 24 m tree with floors 30 m / 100 m, vanish angle, ±8 % hand-over band, `full_tree_cap` 6 000, sinks 0.3 / 0.05 m, near grass 100 m at 1.2 clumps/m², shell fade / height / crown / brightness); rings `forest` 1 100 m, `forest_full` 330 m, `grass_near` 110 m in `data/visuals/chunk_rings.tres`.
- **Pure parts**: `VegetationRanges` (density from `MapScale`, full / impostor / vanish ranges scaled by the species' real height, bands, `budget_reach` = farthest-first cap), `ForestFill` (hash-jittered world grid on forest tiles, no RNG, no ScatterPlanner draws), `TerrainNear.surface_height_at` (the near mesh's raw triangles from the surface, thread-safe).
- **Drawing**: `ForestField` (full LOD0 trees on 1-unit chunks of a camera-centred ChunkManager; impostors on 2-unit chunks of the target manager; budget via `lod_cap` in `foliage_body.gdshaderinc` and `full_reach` in the new `tree_impostor.gdshader`), `TreeImpostors` (one camera-facing quad per tree, all species in one MultiMesh), `ForestShell` (canopy shell over the map's forest tiles, `canopy.gdshader` + `near_fade` / `brightness`), `GrassNear` (real-density grass within 100 m of the camera with GrassField's look), `RealScaleVegetation` (owns the camera-centred manager, switches the near layers off while the camera is higher than they reach). `TreeField` under `true`: metre bands, LOD0 then one impostor node per chunk (LOD1 / LOD2 unused), trees re-seated on the near surface. `MapView.set_camera_position` (fed from the viewport camera in `_process`), `vegetation_ground_height`; the water plane moved to `WaterPlane` to keep MapView under 1 000 lines.
- **Tests**: `test_real_scale_vegetation` (≈2 000 ± 10 % per forest hex and density per ha through `MapScale`; balanced draws no fill / impostors / shell; ranges in metres scale with tree size (12 vs 24 m); `budget_reach` farthest first; cap holds for a synthetic camera with every hidden chunk farther than every shown one and `lod_cap` = reach; deterministic fill, chunk split = whole, ScatterPlanner plan identical under `true`; near grass 0.3–1.5 m, 100 m range, density), `test_real_scale_suwalki` (slow list: on Suwałki within 3 units, offset to `drawn_height_at` mean / max: dense trees 0.0000 / 0.0002 m over 19 473, planned trees and ground cover 0.0000 / 0.0000 m over 434, near grass 0.0000 / 0.0002 m over 36 413, far grass 0.0000 / 0.0001 m over 697).
- **Frame time** (Windows build, RX 580, HIGH, 1280×720, Suwałki, `SCREENSHOT_SCALE_PRESET=true`, `SCREENSHOT_CAMERA=2,-40,<d>`, `SCREENSHOT_MEASURE_FRAMES=120`, avg / max ms; before → after this task): d46 11.7 / 35.2 → 9.1 / 26.8; d24 14.8 / 29.9 → 8.7 / 25.8; d7 13.8 / 29.6 → 9.8 / 32.9; d1.2 11.9 / 35.4 → 10.8 / 37.9 (8.1 M triangles: the stand of full trees around the camera). Draws at d24 3 128 → 1 315, triangles 7.9 M → 1.3 M (LOD0 is now spent only within ~250 m). All under 16.7 ms; maxima are first-frame spikes as before.
- **Screenshots read** (`.screenshots/veg/`): `v2_46`, `v2_24` (forests are closed canopy shells), `f_7` / `f2_7` and `f_3` (forest hex (9, 11) by `SCREENSHOT_FOCUS=25.1,16.5,-40,<d>`: dense impostor forest, shell beyond; the shell's brightness was lowered to meet the impostors' tone), `f_1.2` (closed stand of full trees, impostors behind), `v2_1.2` (meadow, forest edge of full trees). No gaps between tiers in the stills; whether the hand-over pops in motion only the playtest shows.
- **Known limits / for the human**: impostors are baked 16-view pictures of the full trees (baked light, side view from a steep camera, views blended); the shell's 9 m crown pattern aliases slightly at d46; the tone step where impostors give way to the shell (~700–1 000 m) is softened but still visible at d7; only the playable map's forest tiles get fill and shell (the backdrop keeps BackdropCanopy and its sparse trees); bushes / rocks keep their unit-based LOD; real-density ground cover is the near grass on the forest floor (no extra undergrowth meshes). `test_real_scale_vegetation` builds a small map at `true` (~30 s of the fast suite). README screenshot not refreshed: the default (`balanced`) battle is unchanged.

- **Playtest round 1 (2026-11-21)**: (1) the DEVTOOLS SCALE / LOOK switches now apply to normal battles in a `--debug` run (`DevTunables.battle_overrides`). (2) Impostors: a baked 16-view atlas of the real LOD0 models (`TreeImpostors`, SubViewport bake at start, poses pushed to the RenderingServer because Node3D transforms reach it a frame late, 8 views per draw – D3D12 runs out of descriptors with all at once), replacing the procedural silhouettes; the canopy shell takes its colours from the atlas and its crowns are lit as domes (`canopy.gdshader` `lit_domes`, backdrop unchanged). (3) Loading: worker batches are sized by the measured plan cost (`ChunkManager.BATCH_USEC_PER_WORKER`); the impostor layer is never switched off; the shell stays drawn over impostor chunks not built yet (coverage mask); far impostor chunks plan half the trees on the lattice; the fill loop caches per tile and hashes once per value set; full-tree ring 170 m (the 6 000-tree budget never drew farther), impostor ring 1.3 km, impostors to 1.4 km x h / 24 m. Measured on 4 WSL cores after a ~2 km camera jump: impostors within 290 m of the camera after ~1.9 s, the whole full-tree ring after ~16 s (impostors stand in meanwhile); ring planning CPU ~37 s → ~16 s. (4) Real-size look: `REAL_SIZE_LEAF_COLORS` (summer greens, autumn share 1.5 %) and small-leaf / short-twig cards. (5) Fixed: the budget compared a 32-bit reach with a 64-bit distance, so a chunk exactly at the reach was still drawn. Frame time (RX 580, HIGH, 720p, Suwałki): near forest 11.5 ms (GPU 11.0 ms, 7.4 M tris), far 6.9 ms.

### Known limits from review (not fixed)

- `MapView.vegetation_ground_height` uses the near-mesh triangles for the whole lattice rect, but the drawn near terrain reaches only ~433 m (`chunk_rings.tres`). Fill trees / impostors out to 1.1 km can therefore float or sink a little on steep slopes beyond that; not measured. Fix option: fall back to `mesh_height_at` past the near reach.
- Worker-thread planning reads the static look preset and `MapView._near`; the preset must not change while chunks are planning.
- No golden test that `balanced` plan output is unchanged; `map_view.gd` is exactly at the 1000-line lint limit.

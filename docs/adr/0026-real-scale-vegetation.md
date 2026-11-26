# ADR 0026: Real-scale vegetation – dense fill, impostors, canopy shell, full-tree budget, camera-centred layers

- **Status**: accepted
- **Date**: 2026-11-20
- **Task**: TASK-135 (builds on ADR 0021 real scale, ADR 0024 chunked world, ADR 0025 near terrain)

## Context

At real size (`true` VisualScale preset, ADR 0021) a forest hex needs ~2 000 trees to read as a forest instead of 30; Suwałki would have ~250 000. Drawing them all as 230–340-triangle trees is far beyond the frame budget, and the existing tree LOD ranges (30 / 46 world units ≈ 4–7 km) spent LOD0 on sub-pixel trees. Grass at real size (0.3–1 m) at the existing ~1 clump per 230 m² reads as bare ground up close. Real-size content must also stand on the drawn near surface (ADR 0025), not on the 36 m lattice.

## Decision

Everything below applies only under the `true` preset; `balanced` builds and draws exactly what it did.

1. **Dense fill without random streams.** `ForestFill` adds trees on forest tiles on a jittered world grid whose spacing comes from `LookPreset.vegetation()` `forest_trees_per_ha` (370 / ha ≈ 2 000 per 250 m hex) and the hex area of `MapScale`. Each cell's point and values are integer hashes of (seed, cell, salt): no `RandomNumberGenerator`, no draws from ScatterPlanner's streams, chunk-order independent. ScatterPlanner's plan is untouched (tested: identical under `true` and `balanced`).
2. **Three tiers in metres, scaled by the species' real height** (`VegetationRanges`): full 3D trees (LOD0) to 250 m × h / 24 m, impostors (`TreeImpostors`: one camera-facing quad per tree with a baked 16-view atlas of the real LOD0 models (rendered once at start; the first procedural silhouettes and a low-poly 3D version both looked wrong) instead of a procedural crown silhouette in `tree_impostor.gdshader`, all species in one MultiMesh per chunk) to 1.4 km × h / 24 m, beyond that the canopy shell (`ForestShell`: one mesh over the map's forest tiles at crown height, `canopy.gdshader` as for the backdrop, faded in crown by crown with the camera distance). Off-forest items keep their impostor until it is ~2 px (`vanish_angle`). Small scrub has floors (30 m / 100 m). Hand-over per tree in a ±8 % band in the vertex shaders, as TreeField did.
3. **The full-tree budget is a reach.** *(Removed by TASK-221, ADR 0027 amendment: the full trees are GPU-placed, there is no `full_tree_cap`; the reach remains only as the nearest unbuilt full chunk.)* Built full chunks within the full range are taken nearest first while their tree count stays within `full_tree_cap` (LookPreset); the distance of the first chunk that does not fit becomes `lod_cap` of the LOD0 materials and `full_reach` of the impostor material, and farther chunks are hidden. Trees beyond the reach – the farthest – are drawn as impostors, tree by tree, with no gap or double draw. A full chunk not built yet caps the reach the same way.
4. **A second, camera-centred ChunkManager** (`RealScaleVegetation`): the full trees (`forest_full`, since TASK-221 GPU-placed 18 m chunks, drawn to `full_tree_range_m` 45 m) and the near grass (`grass_near`, 36 m chunks, 110 m reach) follow the camera's ground point, not its target (at a close camera the target is 150–250 m ahead of the camera). The impostors (`forest`, 2-unit chunks, 1 100 m) stay on the target manager. Each near layer is off while the camera is higher above the ground than it reaches (hysteresis 1.25×), so the default and overview zooms plan and draw none of them. No ChunkManager change (ADR 0024's layer interface).
5. **Vegetation stands on the drawn near surface.** `TerrainNear.surface_height_at` computes the near mesh's raw triangles from the surface (pure, thread-safe); trees (sunk 0.3 m, scrub 0.05 m instead of TREE_SINK's 2.9 m), the dense fill and both grass layers use it inside the playable mesh (lattice on LOW). Tested on Suwałki: mean and max offset to `drawn_height_at` within 3 units ≤ 0.1 m (measured ≤ 0.2 mm).
6. **Near grass** (`GrassNear`): real density (`near_grass_per_m2` 1.2 on meadow, other terrain by GrassPlanner's ratio) within `near_grass_range_m` 100 m of the camera, GrassField's clump mesh, materials, kinds and colours, hash-placed like the fill.

## Consequences

- (+) Forests read as closed forests at every zoom; Suwałki is cheaper than before at `true` (d7: 13.8 → 9.8 ms) because LOD0 is now spent only within ~250 m.
- (+) All numbers are data (LookPreset `vegetation`, ChunkRings); they follow `MapScale`.
- (−) The fill is planned twice near the camera (full and impostor layers plan the same hash grid) and grass plans read the surface four times per clump (worker threads only).
- (−) The canopy shell covers the playable map's forest tiles; the backdrop keeps its own BackdropCanopy and sparse backdrop trees. The shell's crown pattern is a fixed 9 m cell and can alias at the farthest zoom.
- (−) Impostors are baked pictures on camera-facing quads: baked light (no sun-dependent shading), 16 views blended, a side view from a steep camera; the bake costs ~1 s at start and needs a renderer (headless: flat silhouettes); they cast no shadow (full trees do).
- (−) Bushes and rocks (ScatterChunks) keep their unit-based LOD distance; real-density ground cover comes only from the near grass on the forest floor, not from more undergrowth meshes.

# ADR 0025: Near terrain LOD – a 4.5 m chunk layer with switched edges, ground textures in real metres

- **Status**: accepted
- **Date**: 2026-11-20
- **Task**: TASK-134 (builds on ADR 0021 real scale, ADR 0024 chunked world)

## Context

ADR 0021 brings the camera down to ~1 unit (144 m) and draws units at real size. The terrain mesh is the 36 m lattice of ADR 0024 (4 vertices / unit): on Suwałki it misses the real surface by 0.19 m on average and up to 6.7 m on slopes (measured inside the map), so a 2.4 m tank at a tile centre sinks into or floats above the drawn ground, and a close camera sees folded 36 m facets. The ground textures repeated every 0.7–1.6 units (sized for 7.7 m / unit × 4), a smeared camouflage at the close camera.

## Decision

1. **The near LOD is one more chunk layer** (`terrain_near`, `TerrainNear`), not a clipmap and not a change of `ChunkManager`'s model: chunks of one TerrainChunks block (4 × 4 lattice cells = 1 unit) subdivided 8× (1/32 unit = 4.5 m, 33² vertices), reach 433 m (3 units) in `chunk_rings.tres`, so the usual 1.5 × build / 1.2 × free rings keep ≤ 5 m vertices within 3 units of the target and none beyond ~7 units. Two small manager additions: `set_enabled(id, on)` (the layer is on only while the camera distance is ≤ 12 units, off beyond 14 – at the default zoom a 4.5 m triangle is under a pixel) and a rescan after a quarter of the smallest enabled build ring (a 2-unit rescan step would leave the 4.5-unit ring behind).
2. **Holes, not overlap.** A fine chunk keeps its index buffer per 4 × 4-cell block (with the block's skirt quads); a built near chunk removes its block (`TerrainChunks.set_hole`), freeing it puts the block back. No depth tricks, no double shading, shadows from exactly one mesh.
3. **Edges have two planned variants, switched by the neighbour.** Inner near vertices sample `TerrainSurface` – the function the core tile heights come from, so a unit placed at a tile centre touches the drawn ground (tested ≤ 0.1 m within 3 units). Each edge is planned twice on the worker thread: "raw" (surface heights and normals) and "fine" (the lattice edge interpolated, fine normals interpolated). An edge facing a built near chunk uses raw (both sides compute identical values); an edge facing the fine mesh uses fine, i.e. it lies exactly on the fine triangles' edge – no crack, no T-junction step (tested ± 1 mm). Building or freeing a chunk switches the shared edge of its built neighbours (a ~0.2 ms mesh rebuild each, on the main thread inside the chunk budget). A 0.02-unit skirt covers the rasterisation slivers of the T-junctions. The plan still depends on the chunk alone (ADR 0024); only the edge choice depends on what is built, and it is made on the main thread.
4. **Splat from the lattice.** Ground weights, tints and fine-edge normals are the fine lattice's own per-vertex values (`TerrainChunks.vertex_attributes`, factored out of the chunk plan) interpolated on its triangles, so the ground layers do not change at the ring border; only the shape and the inner normals are finer.
5. **Ground textures in real metres + detail.** `layer_repeat` is each layer's real scanned size (1.3–3 m) through `MapScale` (`TerrainGround.layer_repeats`). A real-size repeat is under a pixel beyond a few units, so by view distance 2.5 → 6 units each layer cross-fades to `layer_repeat_far` (75 × its real size, also metres through `MapScale` – the former look, which reads from the default zoom; screenshots at 24 / 7 unchanged); only fragments inside the band sample both. A procedural detail texture (`TerrainGround.detail_texture`: contrast-stretched normal + height, 24 m repeat plus a rotated 7.2 m sample) modulates albedo (± 30 %, a drier tint on the high patches) and normal close to the camera, faded in by view distance from 6 to 4 units – at 1–3 units the real-size scans alone read almost flat (their 8 × 8-texel mips), the detail gives the meadow its metre-scale patchiness. Roads keep the far pattern (one sample, no cross-fade).
6. **LOW** keeps the lattice mesh only (`GraphicsQuality` `terrain_lod` off) and no detail texture (`terrain_detail` off).

## Consequences

- (+) Close camera: the drawn ground follows the real surface at 4.5 m, units stand on it, real-size grass / gravel / soil texture.
- (+) No new manager concept: TASK-135 can use `set_enabled` / small rings for impostor layers the same way.
- (−) Zooming in below 12 units plans ~80 near chunks (~40 ms each on a worker thread, ~1 ms build each including the neighbour / fine rebuilds): the near mesh fills in over roughly a second, nearest first; until then the fine mesh shows (a small pop of up to a few metres on slopes).
- (−) The far pattern is still the enlarged texture beyond ~6 units of view distance (a deliberate keep: real-size only, the default zoom read as flat mean colours); inside the 2.5–6 band the ground layers cost two samples.
- (−) `MapView.mesh_height_at` stays the 36 m lattice (overlays, grid lines, grass heights): close up, grass and draped overlays can sit up to the lattice error (mean 0.2 m, a few metres on steep slopes) off the near surface. TASK-135 / TASK-136 place real-size content on `TerrainNear.drawn_height_at` or the surface instead.
- (−) The near chunk entries keep their mesh arrays (edge switching) and the fine chunks their plans (hole rebuilds): ~8 MB + ~6 MB on Suwałki.

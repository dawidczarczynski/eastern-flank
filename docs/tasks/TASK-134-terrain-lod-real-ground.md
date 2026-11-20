# TASK-134: Terrain LOD and real-metre ground textures near the camera

- **Status**: done
- **Layers**: presentation (`MapView` terrain mesh, `TerrainGround`, terrain shader)
- **Depends on**: – (soft: TASK-110, TASK-111)
- **Sections**: GDD "Visual direction", "Open questions" (Realistic scale); ADR 0021
- **Model**: opus (mesh LOD, seams, performance)

## Goal

At the close camera of TASK-111 (down to ~1 unit) the ground looks like real ground: a fine mesh near the camera and textures repeating in real metres, instead of 36 m "folded paper" and a smeared pattern.

## Acceptance criteria (testable)

- [x] Terrain vertex spacing near the camera ≤ 5 m (≤ 0.035 units) within a radius of 3 units around the look-at point; beyond ~8 units it is today's 36 m (4 vertices / unit).
- [x] Seams: no gaps or T-junction cracks between LOD rings (test: vertex heights on a ring border equal the coarser edge's interpolated heights ± 1 mm).
- [x] The near mesh samples the same height function as the core tile heights (± 0.001 units at tile centres); a unit placed at a tile centre touches the drawn surface (error ≤ 0.1 m = 0.0007 units).
- [x] `TerrainGround` texture repeat is derived from `MapScale` (1 repeat = a real-metre size per layer, not 7.7 m / unit) within ~2.5 units of view distance, cross-fading to a far pattern (75× real size, still in metres) beyond ~6 units so the default zoom keeps its look (deviation agreed in ADR 0025, pending the human's playtest), plus a detail texture that fades in below distance ~6 units.
- [x] Frame time on Suwałki at distances 24 / 7 / 1.2 is not worse than the ADR 0021 table (≤ 17.8 / 17.0 / 14.0 ms avg on the RX 580).
- [x] LOW quality keeps the single coarse mesh.

## Playtest (for the human)

1. Suwałki, zoom to the minimum: ground is smooth, no cracks while panning, a tank sits on it (not sunk).
2. Zoom out: no visible pop or seam lines between mesh rings.

## Player manual

None (look only); MANUAL §10 camera notes are written by TASK-111.

## Out of scope

- Vegetation (TASK-135), unit models, effects.

## Implementation notes

Near terrain LOD as one more chunk layer (ADR 0025): `TerrainNear` (`src/presentation/terrain_near.gd`, layer `terrain_near`, reach 433 m = 3 units in `data/visuals/chunk_rings.tres`) draws 1 x 1-unit chunks at 1/32 unit (4.5 m) vertex spacing; a built near chunk punches its 4 x 4-cell block out of the fine chunk under it (`TerrainChunks.set_hole`, fine index buffers kept per block incl. skirt quads). Inner near vertices sample `TerrainSurface`; each edge is planned in a "raw" (surface) and a "fine" (lattice edge interpolated) variant, switched on the main thread by whether the neighbouring near chunk is built, so the ring border lies exactly on the fine triangles' edge (0.02 skirt for T-junction slivers). Weights / tints / fine-edge normals are the lattice's own values (`TerrainChunks.vertex_attributes`, factored out of `plan`) interpolated on its triangles. `ChunkManager`: `set_enabled(id, on)` and a rescan after 1/4 of the smallest enabled build ring; the near layer is on at camera distance <= 12 (off beyond 14) and only on HIGH (`GraphicsQuality` `terrain_lod`). `TerrainNear.drawn_height_at` gives the drawn near surface for TASK-136.

Ground: `layer_repeat` = each layer's real scanned size through `MapScale` (`TerrainGround.layer_repeats`), cross-faded by view distance 2.5 -> 6 units to `layer_repeat_far` (75 x the real size, metres through MapScale = the former look; real-size only made the default zoom flat mean colours). Detail texture (`TerrainGround.detail_texture`, procedural normal + height, 24 m + rotated 7.2 m, +-30 % albedo, drier tint, normal tilt) fades in from 6 to 4 units view distance (`terrain_detail`, HIGH only). Roads keep the far pattern.

Tests: `test_terrain_near` (<= 5 m within 3 units, none beyond 8, ring border = fine edge +-1 mm and shared edges equal, fine chunks leave out exactly the near blocks, drawn surface vs tile elevation and unit height <= 0.1 m at every tile centre within 3 units, free/refill holes, far camera / LOW off, pure plans), `test_terrain_ground`, `test_chunk_manager` (disable, small-ring rescan), `test_map_view_detail` (LOW: no detail).

Measured (Windows build, RX 580, HIGH, 1280x720, Suwalki `true` preset, camera on unit 2, yaw -40, `SCREENSHOT_MEASURE_FRAMES=120`, avg / max ms): d24 15.2 / 41.3, d7 13.9 / 38.4, d1.2 11.8 / 28.3 (budget ADR 0021: 17.8 / 17.0 / 14.0 avg; maxima are first-frame spikes as in the ADR table). Earlier runs of the same shots: d24 14.7, d7 13.7, d1.2 11.7-11.8. `tools/bench_large_map.sh --scale=1`: build 1.54 s + chunks 5.47 s, d46 / 24 / 7 / 1.2 = 10.7 / 10.7 / 10.5 / 10.7 ms, pan 8.5 ms with 0 frames > 33 ms. Headless Suwalki at d1.2: 82 near chunks, ~42 ms plan each on a worker thread (summed 3.4 s CPU), ~1.1 ms build each (incl. neighbour edge / fine hole rebuilds). Not measured: the zoom-in transition itself (near chunks filling in over ~1 s while zooming below 12 units: pop, frame spikes) and panning at d1.2 – only the human's playtest shows these.

Deviations / limits: tile-centre exactness is guaranteed within the 3-unit radius; at the ring border (fine-variant edges) a centre can be off by the lattice error (one Suwalki centre at 5.3 units: 0.17 m). `MapView.mesh_height_at` (grass, grid lines, overlays) stays the 36 m lattice, so close up grass / overlays can sit up to the lattice error off the near surface (mean 0.2 m, a few m on steep slopes) – follow-up for TASK-135 / TASK-136. The far texture pattern was kept beyond ~6 units view distance (see above). Grass is not real-scale yet (TASK-135).

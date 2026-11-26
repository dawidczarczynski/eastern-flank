# TASK-221: Full 3D forest trees placed by the GPU

- **Status**: ready
- **Layers**: presentation (`ForestField` full layer, new tree shader, `ForestFill` GDScript reference, `GpuVegetationLayer`, `NearHeightCache`)
- **Depends on**: TASK-189 (GPU impostors, ADR 0027), TASK-217a (GPU vegetation framework, near height cache)
- **Sections**: ADR 0027 decision 4 (the decision this task reverses), ADR 0033; code (grep CODEMAP): `ForestField`, `ForestFill`, `TreeMeshes`, `forest_impostor.gdshader`, `forest_hash.gdshaderinc`, `GpuVegetationLayer`, `NearHeightCache`, `VegetationRanges`
- **Model**: sonnet
- **Tags**: battle-look

## Goal

The near, full-detail (LOD0) forest trees (`forest_full` layer, ~170 m ring) are placed by the GPU from their grid cell, exactly like the impostors and shrubs. Nothing about them is planned on the CPU any more: they stand the frame the camera target reaches them, no chunk-by-chunk filling in after a jump or while panning. `true` preset only; `balanced` untouched.

## Why

ADR 0027 kept the full trees on the CPU ("few, near the camera, they need the exact near-surface height"). Both reasons are gone: TASK-217a built `NearHeightCache` (the near surface as a texture the shaders read), and the player sees the trees pop in as the camera moves. CLAUDE.md: per-instance work goes to the GPU.

## Decisions

- One tree = the same cell function as the impostor (`ForestFill.cell_tree`, hash in `forest_hash.gdshaderinc`), so the full tree and its impostor stand at the same point with the same species, size, yaw and colour. The hand-over band logic stays (full tree below its range, impostor beyond).
- Full trees are `instant` chunks (`GpuVegetationLayer`): one shared MultiMesh per species / variant mesh without instance data, a cell range as instance uniform. The vertex shader collapses cells without a tree of that mesh.
- Base height from `NearHeightCache` (the drawn near surface), not the lattice.
- The per-frame budget (`full_tree_cap`, nearest chunks first) is replaced by a distance rule in the shader; the cap becomes a GPU cost limit, to be re-measured.
- Burns (`MAX_BURNS`) apply to full trees through the same uniform array.

## Acceptance criteria (testable)

- [ ] Under `true`, the `forest_full` layer plans nothing: 0 plan ms in `ChunkManager.stats()` and 0 per-instance MultiMesh data (test).
- [ ] GDScript reference and shader twin agree: fixed-value test for species / variant / position of a set of cells, and the same cell yields the same point for the full tree and its impostor (test on the reference).
- [ ] After a 2 km camera jump, full trees exist within the ring after the first frame (extend `test_real_scale_suwalki.gd`).
- [ ] Hand-over with the impostor: no gap and no double draw (existing hand-over tests green or updated).
- [ ] Full trees stand on the near surface (shader reads `NearHeightCache`; test the height lookup against `TerrainSurface` within the sink tolerance).
- [ ] `balanced` unchanged; existing `ForestField` / `TreeField` tests green.
- [ ] Frame cost: GPU ms of the full-tree layer measured on the RX 580 (HIGH, forest at 30 m) with `tools/perf.sh --only=trees`, written in Implementation notes; total must hold 60 FPS. Budget **[ASSUMPTION]** <= 1.0 ms.
- [ ] Battle load: `Chunk prebuild` line and camera-manager stats show no `forest_full` plan time.

## Playtest (for the human)

1. `true`, HIGH, in a forest at 5-60 m: trees look as before (species mix, sizes, colour), standing on the ground.
2. Jump 2 km onto a forest and pan fast along its edge: full trees are there at once, no filling in.
3. Watch the full-tree / impostor hand-over at 150-250 m: no pop, no gap, no doubled trees.
4. Shoot into a forest: burns still blacken full trees.
5. FPS 60.

## Player manual

None (internal).

## GDD

No change (cosmetic).

## Out of scope

- Impostors, shrubs, grass (done), tree features of TASK-199b (solitary trees, tree lines), balanced preset, game rules.

## Implementation notes

(empty)

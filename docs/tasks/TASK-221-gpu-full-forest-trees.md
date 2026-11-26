# TASK-221: Full 3D forest trees placed by the GPU

- **Status**: to playtest
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
- [ ] (NOT MET: 3.1 ms at the 45 m cap, ~35 ms at 255 m; needs the human's decision, see notes) Frame cost: GPU ms of the full-tree layer measured on the RX 580 (HIGH, forest at 30 m) with `tools/perf.sh --only=trees`, written in Implementation notes; total must hold 60 FPS. Budget **[ASSUMPTION]** <= 1.0 ms.
- [ ] Battle load: `Chunk prebuild` line and camera-manager stats show no `forest_full` plan time. (Verified only by test: 0 plan ms; the `Camera chunk layers:` print shows 0 live at the overview camera, so it proves nothing there. Not checked with a close camera.)

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

Implemented as specified (ADR 0027 amendment), with one forced deviation (the range cap, below).

**What was done**
- `ForestField` full layer is an `instant` `GpuVegetationLayer` (`forest_full`, 18 m chunks): one node per chunk sharing one identity-instance MultiMesh, cells as instance uniform, no plan (0 plan ms), no per-chunk instance data. One surface per species (the 3 variant models merged, variant in the vertex colour's alpha) = 5 draws a chunk.
- New `assets/shaders/forest_tree.gdshader` (= `foliage_body.gdshaderinc` under `PLACED_VEGETATION` + `PLACED_LEAF_COLOR`; the placed block now has an early branch so collapsed vertices skip colour and wind work, and `placed_instance` got a `tag` parameter = vertex colour alpha; `shrub_mesh.gdshader` adapted). It derives the tree from its cell exactly as the impostor (shared new includes `forest_cell.gdshaderinc` – fill uniforms, lattice height, stand test, moved out of `forest_impostor.gdshader` – and `near_height.gdshaderinc` – moved out of `shrub_rules.gdshaderinc`). Cheap hash tests (variant, species, distance) run before any texture read.
- Base height from the shared `NearHeightCache` (now owned by `RealScaleVegetation`, bound to forest + shrubs + grass). Hand-over: the tree is judged by the impostor's own base distance and the very same band expression, so exactly one of the two draws it.
- Removed: `full_tree_cap`, `VegetationRanges.budget_reach`, the CPU plan (`_plan_full` etc.), `ForestField.setup`'s `ground` argument, the `forest_full` ring entry. `ForestField.full_trees(chunk)` is the GDScript reference; `ForestFill.lattice_height` added.
- Tests: new `tests/unit/test_forest_full_trees.gd` (plan-free instant layer, shared MultiMesh, cells uniform, reference == fill trees, mesh variant tags, reach caps both LODs); `test_real_scale_vegetation` (shader expression parity of the tree shader and impostor band, full tree == impostor point); `test_real_scale_suwalki` (2 km jump: every full chunk within the ring after the first frame, 0 plan ms; near-height window vs surface). Camera-manager stats are now printed after the warm-up (`Camera chunk layers:` in `battle_controller.gd`; it prints 0 live for the overview camera, which is above the layer's height limit).
- `tools/perf_profile.gd` got rows "forest full trees" / "forest full tree shadows".

**Deviation: the range cap `full_tree_range_m` (LookPreset, 45 m).** The prescribed design makes every cell cost the vertices of all 15 models (~7 300 vertices a cell, only one of the 14 collapsed copies is a real tree). Measured on the RX 580 (HIGH, 1920x1080, Suwalki, camera 22 m inside a forest, `tools/perf.sh --only="forest full" --windows`): with the old 255 m ring the full-tree layer cost **35.5 ms** (shadows 11.9 ms of it); the GPU is vertex-throughput bound (~1.2 G vertices/s). That is far beyond the 1.0 ms [ASSUMPTION], so the cap now bounds the ring: full trees only to 45 m (each tree at its own point of the `band_share` band, impostors from there; `full_cap` uniform in both shaders), measured **3.1 ms (shadows 1.3 ms)** in that same worst-case in-forest view. This is over 1.0 ms and the forest now shows impostors from ~45 m instead of ~250 m: needs the human's judgement. Scaling is ~r^2 (30 m would be ~1.4 ms). Real fix for a long full range: compact the trees with a compute pass (`RenderingServer.multimesh_get_buffer_rd_rid`), out of scope here.

**NOT measured**: the old CPU path's GPU cost for the same view (no baseline run), the 60 FPS total in a normal (non-in-forest) camera, GPU cost at other camera heights, D3D12 behaviour of the hash jitter for the full trees was only checked by eye (trees stand on their cells in the screenshots). Headless tests cannot run the shader: parity is the reference + fixed values + expression checks.


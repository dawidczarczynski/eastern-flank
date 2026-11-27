# GPU-placed scatter: the patterns and the traps

How the forest (TASK-189, 217, 221; ADR 0027, 0033), shrubs, grass and crops put thousands of
things on the map without CPU planning, and what to copy for **buildings, fences, road furniture,
rocks, debris** or anything else that is many, repeated and tied to the ground. Read it before
starting such a layer. Code: grep `docs/CODEMAP.md` for `GpuVegetationLayer`, `ForestFullTrees`,
`ForestField`, `NearHeightCache`; shaders in `assets/shaders/` (`forest_hash`, `forest_cell`,
`near_height`, `vegetation_hash`, `forest_cells.glsl`).

## 1. The one rule

Every item is a **pure function of its grid cell** (32-bit integer hash of seed, cell, salt) plus
map textures (stand mask, lattice heights, near-surface heights). The GDScript reference
(`ForestFill.cell_tree`, `ForestField.full_trees_around`) and the shader twin give the same bits:
uint32 arithmetic only, constants checked by tests, fixed cell values in a test. No RNG, no
per-item CPU plan. That is what makes "jump 2 km, it is all there at once" true.

## 2. Pick the drawing technique by how many items are *really* there

| Situation | Technique | Example |
|---|---|---|
| Many tiny items, cheap mesh, most cells hold one | **Vertex-derived, identity instances**: one shared MultiMesh of cells, `cells` instance uniform per chunk, the vertex shader derives the item from `INSTANCE_ID` and collapses empty cells (`GpuVegetationLayer`, instant chunks) | impostors, shrubs, grass |
| Heavy mesh (hundreds of vertices), several models | **Compute compaction** (below) | full forest trees |
| A few hand-placed objects from map data, geometry that needs mesh building | CPU plan on `WorkerThreadPool`, justified in the task file | buildings from OSM footprints, bridges |

**The trap (TASK-221 first attempt):** in a vertex-derived scheme a cell is drawn by *every*
model's vertices and collapsed by all but one. With 15 models of ~500 vertices that is 7 300
vertices per cell, ~35 ms at 255 m on the RX 580, and it cannot be fixed by tuning. If an item has
N alternative meshes and heavy vertex counts, do not choose vertex-derived. Count
`cells x sum(model vertices)` before you pick.

## 3. Compute compaction (copy `ForestFullTrees`)

1. A compute shader (`assets/shaders/*.glsl`, `#[compute]`, imported as `RDShaderFile` – glslang at
   import, so a compile error shows in tests: load it and check `get_spirv().compile_error_compute`)
   runs one thread per cell of a square window around the camera, derives the item exactly as the
   reference, and appends it to the list of its model with an `atomicAdd` counter.
2. The lists are **copied** (`RenderingDevice.buffer_copy`) into the buffers of one MultiMesh per
   model (`RenderingServer.multimesh_get_buffer_rd_rid`; 16 floats an instance for a 3D transform
   + custom data, rows of the basis then custom). The ordinary material draws them (INSTANCE_CUSTOM
   for variation). All RD calls run in `RenderingServer.call_on_render_thread`.
3. **Fixed capacity per list** = worst case of "every cell stood on" in range x the model's share
   + 5 sigma. Overflow is dropped, so size it for the largest range the layer can get.
4. **Zero-clear every frame** (`buffer_clear`); an unused slot has a zero basis and the vertex
   shader collapses it before any work (`COMPACTED_TREES` in `foliage_body.gdshaderinc`; `return`
   is not allowed in `vertex()`, use if/else).
5. **Draw only what is there**: read the list counts back asynchronously (`buffer_get_data_async`)
   and set `visible_instance_count` to the count of a few frames ago x 1.3 + 16. Without this the
   unused capacity still costs its vertices (measured: ~7.8 ms, 8.8 M triangles submitted for
   nothing). No synchronous readback, ever.
6. Pack the parameter block into a `PackedByteArray` (std430, only vec4 / ivec4 / uvec4 members)
   and test its layout offsets.
7. **No GPU, no layer**: `RenderingServer.get_rendering_device()` is null in headless tests and the
   Compatibility renderer. Make the layer report `available()`, draw nothing, and let the LOD
   below it (impostors) cover the whole range. Test the reference and the parameter block; the
   compute itself needs a GPU run.
8. Verify on the real GPU: `FOREST_FULL_VERIFY=1 tools/screenshot.sh --windows` style env switch
   (remember `tools/screenshot.sh` forwards only variables listed in its `GODOT_WIN_ENV`), and
   `tools/perf.sh --only=<row> --windows` with a `perf_profile.gd` row that hides the layer.

## 4. LOD hand-over: exactly one of two draws every item

- Each item switches at **its own point of a band** around the range (`band_share`, a per-item
  phase from the hash), never at one distance: no visible wave.
- The decision is **one expression**, judged by the same quantity in both LODs (the impostor's own
  base distance), with the full LOD computing it in the compute pass and the far LOD in its vertex
  shader. Test that the two expressions are the same text.
- **The range follows the view, not a constant.** A fixed range puts the switch inside the picture
  (players saw it as items "being eaten" at the screen edge when panning). Use the distance to the
  ground along the top-corner / top-middle rays of the viewport (`RealScaleVegetation.
  far_view_distance_of`), x 1.1, clamped to [min, max], the same value for every species, and make
  the far LOD start at that same value. The cost then is the number of items really in range.
- Camera height gates the whole layer on and off with hysteresis (`LAYER_ON` / `LAYER_OFF`).

## 5. Streaming rings: a layer that rescans lazily must be built wider than it draws

`ChunkManager` rescans only after the target moved a quarter of the smallest build ring. If a
layer's build ring equals its draw range, chunks inside the range are missing between scans and
anything that depends on "nearest unbuilt chunk" (a `full_reach`-style cap) jumps about while the
camera pans – the far LOD flickers. Build ring >= range / (1 - RESCAN_FRACTION), in practice 1.5x.
A compute layer has no chunks and no such problem: prefer it when the layer follows the camera.

## 6. Ground height

Items stand on the **drawn** surface: `NearHeightCache` (near mesh heights as a texture,
`near_height.gdshaderinc`), falling back to the lattice. Placement decisions (does a cell hold an
item) read the lattice only, so they never depend on which near chunks are built. Bounds /
culling use the lattice span plus a slack for the difference.

## 7. Culling, shadows, bounds

- A compacted layer is a few big draws: set `custom_aabb` every frame around the camera window;
  culling is coarse, so cost is "items in range", not "items on screen". If that is too much, add
  frustum rejection to the compute pass **with a margin towards the sun** or shadows pop.
- Cheap tests first in any shader that derives an item (hash picks before any texture read).
- Burns / removals: a small uniform array (`MAX_BURNS`) read by both LODs and by the reference.

## 8. What to do for a new type

**Buildings** (few, unique geometry from map footprints): not scatter. CPU mesh per chunk is
justified; keep a far LOD as a cheap box / baked impostor with the same per-item band hand-over,
and the same range-follows-the-view rule. **Road furniture, fences, poles, rocks, debris** (many,
few models): compute compaction if a model is heavy, vertex-derived if it is a handful of
triangles. **Roads / rivers** are ribbons along polylines, not scatter: hash-placed items *along*
them (signs, poles) take their cell from distance-along-line instead of a grid, everything else in
this file still applies. In every case: write the GDScript reference first, test it, then the
shader; justify any CPU plan above ~20 ms in the task file (CLAUDE.md performance budget).

## 9. Checklist for a task that adds a layer

- [ ] Reference function + shader twin; constants and expressions checked by a test.
- [ ] Item count x vertices per candidate computed before choosing the technique.
- [ ] Hand-over band per item, one shared expression, range follows the view.
- [ ] Capacity worst case documented; draw count limited by async counts (compute layers).
- [ ] No-GPU fallback and a test that does not need a GPU.
- [ ] GPU run recorded: frame cost with `tools/perf.sh --windows`, the **in-forest-like worst
      case** (camera inside the densest content), not only an overview.
- [ ] Playtest steps: pan fast at the closest zoom, watch the screen edges for switches.

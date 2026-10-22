# TASK-060: Trees v3 – leaf-card crowns with trunks and branches, wind, per-instance variation

- **Status**: to playtest
- **Layers**: presentation (pure tree mesh builder + leaf/needle textures, pure species/variation picker, chunked `TreeField` node, `assets/shaders/foliage.gdshader`, `map_view.gd` scatter), optional CC0 textures in `assets/third_party/`, tests
- **Depends on**: **TASK-059**, **TASK-057** (soft: TASK-030 – `MeshKit.lathe`/`rod` for trunks and branches if done by then, otherwise the existing `ModelParts.lathe_mesh` or a local tapered rod; TASK-050 – `foliage`, `wind`, shadows per quality; TASK-053 done – only for the optional CC0 bark/leaf textures)
- **Model**: opus (leaf-card generation with correct normals for foliage lighting, LOD/visibility ranges per chunk, alpha-scissor shadows, performance)

## Goal

Forests look like real woodland: individual trees with visible trunks and branches, crowns made of many leaf clusters with soft, light-transmitting edges that move in the wind, and enough variation in shape and colour that no two neighbours look alike.

## Current state

`FoliageMeshes`: deciduous crowns = 5 lumpy icosphere lobes (subdivision 2 → 1 600 triangles), conifers = 4 stacked cones (40 triangles), one shared 6-sided trunk (12 triangles), baked AO in vertex colours, bent normals; uniform yellow-green instance colours (`DECIDUOUS_COLOR_A/B`, `CONIFER_COLOR_A/B` in `map_view.gd`); 2 variants each; no wind; one `MultiMeshInstance3D` per mesh type for the whole map (plus the thinned backdrop scatter outside the map). Instances are scaled by `VisualScale.tree_scale()` (balanced preset 1.8). On LOW (`foliage = false`) no trees are built at all.

## Decision (human, 2026-10-22)

- **Option A – procedural trees**: trunks and branches built in code (MeshKit-style lathe/rod geometry), crowns from alpha-scissor leaf cards.
- **Extension**: CC0 **bark** and **leaf-cluster / needle** textures from a CC0 set (Poly Haven, ambientCG, …) are allowed under ADR `docs/adr/0011-third-party-assets.md` – files in `assets/third_party/textures/…`, each credited in `assets/third_party/credits.json`, as TASK-053/055 did. If no suitable CC0 leaf or needle texture is found (an alpha-cut cluster that reads at 0.1 world units), fall back to the procedural `LeafTexture.cluster(size, seed)` (and a needle variant); bark likewise falls back to a procedural tint + vertex-colour striping.
- **Option B (CC0 glTF tree models) rejected**: photoreal CC0 models are far too heavy for thousands of MultiMesh instances; the light ones are stylised low-poly and clash with the realistic terrain, HDRI sky and water; a consistent Polish/Western-Russian species set would be hard to source.
- **Tree size**: unchanged – `VisualScale.tree_scale()` (balanced preset 1.8, TASK-059).
- **Species**: pine/spruce on high ground (today's conifer rule in `ScatterPlanner`), birch/oak/alder elsewhere; **at least 3 variants per species**.

## Design

- **Reuse from TASK-057**: the shared wind include `assets/shaders/wind.gdshaderinc` and its runtime global parameters (`src/presentation/wind.gd`, `Wind.setup(quality["wind"])`); the chunk + `visibility_range` + lazy build pattern of `src/presentation/grass_field.gd` (`GrassField`); the procedural-card approach of `src/presentation/grass_texture.gd` (neutral luminance card, hue from the instance colour, alpha 0/1 for scissor).
- **Species from the plan** – pure `TreeSpecies.pick(tree: Dictionary) -> Dictionary` (static, hash of the planned `position` and `k`, no RNG object): `conifer == true` → `pine` (60 %) or `spruce` (40 %); otherwise `birch` (35 %), `oak` (30 %), `alder` (35 %). Returns `{species: StringName, variant: int (0..VARIANTS-1), custom: Color}`. `ScatterPlanner` is **not** changed (placement, counts and the conifer rule stay; its tests stay unchanged).
- **Tree meshes** – pure `TreeMeshes` (cached like `FoliageMeshes`, deterministic from `(species, variant)`, base at y = 0, model space as today: crown top ≈ 0.25–0.3 before instance scale): one `ArrayMesh` per species/variant with **two surfaces** – surface 0 bark (trunk + branches), surface 1 leaves (cards) – so one MultiMesh draws a whole tree.
  - Trunk: tapered lathe/rod (6–8 sides), **closed at the top** inside the crown; branches: 3–6 main tapered rods (4–5 sides) from the upper trunk into the crown (deciduous), pine: bare trunk with a few short upper branches. Bark UV: u around, v along the height (tiling texture).
  - Deciduous crowns: **60–120 leaf cards** (quads 0.04–0.07 model units) placed on jittered lobe spheres around the branch tips (birch: narrow, drooping, high crown; oak: broad, wide, low; alder: oval), facing outward with random roll.
  - Conifers: **40–100 cards** as drooping skirts in whorls along the trunk (spruce: conical, down to ≈ 15 % of height; pine: flat-topped crown in the upper third) with the needle texture.
  - Card normals = from the crown centre radially outward (bent, as today) so crowns light as volumes; vertex colour: `r` = AO (darker inside / lower), `g` = per-card flutter phase in [0, 1), `b` = 1 on leaves, 0 on bark.
  - **LOD1** = today's lobed crown / cone stack per species shape (deciduous at icosphere subdivision 1, 3–5 lobes) + trunk, recoloured with the same instance custom data; one per species (variants optional).
- **Textures**: `LeafTexture.cluster(size, seed)` / `LeafTexture.needles(size, seed)` (pure, `Image` RGBA8 with mipmaps: overlapping leaf / needle silhouettes, alpha 0 or 1, neutral luminance – hue from the instance colour) used unless CC0 textures are added; CC0 candidates: an ambientCG / Poly Haven leaf set with an opacity map, pine/spruce needle cluster, oak/pine bark, birch bark (1K, within the 2048 px / 80 MB limits of `test_third_party_assets.gd`). CC0 albedo is desaturated to luminance on load (or in the shader) so the per-instance hue still works.
- **Foliage shader** `assets/shaders/foliage.gdshader` (`#include "res://assets/shaders/wind.gdshaderinc"`): alpha scissor 0.5, `cull_disabled` on the leaf surface, **back-lighting** (`BACKLIGHT` ≈ 0.35 × leaf colour), bent normals from the mesh, AO from vertex `r`; wind: whole-tree sway with `wind_offset(world_origin, h, phase)` (h = vertex height / tree height, so the existing 0.012 amplitude bends the top), plus a leaf flutter (≤ 0.003 world units, phase from vertex `g` + instance phase) added as a new function in the include **without changing `wind_offset`** (grass looks the same). Bark surface: same shader with flutter off (`b` = 0), or a second material.
- **Per-instance variation** (`INSTANCE_CUSTOM` = `custom` from `TreeSpecies.pick`): `r` = hue shift in [−0.03, 0.03], `g` = value × in [0.85, 1.1], `b` = saturation × in [0.9, 1.05], `a` = wind phase in [0, 1). Autumn odd tree: deciduous only, 1 in 25 (hash < 0.04), hue shift in [0.04, 0.07] towards yellow – starting values, tune on screenshots. Base leaf colours per species replace `DECIDUOUS_COLOR_A/B`, `CONIFER_COLOR_A/B` (pine/spruce darker and bluer, birch lighter yellow-green, oak/alder mid green).
- **Chunks + LOD** – `TreeField` node like `GrassField`: trees (map and backdrop scatter) grouped into **8 × 8-unit chunks**, one `MultiMeshInstance3D` per chunk × species × variant × LOD that has instances (none for empty combinations), node origin at the chunk centre; built at `MapView.build()` (trees are few; no lazy build needed unless the budget below is missed). LOD0 (cards): `visibility_range_end = 30`, `visibility_range_end_margin = 4`; LOD1: `visibility_range_begin = 30`, `visibility_range_begin_margin = 4`; `visibility_range_fade_mode = FADE_SELF` on both. Note: the playable map is 12 × 10 hexes (≈ 21 × 15 units), so at zoom-in most of it is LOD0; LOD1 is mainly the backdrop and the far zoom.
- **Shadows**: both LODs cast shadows (alpha-scissor shadows for LOD0 – the shader writes `ALPHA_SCISSOR_THRESHOLD`, so shadows are leafy). LOW builds no trees (`foliage = false`) – unchanged.
- **Performance budget**:
  - per tree: **LOD0 ≤ 400 triangles** (bark ≤ 160 + cards ≤ 120 × 2); **LOD1 ≤ 250 triangles** and ≤ 60 % of the same species' LOD0 average;
  - total: the LOD0 triangles of all instances in chunks whose centre lies within **41 units** (30 + margin 4 + `CameraMath.MIN_DISTANCE` 7) of any playable tile centre ≤ **800 000** (worst case at full zoom-in; shadows draw it a second time). If exceeded: fewer cards first, then fewer backdrop trees in LOD0;
  - FPS on the Windows build at full zoom-in over the largest forest, before vs. after (see criteria).
- Bushes and rocks keep `FoliageMeshes` (bushes are TASK-061).

## Acceptance criteria (testable)

- [ ] `tests/unit/test_tree_meshes.gd` (for every species × variant 0..2):
  - deterministic: building the same `(species, variant)` twice gives identical vertex arrays; variant 0 ≠ variant 1 ≠ variant 2 (vertex arrays differ); at least 3 variants per species (`TreeMeshes.VARIANTS >= 3`) for `pine`, `spruce`, `birch`, `oak`, `alder`;
  - 2 surfaces (bark, leaves); leaf card count: deciduous in [60, 120], conifer in [40, 100] (cards = leaf triangles / 2); card sizes in [0.04, 0.07] model units;
  - outward normals: for ≥ 95 % of leaf vertices `dot(normal, vertex − crown_centre) > 0`; all normals unit length (±1e-3);
  - trunk closed under the crown: the bark surface's top cap exists (the trunk's highest ring has a centre vertex / cap triangles) and the trunk top lies below the crown's top and above the crown's lowest card;
  - base at y = 0 (min y of the bark surface in [−0.001, 0.001]); model-space AABB height in [0.2, 0.35];
  - vertex colours: `r` (AO) in [0, 1], `g` (phase) in [0, 1), `b` = 1 on every leaf vertex and 0 on every bark vertex;
  - triangle budget: LOD0 ≤ 400 triangles per mesh; LOD1 ≤ 250 and ≤ 0.6 × the species' LOD0 average.
- [ ] `tests/unit/test_tree_species.gd`:
  - `TreeSpecies.pick` is deterministic for the same tree dictionary; conifer trees get only `pine`/`spruce`, the others only `birch`/`oak`/`alder`;
  - over the default map's scatter plan (`ScatterPlanner.plan(..., MapView.SCATTER_SEED)`) every species and every variant 0..2 occurs; shares within ±10 percentage points of the design values;
  - custom data ranges: `r` in [−0.03, 0.03] or (autumn, deciduous only) in [0.04, 0.07]; `g` in [0.85, 1.1]; `b` in [0.9, 1.05]; `a` in [0, 1); autumn share of deciduous trees 4 % ± 2 %; no conifer is autumn.
- [ ] `tests/unit/test_tree_field.gd` (or in the map view tests):
  - instance bounds follow `VisualScale.tree_scale()`: with `VisualScale.apply_values({"tree_scale": 1.0})` vs. 1.8, the world AABB height of the same planned tree scales by 1.8 (±1 %), positions unchanged; `VisualScale.reset()` afterwards;
  - every LOD0 instance node: `visibility_range_end == 30`, `visibility_range_end_margin == 4`, `visibility_range_begin == 0`; every LOD1 node: `visibility_range_begin == 30`, `visibility_range_begin_margin == 4`; both `FADE_SELF`; both cast shadows;
  - each chunk node's origin is its chunk centre and all its instances lie inside the 8 × 8 chunk;
  - the total instance count (all chunks, LOD0 only) equals the planned tree count (map + backdrop scatter) – no tree lost or duplicated; the same for LOD1;
  - with `foliage = false` no tree nodes are created;
  - total LOD0 budget: the maximum over playable tile centres of the LOD0 triangles within 41 units ≤ 800 000 on the default map (the value logged and noted).
- [ ] Wind: with quality `wind = false`, `Wind.strength() == 0` after `MapView.build()` (existing check still passes); `foliage.gdshader` loads and compiles (shader load test like grass); `wind_offset` in `wind.gdshaderinc` unchanged (grass unaffected).
- [ ] `tests/unit/test_scatter_planner.gd` passes **unchanged** (no edits to the file).
- [ ] If CC0 textures are added: each file listed in `assets/third_party/credits.json` (`kind: "textures"`, CC0-1.0, source URL, author, notes naming TASK-060 and the renames) and `test_third_party_assets.gd` passes (manifest = files on disk, ≤ 2048 px, total ≤ 80 MB). If not: `LeafTexture.cluster` / `needles` are deterministic per seed, return RGBA8 with mipmaps, alpha only 0 or 1, coverage (alpha = 1 share) in [0.35, 0.75] – tested; implementation notes say which path was taken and why.
- [ ] FPS measurement: `tools/screenshot.gd` gains an opt-in frame-time probe (e.g. `SCREENSHOT_MEASURE_FRAMES=N` → prints `Frame time: avg X ms, max Y ms over N frames` after the warm-up). Measured on the Windows build (`tools/screenshot.sh --windows`) at full zoom-in (`CameraMath.MIN_DISTANCE`) over the largest forest, **before** (the parent commit) and **after**; both numbers in the implementation notes. Target: after ≤ 1.25 × before average frame time; if worse, reduce cards and note it.
- [ ] Agent visual check (Windows build) close-up and default framing: trunks visible under crowns, ragged leafy silhouettes against the sky (TASK-052 camera), light shining through crown edges, conifers and deciduous species distinguishable, a few yellower trees, no obvious LOD pop (compare the edge of the 30-unit range), leafy (not solid-blob) shadows.
- [ ] `docs/ARCHITECTURE.md`: "Grass and wind" section extended (or a "Trees" section) with the tree field, LOD ranges, species picker and budget.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it, commit it with the change.

## Playtest (for the human)

1. Zoom in on a forest: trunks and branches visible, crowns made of leaf clusters, edges soft and slightly see-through against the sky.
2. Watch: leaves flutter and trees sway a little, not in sync.
3. Neighbouring trees differ in shape and shade; birches, oaks and alders recognisable in the lowlands, pines and spruces on high ground; a few slightly yellower deciduous trees.
4. Zoom out: no visible switch between the detailed and the simple trees.
5. Frame rate over the largest forest at full zoom-in (Windows) compared with before; `tools/run.sh` (LOW): no trees, no slowdown (unchanged).
6. Units at forest edges and inside forests: as readable as before (balanced preset).

## Player manual

None (presentation only; forest rules unchanged). If the new crowns make units in forests noticeably harder to see than with the TASK-059 balanced preset, add a note to docs/MANUAL.md (via `game-designer`) and record it in the GDD's open questions (occlusion silhouette follow-up).

## Out of scope

- Undergrowth / forest edges and the bush mesh (TASK-061), falling leaves, destructible trees, seasons.
- glTF tree models (option B, rejected), impostors / billboards for the far LOD, GPU-driven culling.
- Changes to `ScatterPlanner` placement, counts or the conifer rule.

## Implementation notes

- **Textures: procedural path** (`LeafTexture.cluster` / `LeafTexture.needles`, 128 px, RGBA8 with mipmaps, alpha 0/1, neutral grey, coverage ~0.39 / ~0.41; bark is a procedural tint + streaks in the shader, birch light with dark marks). No CC0 files were added, so `assets/third_party/credits.json` is unchanged. Why: the cards are 6-15 px on screen at full zoom-in, so a photographic cluster adds nothing a procedural silhouette doesn't; the procedural card is neutral luminance by construction (the per-instance hue works without a desaturation pass), deterministic, tested, and needs no download / licence bookkeeping. CC0 bark/leaf sets can still be swapped in later behind `TreeField.leaf_texture`.
- **New code**: `src/presentation/tree_species.gd` (`TreeSpecies.pick`), `tree_meshes.gd` (`TreeMeshes.lod0/lod1/shape/triangle_count`, 3 variants per species), `leaf_texture.gd`, `tree_field.gd` (`TreeField`, chunked MultiMeshes), `assets/shaders/foliage.gdshader`; `wind.gdshaderinc` gained `wind_flutter` (`wind_offset` untouched, tested). `MapView` hands the map + backdrop tree plans to its `TreeField` (`MapView.trees()`); bushes and rocks keep `FoliageMeshes`; `DECIDUOUS_COLOR_*`, `CONIFER_COLOR_*`, `TRUNK_COLOR` are replaced by per-species `TreeField.LEAF_COLORS` / `BARK_COLORS`. Trunks/branches use a local tapered lathe/rod (indexed, own vertex colours) rather than MeshKit.
- **Triangles** (LOD0 average per species / LOD1): pine 230 / 26, spruce 230 / 42, birch 265 / 155, oak 341 / 155, alder 301 / 155 (all LOD0 meshes <= 400, LOD1 <= 0.6 x LOD0 average). Cards: birch 84, oak 110, alder 96, spruce 94, pine 64. The LOD1 deciduous crowns are 3 lobes at icosphere subdivision 1 with the triangles hidden inside another lobe dropped (3 full lobes would be 240 triangles, over the 0.6 x LOD0 rule).
- **LOD0 budget**: default map 4402 trees (1179 map, 3223 backdrop). With every backdrop tree in LOD0 the worst tile would see ~1.25 M LOD0 triangles, so backdrop trees more than `TreeField.BACKDROP_LOD0_REACH` = 14 units outside the playable tiles (1816 trees) get only an always-on LOD1 "far" node. Worst tile now: **702 333** LOD0 triangles within 41 units (<= 800 000, `test_tree_field.gd` prints it). Consequence for the tests: "LOD0 instances + far = planned" and "LOD1 instances + far = planned" instead of LOD0/LOD1 = planned.
- **Frame time** (Windows build, Radeon RX 580, HIGH, 1280x720, `SCREENSHOT_FOCUS=14.72,4.5,0,7` = full zoom-in over the largest forest at tile (7, 3), `SCREENSHOT_MEASURE_FRAMES=300`, vsync off): **before** (parent state) avg 34.9 / 35.3 ms (max ~57 ms); **after** avg 23.2 / 23.2 ms (max 43-47 ms). Faster than before (the old deciduous crowns were 1 600 triangles each), well inside the 1.25x target.
- **Screenshot tool**: `tools/screenshot.gd` gained `SCREENSHOT_MEASURE_FRAMES=N` (frame-time probe after the warm-up, vsync off) and `SCREENSHOT_FOCUS=<x>,<z>,<yaw>,<distance>` (camera on a world point, `BattleController.debug_focus_point`); parsing in `tools/screenshot_options.gd`, tested.
- **Visual check** (agent, Windows build): close-up over the forest, default framing and a low tilted shot: trunks visible under the crowns (white birch trunks, reddish pine trunks), ragged card crowns, spruce and pine clearly different from the deciduous trees, a few yellower trees, units in and next to forests still readable. The LOD1 backdrop crowns read a touch lighter / rounder than LOD0 at the 30-unit seam; `SOLID_LUMINANCE_FACTOR` was tuned from 0.82 to 0.68 to bring them closer. Light-through (backlight) and the leafy shadows were not isolated in a still – check them in the game. Wind and flutter cannot be seen in a still.
- **Not done here**: committing (`docs/images/gameplay.png` is re-rendered and looks good, commit it with the change). No MANUAL / GDD change: units in forests read as well as with the TASK-059 balanced preset in the screenshots.
- **Playtest** (human): (1) zoom in fully over the big forest east of the river: trunks and branches under crowns of leaf clusters, needle whorls on spruces, flat-topped pines; (2) watch a few seconds: trees sway slightly out of sync, leaves flutter; (3) neighbours differ in shape and shade, an occasional yellower deciduous tree; (4) zoom out slowly from 7 to ~30: no obvious pop when chunks switch from cards to the simple crowns (30 units from the camera) – the LOD1 crowns may look slightly lighter / smoother; (5) pan to the map edge: backdrop trees 14+ units beyond the map are always simple; (6) look for leafy (not blob) shadows on the ground and light shining through crown edges against the sun; (7) `tools/run.sh` (LOW): no trees, no slowdown; (8) frame rate at full zoom-in over the forest vs. before (measured 35 -> 23 ms here).

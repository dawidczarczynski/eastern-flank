# TASK-028: Foliage v2 – lobed crowns with baked AO, bush layer, better rocks

- **Status**: ready
- **Layers**: presentation (pure geometry builder and planner rules tested in `tests/unit/`)
- **Depends on**: TASK-018 (scatter), soft: TASK-026, TASK-027. Reference: `docs/design/v2/game_screen.scene.js` lines 380–403 (`foliageGeo`), 404–412 (`rockGeo`), 562–596 (bushes, instancing, colours).
- **Model**: sonnet

## Goal

Forests read as dense canopies of individual, shaded trees instead of green balls and cones. Crowns are darker inside and at the bottom, and low bushes fill the gaps between trunks and on open plains.

## Design → Godot

- New pure builder `src/presentation/foliage_meshes.gd` (`class_name FoliageMeshes`, static), returning `ArrayMesh`es built with `SurfaceTool`, cached in a static var:
  - `deciduous(variant: int)`: five icosphere lobes `[x, y, z, r]` = `[0, .15, 0, .072]`, `[.042, .13, .02, .054]`, `[−.036, .135, .03, .054]`, `[.01, .128, −.045, .054]`, `[−.01, .198, .004, .05]`, each subdivided twice, every vertex scaled by `1 + (hash(vertex, lobe, variant) − 0.5)·0.4`. Godot has no icosphere primitive: generate it (icosahedron + 2 subdivisions) or use a `SphereMesh` with low radial segments – the lumpy silhouette matters, not the exact topology.
  - `conifer(variant: int)`: four stacked cones `i = 0..3`, radius `0.085 − 0.018·i`, height `0.12 − 0.012·i`, base at `0.08 + 0.052·i`, 10 sides; the skirt vertices of each cone are pushed out by `1 + (hash(side, i, variant) − 0.5)·0.5` (jagged branch tips).
  - For both: **bent normals** – `n = normalize(0.75·radial + 0.25·face_normal)`, radial measured from the crown centre (`y = 0.15` deciduous / `0.16` conifer, conifer's radial y squashed ×0.4 and lifted 0.04). **Baked AO in vertex colours**: `ao = 0.5 + 0.5·smooth(0.06, 0.24, y)·(0.7 + 0.3·hash)`, light jitter `lh = 0.85 + 0.3·hash`, colour `(ao·lh, ao·lh, ao)`.
  - `bush()` = `deciduous(3)`; `trunk()` = cylinder r 0.008 → 0.014, height 0.12, 6 sides, base at y 0; `rock()` = icosahedron (1 subdivision) radius 0.05 with vertices scaled 0.75–1.25, flat shaded.
- **Instancing** (`map_view.gd`, `_build_scatter`): two variants per crown type, chosen by `k < 0.5`. Instance colours multiply the baked vertex colour: conifers `#2c4626 → #40603a` by `k`, deciduous `#41602c → #72853a`, bushes `#3f5a28 → #6f7a38`, rocks `#7d776a → #9a958a`. Verify that `MultiMesh` instance colour and vertex colour are multiplied with a `StandardMaterial3D` (`vertex_color_use_as_albedo`); if not, use a small `ShaderMaterial` (`ALBEDO = COLOR.rgb * INSTANCE_CUSTOM…` or equivalent) and note it.
- **Bushes** in `ScatterPlanner`: forest tiles 8, plains tiles 2 per tile; position `angle = hash·2π`, `r = sqrt(hash)·0.92` from the tile centre; scale `s = 0.28 + hash·0.25`; skip when the ground height < `MIN_TREE_GROUND`; sink `0.06·s`, y-scale `0.6·s`. Same deterministic view-local RNG / hash rules as the existing trees.
- Shadows: crowns and bushes cast shadows (bushes may have casting off if the shadow pass gets expensive – note it).

## Acceptance criteria (testable)

- [ ] `tests/unit/test_foliage_meshes.gd`: each mesh is deterministic (same vertex arrays on two builds), variants 0 and 1 differ; deciduous bounds lie within x/z ±0.13 and y [0.05, 0.27]; conifer bounds y [0.08, 0.36]; all normals unit length and `dot(normal, vertex − centre) > 0` for ≥ 95 % of vertices; all vertex colours within [0.35, 1.15] and the mean brightness of vertices with `y < 0.1` is lower than of vertices with `y > 0.2`.
- [ ] `test_scatter_planner.gd`: bush counts per tile (forest ≤ 8, plains ≤ 2, none on hills/water), all inside radius 0.92 of their tile centre, scales in [0.28, 0.53], deterministic for a seed.
- [ ] Existing scatter tests pass (tree counts and positions unchanged – only the meshes change).
- [ ] Agent visual check: default screenshot, compare with `docs/design/v2/shots/01-v2-zoom.jpg`: crowns have visible lobes and a dark underside, forests look dense, bushes are visible on plains. Note the draw-call / instance counts if the profiler is available.

## Playtest (for the human)

1. Zoom into a forest: deciduous trees are lumpy, conifers have jagged tiers; the lower parts of the crowns are clearly darker.
2. Plains have a few low bushes; forest floors have bushes between the trunks.
3. Rotate the camera around a forest: no flickering or obviously identical trees side by side.
4. Check the frame rate at full zoom-out over the largest forest.

## Out of scope

- Wind animation, LODs/impostors, grass.

## Implementation notes

_Filled in by the agent when done._

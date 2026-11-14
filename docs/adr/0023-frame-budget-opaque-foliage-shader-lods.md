# ADR 0023: Frame budget – opaque foliage, LOD switch in the shader, mesh LODs for units

- **Status**: accepted
- **Date**: 2026-11-14
- **Task**: none (performance pass asked for by the human)

## Context

The default battle ran at about 27 ms a frame (ADR 0022) at 1920×1080 on the target GPU (RX 580, HIGH, D3D12 Forward+, 4x MSAA), against a budget of 16.6 ms (60 FPS). `tools/perf.sh` (new) times the frame with one part of the picture switched off at a time. What it showed:

| Part | Cost | Cause |
|---|---|---|
| Tree / bush LOD cross-fade | ~5.6 ms | `VISIBILITY_RANGE_FADE_SELF`: Godot draws a fading instance alpha-blended, in the alpha pass without the depth prepass, so every layer of every tree in the band was lit |
| Near trees (leaf cards) | ~1.6 ms | alpha antialiasing (alpha to coverage) puts the whole mesh into the alpha pass too |
| Bushes | ~1.8 ms | the 1 600-triangle near mesh out to 28 units |
| Terrain texturing | ~3.5 ms | 3 anisotropic fetches per layer and scale, for every layer with a weight |
| Units | ~2.6 ms | ~36 k unshared triangles per model at any distance; the camo shader runs for every sub-pixel triangle |

## Decision

1. **Nothing in the scenery uses Godot's visibility-range fade.** Trees hand over between LODs per tree in the vertex shader: each LOD's material has the bands `lod_in` / `lod_out` (`TreeField.lod_bands`), a tree switches at its own random point of the band and the LOD that does not draw it collapses it to a point. Node visibility ranges only cull chunks (`RANGE_SLACK` wider than the bands). Bushes switch hard at 16 units (the two meshes differ by one subdivision of a blob a dozen pixels wide).
2. **Foliage stays in the opaque pass.** Distant trees use `foliage_solid.gdshader` (no `ALPHA` at all); the leaf cards of LOD0 use the alpha scissor alone, without alpha antialiasing. Both shaders share `foliage_body.gdshaderinc`.
3. **A terrain sample is two fetches, and only for layers that show.** `TerrainTextures` packs normal x, y + roughness + AO into one array (`normal_rough_ao`, z rebuilt in the shader, trilinear; the albedo keeps anisotropic filtering). The shader first reads albedo / height of the weighted layers, then the detail array only for layers that survive the height blending, and skips the anti-tiling scale that does not show. The result is the same picture.
4. **Unit meshes get automatic LODs** (`MeshLods`, applied to every model prototype in `ModelParts.cached`): surfaces are indexed and run through `ImporterMesh.generate_lods`, the renderer picks the level per instance. Costs 65–160 ms per model kind at the first build.
5. **SSIL runs at its lowest quality** (`rendering/environment/ssil/quality=0`): at intensity 0.6 and half resolution the difference does not show; 0.64 ms.

## Consequences

- 27 ms -> 16.5 ms a frame in the default battle overview (1 929 draws, 3.95 M triangles; GPU 15.9 ms). That is at the budget, not under it with a margin: larger maps (Suwałki) and close-ups still need measuring.
- Leaf card edges are no longer smoothed by alpha to coverage; in exchange the near trees receive SSAO. Screenshots before / after show no visible difference at game distances; shimmer in motion has to be judged in the game.
- A new alpha-tested or fading material must be checked with `tools/perf.sh`: anything with `ALPHA` (without a plain scissor) or a range fade leaves the depth prepass.
- The packed texture cache format changed (`TerrainTextures.CACHE_VERSION` 2): the first start repacks the ground textures (~2.5 s); the arrays take a third less memory (~56 MB instead of ~84 MB).
- What is left, by cost: terrain 3.3 ms, trees 3.3 ms, sun shadows 3.2 ms (PCSS 1.2, four splits 1.0), MSAA 3.2 ms, units 1.8 ms (the camo shader on small triangles – a merged far model would be the next step), SSIL 0.9 ms.

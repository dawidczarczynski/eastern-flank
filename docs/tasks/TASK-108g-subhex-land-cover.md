# TASK-108g: Real-terrain look – visuals from a sub-hex land-cover raster (hexes are mechanics only)

- **Status**: done
- **Layers**: tools (`tools/import_map.py`) + data (`TacticalChunk`, `TacticalLayer`) + presentation (new `LandCover` reader, `TerrainSplat`, `ScatterPlanner`, `GrassPlanner`, `FieldParcels`, `TerrainGround`, `MapView`) + docs (ADR, ARCHITECTURE)
- **Depends on**: TASK-108 (done), TASK-094b (tactical layer, done); precedes TASK-108d, TASK-108f follow-up
- **Model**: opus (data format + importer), sonnet for the planners
- **Topic**: Two-layer game

## Goal

Human decision: "I don't want hexes to define the look of the map. The map should be as natural and realistic as possible, only divided into hexes for the game mechanics." Today the importer rasterises OSM land use **into hex tiles** (one `Terrain.Type` per hex, majority rule) and the view reads that type back to paint ground, plant trees and grass. So forest ends on hex borders, bare patches are hex-shaped, villages are hex-shaped. Fix the data flow so it is one-way:

```
real data (OSM areas / lines, metres) -> land-cover raster (10-20 m / px)
        |-> look: ground splat, trees, grass, parcels, houses, roads
        '-> per-hex aggregate (dominant type + shares) -> rules only
```

`Terrain.Type` of a hex stays what the rules use (cover, move cost) and stays derived by majority; the view must not read it for appearance.

## Findings (where the view still reads the hex type)

- `terrain_splat.gd` `weights(terrain, ...)` – ground layers per vertex from the hex type.
- `scatter_planner.gd` (l. 96-240) – tree / bush / rock density and species per hex type; forest edge = hex edge.
- `grass_planner.gd` (l. 140-435) – grass height, thinning, forest-edge test via `grid.get_terrain(n)`.
- `field_parcels.gd` (l. 148, 259-276) – the FIELDS test per hex (already spills over neighbours, but source is still hex type).
- `backdrop_types.gd`, `map_view.gd` (l. 496-521) – backdrop copies hex types.
- Importer (`tools/import_map.py`): OSM polygons are reduced to one class per hex; the sub-hex geometry is discarded, so the view cannot recover it. A new plane is needed.

## Design

- **Importer**: per tactical chunk also write a `cover` raster (uint8 class per cell, 16 m cells, same extent as the hex chunk, classes: field A, grass G, forest F, water W, urban U, marsh M, orchard / scrub, bare, plus a separate byte for road / building density if cheap). Same OSM tiles and tag table as today (`_TAG_CLASSES`, `lu1`), no new downloads. Hex type = majority of the cell classes in that hex (must reproduce today's types except at ties; test on Suwałki).
- **`LandCover`** (pure, `src/presentation/` or `src/core/data/`): `class_at(x, z)`, `share_in(rect)`, bilinear "weight of class c at (x, z)" for soft edges. Map built from the layer cut; generated / default maps (no raster) get a fallback that expands the hex types (look unchanged).
- Planners take `LandCover` instead of `Terrain.Type` for appearance: forest density from the cover weight with a noisy soft edge (no hex edge), grass and splat likewise, parcels where cover = field, houses (108d) where cover = urban, backdrop from the raster beyond the cut.
- The hex grid overlay is drawn thin and translucent, fades out unless selected / reach / `G`; it must not tint the ground.
- Determinism: no `GameState.rng`; integer hashes as in 108f. Rules, commands and saves unchanged.

## Acceptance criteria (testable)

- [ ] `import_map.py` writes the cover plane; per-hex majority equals the previous hex types on the Suwałki fixture (diff reported, ties only).
- [ ] `LandCover` tests: class lookup, share in rect, soft weight is continuous across a hex border of one class.
- [ ] A forest region that covers a hex only partly gets trees only on the covered part (planner test with a synthetic raster).
- [ ] No appearance code in `terrain_splat`, `scatter_planner`, `grass_planner`, `field_parcels` calls `grid.get_terrain` when a raster exists (grep check in a test).
- [ ] Maps without a raster look pixel-identical to today.
- [ ] Chunk file size and load time recorded; frame budget on Suwałki not worse than today.
- [ ] ADR "Sub-hex land cover; hexes are mechanics only" + ARCHITECTURE updated.

## Carried over from TASK-072b

- The farmland parcel texture still covers the whole map (~72 MB at 16x). Replace it with a windowed texture / analytic planner query per chunk as part of the land-cover plane, so static memory stops growing with map area.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle`, grid off (`G`): forest edges, fields, villages and meadows follow natural outlines and cross hex borders; no hex-shaped patches anywhere.
2. Grid on: lines only, no change of ground colour inside a hex.
3. Pan to the map edge: backdrop continues the same land cover.

## Implementation notes

### Data half (done 2026-11-22; ADR 0028)

- **Importer** (`tools/import_map.py`): tactical maps and the tactical layer keep a 16 m land-cover raster (`--cover-cell`, 0 = none). Codes `LAND_COVER = ".GAUFMWOSB"`: 0-6 are the old cover classes, plus 7 orchard / vineyard / nursery, 8 scrub / heath, 9 bare (quarry, landfill, brownfield). They are sub-classes of fields / grass in every rule (`fold_counts`); overlaps resolve by `LAND_COVER_PRIORITY`, so the parents win as before. Same OSM tiles and tag table, no new downloads. There is no road / building density byte: the op1 / lu1 inputs have no minor roads and no buildings. The hex type is `classify` on the counts of the cells inside the hex (`cell_counts`, whole row runs). Heights still come from the DEM sample points. On the layer, the sea is flood-filled on the 50 m lattice and copied into the raster (`_fill_sea_coarse`).
  - `ImportedMap`: `land_cover*` fields (whole raster, zlib).
  - `TacticalLayer`: raster geometry in `layer.tres`. Each `TacticalChunk` has its own non-overlapping window (`cover*`, `cover_windows`).
- **Hex types vs the old import**:
  - `suwalki.tres` (30 x 24): 20 of 720 hexes changed (2.8 %). Every one is within ~0.05 of a classify threshold: 50 / 50 forest, 0.20 urban, 0.25 marsh, fields vs plains. That is 11 forest / water changes and 9 among the open types. `test_imported_map` lists them.
  - Synthetic sample map: unchanged.
  - Tactical layer: 67 969 of 1 764 560 hexes changed (3.85 %). The old layer counted only ~25 points on a 50 m lattice per hex, the new one ~212 cells. Biggest flows: F->P 8 850, A->P 8 213, P->A 7 881, U->P 7 644, P->F 6 896, P->U 4 064.
- **Sizes and times** (WSL, 4 cores):

  | | before | after |
  |---|---|---|
  | `suwalki_tactical/` | 3.44 MB, median chunk ~28 KB | 28.1 MB, median chunk 251 KB, max 451 KB |
  | Chunk `.tres` load | 20 ms | 41 ms |
  | `decode()` | 0.25 ms | 0.25 ms (unchanged) |
  | `decode_cover()` | – | 5.6 ms |
  | `find` + `region_grid` of a 40 x 30 cut | 51 ms | 96 ms |
  | `region_land_cover` (+10 units margin, 815 x 593 cells) | – | 17 ms |
  | Layer import (offline) | ~9 min | 15.4 min, 1.34 GB peak RSS |
  | `suwalki.tres` | 16 KB | 34 KB |

- **`LandCover`** (`src/core/data/land_cover.gd`, pure): `for_map`, `from_imported`, `from_cells`, `from_grid` (fallback), `class_at`, `share_in` / `shares_in`, `weight` / `weights_at` (bilinear), `cells`, `world_rect`, `has_raster`, `kind_of_terrain`, `PARENT`. Layer cut: `TacticalLayer.region_land_cover(region, margin)`. Old data without a raster loads and gets the fallback. Tests: `tests/unit/test_land_cover.gd` and the Python `LandCoverRasterTest`, plus `TacticalLayerTest.test_the_chunks_tile_the_land_cover_raster`.
- Open for the presentation half: planners / splat / parcels / backdrop switch to `LandCover`, the grep test, pixel-identical no-raster maps, the frame budget, the farmland texture carry-over, and the playtest.

### Presentation half (2026-11-22)

- **Source**: `BattleCover.for_battle` (new) picks the battle's map (setup or scenario name; GameState has no map id) and calls `LandCover.for_map` with a margin of `MapView.EXTENT + BACKDROP_WIDTH + 2`; BattleController sets `MapView.land_cover` before `build`. `CoverLook.make` (new, `src/presentation/cover_look.gd`) returns null for the fallback cover, and every consumer takes `look: CoverLook = null` – null keeps the old hex-type code path unchanged.
- **CoverLook**: `terrain_at` (Kind -> the Terrain.Type whose look it shows; orchard / scrub / bare -> plains), `is_forest` / `forest_k` / `has_kind` (bilinear weight between cell centres + a two-octave integer-hash value noise, cut at 0.5, so edges wander by up to half a cell and interiors never change), beyond the raster: open land (no stretched edge cells; Suwałki's raster covers the map only).
- **Consumers on the raster path** (none reads `grid.get_terrain`; `test_cover_look` greps the `_cover` functions):
  - Ground splat: `TerrainChunks.vertex_attributes` takes the type from `look.terrain_at(vertex)` (no hex jitter), also in the off-map margin; TerrainNear interpolates it. `MapView._grass_color` likewise.
  - Scatter: `ScatterPlanner._plan_cover` – per tile, fixed draws spread uniformly over the hex, the cover at each candidate decides (trees on forest, ~2 per hex on open land, none on villages / water; bushes, ground cover; edge shrubs and young trees where the forest test flips within `COVER_EDGE_REACH`; meadow thickets on open ground; rocks on slopes > `COVER_ROCK_SLOPE` instead of the hills type). `FoliageChunks.is_forest` reads the cover.
  - Grass: `GrassPlanner` clump / flower type from `_terrain_cover`, nettle band from `_near_forest_cover`, the slope limit on all steep ground (no hills type in the cover). GrassField and GrassNear pass the look.
  - Farmland: `FieldParcels` votes on FIELD cover (`_field_share_cover`); the outline clip is not baked but per point – `ParcelMap.look` (kind_at = NONE off the noisy FIELD outline) and `terrain.gdshader` (`cover_on`, raw Kind codes as an R8 texture, `in_field_cover` = the GLSL twin of `has_kind`, same hashes via forest_hash.gdshaderinc). Baking the clip into the 5 m image cost 4-8 s.
  - Real-scale forest: `LandCoverForestMaskSource` (new ForestMaskSource: soft forest value on a ~1-cell lattice, resized bilinearly, cut at 0.5 by ForestFill and the impostor shader), `ForestShell` cover from `forest_k`.
  - Backdrop: `BackdropTypes.shares_at` / `forest_at` / `ring_type` continue the raster beyond the cut where it reaches, else the border tiles as before. The backdrop vertex callbacks moved from MapView into BackdropTypes (`backdrop_vertex`, `canopy_vertex`) to keep map_view.gd under the 1000-line limit.
- **Grid overlay**: already lines only (unshaded, alpha by camera distance, `G` toggles); no change. The hex-shaped flat grey-green patches still visible on Suwałki are the water plane over the hex-shaped water / marsh depressions of TerrainSurface (heights from the hex types) – not part of this task.
- **Not done**: (1) the ground splat is per terrain vertex (36 m, smoothed), not an R8 texture in the shader – the vertex weights are also read by the backdrop canopy, motion effects, the grass colour and TerrainNear, so the switch is a separate shader task; the field outline does use the texture. (2) The ~72 MB whole-map parcel texture stays: parcels vote per 150 m strip piece with gap bridging (non-local), and all terrain chunks share one material, so a windowed texture needs per-chunk materials – left for a follow-up.
- **Costs** (WSL, RX 580, HIGH, Suwałki readme camera, 300 frames): without cover 15.56 ms avg / GPU 15.10 ms / 8.53 M tris; with cover 15.65 ms / GPU 15.14 ms / 8.08 M tris (first try with 48 edge draws per hex was +0.7 ms GPU, cut to 32). Build (headless, whole map): cover cut 4 ms (Suwałki) / 346 ms (contact cut, 1031 x 810 cells); parcels 60-93 ms (hex path 93-144 ms); scatter planning (all chunks, worker threads) 1.8 s vs 0.8-1.1 s; true-size forest mask 1.2-1.3 s vs 0.1 s (main thread, `true` preset only).
- **Pixel identity without a raster**: generated default battle before / after differ at the run-to-run noise level (63 k pixels > 0, 34 > 8/255 vs 29 k / 31 between two after-runs).
- Tests: `tests/unit/test_cover_look.gd` (partial-hex forest, density ratios, edge plants on the outline, determinism, grass ratio, parcels clipped, forest mask, backdrop, off-raster, shader constants, grep check).

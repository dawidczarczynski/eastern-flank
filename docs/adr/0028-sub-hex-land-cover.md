# ADR 0028: Sub-hex land cover; hexes are mechanics only

- **Status**: accepted
- **Date**: 2026-11-22
- **Task**: TASK-108g (builds on ADR 0018 maps from real geography / tactical layer, ADR 0019 real terrain types)

## Context

The importer rasterised the OpenStreetMap areas onto a sample lattice (25 m for tactical maps, 50 m for the theatre's tactical layer), reduced them to **one `Terrain.Type` per hex** and threw the lattice away. The view could only read that hex type back, so everything it painted (ground splat, trees, grass, field parcels, the backdrop) followed hex borders: forests ended in hex edges, bare patches and villages were hex-shaped. The human's decision: the map should look as natural as the real ground; hexes exist only for the game mechanics.

## Decision

1. **One-way data flow.** Real data (OSM areas, metres) -> a **land-cover raster** of 16 m cells -> (a) the look and (b) the per-hex aggregate for the rules. Nothing goes back from the hex type to the look on maps that have a raster.
2. **The raster is part of the map data.** `tools/import_map.py` keeps the rasterised areas as one byte per cell (`LAND_COVER` codes: 0-6 the old cover classes open / grass / fields / urban / forest / marsh / water, plus 7 orchard, 8 scrub / heath, 9 bare ground). Same OSM inputs and tag table as before (no new downloads); the three new classes are finer kinds of open ground that count as their parent (fields, grass, grass) in every rule, and overlapping areas keep the class later in `LAND_COVER_PRIORITY` (the old priority with the sub-classes right after their parent), so the parents win exactly as before.
   - Tactical maps (`ImportedMap`): the whole raster, zlib, in `land_cover` (+ `land_cover_cell_m`, `_width`, `_height`, `_origin_easting` / `_northing` = the centre of the north-west cell).
   - The tactical layer (`TacticalLayer`): the raster geometry in `layer.tres`, the cells in one window per chunk (`TacticalChunk.cover`, `cover_column` / `cover_row` / `cover_width` / `cover_height`). The windows tile the raster without overlap (chunk column cx starts at the west edge of hex column cx * 128, chunk row cy halfway between hex rows cy * 128 - 1 and cy * 128). A cut reads the windows of the chunks around it; the cover is decoded only when asked for, so `region_grid` costs what it cost before.
   - Operational maps (5 km hexes) get no raster; their graphic layers (TASK-126) stay as they are.
3. **The hex type is the majority of the raster cells inside the hex** (the cells whose centre lies in the hex, counted as whole row runs), through the unchanged `classify` thresholds (dominance for water / forest, shares for urban / marsh, relief for hills, largest open class for fields). The heights still come from the DEM sample points. On the Suwałki map 20 of 720 hexes changed type, every one within ~0.05 of a deciding threshold (a 50 / 50 forest share, a 0.20 urban share, a 0.25 marsh share) – the 16 m cells are a finer estimate of the same shares, not a different rule.
4. **`LandCover` (`src/core/data/land_cover.gd`, pure) is the only reader.** `class_at(x, z)`, `share_in(rect, kind)` / `shares_in`, `weight(kind, x, z)` / `weights_at` (bilinear between cell centres: continuous everywhere, also across hex borders), `cells()` for a texture. `LandCover.for_map(map_id, region, grid, margin)` picks the source of a battle (the layer cut plus a margin for the backdrop, the imported map, else the fallback).
5. **Maps without a raster keep their look.** Generated maps and data imported before the raster get the fallback cover that expands the hex types (`kind_of_terrain`, hard hex edges); `has_raster()` tells the view which path it is on, so it can keep today's code for those maps unchanged.
6. **The rules and the simulation are untouched**: no rule, command, AI or save reads `LandCover`; it uses no `GameState.rng`.

## Consequences

- (+) The view can draw forest edges, fields, villages and meadows along their real outlines, and the backdrop beyond a cut from real data.
- (+) The hex types and the look come from the same raster, so they cannot disagree beyond the threshold cases.
- (+) Old layers and maps still load (no raster -> fallback); a re-import adds the raster.
- (−) The tactical layer grows from ~3.4 MB to the size recorded in TASK-108g, and its import takes longer (a 16 m raster of the whole theatre in memory); the sea is flood-filled on the 50 m lattice and copied into the raster (a 16 m flood fill of the Baltic would be tens of millions of steps), so the coastline is drawn at 50 m.
- (−) Re-importing changes a few threshold hexes' types (reported in TASK-108g), so scenarios on imported maps can shift slightly.
- (−) Until the presentation switches over (TASK-108g, presentation half), the raster is data no one draws.

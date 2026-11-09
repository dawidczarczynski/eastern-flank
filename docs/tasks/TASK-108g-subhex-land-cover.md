# TASK-108g: Real-terrain look – visuals from a sub-hex land-cover raster (hexes are mechanics only)

- **Status**: ready
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

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle`, grid off (`G`): forest edges, fields, villages and meadows follow natural outlines and cross hex borders; no hex-shaped patches anywhere.
2. Grid on: lines only, no change of ground colour inside a hex.
3. Pan to the map edge: backdrop continues the same land cover.

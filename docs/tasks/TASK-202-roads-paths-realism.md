# TASK-202: Real-scale roads, tracks and paths – class, width, surface, edges

- **Status**: ready
- **Layers**: importer (`tools/import_map.py`, python tests) + data (road style in the map `.tres` / `TacticalChunk`, `data/` resource with widths) + presentation (`FeatureRibbonPlanner`, `FeatureRibbons`, `assets/shaders/road.gdshader`)
- **Depends on**: TASK-134 (soft: TASK-216, TASK-199b)
- **Sections**: ARCHITECTURE "Terrain rendering" (road ribbon bullet), "Two layers" (tactical layer planes); look reference (TASK-190); read in code: `feature_ribbon_planner.gd`, `feature_ribbons.gd`, `road.gdshader`, `hex_grid.gd` (road links), `imported_map.gd`, `tactical_layer.gd`, `tactical_chunk.gd`
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Roads read like the reference at real scale: a village road is a few metres of asphalt, a field track is gravel or two dirt ruts with a grassy middle, a main road has a centre line – with the right width in metres, soft verges and clean junctions.

## Decisions (2026-11-23)

- ONE task (split declined); criteria kept tight. Data like TASK-216 does for rivers: the importer keeps the OSM `highway` class and `surface` tag of every road; old maps need no re-import (loader default = one class with today's look: 5 m gravel); Suwałki is re-imported.
- The new look exists ONLY on the `true` VisualScale preset (like TASK-199b); `balanced` / default keep today's 5 m gravel ribbon (test).
- Out of scope (possible follow-up task): close-up pebbles / cracks detail and puddle patches. Skid marks stay with TASK-058.
- Storage: roads are per-tile link masks (`HexGrid.road_links`), so the class is a per-tile **road style byte** (low 4 bits = class id, high 4 bits = surface id; 0 = unknown -> default) of the best road class touching the tile, in `HexGrid` (`set_road_style` / `road_style`, sparse dictionary like the link masks, bumps the same change counter). `ImportedMap` stores it in its `.tres`; `TacticalChunk` gets one extra optional plane after the five existing ones (a chunk with 5 planes decodes as style 0 – no re-import needed). Update ARCHITECTURE "Two layers" (tactical layer planes) and "Terrain rendering" (road ribbon bullet).
- Merge-conflict risk with TASK-216 (it touches the same importer function that walks `waterway` / `highway` lines, `ImportedMap` / `TacticalLayer` loaders, and probably adds its own chunk plane): whichever lands second takes the next plane index; the loader tells planes apart by the decoded size (`PLANES` stays derived from the byte length, not hard-coded to one number). Do not refactor shared link code in this task.
- Classes and surfaces: class ids motorway/trunk = 1, primary = 2, secondary/tertiary = 3, residential/unclassified = 4, service/track = 5, path/footway/cycleway = 6; `*_link` takes the parent class; unknown -> default. Surfaces: asphalt/paved/concrete = 1, gravel/compacted/fine_gravel = 2, dirt/ground/earth/unpaved/grass/sand = 3; no tag -> the class default.
- **[ASSUMPTION]** widths (carriageway, m) at the middle of the given ranges: motorway/trunk/primary 8.5 (asphalt), secondary/tertiary 5 (asphalt), residential/unclassified 4.5 (asphalt), service 3.5 and track 3 (gravel), path 1.5 (worn earth). Verge 1.5 m each side on asphalt, 1 m on tracks; widths and colours live in `data/` (a Resource), not constants.
- **[ASSUMPTION]** markings: one centre line (dashed 3 m / 6 m on secondary, solid on primary/motorway) only on those classes; none on residential, tracks or paths.
- **[ASSUMPTION]** a tile's style applies to all its links; where two neighbouring tiles differ, width and surface blend over one tile length. The importer takes the best class of the roads through a tile.
- **[ASSUMPTION]** "little used" dirt tracks (grassy centre strip, 0.8 m wide) = hash of the tile coordinate < 0.4; no `GameState.rng`, deterministic.
- **[ASSUMPTION]** frame time within 0.3 ms of before on `true`; no new draw calls (same ribbon mesh and material, extra shader parameters / vertex colour only).

## Acceptance criteria (testable)

- [ ] Importer (python tests): `highway` -> class id and `surface` -> surface id per the tables above; `_link` takes the parent class; unknown class/surface -> 0; the best class wins on a tile with two roads; same input twice -> identical output.
- [ ] Loader: a map or chunk without style data gives style 0 for every road tile and the default class (5 m gravel); `HexGrid.road_style` round-trips through `ImportedMap` and `TacticalChunk`; a 5-plane chunk still loads.
- [ ] Planner on `true`: carriageway widths in metres per class equal the table (primary 8.5, secondary 5, residential 4.5, track 3, path 1.5 m, via `MapScale`); the surface tag overrides the class default (a `track` with `asphalt` -> asphalt colour id).
- [ ] Planner: verge width per class as above; marking segments exist only on primary / secondary / motorway (dashed 3 m / 6 m on secondary) and are absent on all other classes.
- [ ] Dirt tracks carry a rut pair (darker band offset ±0.3 × width) and, by tile hash < 0.4, a grassy centre; same map twice -> identical planner output.
- [ ] Ribbon edges lie on the near surface (height within 0.1 m of the drawn terrain on a 15 % slope fixture, TASK-134) and blend into the verge (shader edge alpha reaches 0 at the verge outer edge).
- [ ] Junctions and ends: at a T-junction and a crossing of two classes the planner emits no overlapping coplanar quads (the narrower road is lifted by the existing ROAD_LIFT step or merged); a dead end closes with a rounded or squared cap inside the verge; planner tests extended.
- [ ] Bridges and culverts keep their treatment: `bridge_sites` / `bridges` output on a fixture is identical before and after.
- [ ] `balanced` preset: the planner output for a road fixture is identical to the pre-task output (test).
- [ ] Re-import Suwałki: the number and course of road links are unchanged; classes are set on > 90 % of road tiles.
- [ ] Frame time on `true` within 0.3 ms of before (existing frame benchmark / `tools/screenshot.sh` timing), 60 FPS kept.
- [ ] Screenshots Read at camera distance 0.4 / 1.2 / 5 for a village road, a field track and a forest track, compared with the look reference (TASK-190); deviations stated.

## Playtest (for the human)

1. `tools/run.sh --scenario=suwalki_battle` on the `true` scale: village roads are narrow asphalt, main roads wider with a centre line, field and forest tracks are gravel or dirt with ruts, some with a grass middle; edges are soft.
2. Follow a road over hills and through a junction and over a bridge: no floating or sunken edges, no z-fighting flicker, bridges look as before.
3. Switch to the default scale: roads look exactly as before.

## Player manual

docs/MANUAL.md "Roads and rivers": on the true-size scale a road's look follows its class – wide asphalt with a centre line for main roads, narrow asphalt in villages, gravel or dirt tracks with ruts and grassy middles, thin earth paths; the default scale keeps the single gravel road look. No rule or movement change.

## GDD

No rule changes – GDD stays untouched (roads still only give the existing movement bonus by link).

## Out of scope

- Close-up pebbles / cracks detail and puddle patches (possible follow-up); skid marks (TASK-058).
- Traffic; bridge models; railway detail; per-link class inside one tile; movement rules by road class.

## Implementation notes

_Filled in by the agent when done._

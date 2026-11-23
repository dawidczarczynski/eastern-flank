# ADR 0032: Real field parcel boundaries – OSM land use split by tracks and hedges, committed as polygons

- **Status**: accepted
- **Date**: 2026-11-23
- **Task**: TASK-215a (research, import and loaders; the drawing is TASK-215b). Builds on ADR 0018 (maps from real geography), ADR 0028 (sub-hex land cover), ADR 0031 (satellite colour layer, the pattern for an opt-in layer); replaces the input of TASK-108f's procedural strips where real data exists

## Context

TASK-108f paints farmland as procedural strips: 2.5 km regions with one hashed orientation, strips 150–400 m wide and up to 2.5 km long. Next to the Sentinel-2 colour (ADR 0031) they read as invented: the real Suwałki fields are much smaller, follow the roads and run in many directions. TASK-215b wants to draw the real field outlines, so the maps need the real parcel polygons, loadable in the pure core, offline, deterministic, and small.

## Options compared

| | OSM split (chosen) | Polish EGiB (cadastre) / LPIS | Sentinel-2 field-edge detection |
|---|---|---|---|
| What it is | `landuse=farmland\|meadow\|orchard` areas, cut by roads, tracks, hedges, tree rows, fences | EGiB: cadastral plots (*działki ewidencyjne*); LPIS: farmers' declared agricultural parcels | Field edges found in 10 m imagery (multi-date gradients or a trained model) |
| Poland (Suwałki) | Yes, but patchy: on the Suwałki map 674 ha of farmland + 134 ha of meadow are mapped, 1977 ha of open land is not (see Statistics) | EGiB: complete, downloadable per area from GUGiK's collective WFS (*Zbiorcza usługa WFS EGiB*) and per-county GeoPackages ("open data" mode of the GUGiK QGIS plugin). LPIS: not public (personal data of the applicants) | Complete wherever there are cloud-free scenes |
| Lithuania | Yes (same quality questions) | EuroCrops harmonises the Lithuanian declared parcels (Poland is not in EuroCrops); licence per national source | Yes |
| Belarus, Kaliningrad | Yes (sparser mapping) | None open | Yes |
| Shape fidelity | The mapper's field outline; real splits where the splitters are mapped | EGiB plots are ownership strips, often 10–30 m wide and many to one farmed field (or one plot farmed as several crops): not the field you see | 10 m pixels: Suwałki fields of 20–60 m width are 2–6 pixels; strips merge, edges blur |
| Licence | ODbL 1.0, attribution already in CREDITS | EGiB: free of charge under the Polish geodesy law since 2020; reuse terms for redistribution in a product not checked; EuroCrops: per country source | Copernicus terms (as ADR 0031) |
| Size per tactical map | 78 KB (Suwałki, see below) | Thousands of plots per km²: estimated > 1 MB before merging | Depends on vectorising; similar to OSM after simplification |
| Importer cost | ~60 lines of query + ~450 lines of stdlib geometry; one 0.9 MB Overpass answer per map | A new WFS client (GML parsing, paging), plus merging plots into fields, which needs a crop / colour signal anyway; Poland only | Multi-date stacks of 4 bands per scene, edge detection or a neural network (not stdlib Python; the ready models such as Fields of The World need PyTorch), vectorising and cleaning – the most expensive by far |

**Decision: OSM split** (the default of TASK-215a). EGiB is rejected for the field shapes (ownership strips, not fields; Poland only; reuse terms unchecked), LPIS is not public in Poland, and Sentinel-2 edge detection is rejected on cost and on resolution (the Suwałki fields are 2–6 pixels wide). EGiB plots stay a candidate for a later *subdivision* source inside big OSM polygons (TASK-215b's fallback) if the reuse terms allow it; checked sources: geoportal.gov.pl EGiB page and the GUGiK WFS / QGIS plugin announcements, EuroCrops (Scientific Data 2023, Zenodo), 2026-11-23.

## Decision

1. **Input** (`tools/import_map_parcels.py`, `--parcels`, tactical profile only): the farmland / meadow / orchard areas of the map's land-cover extract (`osm_<bbox>.json`, the existing tactical fetch; multipolygons with their inner rings), split by the ways of a second Overpass answer for the same bbox, `pc1_<s>_<w>_<n>_<e>.json` in `~/.cache/eastern-flank/maps/osm/` (`parcel_query`: `highway=track|service|unclassified|residential|tertiary|secondary|primary|trunk|motorway`, `barrier=hedge|fence|wall`, `natural=tree_row`; the tactical answer has no hedges, fences or service roads), plus the roads and tracks of the land-cover extract. `--offline` fails naming a missing file; `--parcel-osm` reads a given file (tests).
2. **Split** (planar graph per area): the splitter lines are cut where they meet the area's rings; a piece is kept only when some point of it lies more than **3 m** inside the area (`TOUCH_M`) – a hedge drawn along the edge or zigzagging across it does not cut slivers off; kept pieces are noded where they cross, pieces with a free end (a track ending in the field) are pruned; the bounded faces inside the area are the parcels, and an inner ring (a wood inside the field) stays the hole of the face it lies in. Other land cover drawn *over* farmland without an inner ring (a separate forest polygon) is not cut out here: the renderer masks parcels by the land-cover raster (ADR 0028).
3. **Clean-up**: rings simplified (Douglas-Peucker 1 m), rounded to whole metres; faces < 200 m² or thinner than 5 m (2 × area / perimeter: the strip between a track and a hedge mapped side by side) are dropped; parcels wholly outside the map's hexes are dropped (the others are kept whole, up to the 500 m fetch margin).
4. **Edge kinds**: every edge is `hedge` or `track` when at least half of its 10 m samples lie within **8 m** of a splitter of that kind running within 25° of parallel (tracks are mapped on their centreline, a few metres from the field edge; the nearest splitter decides per sample), else `plain`. Fences and walls split but count as `plain`; every road kind counts as `track`.
5. **Big parcels**: not subdivided (`LARGE_PARCEL_HA` = 15 ha, **[ASSUMPTION]**, only reported here); TASK-215b subdivides them.
6. **Storage** (`ImportedMap`, after the existing fields; without `--parcels` the importer writes exactly what it wrote before): `parcel_landuse_codes` (base64 bytes: 0 farmland, 1 meadow, 2 orchard), `parcel_rings` (rings per parcel), `parcel_ring_sizes` (vertices per ring), `parcel_points` (x, z pairs, whole metres east / south of tile (0, 0)'s centre – the frame of `ImportedMap.sample`), `parcel_edge_codes` (base64 bytes, one `PARCEL_EDGE_*` per vertex: the edge to the next vertex). The outer ring runs counter-clockwise seen from above with north up, holes the other way round; parcels are sorted by land use, then outer ring. Budget **150 KB per tactical map** (kept: Suwałki 78 KB). **Loaders** (pure core): `has_parcels()`, `parcel_count()`, `parcel_polygon(i)` (`Array[PackedVector2Array]`, metres), `parcel_edge_kinds(i)` (`Array[PackedByteArray]`), `parcel_landuse(i)` (`&"farmland"` / `&"meadow"` / `&"orchard"`); `problem()` checks the arrays. No rule, command, AI or save reads them; no `GameState.rng`.

## Statistics (Suwałki, `data/maps/suwalki.tres`, OSM of 2026-10-31 + splitters of 2026-11-23)

| | OSM parcels (this ADR) | TASK-108f strips (nominal, before the farmland cut) |
|---|---|---|
| Count | 282 (209 farmland, 73 meadow, 0 orchard) on 30 × 24 hexes | 3993 strips over 20 × 20 regions of 2.5 km |
| Median | 1.70 ha | 61.6 ha |
| p10 / p90 | 0.38 / 7.06 ha | 34.3 / 93.6 ha |
| Largest | 49.9 ha; 8 parcels over 15 ha | 129 ha (min 12.6 ha) |
| Edges | 5771: 4629 plain, 1128 track, 14 hedge | – |

- Farmland of the land-cover raster (16 m cells, 674 ha on the map) inside a farmland parcel: **98.6 %** (99.8 % inside any parcel; the rest are the dropped slivers and road strips). Grass / meadow cells (134 ha): 94.7 %.
- But only **28.6 %** of all open land on the map (2798 ha) lies in a parcel: **1977 ha of open land has no land use in OSM** (the north-west and west of the map, clearly fields on the satellite image). TASK-215b needs its fallback (procedural or colour-driven subdivision) there, not only inside big polygons.
- Real fields are ~35 × smaller than the procedural strips (median 1.7 vs 61.6 ha) – the main reason the strips looked invented.
- Hedges are barely mapped (14 edges); most real field edges are `plain` balks or tracks.
- Figure: `docs/adr/0032-suwalki-parcels.jpg` – the parcels over the map's colour layer (2 × upscaled; yellow plain, orange track, green hedge). The outlines sit on the field edges of the image.

## Consequences

- (+) Real field shapes and sizes from the source the maps already use, one attribution (ODbL), 78 KB, deterministic (same cache → byte-identical file), and the hex data and colour layer are unchanged.
- (+) The same code serves every country of the theatre.
- (−) Coverage is only as good as OSM land-use mapping: on Suwałki 71 % of the open land has no polygon. A fallback in TASK-215b is mandatory.
- (−) One more Overpass download per map (0.9 MB for Suwałki); the public server is often at capacity (two 502 answers before it succeeded).
- (−) Overlaps with other OSM land cover are not resolved here; the renderer masks by the land-cover raster.
- Follow-ups: the theatre's tactical layer and operational maps (out of scope); EGiB plots as a subdivision source if their reuse terms allow redistribution.

## Addendum (TASK-215b rework, 2026-11-23): fill and look

The human rejected the first drawing (only OSM polygons; 71 % of the open land stayed plain grass; flat, washed-out colours) and set a Warno / Wargame-style target: fields on all open land, 1–5 ha parcels with straight edges, strong neighbour contrast, tree lines on many edges, visible stripes. Decisions, all look data in `RealParcelLook` (`data/fields/real_parcels.tres`) and `CropKind` (`data/fields/crops.tres`):

- OSM polygons over **5 ha** (was 15 ha) are subdivided across their long axis.
- **Fill** (`ParcelFill`): the open land without a polygon is cut into field systems (Voronoi cells of a jittered 650 m grid) with the direction of the nearest OSM parcel, split recursively across the longer side into ~4 ha parcels (× 1 ± 0.6); kept where some of the parcel may show (not forest, water, village, marsh). 70 % of the system borders and 30 % of the splits are hedges (balk + tree line every 12 m). Deterministic from the map seed and cell index.
- **Look**: a more contrasting crop palette (gold wheat, fresh green, purple-brown ploughed, pale stubble, yellow rape; weights unchanged, so the strips stay byte-identical), coarse stripes per crop (tramlines / swaths / furrow bands, 3–14 m), crop saturation 1.2, crop tint 0.12, and a real parcel takes only 15 % of the satellite layer's hue at every distance instead of the layer's own colour far away.

Statistics (Suwałki, `true`): 282 polygons → 375 OSM parcels (median 2.64 ha, p10 0.47, p90 4.58, max 5.0) + 3813 fill parcels (median 2.28 ha, p10 0.75, p90 4.60); all parcels median 2.30 ha; **99.4 %** of the open land inside the map covered (50 m lattice, `allows_parcel`); 10 073 neighbour pairs, 0 with the same crop; 1688 hedge lines; bake 1.6–1.9 s (Linux headless, 4 cores; hidden behind the terrain build on Windows: 0 ms main-thread wait).

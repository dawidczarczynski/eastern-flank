# TASK-215b: Real field parcel boundaries (B): bake and draw

- **Status**: done
- **Layers**: presentation (`FieldParcels`, `ParcelMap`, terrain shader inputs)
- **Depends on**: TASK-215a
- **Sections**: ADR 0032 (parcel boundaries), ADR 0031; ARCHITECTURE "Terrain rendering"; TASK-200, TASK-108f / 108g, TASK-199 (hedges)
- **Model**: opus (geometry, determinism, frame budget)
- **Tags**: battle-look

## Goal

Farmland is drawn as the parcels that really exist: straight boundaries, real sizes (typically 1–10 ha), distinct neighbouring crops and hedge balks on the real edges, so the patchwork reads like the satellite view. Hexes stay mechanics only.

## Decisions (2026-11-23)

- Where `ImportedMap.has_parcels()`, `FieldParcels` / `ParcelMap` bake from the polygons; elsewhere (no data, `balanced` preset) the procedural strips of TASK-108f / 108g stay unchanged.
- Polygons larger than 15 ha (**[ASSUMPTION]**, one configurable constant) are subdivided into plausible parcels along their long axis; deterministic and seeded from the map seed and polygon id (no RNG outside `GameState.rng`-free pure functions, no global randomness).
- Areas with no polygon keep the procedural strips.

## Acceptance criteria (testable)

- [ ] Each polygon gets one crop by the TASK-200 rule; two polygons sharing an edge never get the same crop (test on the Suwałki map: 0 same-crop neighbour pairs).
- [ ] Polygon edges of kind `hedge` get BALK pixels along the edge (width as `FieldParcels.BALK_M`); the BALK edge is a polyline TASK-199 can follow (accessor tested).
- [ ] A 40 ha square becomes 3 parcels (15 ha threshold: ceil(area / 15 ha)), each 8–15 ha, cut perpendicular to the long axis; a 10 ha polygon is not subdivided; the parcels' areas sum to the original within 1 %.
- [ ] Subdivision is deterministic: same polygon + seed twice gives identical parcels; a different polygon id gives a different crop / row direction.
- [ ] A map without parcels and the `balanced` preset bake byte-identically to before (test compares the ParcelMap image hash).
- [ ] Parcel size stats of the baked Suwałki result (median, p10, p90, count) are recorded and compared with the strips'; median parcel is 1–10 ha.
- [ ] Frame time within 0.3 ms of TASK-200 on the Suwałki battle (HIGH, 1.2 / 5 / 24 views); bake time and memory recorded in the notes.
- [ ] Screenshots at 1.2 / 5 / 24 Read against the satellite reference; deviations stated.

## Playtest (for the human)

1. `true` preset, Suwałki: fields have straight real-looking edges and mixed sizes, hedges on field edges; compare with the satellite view at all three zooms.
2. Check a field area with no parcel data still shows strips, and `balanced` looks as before.
3. Frame rate stays 60 FPS.

## Player manual

None (visual only; no mechanic or control changes).

## Out of scope

- Field roads / tracks as geometry (TASK-202), buildings (TASK-193+), animated crops, new importer work (TASK-215a).

## Implementation notes

- **Code** (first version; see playtest fix 1 below for the edges): `RealParcels` (new, `src/presentation/real_parcels.gd`, pure): polygons from `ImportedMap` (seed = hash of the map id, key = `FieldParcels.hash4(seed, polygon id, part, salt)`), subdivision of polygons > `LARGE_PARCEL_HA` (15 ha) into ceil(area / 15 ha) equal-area slabs across the long axis of the min-area rectangle (bisection + Sutherland-Hodgman, holes kept), row direction along the parcel's long side (20 % across by hash), scanline rasterising, neighbours from pixel spans (touching or ≤ 1 px apart along ≥ 2 px), smallest-last greedy crop colouring (farmland: the look's shares; meadow / orchard: `MEADOW_SHARES` meadow 0.7 / green 0.3, then any crop), hedge / track polylines (shared edges once) painted as BALK (`BALK_M` 10 m / `TRACK_M` 7 m). `FieldParcels.bake(…, look, real)` paints them over the strips (image RGB8, blue = 1 + row angle; without `real` nothing changes); `ParcelMap.real` / `real_crops` / `real_neighbours` / `hedge_lines()` (the polyline accessor for TASK-199) / `is_real_at_metres`; real pixels are masked by `CoverLook.allows_parcel` (not forest / water / village / marsh, noisy outline) instead of the FIELD outline, shader twin `in_cover(xz, COVER_PARCEL_MASK)`; rows in the shader run along the decoded angle; within 1.5 km the shader picks the 2 × 2 texel label with the largest bilinear weight (`parcel_label`, `TerrainGround.PARCEL_SMOOTH_M`), so slanted edges are not 5 m steps. `BattleCover.parcels_for_battle` (true preset + imported map only) → `MapView.real_parcels`. `ScatterPlanner.plan_hedges` keeps its strip copses off real balks. ARCHITECTURE "Terrain rendering" has a new bullet.
- **Tests**: `tests/unit/test_real_parcels.gd` (11): 40 ha square → 3 parcels of 13.3 ha, areas within 1 %, a 1000 × 400 m field cut across x; 10 ha not cut; holes keep area; determinism and id-keyed crop / angle; rows along / across the long side and the angle code round trip; hedge balk on both sides of the edge, `hedge_lines()` polyline, plain edge without balk; 6 × 6 grid of touching parcels with distinct crops and edge-only neighbours; forest mask vs open cover; shader constant parity; **byte-identical bakes** (sha256 of the image, recorded before the change) for a hex-grid map and Suwałki, `balanced` and `true`, with no parcels; Suwałki stats and 0 same-crop neighbour pairs.
- **Stats (Suwałki, `true`)**: 282 polygons → 295 parcels (8 polygons over 15 ha subdivided), median **1.86 ha**, p10 0.39, p90 9.52, max 13.77 ha; 195 neighbour pairs, **0 with the same crop**; 6 hedge polylines (20 points), 317 track polylines. Strips (TASK-108f nominal): 3993 strips, median 61.6 ha, p10 34.3, p90 93.6. Nearly no strip pixel is left on Suwałki: the FIELD cover is the OSM farmland the polygons come from (98.6 % covered), so the fallback strips only fill the remaining slivers.
- **Bake / memory**: `RealParcels.from_imported` 40 ms (main thread, in BattleCover), bake 367 ms vs 221 ms without parcels (+146 ms, worker thread during the terrain build; Linux headless). Parcel map 1987 × 1516 RGB8 = 8.6 MB CPU (was RG8 5.8 MB; the GPU copy is likely padded to RGBA8, ~12 MB vs ~6 MB); only maps with polygons pay it.
- **Frame time** (Windows D3D12, HIGH, `true`, Suwałki, focus 41.57,9 yaw 30, 300 frames, before = same code with `real_parcels` forced null, i.e. the TASK-200 strips): distance 1.2: 9.87 → 9.72 ms; 5: 9.94 → 9.82 ms; 24: 8.68 → 8.69 ms (within noise; fewer scatter items on the parcels, the smoothing adds 3 texel fetches within 1.5 km).
- **Screenshots** (`.screenshots/real_d12.png`, `after2_5.png`, `real_24.png`, before: `before_*.png`) against the colour layer / ADR 0032 figure: at 5 the 2.5 km straight-ended strips are replaced by the real outlines – slanted, irregular field shapes with a pale stubble field, brown ploughed and green parcels in the places of the figure's polygons; at 1.2 the edges are clean straight-ish lines (no 5 m steps) and the track balks show as pale lines; at 24 the satellite colour dominates as before. **Deviations**: (1) the 1977 ha of open land without OSM land use stays grass (no strips either: the strips only ever grew on FIELD cover) – a colour-driven fallback there would be a follow-up; (2) OSM polygons often merge several real narrow strips of the satellite image (Suwałki strip fields 20–60 m wide), so the patchwork is coarser than the photo inside a polygon below 15 ha; (3) where a parcel meets forest / village cover its edge follows the 16 m land-cover outline (noisy), not the polygon; (4) plain edges get no balk line (only crop contrast, the headland darkening appears only next to balks); (5) the CPU `kind_at` reads the nearest texel, the shader the smoothed label (differs by < 1 texel on edges); (6) rows are still not visible at 1.2 (as in TASK-200).
- README screenshot re-rendered; unchanged (the README scenario uses `balanced`, which has no parcels).

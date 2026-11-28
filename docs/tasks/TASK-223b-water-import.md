# TASK-223b: Water network (2/7): importer keeps real water geometry – polylines with flow direction, water polygons, bridges, fords, lake levels

- **Status**: ready
- **Layers**: importer (`tools/import_map.py`, python tests) + data (theatre, tactical layer, battle map)
- **Depends on**: –
- **Sections**: ADR 0034 decisions 1, 2, 7; data/maps/CREDITS (re-import commands)
- **Model**: sonnet
- **Tags**: battle-look

## Goal

The game gets the real course, width and shape of every river and lake instead of hex-to-hex links, so nothing downstream has to guess.

## Acceptance criteria (testable)

- [ ] Rivers: every `waterway` way (river / stream / canal / ditch ≥ named or ≥ 2 m) as a polyline in the map CRS, simplified (Douglas–Peucker 5 m), **vertex order = OSM way order (downstream)**; ways joined at shared nodes into reaches; `tunnel=*` / `culvert` parts dropped; attributes: class, name, `width` (parsed as TASK-216), `intermittent`.
- [ ] Water polygons: `natural=water` (any `water=*`), `waterway=riverbank`, with inner rings (islands) kept; each with `ele` when tagged.
- [ ] Width per river vertex: measured across the matching water polygon when one covers it (shortest chord through the vertex), else the tag, else the class default (stream 3, river 8, canal 10 m).
- [ ] Lake level: OSM `ele`, else the 10th percentile of the DEM along the shore ring.
- [ ] Bridges (`bridge=*` on roads and railways crossing water) and fords (`ford=*` nodes / ways) with position, length, road id.
- [ ] Written into the theatre / tactical layer data in a compact form (per chunk for the layer); old `river_rows` / `river_width_rows` still written and readable.
- [ ] Python tests: flow direction kept, a reversed way flipped only when the way is tagged as reversed (no height guessing), an island survives, widths from polygon vs tag vs class, same input twice → identical output.
- [ ] Suwałki re-imported (theatre, `suwalki_tactical`, `suwalki`); counts of reaches, polygons, bridges, fords in the notes; `tools/check.sh --full` passes.

## Playtest (for the human)

None visible yet (data only); 223a's report must still run.

## Player manual

None.

## Out of scope

- Using the data in the game (223c onwards).

## Implementation notes

_Filled in by the agent when done._

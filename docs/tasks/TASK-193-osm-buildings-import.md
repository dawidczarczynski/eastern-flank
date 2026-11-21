# TASK-193: Buildings from OpenStreetMap – import into the map data

- **Status**: idea
- **Layers**: tools / presentation data (`tools/import_map.py`, `ImportedMap`)
- **Depends on**: –
- **Sections**: ADR 0018 (maps from real geography), ARCHITECTURE "Terrain"; look reference (TASK-190)
- **Model**: opus

## Goal

Maps carry the real buildings of their area (footprint, type, levels, material, roof tags), so villages and towns can later be drawn as they really are – the data the building tasks (TASK-194 .. 198) need. Hexes stay mechanics only: the buildings are appearance and are independent of the hex terrain.

## Acceptance criteria (testable)

- [ ] Research first, recorded in a new ADR: OSM `building=*` / `man_made=silo|tower|chimney` / `building:levels`, `height`, `building:material`, `roof:shape|material|colour`, `start_date` coverage on the Suwałki theatre (counts per tag), the Overpass query cost, ODbL attribution, size per map; decision how tags missing in OSM are defaulted (that belongs to TASK-194 / 196, the importer keeps what OSM says).
- [ ] `tools/import_map.py` downloads buildings once into `~/.cache/eastern-flank/maps` (resumable, retried, `--offline` fails naming a missing tile, like the other layers) and writes them into the map / layer resource: per building a simplified footprint polygon (world units, `0.1 m` snap, simplified, winding fixed), type, levels, height, material / roof tags; byte-identical on re-import.
- [ ] Footprints are cleaned: self-intersections and < 4 m² slivers dropped, multipolygons with holes (courtyards) kept, buildings split by tile chunk so a 128 x 128 `TacticalLayer` chunk loads only its own.
- [ ] Attribution in `data/maps/CREDITS`; a Python test on a small fixture (`tools/test_import_map.py`, fixtures re-made with `--make-fixtures`).
- [ ] `ImportedMap` / the layer exposes `buildings_in(rect)` (pure, tested): count, footprint area and tags of a known fixture.
- [ ] Map file size growth recorded; the committed sample map stays within the repo's size habits (otherwise the data stays in the cache and only a reduced sample is committed – decide in the ADR).

## Playtest (for the human)

1. `tools/import_map.py ... --offline` reproduces the map byte-identically.
2. A debug dump / overlay of footprints over the Suwałki map (screenshot) shows the real villages and roads' houses where they should be.

## Player manual

None.

## Out of scope

- Drawing the buildings (TASK-194 .. 198); building mechanics (cover, destruction).

## Implementation notes

_Filled in by the agent when done._

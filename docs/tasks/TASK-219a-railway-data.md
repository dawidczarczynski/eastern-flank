# TASK-219a: Railways (1/3) – import and data: lines, class, electrification, stations, level crossings

- **Status**: ready
- **Layers**: importer (`tools/import_map.py`, python tests) + data (map `.tres`, `HexGrid`, `ImportedMap`, `TacticalChunk`, loaders)
- **Depends on**: – (soft: TASK-202 – same importer walk and loaders; whichever lands second takes the next chunk plane index)
- **Sections**: ARCHITECTURE "Two layers" (tactical layer planes), "Terrain rendering"; code (grep CODEMAP): `imported_map.gd`, `tactical_layer.gd`, `tactical_chunk.gd`, `hex_grid.gd` (road / river link masks)
- **Model**: sonnet
- **Tags**: battle-look

## Goal

The map knows where the railways are. Today `railway` is only a landuse tag that paints "built-up" (`tools/import_map.py`); no line, class or station is stored. This task imports them so TASK-219b can draw tracks and TASK-219c the infrastructure. No visuals here.

## Decisions / assumptions

- **[ASSUMPTION]** Imported ways: `railway=rail|light_rail|narrow_gauge|tram|siding|yard|spur` (rail-class `abandoned|disused` kept as class 7 "dismantled": only an embankment, no track). Stored per tile like roads: a **rail link mask** per tile (`HexGrid.rail_links`, sparse dictionary, same change counter) plus a **rail style byte** (low 4 bits = class, high 4 bits = flags).
- Classes: 1 main (`rail`, `usage=main|branch` or none), 2 secondary (`usage=industrial|military|tourism`), 3 siding / yard / spur (`service=*` or `railway=siding|yard|spur`), 4 light rail / tram, 5 narrow gauge, 7 dismantled. Flags (bits): electrified (`electrified` != `no`), double track (`tracks=2` or two parallel ways closer than 15 m – merge them into one tile link, flag set), bridge, tunnel, embankment / cutting kept from `bridge` / `tunnel` / `embankment` / `cutting` tags (bridge and tunnel are mutually exclusive; they only mark the tile).
- **[ASSUMPTION]** Points (sparse list in the map, world coordinates in metres, deterministic order): `railway=station|halt` (with `name`, kind), `railway=level_crossing|crossing`, `railway=signal` is NOT imported (rules place signals in 219c), `railway=switch` is NOT imported (rules).
- Old maps need no re-import (loader default: no railways; a chunk with fewer planes decodes as 0). `PLANES` stays derived from the decoded size. Suwałki is re-imported; the cache download is extended with a `railway` query for the existing bboxes.
- No game rules: railways do not change movement or supply here (a later GDD decision, see Out of scope).

## Acceptance criteria (testable)

- [ ] Importer (python tests): `railway` / `usage` / `service` -> class ids per the table; `electrified`, `tracks`, `bridge`, `tunnel`, `embankment`, `cutting` -> flag bits; unknown or `proposed` / `construction` ways are ignored; same input twice -> identical output.
- [ ] The existing landuse "built-up" painting from `railway` areas (yards, stations) is unchanged (python test).
- [ ] A double track made of two parallel ways closer than 15 m becomes one link with the double flag; farther apart -> two separate links.
- [ ] Points: station / halt / level crossing nodes are stored with kind and name; ordering deterministic; nodes farther than 100 m from any imported railway are dropped.
- [ ] Loader: a map or chunk without rail data gives no rail links and no points; `HexGrid.rail_links` / `rail_style` and the points round-trip through `ImportedMap` and `TacticalChunk`; a chunk with older plane counts still loads.
- [ ] Re-import Suwałki: counts of rail links per class and of stations / crossings logged in the notes; road and river data unchanged (diff of their planes is empty).
- [ ] Docs: ARCHITECTURE "Two layers" (planes) updated; devtools terrain viewer (hex inspector) lists rail class and flags of a tile.

## Playtest (for the human)

1. `tools/devtools` terrain viewer on Suwałki: click a hex on a known line (Suwałki – Trakiszki) – the inspector shows rail class and flags; a station hex lists its name.

## Player manual

none (internal data).

## GDD

No rule changes.

## Out of scope

- Drawing (TASK-219b, 219c); rail movement, supply or operational-layer railways (follow-up GDD decision); gauge, track numbers, timetables; yards as detailed track layouts.

## Implementation notes

_Filled in by the agent when done._

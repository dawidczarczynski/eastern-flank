# ADR 0019: Real-terrain types, per-link roads and per-hex rivers

- **Status**: accepted
- **Date**: 2026-10-31
- **Task**: TASK-108 (extends [ADR 0018](0018-maps-from-real-geography.md))

## Context

ADR 0018 imported real terrain with only the four generated types (plains, forest, hills, water) and stored the land cover per hex (`cover_rows`) and the OSM roads and waterways in the cache for later. TASK-108 turns them into rules: villages, fields and marshes get their own terrain types, roads speed movement, rivers slow it. The random-map battles must not change.

## Decision

### Terrain types

`Terrain.Type` gets `FIELDS, URBAN, MARSH` **appended** (`PLAINS, FOREST, HILLS, WATER, FIELDS, URBAN, MARSH`) so stored int values keep their meaning. Numbers in `data/terrain/*.tres`: fields 1 / +0 (the plains rules; look only, hook for later rules), urban 1 / +2 (as hills), marsh 2 / +0. `MapGenerator` never produces them.

### Roads and rivers: one link mask per tile and feature

Per tile a **6-bit link mask** per feature, bit *i* = a line from the tile centre across the side towards `tile + Hex.DIRECTIONS[i]`. In `HexGrid` (`set_road_links` / `road_links` / `has_road`, `set_river_links` / `river_links` / `is_river`) and in `ImportedMap` as `road_rows` / `river_rows` (one character per tile, `LINK_CHARS[mask]`, `LINK_CHARS = ".123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ#@"`, `.` = none; empty arrays = no links).

- **Storage rule**: a link between two land tiles is stored on both; land → water and land → off-map only on the land tile (drawn to the shared side, no rule effect); water tiles have none. `ImportedMap.problem()` enforces it.
- **Roads apply per link**: a step A → B costs `road_move_cost` (1) when A has a road link towards B, whatever B's terrain; an impassable B stays impassable. Rejected: a per-hex "road hex" flag – two parallel roads in neighbouring hexes (common in villages at 250 m) would give a free sideways step, and the importer would lose which way a road leaves a hex.
- **Rivers apply per hex**: a tile with any river link is a river hex; entering it costs `river_extra_cost` (+1) on top of its terrain unless the step follows a road link (a bridge); leaving is free. Rejected: rivers along hex sides – an OSM river runs through hex interiors and turning it into a chain of hex sides is ill-defined.
- `HexGrid.step_cost(from, to)` implements both and is the only cost the Dijkstra search uses, so moves, the AI, the path preview and the path cost follow automatically. Numbers in `TerrainFeatures` (`data/terrain/features.tres`, `Terrain.features()`).
- **Invariant**: the most expensive passable step (2 + 1 = 3) never exceeds the smallest unit movement (3), tested over `data/units/*.tres`.

### Importer classification (first match wins)

Shares of the hex's ~70 sample points: water / forest by dominance (ADR 0018, unchanged) → **urban** when built-up cover ≥ 20 % (`--urban-share`) → **marsh** when wetland ≥ 25 % (`--marsh-share`) → **hills** by relief ≥ 15 m → **fields** when farmland is the largest open class → **plains**. Urban comes before hills because buildings distort the DSM relief and urban matters most for combat; marshes are flat by nature; a ploughed hill stays a hill.

### Importer lines → links

Rule roads: `highway` motorway, trunk, primary, secondary, tertiary, unclassified, residential and their `_link` variants (not `track`). Rivers: `waterway` river, canal and named streams (not ditches, drains, unnamed streams). Each way (sorted by kind, id) is projected to UTM, densified every 10 m, and every sample mapped to its hex (also off the map); consecutive distinct hexes give links. **Corner-clip smoothing**: a stretch shorter than 40 m through a hex whose previous and next hexes are neighbours (or the same) is dropped. Then the storage rule. Deterministic as before: the Suwałki re-import is byte-identical across runs.

### Look (basic)

Splat weights per new type, scatter / grass rules, and flat road / river ribbons: half-segments centre → side midpoint, one mesh per kind. The realistic look (ground layers, houses, bridges, water-shaded rivers) is TASK-108b.

## Consequences

- (+) Roads and rivers need no change to the search beyond the step function; every caller of `reachable` / `path_to` gets them.
- (+) Generated maps have no links and none of the new types: the default, objective and command-points battles are unchanged (same simulation summary, same replays).
- (+) The link masks draw continuous lines and keep the direction a road leaves a hex.
- (−) Lines that run along a hex row boundary zigzag between the two rows (each hex they cross gets links); readable, but a road along a boundary looks wavy at 250 m.
- (−) A road over a water hex (bridge over a lake narrows) is lost: water stays impassable.
- (−) Streams with a name but little water count as rivers; tracks don't count as roads at all (GDD open questions).

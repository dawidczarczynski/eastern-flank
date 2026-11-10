# TASK-133: Road classes – dirt, asphalt, expressway, motorway (look and speed)

- **Status**: ready
- **Layers**: tools (importer) + core (data, `HexGrid`, movement) + presentation (road look) + docs
- **Depends on**: TASK-108 (done); soft: TASK-108b (road look, to playtest)
- **Sections**: GDD "Map" (bullet "Road classes"), "Open questions" (bullet "Road classes"); `docs/tasks/TASK-108-terrain-types-from-real-data.md` (link encoding, "Road classes"); ADR 0011 (CC0 textures), ADR 0019
- **Model**: split – see "Suggested split" (133a opus, 133b sonnet, 133c sonnet)

Decision of the human, 2026-11-10: roads are told apart by class, each class **looks different and changes the rules** (speed, hence movement cost). Status stays `idea` until the open questions are answered; then split into 133a-c and mark `ready`.

## Goal

The player sees dirt roads, asphalt roads, expressways and motorways as different things on the real-terrain map, and uses them: a column races along a motorway, crawls along a dirt road through the forest, and the AI picks the fast road.

## Class table (numbers = balancing candidates, in `data/terrain/features.tres`)

| Class | OSM | Cost along link | Width (real) |
|---|---|---|---|
| dirt | `unclassified` w/o paved `surface`, any with unpaved `surface` | 1.5 MP, ≤ terrain cost | 4 m |
| asphalt | `primary`/`secondary`/`tertiary`/`residential`, `unclassified` paved | 1 MP | 7 m |
| expressway | `trunk` | 0.75 MP | 14 m |
| motorway | `motorway` | 0.5 MP | 28 m |

Full mapping, `surface` lists, the `min(terrain, class)` rule and the fixed-point decision: GDD "Map" → "Road classes".

## Layers

**A. Importer + data (`tools/import_map.py`, `ImportedMap`)**
- Class per way from `highway` / `surface` / `tracktype`; per link the highest class wins; class symmetric on both sides of a link.
- New `ImportedMap.road_class_rows` (`PackedStringArray`, 6 chars per tile, direction order = `Hex.DIRECTIONS`, `.` = no link, `1`-`4` = dirt..motorway). `road_rows` stays as the union mask (back-compat). Empty `road_class_rows` → every link is asphalt (today's behaviour).
- Re-import `suwalki` and the fixtures offline from the existing cache (command in `data/maps/CREDITS`). If the cache has no `surface` / `tracktype` tags, stop and ask the human (a re-download would give today's OSM).
- Optional importer flag `--tracks=grade2` (default off) maps `track` with `tracktype` grade1-2 to dirt.

**B. Core cost rules (`HexGrid`, `TerrainFeatures`)**
- `TerrainFeatures`: `move_scale` (4), `road_class_costs` (dirt 6, asphalt 4, expressway 3, motorway 2 in 1/4 MP). `HexGrid.road_class(tile, dir)`, `set_road_class(...)`, `step_cost` = `min(terrain cost of B, class cost)` along a link; river bridge rule unchanged.
- Fixed-point movement points: `moves_left` and costs in 1/4 MP everywhere (`MoveUnitCommand`, `reachable`, `path_to`, preview, AI); display `1.5 / 3 MP`. No float in the simulation (determinism).
- Generated maps have no class data: costs and `tools/simulate.sh 50 --seed=1` summary identical to before.

**C. Presentation (road look)**
- `FeatureRibbonPlanner`: one ribbon batch per class, width from the table via `MapScale` (1.5 px minimum stays); a higher class draws over a lower one at junctions.
- `road.gdshader` per class using the ribbon `across` attribute: dirt = current gravel look; asphalt = CC0 asphalt texture, dashed centre line; expressway = two dark carriageways, thin central barrier; motorway = two carriageways, green median, hard shoulders. Textures: ambientCG / Poly Haven asphalt set (CC0, ADR 0011), listed in the credits file. LOW preset: flat colours without texture.
- Terrain panel tag: `Road`, `Dirt road`, `Asphalt road`, `Expressway`, `Motorway` (+ cost). Menu/scenario preview and the staff map: lines styled per class (staff map already has main/secondary/minor line styles – map classes onto them; no new operational rule).

## Acceptance criteria (testable)

Importer (Python test or fixture check):
- [ ] `highway=motorway` / `motorway_link` -> 4; `trunk` -> 3; `primary`, `secondary`, `tertiary`, `residential` -> 2; `unclassified` no surface -> 1; `unclassified` + `surface=asphalt` -> 2; `primary` + `surface=gravel` -> 1; `motorway` + `surface=dirt` -> 4.
- [ ] Two ways on one link (asphalt + dirt): class 2. `track` is not a road by default; with `--tracks=grade2`: `tracktype=grade1`/`grade2` -> 1, `grade3` -> none.
- [ ] Re-import is byte-deterministic; `suwalki.tres` has >= 1 link of each class that exists in the cache (report counts); `road_rows` equals the union of `road_class_rows`.

Core:
- [ ] `ImportedMap.problem()`: `road_class_rows` wrong size, bad char, class on a link without a `road_rows` bit, asymmetric class -> non-empty message; empty array valid; `to_grid()` sets classes.
- [ ] `step_cost` plains -> plains along each class: 1, 1, 0.75, 0.5 MP (`1.5` capped at terrain 1 for dirt). Into forest (2): dirt 1.5, asphalt 1, expressway 0.75, motorway 0.5. Into hills/marsh (2): same. Into forest river hex along a link: class cost (no +1). Not along a link: unchanged.
- [ ] A unit with 3 MP: along a motorway on plains reaches 6 hexes, expressway 4, asphalt 3, dirt 3; through forest on dirt 2 hexes (3.0), on asphalt 3.
- [ ] `MoveUnitCommand` spends fixed-point cost exactly (motorway 3 hexes = 1.5 MP left 1.5); no float drift over 100 steps.
- [ ] Path choice: motorway detour of 5 hexes (2.5 MP) beats a direct 2-hex forest crossing (4 MP) for a 5 MP budget; AI test: tank ends its move on the far end of the motorway.
- [ ] Missing class data -> all links asphalt; generated maps identical to before (simulate summary); existing replay tests pass.

Presentation:
- [ ] `FeatureRibbonPlanner` widths: dirt 4 m, asphalt 7 m, expressway 14 m, motorway 28 m at scale 250 m/hex; below 1.5 px on screen clamped.
- [ ] A map with all four classes builds four distinct ribbon batches / materials; junction of two classes: higher class on top (draw order test).
- [ ] Terrain panel model returns the class tag and cost for each class.
- [ ] No tree/rock/grass instance closer than half-width + margin to a motorway segment (scatter exclusion uses the per-class width).
- [ ] FPS on `suwalki_battle` not worse than TASK-108b's budget (+0.3 ms).

## Playtest (for the human)

1. Start `suwalki_battle`: the four classes are visually different (dirt gravel, asphalt with centre line, expressway, motorway with median); the motorway is clearly the widest.
2. Select a tank next to a dirt road in forest: reach stretches a little along it (1.5 per hex); next to a motorway: far along it.
3. Hover along each class: path cost shows 1.5 / 1 / 0.75 / 0.5 per hex; the terrain panel names the class.
4. Let the AI play: columns drive on fast roads.
5. Zoom out: roads stay visible as thin lines, the staff map shows class styles.

## Player manual

MANUAL.md: replace "Roads cost 1" (Movement section, lines ~87-98 and the 111 example) by the class table (names, speeds, where each helps, widths as looks); movement points may be fractional (`1.5 / 3 MP`); terrain panel tags; real-terrain map list of what counts as which class; staff map legend (line ~366) with classes; "Not in the game": foot/wheeled differences, access points, weather.

## Out of scope

- Operational-layer road classes, movement types (foot / wheeled / tracked), weather and mud, access points to motorways, bridges over water, forest tracks as roads (except the off-by-default flag), supply along roads (TASK-096), traffic or road damage.

## Suggested split

1. **TASK-133a** (opus): importer + `ImportedMap` + `HexGrid`/`TerrainFeatures` + fixed-point movement + tests + manual. Ready once open questions 1-4 are answered. Delivers the rules; roads still look like one gravel look.
2. **TASK-133b** (sonnet): per-class ribbons, widths, shaders, CC0 asphalt set, panel tag, scatter exclusion. Depends on 133a and TASK-108b (done/playtested).
3. **TASK-133c** (sonnet): staff map and scenario-preview line styles per class. Depends on 133a.

## Decisions (human, 2026-11-10)

1. Fractional MP: **yes**, fixed-point quarters (`move_scale` 4).
2. Foot units gain less from fast roads: **later**, with movement types (out of scope here).
3. Units may join / leave motorways and expressways at any hex: **yes**.
4. `unclassified` without `surface` = dirt, `residential` = asphalt, `track` grade1-2 as dirt only behind `--tracks=grade2` (default off): **yes**.
5. Cache check (agent, 2026-11-10): the operational OSM cache (`~/.cache/eastern-flank/maps/osm/op1_*.json`) holds `surface` tags (hundreds per tile) but no `tracktype`, because the operational query does not fetch `highway=track` (`OP_ROAD_HIGHWAYS`). So class from `highway` + `surface` works offline; `--tracks` would need a new download, so it stays off and is not part of 133a.
6. Numbers 1.5 / 1 / 0.75 / 0.5 and widths remain balancing candidates; check with `tools/simulate.sh --scenario=suwalki_battle`.

## Implementation notes

_Filled in by the agent when done._

# TASK-093a: Staff map (1/3) – the theatre on paper: entry from the menu, 2D pan / zoom camera, land cover, roads, rivers, hex inspector

- **Status**: blocked
- **Layers**: presentation (`src/presentation/operational/`, `scenes/operational/`) + one small pure helper (map → draw data) + docs
- **Depends on**: TASK-092a, TASK-124
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The first thing of the operational layer the human can **click**: from the main menu they open the Suwałki theatre as a flat paper staff map and look around (GDD "Operational map view"). Nothing is simulated yet – this task also makes TASK-092a's real-data import checkable by eye (coastline, lakes, the Gap, roads, rivers), which a unit test cannot do. Every later operational task adds one visible thing to this scene (rule "every operational task is clickable", BACKLOG).

## Acceptance criteria (testable)

Entry:

- [ ] The main menu (TASK-124) has an **Operation** entry that opens the scene `scenes/operational/staff_map.tscn` with the map `suwalki_theatre`; Esc / a Back button returns to the menu. `tools/run.sh --scene=staff_map` (or the existing launch mechanism – the agent checks docs/TOOLS.md) opens it directly for agents and screenshots; `tools/screenshot.sh` can render it headless-equivalent to the battle (extend it with `--scene=`).
- [ ] Rule 3 holds: the scene only reads `ImportedMap` / `HexGrid`; no rules in `src/presentation/operational/`. A loading notice (TASK-080 style) shows while the map is built; the first frame appears in ≤ 3 s on the dev machine (measured and noted).

Drawing (flat, top-down, no 3D):

- [ ] Pure helper `StaffMapLayers` (`src/core/…` only if it needs no `Node`; tests on a small hand-made `HexGrid`): hexes → per-terrain fill polygons smoothed across hex edges (marching squares or per-corner majority – the agent picks and documents), lines for road links and river links as polylines joined across hexes. Tests: a lake hex gives a water polygon, a road link chain gives one polyline, two rivers do not merge, output is deterministic.
- [ ] Paper tint background; forests green, water / lakes / sea blue, marshes with a blue hatch, towns as grey blocks, hills / relief as a low-contrast hillshade from the per-hex elevation; roads as red-orange lines, rivers as blue lines. Colours come from one palette resource, not literals in the scene.
- [ ] 2D camera, fixed top-down: pan with drag / WASD / arrows / screen edge, zoom with the wheel (cursor-centred), clamped to the map; no rotation or tilt. Minimum zoom shows the whole theatre, maximum zoom shows ~10 × 10 hexes.
- [ ] Hex grid **hidden** by default, a faint grid on **G**.
- [ ] Hover inspector (small card in the HUD v3 style): hex coordinate, terrain type, elevation, road / river flags. It follows the cursor hex and hides outside the map.
- [ ] Performance: 60 FPS (focused window) at every zoom level on the dev machine; the map is drawn from cached meshes / textures, not rebuilt per frame (measured with the frame-time overlay and noted; if it misses, the task is not done).
- [ ] Translations for every string (`tr()`, rows in the translation file), `test_localization.gd` green.

## Playtest (for the human)

1. Start the game → **Operation**. The theatre appears: the Baltic and the Curonian Lagoon in the north-west, Kaliningrad oblast, Lithuania, the Gap, Poland's Masuria and Podlasie, western Belarus.
2. Zoom out fully: the whole map fits. Zoom in on Suwałki: roads (S61 / DK8) and rivers (Niemen, Biebrza) look like the real ones; lakes are blue.
3. Press **G**: a faint hex grid; hover a hex: the card names terrain, elevation and road / river.
4. Pan to every edge: the camera stops at the map border. Esc returns to the menu.
5. Spot-check a known place against a real map: Suwałki, Kaliningrad, Grodno, Białystok, Vilnius are where they should be (this is the visual acceptance of TASK-092a).

## Player manual

New chapter "Operational map" (start): opening it from the menu, camera, what the colours and lines mean, the grid toggle, the hex card. Later tasks append their sections (formations 092b, turns 093b, routes 092c, orders 092d, execution 092e, front line 093c). Credits note for the map data (OSM, Copernicus) in the chapter.

## Out of scope

- Formations, turns, orders (later tasks); country borders and stance tints (TASK-113 / TASK-119); place names and a fine relief raster (TASK-112) – until then no labels except what the hex card shows.
- Sound, music, fog of war.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

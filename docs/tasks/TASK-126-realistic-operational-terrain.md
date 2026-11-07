# TASK-126: Realistic operational-map terrain – fine graphic layers instead of per-hex colour

- **Status**: ready
- **Layers**: tools (`tools/import_map.py`), core data (`ImportedMap` graphic layers, no rules), presentation (`src/presentation/operational/`, a shader)
- **Depends on**: TASK-092a, TASK-125 (soft: TASK-113 – it draws the border polylines; do not touch its files)
- **Model**: opus
- **Topic**: Two-layer game
- **Sections**: GDD "Operational map" (map principle), "Operational map view"; ADR 0018; docs/TOOLS.md (import_map)

## Goal

The staff map looks like real geography (human decision 2026-11-07): true coastline and lakes, forests, fields and towns as smooth shapes, relief shading – no hex-shaped colour patches. Hexes stay the rules grid; the grid is a thin optional helper.

## Acceptance criteria (testable)

- [ ] Importer (`--profile=operational`) emits **graphic layers** next to the rules grid, at **250 m per pixel** (≈ 1 360 × 1 108 px for `suwalki_theatre`): `water` (1 bit: sea from the OSM coastline, lakes / reservoirs / wide rivers from `natural=water`, `waterway=riverbank`), `cover` (1 byte per pixel: field, forest, urban, marsh, bare/other; same OSM classes as the hex terrain rules), `relief` (1 byte hillshade from the 90 m DEM, sun from the NW). Stored with the map (`ImportedMap` fields, packed bytes); the rules grid, its fields and `to_grid()` are unchanged (test: existing hex terrain / elevation / country values are byte-identical before and after).
- [ ] **Deterministic**: two offline imports from the same cache give identical layer bytes (test on the tool's fixture cache, `tools/test_import_map.py`); no `random`, sorted iteration, fixed rasterisation order.
- [ ] **Golden tests** on the fixture map: a pixel inside a known lake is `water`; a pixel on the sea side of the coastline is `water`, one a few hundred metres inland is not; a forest polygon gives `cover = forest` inside and not outside; a pixel in a known town is `urban`; a flat DEM gives a constant hillshade, a slope facing the NW is brighter than one facing the SE.
- [ ] Lakes and features smaller than a hex are kept (Wigry-sized lake ≥ 3 px wide stays `water` although its hex is not WATER); the Curonian Spit is visible as land.
- [ ] Round trip: save → load keeps the layers byte for byte; a map without layers (older `.tres`, tactical maps) loads and the staff map falls back to the v0 hex look with a one-time warning (test).
- [ ] The map file stays ≤ 2.5 MB (layers compressed, e.g. PNG/zstd-packed) and load adds ≤ 150 ms; recorded in the notes.
- [ ] The staff map draws water, cover and relief from the layers as **one textured surface** (layers combined in a shader, linear filtering, edges smoothed at least 1 px); **no per-hex colour fill and no hex-edge line is drawn** for terrain (test: scene has no per-hex terrain mesh/fill node; the terrain draw path does not read the hex terrain).
- [ ] Coast and lake edges are antialiased and do not follow hex edges: test samples the rendered/layer value across a coastline hex edge and finds the transition off the edge (≥ 1 px from any hex edge on the golden sample).
- [ ] The **hex grid is a thin helper**: hidden by default, toggled with **G**, ≤ 1 px line at ≤ 25 % alpha, drawn above terrain; test: toggle on/off, default off.
- [ ] Rivers, roads, borders (TASK-113 polylines) and counters keep working on top; when TASK-113 is not merged the borders may stay as they are.
- [ ] Performance: layers are built into GPU textures once at load (no per-frame rebuild); staff map holds **60 FPS** on the target GPU at all zoom levels and in both camera modes (measured with the frame counter and noted); no new per-frame allocation.
- [ ] `suwalki_theatre` re-imported **offline** from the existing cache (`data/maps/suwalki_theatre.tres`), hex values unchanged, `tools/check.sh` green.

## Playtest (for the human)

1. Main menu -> Operation. Zoom to the Baltic coast and the Curonian Lagoon: the shoreline is a natural curved line, not stepped hexes.
2. Pan to the Suwałki lakes (Wigry, Hańcza): they appear as real lake shapes although the hex under them is land.
3. Look at forests and fields: irregular patches with soft edges, towns (Suwałki, Kaunas) as small grey blobs; no hex-shaped colour areas anywhere at any zoom.
4. Press **V** (flat <-> tilt): relief shading is visible in both and the picture stays smooth.
5. Press **G**: a thin faint hex grid appears; hex inspector and counters still follow the hex under the mouse. Press **G** again: it is gone.
6. Feel the frame rate while panning and zooming: smooth, no stutter at the tile/zoom change.

## Player manual

"Operational map" chapter: terrain is drawn from real geography (coasts, lakes, forests, fields, towns, relief); the hexes underneath only decide movement and borders; **G** shows a thin helper grid (default off).

## Out of scope

- Place names (TASK-112), country border polylines (TASK-113), fronts / tints (TASK-093c), road/river re-classification.
- Resolution finer than 250 m, contour lines, seasons, any 3D objects, changes to hex terrain rules or the movement costs.
- Tactical map import.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

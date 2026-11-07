# TASK-125: Staff map restyle – modern dark look, 2.5D camera over a stylised relief

- **Status**: done
- **Layers**: presentation (`src/presentation/operational/`, `scenes/operational/`, a shader) + palette resource + docs; the pure `StaffMapLayers` only gains data it already has (no rules)
- **Depends on**: TASK-093a
- **Model**: opus
- **Topic**: Two-layer game
- **Sections**: GDD "Operational map view" (direction-change note); reference [docs/design/operational_map/](../design/operational_map/README.md) (open the two html files in a browser)

## Goal

The staff map looks like the Claude Design proposal (dark, muted, clean digital tactical map – no paper) **and is 2.5D** (decided by the human, 2026-11-07): a tilted camera over a mildly extruded, stylised relief, clearly different from the 3D battle (no unit models, no battle terrain). The designer recommended a flat view and warned that tilt compresses the north and makes lines uneven; this task answers those objections instead of dropping the tilt.

## Acceptance criteria (testable)

Look (replaces the paper v0 of TASK-093a; palette stays one resource, names as in the reference README):

- [ ] `StaffMapPalette` gets the reference colours (`map.void/land/forest/urban/marsh`, `water.*`, `river.*`, `road.t1–t3`, `rail`, `border`, `side.own/enemy/neutral`, `ui.*`); the paper tint, red-orange roads and green forest of v0 are gone. Land `#1d211c`, forest a slight hue shift + edge, towns grey block, marsh hatch, sea / lakes dark blue with a 1 px shore line.
- [ ] Hillshade from the per-hex elevation (az 315°, alt 38°, soft-light ~0.8) baked into the base; stronger (×1.4) at the far zoom.
- [ ] Line widths per zoom level Z0 / Z1 / Z2 as in the reference (roads t1 1.3 / 1.9 / 2.4 px …), **constant in screen pixels under zoom and tilt**; road t1 with dark casing. Line classes become separate meshes; the importer data we have is enough (full OSM classification / simplified geometry stays TASK-112). Layers fade in by zoom with 150 ms and ±10 % hysteresis.
- [ ] Grid still hidden by default, `G` shows it (12 % on every zoom).

2.5D:

- [ ] Perspective (or oblique-orthographic – the agent picks and documents) camera with **pitch**: default ~35°, range 0° (flat) … 50°, changed with `Ctrl` + wheel or `Q` / `E` and a `V` toggle flat ↔ tilt; no yaw (north stays up so labels read). Pan / cursor-centred zoom / clamp to the map as in v0, in the ground plane. `StaffMapCameraMath` holds the maths, with tests (pitch 0 reproduces v0 numbers; clamp; cursor-centred zoom with tilt).
- [ ] Relief: ground mesh displaced by the per-hex elevation with a stylised exaggeration (starts ~3×, a palette value), smooth across hexes; **picking** uses a ray against that surface (or the ground plane plus a documented correction) – test: hover returns the right hex at pitch 0, 35° and 50° on a hand-made grid with a ridge; max error < ½ hex.
- [ ] Anti-compression: at the default pitch the far (north) edge keeps ≥ 70 % of the near edge's pixels per hex (field of view / pitch chosen for it – measured and noted); labels, lines and later counters are **screen-space** objects (billboards / px-width ribbons), so the tilt never makes them uneven.
- [ ] The hover card, G grid and Back / Esc work at every pitch; the minimum zoom still shows the whole theatre, the maximum ~10 hex rows.
- [ ] Performance: 60 FPS (focused window) at every zoom and pitch on the dev GPU – cached meshes, one displaced ground mesh (chunked if needed), no per-frame rebuilds; measured with the frame-time overlay and noted. If it misses, the task is not done (a quality level may drop the relief, never the frame rate).
- [ ] `tools/screenshot.sh` renders the staff map at `pitch:0` and `pitch:35` (extend `SCREENSHOT_STAFF_MAP` with `pitch:N`); Read both and describe only what you see.
- [ ] Strings `tr()`, `test_localization.gd` green.

## Playtest (for the human)

1. Start → **Operation**: the map opens dark and tilted, relief visible on the lake district hills, no paper look.
2. `V`: flat and tilted views both look right; compare the north and south edge – hexes should not be tiny at the top.
3. `Ctrl` + wheel (or `Q` / `E`): pitch changes smoothly; wheel zoom stays under the cursor; pan stops at the map border.
4. Hover hexes near a ridge and near the far edge: the card names the hex under the cursor, not a neighbour.
5. Zoom Z0 → Z2: roads / rivers keep their pixel width, small features fade in; `G` shows the grid.
6. Check 60 FPS in all of the above (frame-time overlay).

## Player manual

Update the "Operational map" chapter: new look (legend of roads / rivers / terrain), camera controls incl. pitch, `V`.

## Out of scope

- Counters, orders, front line, turn bar and panels (TASK-092b … 093c, restyled there to the reference); borders and country tints (TASK-113 / 114); place-name labels and the fine DEM raster (TASK-112); yaw rotation; any 3D units.

## Implementation notes

- **Camera: tilted orthographic** (`StaffMapCameraMath`), pitched about the east axis only (no yaw), default 35°, 0–50°, Ctrl + wheel (5°/notch, smoothed), Q / E held (60°/s), V flat ↔ last tilt. The v0 2D state is kept (position in world px, zoom = screen px per world px); the ground plane is handled through a "ground viewport" (height / cos pitch), so pitch 0 reproduces v0 exactly (tested) and clamp / cursor-centred zoom stay the v0 functions. **Anti-compression measured** in `test_staff_map_relief.gd`: projected hex area far edge / near edge at 35° = **1.00** (orthographic: no perspective shrink; the same test with a 30° FOV perspective camera would give ~0.56). The 2.5D cue is the uniform foreshortening (cos pitch) plus the displaced relief and hillshade.
- **Relief** (`StaffMapRelief`, pure): per-hex height over the mean land height, interpolated linearly on the lattice of hex centres (the same triangles as the fills), so the surface is continuous. **Exaggeration 20×** (palette `relief_exaggeration`), not ~3×: the theatre's relief is 0–263 m on 5 km hexes, at 3× that is 0.27 hex units – invisible at every zoom. Picking: the camera ray marched against the surface + bisection (`raycast`); tested on a ridge grid at pitch 0 / 35 / 50 with 30× exaggeration: max error < 0.05 hex units (a plane pick misses by a hex there, also tested).
- **Hillshade** az 315°, alt 38°, soft-light 0.8, from per-hex slopes with a shading-only z factor (20, palette); baked per vertex, blended in the ground shader; gain ×1.4 at Z0.
- **Lines** are screen-space ribbons (`assets/shaders/staff_map_line.gdshader`, mitred joints in screen space, 1 px AA fringe, no depth test, render_priority orders the layers), one mesh per class built once (`StaffMapLines`): land-cover edges (forest, town), shore, rivers minor / named / major, roads t3 / t2 / t1 (+ casing), grid, hover outline. Road and river classes come from the link data via **strokes** (`StaffMapLayers.strokes`: links continued straight through junctions) ranked by length (palette km thresholds; t1 ≥ 100 km, t2 ≥ 40 km; rivers major ≥ 80 km, named ≥ 40 km). No rail / canal data yet (rail colour and widths are in the palette, no layer).
- **Zoom levels** by px/km at the screen centre with ±10 % hysteresis; thresholds 5 / 9 px/km (palette) instead of the reference's 1.6 / 5, which are for a continental extent – the 340 km theatre already shows 3–5 px/km at full overview. Layers fade and widths change over 150 ms (`StaffMapView._process`, only while a fade runs).
- Sea vs lakes: water connected to the map edge and ≤ 5 m (`StaffMapLayers.sea_tiles`). Faint overlays (grid 12 %, hover fill 10 %) get their alpha converted so the linear-light blend matches the reference's sRGB mix.
- Screenshot: `SCREENSHOT_STAFF_MAP=pitch:N` (with `zoom:min` resolved after the pitch).
- **Not measured: FPS** (the agent cannot run the frame-time overlay). Nothing is rebuilt per frame: the ground is one mesh (~50 k triangles), each line class one mesh, uniforms change only during a 150 ms fade or a zoom / pitch change, the hover outline only when the hovered hex changes.

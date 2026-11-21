# TASK-204: Map edge and backdrop at real scale – no visible end of the map

- **Status**: idea
- **Layers**: presentation (`BackdropMesh`, `BackdropTypes`, `BackdropCanopy`, `ForestShell`, `MapView`, camera clamp), data (`TacticalLayer` read beyond the playable rect)
- **Depends on**: TASK-135, TASK-108g, TASK-190 (soft: TASK-192, TASK-189)
- **Sections**: ARCHITECTURE "Real-scale vegetation", "Chunked lazy world"; ADR 0026; TASK-052 (backdrop ring); look reference (TASK-190)
- **Model**: opus (data beyond the playable rect, LOD of a large ring, seams)
- **Tags**: battle-look

## Goal

The end of the playable map does not show: the landscape continues past it as real terrain, with the same forests, colours and haze, and fades into the horizon – instead of the dense forest and hexes stopping at a line in front of a flat, featureless olive plain with a few dots for trees (human, 2026-11-21; screenshots `.screenshots/edge/`).

## Acceptance criteria (testable)

- [ ] The backdrop ring (`BACKDROP_WIDTH` 14 units ≈ 2 km) takes its ground heights and land cover from the real data around the playable map (the theatre `TacticalLayer` / DEM beyond the rect, via TASK-108g's `LandCover`), not from copies of the border hex types (`BackdropTypes`); where no data exists (outside the layer) it falls back to the border copy with the same fade.
- [ ] Forest over the ring has the same look as on the map: the canopy shell (lit crowns, atlas colours, tone matched; `ForestShell` / `canopy.gdshader`) over the ring's forest cover, with tree impostors in the inner part of the ring (their range is the impostor range) – no step in density, colour or brightness at the map border (screenshot crop comparison, ≤ 10 % mean-luminance difference across the border).
- [ ] Ground colour and detail continue across the border: the ground splat / satellite colour (TASK-192 when present) covers the ring; the ring's value / saturation factors (`BACKDROP_VALUE` / `BACKDROP_SATURATION`) are retuned so the border is not visible at distances 5, 12 and 24.
- [ ] The hex-shaped cut of forest, bare ground and villages at the border is gone (follows from the land-cover raster); the hex overlay may end at the border, the landscape may not.
- [ ] The ring's outer edge ends in haze (TASK-190's aerial perspective) and sky: no visible rim, seam or hard cut at any camera height and yaw on the Suwałki map; the horizon band is checked at the camera's lowest pitch.
- [ ] The camera target stays inside the playable rect (clamp with a soft stop); the camera at its widest zoom over a corner shows no void.
- [ ] Planning of the ring stays off the main thread and chunked (ADR 0024): memory and plan cost of the ring recorded; frame time at 1.2 / 5 / 24 over the east, south and a corner edge ≤ 16.7 ms (RX 580, `true`, HIGH, 720p).
- [ ] `balanced` unchanged apart from the shared data path (golden test of the backdrop output).
- [ ] Screenshots Read: four edges and a corner at 5 / 12 / 24 before and after, each compared with the reference views (human, 2026-11-21).

## Playtest (for the human)

1. `true` preset, Suwałki: pan to every edge and corner at several zooms – the landscape continues, forests and fields do not stop at a line, the far end fades into haze.
2. Zoom to the widest view over an edge and a corner: no flat plain, no hard rim.

## Player manual

None (look only).

## Out of scope

- Making the ring playable; the operational map's own borders; terrain outside the theatre layer (falls back to the border copy).

## Implementation notes

_Filled in by the agent when done._

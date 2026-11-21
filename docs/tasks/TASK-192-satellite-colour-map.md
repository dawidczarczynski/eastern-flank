# TASK-192: Real-scale look (C): terrain and forest colour from Sentinel-2 imagery

- **Status**: idea
- **Layers**: tools (`tools/import_map.py`), presentation (terrain / canopy shaders, `ImportedMap`)
- **Depends on**: TASK-190 (soft: TASK-191)
- **Sections**: ARCHITECTURE "Terrain", "Real-scale vegetation"; ADR 0018 (maps from real geography); look reference (TASK-190)
- **Model**: opus (data pipeline, licence, shader blending)

## Goal

The terrain reads like the reference from above: mottled meadows, distinct field parcels and forests in their real colours, because the far terrain and the canopy take their colour from real satellite imagery of the map (as Arma blends a satellite colour map in the distance), while the near ground keeps the detail textures.

## Acceptance criteria (testable)

- [ ] Research first, recorded in an ADR: source and licence of a cloud-free summer mosaic (Copernicus Sentinel-2 L2A, 10 m, free and open with attribution – same ecosystem as the GLO-30 DEM; or a mosaic product such as EOX s2cloudless, licence per year), how it is downloaded offline-repeatably, colour correction (L2A → sRGB, haze, seasonal look), file size per map.
- [ ] `tools/import_map.py` writes a colour layer for the map (≤ 10 m per pixel, compressed, byte-identical on re-import), attribution in `data/maps/CREDITS`; a Python test on a fixture.
- [ ] The terrain shader blends the colour layer over the splat textures with distance (near: textures + a light tint from the layer; far: the layer), and the canopy shell uses the layer's colour over forest; both only under `true` (`balanced` unchanged, test).
- [ ] Field parcels (`ParcelMap`) keep their crop colours near the camera and agree with the layer from afar (no colour jump at the blend distance, screenshot).
- [ ] Frame time unchanged within 0.5 ms (one more texture sample); memory of the layer recorded.

## Playtest (for the human)

1. `true` preset, Suwałki, widest zoom: fields, meadows and forests look like the satellite view of the area; compare with the reference.
2. Zoom in: the satellite colour gives way to the ground textures without a visible seam.

## Player manual

None (look only).

## Out of scope

- Buildings, roads and villages from imagery; seasons / weather.

## Implementation notes

_Filled in by the agent when done._

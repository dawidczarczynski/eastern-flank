# TASK-215: Real field parcel boundaries – import and draw

- **Status**: idea
- **Layers**: tools / presentation data (`tools/import_map.py`, `ImportedMap`), presentation (`FieldParcels`, `ParcelMap`, terrain shader)
- **Depends on**: TASK-200 (soft: TASK-192b)
- **Sections**: ADR 0018 (maps from real geography), ADR 0031 (satellite colour layer), ARCHITECTURE "Terrain"; TASK-200
- **Model**: opus
- **Tags**: battle-look

## Goal

Farmland is cut into the parcels that really exist, not into procedural strips clipped by the land-cover outline: fields have straight boundaries, real sizes (typically 1–10 ha) and realistic neighbours, so the patchwork reads like the satellite view. Hexes stay mechanics only.

## Background

TASK-108f cuts farmland into 150–400 m strips (up to 2.5 km long) and TASK-108g clips them by the noisy land-cover outline, so fields look like large rounded blobs with few straight edges (human feedback, 2026-11-23). TASK-200 colours and rows those parcels but does not change their shapes.

## Acceptance criteria (draft – refine before implementing)

- [ ] Research first, recorded in a new ADR: sources of real parcel boundaries for the Suwałki theatre (OSM `landuse=farmland|meadow|orchard`, field polygons from the Sentinel-2 composite of TASK-192a, national LPIS / EGiB open data), coverage, licence and attribution, size per map, importer cost; decision which source (or combination) is used.
- [ ] The importer writes the parcel polygons (committed, byte-identical on re-import, CREDITS updated) in a compact format with a loader in `ImportedMap`.
- [ ] `FieldParcels` / `ParcelMap` bake from the polygons when present (crop by the TASK-200 rule per polygon); maps without them keep the procedural strips; `balanced` unchanged (test).
- [ ] Parcel sizes on the Suwałki theatre are recorded (median, 10th / 90th percentile) and compared with the strips'.
- [ ] Frame time within 0.3 ms of TASK-200; bake time and memory recorded.
- [ ] Screenshots Read at 1.2 / 5 / 24 against the reference; deviations stated.

## Playtest (for the human)

1. `true` preset, Suwałki: fields have straight real-looking edges and mixed sizes; compare with the satellite view.

## Player manual

None (visual only).

## Out of scope

- Buildings (TASK-193+), field roads / tracks (TASK-202), animated crops.

## Implementation notes

_Filled in by the agent when done._

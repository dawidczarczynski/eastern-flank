# TASK-196: Building facades and roofs textured by rules

- **Status**: idea
- **Layers**: presentation (`building_facade.gdshader`, `BuildingStyle` data, materials)
- **Depends on**: TASK-194
- **Sections**: ADR for buildings (TASK-193); ADR 0025 (textures in real metres); look reference (TASK-190)
- **Model**: opus
- **Tags**: battle-look

## Goal

Buildings look finished, not like grey boxes: every wall and roof is textured by rules from the building's type, age, region and a hash of its footprint – wall materials, windows and doors laid out by a grammar, roofs with the right tile and colour, weathering – so a village looks like one from Mazovia / Podlasie and each house still differs.

## Acceptance criteria (testable)

- [ ] Style rules are data (`data/buildings/*.tres`, class in `src/core/data/` or `src/presentation/`): per type (house, farm, barn, apartments, industrial, silo, shed) and era (pre-war, 1960–89, post-2000): wall material pool (plaster in a regional palette, brick, wood, concrete panel, sheet metal), roof material pool (red clay tile, grey cement tile, bitumen, asbestos-cement grey, sheet metal), floor heights, window grid (width, spacing, sill, share of wall), door rule, colour jitter; OSM tags (`building:material`, `roof:colour`, `start_date`) override the pools.
- [ ] A pure `BuildingStyle.pick(tags, footprint_hash) -> params` is deterministic and unit-tested (same footprint, same params; the spread over 1 000 houses covers every palette entry; tagged brick stays brick).
- [ ] CC0 tileable PBR materials (albedo / normal / roughness) for the pools from ambientCG or Poly Haven (licence and attribution in `data/maps/CREDITS` or `assets/third_party/`), in a texture array; scale in real metres through `MapScale`.
- [ ] `building_facade.gdshader` lays windows, doors and plinths per wall in wall space (metres): rows by floor count, windows centred in bays, doors on the street-side wall, blank gable walls on barns, strip windows on halls; per-building parameters travel as instance custom data; no per-building texture.
- [ ] Weathering by rule: darker plinth, vertical stains under sills, moss / dirt on old roofs, brighter new plaster; strength from the era.
- [ ] Roofs: tile / sheet pattern in real metres, ridge and edge trim, lighter sun side by the scene's sun.
- [ ] Frame time over the densest village <= 1 ms more than flat-shaded buildings (RX 580, HIGH, 720p); memory of the texture array recorded.
- [ ] Screenshots Read: a village at 0.4 / 1.2 / 5 and a block estate at 1.2 – compared with the reference images (human, 2026-11-21): houses read as houses, roofs red / grey, no texture stretching on gables.

## Playtest (for the human)

1. Fly over villages and Suwałki: houses differ from each other but belong to one region's style; blocks look like blocks; barns and halls look industrial.
2. Zoom from far to ~100 m: the facade fades in without swimming textures.

## Player manual

None.

## Out of scope

- Interiors; landmark buildings (TASK-197); weather and seasons.

## Implementation notes

_Filled in by the agent when done._

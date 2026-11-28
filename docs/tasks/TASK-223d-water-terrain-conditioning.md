# TASK-223d: Water network (4/7): render heightfield and terrain shaped by the water – channels, cut banks, floodplains, lake shores

- **Status**: blocked
- **Layers**: core (heightfield data + conditioning, pure) + presentation (terrain chunks read it)
- **Depends on**: TASK-223c
- **Sections**: ADR 0034 decisions 2, 3; ARCHITECTURE "Chunked world" (ChunkManager), CLAUDE.md performance budget
- **Model**: opus
- **Tags**: battle-look

## Goal

The ground has real river valleys and lake shores: water lies in a channel below steep or gentle banks, lakes sit at their own level without pits, and the hex-blended relief no longer decides where water goes.

## Acceptance criteria (testable)

- [ ] A render heightfield at 25 m (try 50 m if memory / load time demand; decision with numbers in the notes), chunked, from the DEM (importer adds the raster if the current data is too coarse), not tied to hexes; `TerrainSurface` reads it when present.
- [ ] Conditioning by `WaterNetwork`: bed under the water (flat for the middle third, rising to the surface at the water edge), bank slope to the bank top, cut bank (≥ 35°) on the outer side of bends, floodplain ≤ 1.5 m above the surface on the inner side within a width scaled by the river width, lake bed at the lake level minus a shore profile; the global y = 0 plane no longer decides lake depth.
- [ ] 223a's validator: zero `dry_bed`, `flooded_bank`, `shallow` on Suwałki (theatre 47,45 cut and the battle map).
- [ ] Load time and memory measured with `ChunkManager.stats()` before / after on Suwałki; battle load grows by ≤ 1.5 s; 60 FPS on HIGH kept.
- [ ] Removes the 2026-11-28 stop-gap `RiverChannel` (its tests move to the new conditioning).

## Playtest (for the human)

1. Terrain viewer 47,45: rivers lie in valleys; on the outer side of bends a steep bank, on the inner side flat meadow.
2. Lakes are shallow basins at their own level, rivers enter them without a step.

## Player manual

None (look only; crossing rules in 223f).

## Out of scope

- Water meshes and bank materials (223e).

## Implementation notes

_Filled in by the agent when done._

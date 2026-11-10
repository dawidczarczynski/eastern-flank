# TASK-134: Terrain LOD and real-metre ground textures near the camera

- **Status**: ready
- **Layers**: presentation (`MapView` terrain mesh, `TerrainGround`, terrain shader)
- **Depends on**: – (soft: TASK-110, TASK-111)
- **Sections**: GDD "Visual direction", "Open questions" (Realistic scale); ADR 0021
- **Model**: opus (mesh LOD, seams, performance)

## Goal

At the close camera of TASK-111 (down to ~1 unit) the ground looks like real ground: a fine mesh near the camera and textures repeating in real metres, instead of 36 m "folded paper" and a smeared pattern.

## Acceptance criteria (testable)

- [ ] Terrain vertex spacing near the camera ≤ 5 m (≤ 0.035 units) within a radius of 3 units around the look-at point; beyond ~8 units it is today's 36 m (4 vertices / unit).
- [ ] Seams: no gaps or T-junction cracks between LOD rings (test: vertex heights on a ring border equal the coarser edge's interpolated heights ± 1 mm).
- [ ] The near mesh samples the same height function as the core tile heights (± 0.001 units at tile centres); a unit placed at a tile centre touches the drawn surface (error ≤ 0.1 m = 0.0007 units).
- [ ] `TerrainGround` texture repeat is derived from `MapScale` (1 repeat = a real-metre size per layer, not 7.7 m / unit), plus a detail texture that fades in below distance ~6 units.
- [ ] Frame time on Suwałki at distances 24 / 7 / 1.2 is not worse than the ADR 0021 table (≤ 17.8 / 17.0 / 14.0 ms avg on the RX 580).
- [ ] LOW quality keeps the single coarse mesh.

## Playtest (for the human)

1. Suwałki, zoom to the minimum: ground is smooth, no cracks while panning, a tank sits on it (not sunk).
2. Zoom out: no visible pop or seam lines between mesh rings.

## Player manual

None (look only); MANUAL §10 camera notes are written by TASK-111.

## Out of scope

- Vegetation (TASK-135), unit models, effects.

## Implementation notes

_Filled in by the agent when done._

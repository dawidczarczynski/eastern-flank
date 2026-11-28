# TASK-223e: Water network (5/7): rendering – flat water surfaces per river and lake, shoreline from the terrain, bank materials, bridges

- **Status**: blocked
- **Layers**: presentation (water meshes, `water.gdshader` / `river.gdshader`, terrain splat, bridges)
- **Depends on**: TASK-223d
- **Sections**: ADR 0034 decision 4; ARCHITECTURE "River water and bridges"
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Water looks real and reads as a barrier: a calm, sky-reflecting surface whose shoreline is where the ground meets it, banks that look like soil, grass or reeds as their slope demands, bridges that span it.

## Acceptance criteria (testable)

- [ ] Each reach and each body gets a flat water mesh at its `WaterNetwork` level, wider than the channel by the bank band, so the terrain cuts the shoreline; the global plane stays for the sea only; the ribbon's painted water edge is removed.
- [ ] Reach meshes follow the surface profile (flat across, falling along); at junctions the meshes meet without a gap or overlap step (test: heights equal at the seam).
- [ ] Bank material from slope and context (terrain splat): ≥ 30° exposed soil / clay, gentle banks grass, reeds on flat banks of shallow water, sand only on point bars and tagged beaches; thresholds in a `.tres`.
- [ ] Shape smoothing: river outlines from data smoothed (Catmull-Rom); noise only as bank detail ≤ 10 % of the width, never moving the centre line.
- [ ] Bridges from 223b data: span = the water crossing + abutments, deck above the surface with clearance; validator `bridge_short` zero.
- [ ] Readability: from the default gameplay camera over Suwałki, water contrasts with forest, fields and meadow (screenshots Read by the agent, compared and described in the notes).
- [ ] 60 FPS on HIGH kept (measured with `SCREENSHOT_MEASURE_FRAMES`).

## Playtest (for the human)

1. Battle on Suwałki: rivers and lakes calm and reflective, shoreline follows the ground, no painted strip.
2. Zoom close at a bend: steep soil bank outside, grass / reeds inside; bridges reach both banks.

## Player manual

"Roads and rivers": rivers and lakes drawn from real geography.

## Out of scope

- Riparian vegetation (223g), crossing rules (223f).

## Implementation notes

_Filled in by the agent when done._

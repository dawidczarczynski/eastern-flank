# TASK-201: Real-scale shadows and scene lighting – forest shadows, long sun range, grade

- **Status**: idea
- **Layers**: presentation (sun, `GraphicsQuality`, `LookPreset` grade)
- **Depends on**: TASK-191
- **Sections**: ARCHITECTURE "Graphics quality"; ADR 0023 (frame budget); look reference (TASK-190)
- **Model**: opus

## Goal

The landscape has the contrast and depth of the reference: forests cast soft shadows on meadows and slopes, hillsides facing away from the sun are visibly darker, light is warm, and the colour grade ties it together – within the frame budget.

## Acceptance criteria (testable)

- [ ] Shadow plan decided and recorded (ADR): cascaded sun shadows with a longer far cascade under `true` (distance in metres through `MapScale`), whether impostors / the canopy shell cast (a cheap proxy: forest hexes darken the terrain by a baked or per-chunk shadow mask) and the cost of each option measured on the RX 580.
- [ ] Terrain and trees receive a visible, stable shadow from forest edges and relief at the default camera range (no shimmering when the camera moves, no peter-panning on trunks); LOW keeps its current setup.
- [ ] Sun direction, colour and ambient are data in the look (`LookPreset`): a warm, lower sun for `true` (reference: golden-hour feel without crushing the shadows); `balanced` unchanged.
- [ ] Colour grade for `true`: saturation / contrast / shadow-tint values tuned from the reference screenshots (recorded) and applied by the existing grade path.
- [ ] Frame time at 1.2 / 5 / 24 <= 16.7 ms avg on the RX 580 (`true`, HIGH, 720p), or the shortfall and the quality level that holds it recorded.
- [ ] Screenshots Read at 5 / 12 / 24: shadows on slopes and behind forests, no light leaking, tone matching the reference.

## Playtest (for the human)

1. `true` preset: orbit the camera around a forest and a hill – shadows move with the sun's direction consistently, no flicker, contrast like the reference.
2. Frame rate while panning.

## Player manual

None.

## Out of scope

- Time of day / weather; volumetric light rays.

## Implementation notes

_Filled in by the agent when done._

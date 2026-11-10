# TASK-137: Real-size effects, decals and tracks

- **Status**: blocked
- **Layers**: presentation (`MuzzleFlash`, `MotionFx`, `WreckView`, `GroundMarks`, `RocketVolley`, unit rings)
- **Depends on**: TASK-136 (soft: TASK-134)
- **Sections**: GDD "Visual direction"; ADR 0021; TASK-110 notes "Inventory: scatter, effects, HUD anchors"
- **Model**: sonnet

## Goal

Effects match the real-size models: a muzzle flash of a few metres, dust and smoke puffs of metres, small craters, real-width tracks – and still readable at the closest camera.

## Acceptance criteria (testable)

- [ ] Sizes derive from `MapScale` (metres → units): flash 3–5 m, dust 5–15 m, wreck smoke puffs 5–20 m, columns 50–100 m, craters 2–5 m, scorch impact/death/wreck 5/10/20 m, tracks 3.7 m wide, launch flash 5–10 m; tested as pure size functions at 144.34 m / unit (± 5 %).
- [ ] `balanced` preset values unchanged (factor 1).
- [ ] Rockets 4–8 m long; trajectories stay the stylised arc (apex unchanged).
- [ ] Hex rings and path dots stay hex-sized; the ring band is thinned to ≥ 2 px wide when the camera is closer than 3 units.
- [ ] Effects that fall below 2 px on screen at the default zoom keep a pixel-size floor (flash and smoke visible when units fire from 24 units away).
- [ ] Screenshots Read by the agent: firing, moving, wreck, crater at distances 24, 7, 1.2; frame time not worse than before.

## Playtest (for the human)

1. Fire, move and destroy units at three zoom levels: effects look proportionate and are still visible when zoomed out.

## Player manual

None (look only).

## Out of scope

- Default preset switch (TASK-138); sound.

## Implementation notes

_Filled in by the agent when done._

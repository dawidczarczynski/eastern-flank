# TASK-212: Continuous tactical space (8/9): terrain look and objective markers without the hex grid

- **Status**: blocked
- **Layers**: presentation
- **Depends on**: TASK-208
- **Sections**: ADR 0028, ADR 0029; ARCHITECTURE "Chunked world", "Terrain rendering"
- **Model**: sonnet
- **Tags**: continuous-space, battle-look

## Goal

The terrain look reads the metric data (land cover raster, height at a point), so it no longer needs the tactical hex grid.

## Acceptance criteria (testable)

- [ ] `scatter_planner`, `grass_planner`, `feature_ribbon_planner`, `field_parcels`, `forest_fill`, `hex_forest_mask_source`, `backdrop_types`, `overlay_geometry`, `scenario_preview` take a `TacticalMap` / `LandCover` and positions in metres; no `Hex.*` or `HexGrid` use remains in battle code (grep test).
- [ ] `objective_markers` draw circular zones of the objective radius; the grid layer of `MapView` is removed from the battle (the operational staff map keeps its grid).
- [ ] The rendered battle looks the same on maps with a raster (screenshot before / after, Read, differences stated); generated maps without a raster still render.
- [ ] 60 FPS budget unchanged (frame-time numbers in the notes); planning time of a cut unchanged or lower.
- [ ] `tools/readme_screenshot.sh` re-run and the images committed.

## Playtest (for the human)

1. Open a battle on the Suwałki map: forests, fields and villages look as before; objective zones are circles; no tile outlines anywhere.

## Player manual

none

## Out of scope

- Operational map visuals.

## Implementation notes

_Filled in by the agent when done._

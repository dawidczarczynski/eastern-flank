# TASK-180: GLB measurements: section profiles and part detection into measurements.json

- **Status**: ready
- **Layers**: tooling (presentation tools, no game rules)
- **Depends on**: TASK-179
- **Sections**: ADR 0010 (budgets), ADR 0014 (mechanisms), docs/TOOLS.md (render_unit, unit_catalog)
- **Model**: opus

## Goal

Extract from the normalised GLB the constants a procedural model starts with (hull length, deck / roof height, turret centre and ring radius, gun trunnion and overhang, wheel positions and radii, hull half widths), so the modeler stops guessing them from photos.

## Acceptance criteria (testable)

- [ ] Height and half-width profiles along the length every 0.1 m (hull and, separately, everything above the deck) in `measurements.json`.
- [ ] Part detection from connected components and heuristics: turret (largest component above the deck), gun (thin long component from the turret), wheels (repeated cylinders: count, positions, radii); each value carries `confidence` 0..1 and a name matching the model constants (`DECK_H`, `ROOF_H`, `TURRET_X`, `TURRET_RING_R`, `TRUNNION`, `UPPER_HW`, `LOWER_HW`, ...).
- [ ] Foot units: height and proportions only.
- [ ] Verified on the GLBs of T-72B3 and M1A2: measured values within 5 % of the constants in their model files (report the table in Implementation notes; differences judged by the human).
- [ ] Low-confidence or catalog-conflicting values are listed under `warnings`, never silently used.
- [ ] Unit tests on synthetic GLBs (box hull + cylinder turret + cylinder wheels).

## Playtest (for the human)

1. Run the analysis on a GLB of a unit that already has a model.
2. Compare `measurements.json` with the constants at the top of its model file; large differences should be explainable.

## Player manual

none

## Out of scope

- Shipping the GLB in the game or importing it as an asset: it is a reference only (the game model stays procedural, MeshKit). GLBs live outside git; `measurements.json` and reference renders are committed.

## Implementation notes

_Filled in by the agent when done._

# TASK-179: GLB reference: normalise a Meshy GLB and render orthographic reference views

- **Status**: ready
- **Layers**: tooling (presentation tools, no game rules)
- **Depends on**: –
- **Sections**: ADR 0010 (budgets), ADR 0014 (mechanisms), docs/TOOLS.md (render_unit, unit_catalog)
- **Model**: sonnet

## Goal

A Meshy GLB replaces photos as the unit's reference (human decision 2026-11-18): `tools/analyze_glb.sh <id>` loads `docs/design/units/units/<id>/reference.glb` headless in Godot (`GLTFDocument`), normalises it with the catalog dimensions and renders the same views as `tools/render_unit.sh`.

## Acceptance criteria (testable)

- [ ] Normalisation: front axis = longest axis (override `--front=±x|±z`), uniformly scaled so the length equals `dimensions.hull_length` (foot units: height), centred on x/z, standing on y = 0; the applied transform is written to `normalisation.json`.
- [ ] Renders side / front / top / three_quarter (orthographic at the same scale and framing as render_unit) into the unit folder (`reference_views/`).
- [ ] `tools/render_unit.sh <id>` uses the side view as `--reference` when no photo is given.
- [ ] A GLB with no mesh or a bounding box differing > 25 % from the catalog dimensions exits 1 with a message.
- [ ] A test with a tiny fixture GLB (box with a known size) checks scale, ground level and front detection; `docs/TOOLS.md` documents the tool; `.gitignore` keeps `reference.glb` out of git.

## Playtest (for the human)

1. Put a GLB at `docs/design/units/units/t72b3/reference.glb`, run `tools/analyze_glb.sh t72b3`.
2. Open the four views: the tank stands level, the barrel points the right way, the proportions match the catalog.

## Player manual

none

## Out of scope

- Shipping the GLB in the game or importing it as an asset: it is a reference only (the game model stays procedural, MeshKit). GLBs live outside git; `measurements.json` and reference renders are committed.

## Implementation notes

_Filled in by the agent when done._

# TASK-182: Catalog and /model-unit use the GLB reference and the IoU gate

- **Status**: blocked
- **Layers**: tooling (presentation tools, no game rules)
- **Depends on**: TASK-179, TASK-180, TASK-181
- **Sections**: ADR 0010 (budgets), ADR 0014 (mechanisms), docs/TOOLS.md (render_unit, unit_catalog)
- **Model**: sonnet

## Goal

Uploading a GLB in the unit catalog is enough to prepare a unit for modelling, and `/model-unit` builds from the measurements and finishes when the silhouettes match.

## Acceptance criteria (testable)

- [ ] `unit.json`: `reference_glb` view; `ready_for_model` accepts a GLB in place of a `side` image (and relaxes the silhouette features minimum to 1 when a GLB exists); the contract in docs/design/units/README.md is updated.
- [ ] `tools/unit_catalog.sh`: GLB upload button; after upload the analysis (179 + 180) runs as a headless job (ADR 0008) and shows the views and warnings.
- [ ] `/model-unit` step 0 runs the analysis; the agent gets `measurements.json`, the diff images and the IoU target; it stops at IoU >= threshold or after 4 iterations and reports the numbers.
- [ ] `.claude/agents/unit-modeler.md` tells it to take constants from `measurements.json` and judge by IoU, details from photos / features.
- [ ] Python tests of the catalog cover the upload and the new gate.

## Playtest (for the human)

1. In `tools/unit_catalog.sh` upload a GLB for a new unit, wait for the analysis.
2. Run `/model-unit <id>`: it reports the final IoU and the render sheet.

## Player manual

none

## Out of scope

- Shipping the GLB in the game or importing it as an asset: it is a reference only (the game model stays procedural, MeshKit). GLBs live outside git; `measurements.json` and reference renders are committed.

## Implementation notes

_Filled in by the agent when done._

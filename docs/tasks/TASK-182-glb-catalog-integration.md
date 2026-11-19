# TASK-182: Catalog and /model-unit use the GLB reference and the IoU gate

- **Status**: done
- **Layers**: tooling (presentation tools, no game rules)
- **Depends on**: TASK-179, TASK-180, TASK-181
- **Sections**: ADR 0010 (budgets), ADR 0014 (mechanisms), docs/TOOLS.md (render_unit, unit_catalog)
- **Model**: sonnet

## Goal

Uploading a GLB in the unit catalog is enough to prepare a unit for modelling, and `/model-unit` builds from the measurements and finishes when the silhouettes match.

## Acceptance criteria (testable)

- [x] `unit.json`: `reference_glb` view; `ready_for_model` accepts a GLB in place of a `side` image (and relaxes the silhouette features minimum to 1 when a GLB exists); the contract in docs/design/units/README.md is updated.
- [x] `tools/unit_catalog.sh`: GLB upload button; after upload the analysis (179 + 180) runs as a headless job (ADR 0008) and shows the views and warnings.
- [x] `/model-unit` step 0 runs the analysis; the agent gets `measurements.json`, the diff images and the IoU target; it stops at IoU >= threshold or after 4 iterations and reports the numbers.
- [x] `.claude/agents/unit-modeler.md` tells it to take constants from `measurements.json` and judge by IoU, details from photos / features.
- [x] Python tests of the catalog cover the upload and the new gate.

## Playtest (for the human)

1. In `tools/unit_catalog.sh` upload a GLB for a new unit, wait for the analysis.
2. Run `/model-unit <id>`: it reports the final IoU and the render sheet.

## Player manual

none

## Out of scope

- Shipping the GLB in the game or importing it as an asset: it is a reference only (the game model stays procedural, MeshKit). GLBs live outside git; `measurements.json` and reference renders are committed.

## Implementation notes

- `unit.json` gets `reference_glb: {file: "reference.glb", source_url, license, note}` (a top-level object, not an image view: a GLB is not an image file). `catalog.py`: `has_glb`, `add_glb_bytes` (GLB header + length check, ≤ 200 MB), `delete_glb`, `glb_info` (views, warnings from `normalisation.json` / `measurements.json`), readiness: the GLB replaces the side / drawing / soldier-photo requirement and the silhouette minimum drops 3 → 1; `PUT` of the form keeps the GLB (only metadata editable). k9_thunder's `unit.json` now records its GLB.
- Server: `PUT /api/units/<id>/reference_glb` (raw `model/gltf-binary` body, the only non-JSON mutating route), `DELETE` the same path; the upload queues an `analyze` job. `jobs.py`: new kind `analyze` runs `tools/analyze_glb.sh <id>` (no Claude CLI needed, log streamed, report = `glb_info`); the model job's allow-list gained `analyze_glb.sh` and `compare_silhouette.sh`.
- UI (`app.js`): section *Reference GLB* (upload / replace / re-run analysis / remove, four views, sheet link, warnings), checklist mirrors the new gate. It reuses existing catalog components; no new design.
- `/model-unit` step 1b runs the analysis, passes `measurements.json`, diff images, IoU target 0.90 and the 4-iteration limit; `unit-modeler.md` takes constants from `measurements.json` and judges by `compare_silhouette.sh`. Contract documented in docs/design/units/README.md ("Reference GLB"), docs/TOOLS.md, `unit.schema.json`.
- Tests: `test_catalog.py` (gate, validation, add/delete, PUT), `test_jobs.py` (analysis job with a fake script, failure, validation, upload route). `tools/check.sh`: only unrelated failures (see summary).

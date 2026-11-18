# TASK-181: Silhouette comparison: IoU of the game model against the GLB in three views

- **Status**: ready
- **Layers**: tooling (presentation tools, no game rules)
- **Depends on**: TASK-179
- **Sections**: ADR 0010 (budgets), ADR 0014 (mechanisms), docs/TOOLS.md (render_unit, unit_catalog)
- **Model**: sonnet

## Goal

`tools/compare_silhouette.sh <id>` replaces eyeballing: it renders the game model and the GLB reference in the same orthographic views and reports how well their silhouettes match.

## Acceptance criteria (testable)

- [ ] Masks of side / front / top for the model and the GLB at the same scale and framing; output per view: IoU, area difference, and a diff image (missing / extra pixels in two colours) in `.screenshots/units/<id>_diff_<view>.png`.
- [ ] Last stdout lines `IoU side=0.93 front=0.90 top=0.91` plus the 3 largest mismatch regions in metres (e.g. `glacis +0.12 m high`).
- [ ] Exit 0 when every IoU >= threshold (default 0.90, `--min-iou`), otherwise 1.
- [ ] Tests: identical shapes -> IoU 1.0, a shifted box -> the expected value.
- [ ] `docs/TOOLS.md` updated.

## Playtest (for the human)

1. Run it on an existing model with its GLB.
2. Open the diff images: the red / blue areas should show where the model really differs.

## Player manual

none

## Out of scope

- Shipping the GLB in the game or importing it as an asset: it is a reference only (the game model stays procedural, MeshKit). GLBs live outside git; `measurements.json` and reference renders are committed.

## Implementation notes

_Filled in by the agent when done._

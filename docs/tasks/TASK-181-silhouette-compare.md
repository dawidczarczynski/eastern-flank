# TASK-181: Silhouette comparison: IoU of the game model against the GLB in three views

- **Status**: done
- **Layers**: tooling (presentation tools, no game rules)
- **Depends on**: TASK-179
- **Sections**: ADR 0010 (budgets), ADR 0014 (mechanisms), docs/TOOLS.md (render_unit, unit_catalog)
- **Model**: sonnet

## Goal

`tools/compare_silhouette.sh <id>` replaces eyeballing: it renders the game model and the GLB reference in the same orthographic views and reports how well their silhouettes match.

## Acceptance criteria (testable)

- [x] Masks of side / front / top for the model and the GLB at the same scale and framing; output per view: IoU, area difference, and a diff image (missing / extra pixels in two colours) in `.screenshots/units/<id>_diff_<view>.png`.
- [x] Last stdout lines `IoU side=0.93 front=0.90 top=0.91` plus the 3 largest mismatch regions in metres (e.g. `glacis +0.12 m high`).
- [x] Exit 0 when every IoU >= threshold (default 0.90, `--min-iou`), otherwise 1.
- [x] Tests: identical shapes -> IoU 1.0, a shifted box -> the expected value.
- [x] `docs/TOOLS.md` updated.

## Playtest (for the human)

1. Run it on an existing model with its GLB.
2. Open the diff images: the red / blue areas should show where the model really differs.

## Player manual

none

## Out of scope

- Shipping the GLB in the game or importing it as an asset: it is a reference only (the game model stays procedural, MeshKit). GLBs live outside git; `measurements.json` and reference renders are committed.

## Implementation notes

Done 2026-11-19.
- `tools/silhouette.gd` (pure: orthographic rasterising of a triangle list into side / front / top masks, IoU, diff image, connected mismatch regions with a "+0.12 m high" description; tested in `tests/unit/test_silhouette.gd`), `tools/compare_silhouette.gd` (loads the game model's visible triangles via `UnitModels.build` and the GLB normalised as `analyze_glb.sh` did, front from `normalisation.json`), `tools/compare_silhouette.sh` (headless, no rendering). Documented in docs/TOOLS.md.
- Both meshes are centred in x / z over their bounding boxes and stand on y = 0. Mismatch regions are connected components, so when the shapes differ a lot (K9: model 8.8 m long vs. 12 m GLB) the biggest region is one giant blob; it is meaningful for models already close to the GLB.
- Pilot K9 Thunder: IoU side=0.42 front=0.44 top=0.56 (the model is ~26 % shorter than the GLB incl. barrel; the GLB's antenna and elevated gun enlarge its silhouette). ~50 s run time, mostly GLB loading and rasterising 1.76 M triangles in GDScript.
- Not done: a 'part name' for regions (e.g. "glacis"): regions are reported as ranges in metres.


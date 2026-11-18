# TASK-179: GLB reference: normalise a Meshy GLB and render orthographic reference views

- **Status**: done
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

Done 2026-11-18, pilot unit K9 Thunder (`~/Downloads/k9.glb`, 61 MB, one mesh, 1.76 M triangles).
- `tools/glb_reference.gd` (loading via `GLTFDocument`, normalisation, front detection, warnings), `tools/render_glb.gd` (subclass of `render_unit.gd`, like `render_weapon.gd`), `tools/analyze_glb.sh` (wrapper: `render_unit.sh --glb`). Output: `<unit folder>/reference_views/glb_*.png`, `glb_sheet.png`, `normalisation.json`.
- Front detection: the end of the longer horizontal axis whose slab (12 %) has the smaller cross-section is the front (barrel / thin nose); `--front=` overrides. Worked on the K9 (gun to +x, matches the photo).
- Height is compared with the catalog without the top 2 % of vertices (percentile): the K9 GLB has a whip antenna and a raised barrel (+81 % with all vertices, +9 % robust). `--force` renders despite warnings.
- Not done: the up axis is always glTF +Y (no `--up`); the Windows run prints leaked-RID errors at exit (also seen in other render tools), the exit code is unaffected.
- `reference.glb` is gitignored; `normalisation.json` and the reference views are committed next to the unit.

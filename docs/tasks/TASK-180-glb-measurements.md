# TASK-180: GLB measurements: section profiles and part detection into measurements.json

- **Status**: done
- **Layers**: tooling (presentation tools, no game rules)
- **Depends on**: TASK-179
- **Sections**: ADR 0010 (budgets), ADR 0014 (mechanisms), docs/TOOLS.md (render_unit, unit_catalog)
- **Model**: opus

## Goal

Extract from the normalised GLB the constants a procedural model starts with (hull length, deck / roof height, turret centre and ring radius, gun trunnion and overhang, wheel positions and radii, hull half widths), so the modeler stops guessing them from photos.

## Acceptance criteria (testable)

- [x] Height and half-width profiles along the length every 0.1 m (hull and, separately, everything above the deck) in `measurements.json`.
- [x] Part detection from connected components and heuristics: turret (largest component above the deck), gun (thin long component from the turret), wheels (repeated cylinders: count, positions, radii); each value carries `confidence` 0..1 and a name matching the model constants (`DECK_H`, `ROOF_H`, `TURRET_X`, `TURRET_RING_R`, `TRUNNION`, `UPPER_HW`, `LOWER_HW`, ...).
- [x] Foot units: height and proportions only.
- [ ] Verified on the GLBs of T-72B3 and M1A2: measured values within 5 % of the constants in their model files (report the table in Implementation notes; differences judged by the human).
- [x] Low-confidence or catalog-conflicting values are listed under `warnings`, never silently used.
- [x] Unit tests on synthetic GLBs (box hull + cylinder turret + cylinder wheels).

## Playtest (for the human)

1. Run the analysis on a GLB of a unit that already has a model.
2. Compare `measurements.json` with the constants at the top of its model file; large differences should be explainable.

## Player manual

none

## Out of scope

- Shipping the GLB in the game or importing it as an asset: it is a reference only (the game model stays procedural, MeshKit). GLBs live outside git; `measurements.json` and reference renders are committed.

## Implementation notes

- `tools/glb_measurements.gd` (pure `RefCounted`, static functions on a triangle list in metres) does the work; `tools/glb_reference.gd` got `triangles(scene)` (the normalised mesh incl. `scene.transform`); `tools/render_glb.gd` writes `<unit folder>/measurements.json` right after normalising, automatically on every `tools/analyze_glb.sh` run (`--no-measure` skips it). `tools/render_unit.sh --glb` time limit 60 -> 180 s: the Windows Godot run of the K9 GLB (1.76 M triangles) took 57 s with ~18 s of measuring. Documented in docs/TOOLS.md (analyze_glb entry).
- Method: triangles are sampled (vertices + a 5 cm grid inside large triangles) into a point cloud. Deck / roof = the largest up-facing area bin (Godot winds front faces clockwise) inside 30-85 % of the robust height / above deck + 0.25 m. Hull nose / length = extent of everything below the deck; output frame = model files' frame (x from the nose rearwards). Profiles every 0.1 m for the hull (<= deck) and everything above it. Turret = contiguous run around the widest slab of the layer 0.05-0.25 m above the deck (centroid -> `TURRET_X`, equal-area disc -> `TURRET_RING_R`, plus `TURRET_FRONT/REAR/HW`); confidence from its roundness, +0.1 when it is a separate connected component. Gun = thin slabs (< 0.7 m) ahead of the turret, axis by least squares, `TRUNNION` = where the axis meets the mantlet (wider than a barrel). `UPPER_HW` = 99th percentile |z| in the 0.45 m below the deck; `LOWER_HW`/`TRACK_Z`/`TRACK_WIDTH` from the track band 0.05-0.3 m above the ground. Wheels: round connected components (welded at 1 mm) grouped by radius; fallback for fused meshes = runs in the side depth map (confidence 0.45, so always a warning). Foot units: `HEIGHT`, `WIDTH`, `DEPTH` and the two proportions only.
- Tests: `tests/unit/test_glb_measurements.gd` (10 tests) on a synthetic tank written to and loaded from a GLB (box hull, cylinder turret, cylinder gun, 2 x 5 cylinder wheels, track boxes), a fused-wheel mesh, a featureless box (wheels -> warning, not a guess), a foot unit, warnings for catalog conflicts and low confidence.
- **T-72B3 / M1A2 verification: not possible yet.** Neither `docs/design/units/units/t72b3/reference.glb` nor `docs/design/units/units/m1a2_sepv3/reference.glb` exists (the GLBs are not in git; only `k9_thunder/reference.glb` is present). The 5 % criterion stays open for the human: drop the two GLBs in and run `tools/analyze_glb.sh t72b3` / `m1a2_sepv3`. Instead, the K9 Thunder GLB (`k9_thunder/measurements.json`, committed) vs. `src/presentation/models/k9_thunder.gd`:

| Constant | Measured | Model | Diff | Confidence |
|---|---|---|---|---|
| HULL_LENGTH | 7.52 | 7.44 | +1.1 % | 0.80 |
| DECK_H | 1.829 | 1.82 | +0.5 % | 0.86 |
| ROOF_H | 2.817 | 2.72 | +3.6 % | 1.00 |
| GUN_OVERHANG | 4.112 | 4.06 | +1.3 % | 0.80 (gun elevated 4.5 deg in the GLB: warning) |
| REAR_OVERHANG | 0.369 | 0.5 | -26 % | 0.70 |
| UPPER_HW | 1.679 | 1.65 | +1.8 % | 0.75 |
| LOWER_HW | 1.089 | 1.08 | +0.8 % | 0.60 |
| TRACK_Z / TRACK_WIDTH | 1.363 / 0.548 | 1.375 / 0.55 | -0.9 % / -0.4 % | 0.60 |
| TURRET_FRONT | 3.2 | 3.24 | -1.2 % | 0.60 |
| TURRET_REAR | 7.9 | 7.54 | +4.8 % | 0.60 |
| TURRET_HW | 1.601 | 1.5 | +6.7 % | 0.60 |
| TURRET_X | 5.577 | 5.2 | +7.3 % | 0.60 (box turret: base-layer centroid, not a ring centre) |
| TURRET_RING_R | 1.601 | – (K9 has none) | | 0.69 |
| TRUNNION | (3.2, 2.41) | (3.94, 2.22) | x -19 %, h +8.6 % | 0.55 (mantlet face, the trunnion sits behind it) |
| ROAD_WHEELS | 8 per side at 0.54, 1.5, 2.52, 3.315, 4.29, 5.235, 6.18, 7.005; r 0.33; h 0.555 | 6 at 1.57, 2.47, 3.34, 4.24, 5.12, 5.99 (+ sprocket 0.6, idler 6.99); r 0.34; h 0.42 | positions within 0.07-0.19 m, r -3 %, h +32 % | 0.45 (fused mesh fallback, warning; it counted the sprocket and idler) |

  Hull, deck, roof, widths and track are within 5 %; the turret plan of the box-shaped K9 turret and the trunnion are the weak spots (they say so through their confidence / note), and wheel detection on a fused Meshy mesh is only a starting point.

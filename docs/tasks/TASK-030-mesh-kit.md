# TASK-030: Mesh kit v2 – the model study's kit as a shared, tested library (chamfers with edge flags, pillow, sweep, tube, plate, bolt; RGB vertex masks)

- **Status**: ready (rewritten 2026-10-22: the original port of the v2 design's three.js helpers is obsolete – the six real-unit models were built with `ModelParts` / `VehicleFrame` without it, and the model detail study of 2026-10-21 defines the kit the next models need)
- **Layers**: presentation (`src/presentation/models/parts/mesh_kit.gd`, pure geometry, tested headless); no model changes
- **Depends on**: – . Reference: `docs/design/showcase/m1a2_showcase.gd.txt` (`class Kit`, `class Kits`), `docs/design/showcase/infantry_showcase.gd.txt` (`sweep`, `pillow`, `tube`), `docs/design/showcase/showcase_paint.gdshader.txt` (what the vertex colour channels mean), `docs/design/showcase/README.md` (findings).
- **Blocks**: TASK-062 (weathering paint reads the masks), TASK-067 (infantry v3), the tank v3 rework (TASK-069), every later `/model-unit` run that wants chamfers.
- **Model**: opus (geometry: chamfer offsets, normals and winding, smooth sweeps without twisting, vertex masks consistent across primitives)

## Goal

Both studies carry their own copy of the same mesh kit. Move it into one shared, tested library so models can be built from chamfered, soft parts that carry the vertex masks the weathering paint needs – instead of every model file growing its own helpers.

## Current state

`ModelParts` has `prism_mesh`, `loft_mesh`, `lathe_mesh`, `band_mesh`, `gear_outline`, `circle_hull`, `merged_mesh` (per-material merge, pivots kept by building them as separate nodes); `VehicleFrame` has `slab`, `pair`, `drum`, `profile`, `loft`, `merged` in vehicle units. No chamfers, flat normals, no vertex colours. The studies' `Kit` adds chamfers, smooth primitives and vertex masks.

## Design

- **`MeshKit`** (`src/presentation/models/parts/mesh_kit.gd`, `RefCounted`): a mesh builder for one material, port of the studies' `Kit` (merge the tank and infantry variants into one class): `tri`, `poly`, `poly_auto`, `cbox(c, s, b, rot)` (chamfered box), `pillow(c, s, rot, e, rings, sides)` (superellipsoid), `lathe(c, rot, prof, sides, smooth)`, `rod(c, dir, r, length, sides, b)`, `bolt`, `stack`, `loft`, `plate` (outline with chamfered rim), `profile(points, hw, z0, b)` (chamfered side-profile extrusion), `sweep(path, radii, sides, side0)` (elliptic rings along a polyline, parallel-transport frames, no twist), `tube(path, r, sides)`, `commit() -> ArrayMesh`. An optional base transform (`Frame` + `Transform3D`) maps model units, as in the tank study.
- **`MeshKits`**: one `MeshKit` per material role (`k(&"body")`), `add_to(parent, materials)` – replaces the studies' `Kits`; works with `ModelParts.cached` and keeps pivots as separate nodes (as today).
- **Vertex masks** (`ARRAY_COLOR`, written by every primitive; the convention is documented in the class doc and in `docs/ARCHITECTURE.md` "Unit visuals"):
  - `r` = chamfer / edge (1 on chamfer bands and edge rings, 0 on faces) – paint wear;
  - `g` = openness (1 open, towards 0 in cavities – inner faces, under overhangs where the primitive knows it, e.g. the inside of a tube or a lathe's inner wall) – cavity darkening;
  - `b` = per-part tint seed (from the part centre hash, constant per part) – per-part tint.
- `ModelParts` / `VehicleFrame` helpers stay unchanged; existing models keep working. Moving the existing models onto the kit is their own `/model-unit` reworks (TASK-062 / TASK-067 / TASK-069).
- **ADR** (next free number in `docs/adr/`, currently `0011-mesh-kit-v2.md`): procedural geometry in code instead of imported models (CC0 unit models stay excluded, TASK-053), one shared kit with vertex masks as the contract between geometry and paint, chamfers in geometry instead of normal maps.

## Acceptance criteria (testable)

- [ ] `tests/unit/test_mesh_kit.gd`:
  - `cbox(Vector3.ZERO, Vector3(0.1, 0.05, 0.2), 0.01)` AABB equals the size centred on the origin (±1e-5); with `b = 0` it has 12 triangles; with `b > 0` more, and some vertices have `r == 1`, some `r == 0`.
  - Winding (Godot: front faces clockwise seen from outside, as in `map_view.gd`'s terrain indices): for every triangle of every primitive, `(v2 − v0).cross(v1 − v0)` has a positive dot product with the triangle's vertex normals; all normals unit length.
  - `pillow` with exponent → 2 approximates an ellipsoid (vertices within 2 % of the ellipsoid surface); AABB = size.
  - `sweep` along an L-shaped path with constant radius: every ring is perpendicular to its path segment (±1e-3) and consecutive rings are not twisted (the `side0` direction rotates by less than 1° between rings on straight parts).
  - `tube` and `lathe`: closed where the profile radius is 0, AABB as expected.
  - Vertex `b` is equal on all vertices of one part and differs between two parts at different centres.
  - `MeshKits.add_to` with 2 materials → 2 `MeshInstance3D`; the vertex count is preserved; deterministic (no randomness).
- [ ] The kit is pure (no scene tree access except `add_to`, no autoloads, no randomness).
- [ ] Re-port check: the study models (`docs/design/showcase/*.gd.txt`) run against the shared kit (temporarily copied in as the showcase README describes, then removed) and give the same triangle counts (±2 %) – noted in the implementation notes.
- [ ] `tools/check.sh` passes; no visual change (`docs/images/gameplay.png` not re-rendered – say so in the notes).

## Playtest (for the human)

Nothing visible changes (a library). Optional: `tools/render_unit.sh` on the temporarily copied-in study model looks like `docs/design/showcase/m1a2_cut_hero.jpg`.

## Out of scope

- Using the kit in the game models (TASK-062 re-renders, TASK-067 infantry, TASK-069 tank v3), the paint shader (TASK-062), UVs (camo uses object-space position).

## Implementation notes

_Filled in by the agent when done._

# TASK-030: MeshKit – profile extrusion with bevels, lathe, taper, rods, and baking per material

- **Status**: ready
- **Layers**: presentation (pure geometry helpers, fully tested headless)
- **Depends on**: – (soft: TASK-029, the baker keeps its materials). Reference: `docs/design/v2/game_screen.scene.js` lines 163–186 (`M`, `prof`, `plan`, `rbox`, `lathe`, `taper`, `rod`, `hull2d`, `circ`, `gear`, `mergeGeos`, `bake`).
- **Model**: opus (geometry: triangulation with holes, bevel offsets, normals and winding, merging by material while keeping animated pivots)

## Goal

A small toolkit that turns 2D outlines into solid parts with rounded edges, so the detailed unit models (TASK-031 … TASK-033) can be ported almost line by line from the design, and a baker that merges a model's hundreds of parts into a few meshes so they stay cheap to render.

## API (`src/presentation/mesh_kit.gd`, `class_name MeshKit`, static, `RefCounted`)

All functions return an `ArrayMesh` (one surface, with normals; no material) unless stated. Godot front faces are clockwise seen from outside – every helper must produce outward-facing triangles.

- `extrude_profile(outline: PackedVector2Array, width: float, bevel := 0.006, bevel_segments := 2, holes: Array[PackedVector2Array] = []) -> ArrayMesh` – port of `prof`: outline in the XY plane (side view), extruded along Z, centred on z = 0, total width `width`. With `bevel > 0`, the caps are the outline inset by `bevel` (`Geometry2D.offset_polygon`) and the edge band is rounded in `bevel_segments` steps between the inset cap and the full outline at `z = ±(width/2 − bevel)` (three.js `bevelThickness = bevelSize = b`). Holes cut through (the tank track). Triangulation: `Geometry2D.triangulate_polygon` does not support holes – bridge each hole into the outline or decompose; document the method.
- `extrude_plan(outline_xz: PackedVector2Array, height: float, bevel := 0.006, bevel_segments := 2) -> ArrayMesh` – port of `plan`: outline seen from above, extruded up from y = 0 to `height`.
- `rounded_box(size: Vector3, radius := 0.004) -> ArrayMesh` – port of `rbox` (a plan-extruded rectangle with bevel, centred on the origin), radius clamped to `min(size)/2.2`.
- `lathe(points: PackedVector2Array, segments := 18) -> ArrayMesh` – `(radius, y)` points revolved around Y (port of `LatheGeometry`; points with radius 0 close the shape).
- `taper(mesh: ArrayMesh, factor: float) -> ArrayMesh` – port of `taper`: x/z scaled linearly from 1 at min y to `factor` at max y, normals recomputed.
- `rod_transform(a: Vector3, b: Vector3) -> Transform3D` + `rod(radius, length, capsule := false, segments := 8) -> Mesh` – port of `rod`: a cylinder or capsule from `a` to `b` (Godot `CylinderMesh` / `CapsuleMesh` are fine for the mesh; the transform is the logic to test).
- `gear_outline(r0, r1, teeth) -> PackedVector2Array`, `circle_outline(center, r, n := 24)`, `convex_hull(points)` (port of `hull2d`; `Geometry2D.convex_hull` is acceptable).
- **Baker**: `bake(root: Node3D, keep: Array[StringName]) -> Node3D` – port of `bake`: walks the subtree, transforms every `MeshInstance3D` into `root` space and merges all surfaces that share a material into one `ArrayMesh` surface. Nodes whose name matches `keep` (e.g. `Turret`, `Wheel*`, `Soldier*`, `Pod`, `Mouth*`) are **not** flattened into the parent: they stay as `Node3D` pivots with the same transform, and their own subtree is baked separately (recursively), so TASK-025 locomotion and the rocket volley keep working. Name patterns use `String.match` (`"Wheel*"`).

## Acceptance criteria (testable)

- [ ] `tests/unit/test_mesh_kit.gd`:
  - `extrude_profile` of a unit square `(0,0)…(1,1)`, width 0.5, bevel 0: AABB = `(0,0,−0.25)…(1,1,0.25)`, 12 triangles; every triangle's normal points away from the centroid `(0.5, 0.5, 0)`; with bevel 0.05 the AABB is the same (bevel stays inside the outline) and the triangle count is larger.
  - Winding (Godot: front faces are clockwise seen from outside, as in `map_view.gd`'s terrain indices): for every triangle of every helper, `(v2 − v0).cross(v1 − v0)` has a positive dot product with the triangle's vertex normals.
  - A square outline with a square hole: no triangle's centroid lies inside the hole (in the XY projection of the cap triangles).
  - `lathe([(0,0), (1,0), (1,1), (0,1)], 16)` → closed cylinder, AABB `(−1,0,−1)…(1,1,1)`, normals unit length.
  - `taper` with factor 0.5 on a box: top x/z extents half of the bottom ones.
  - `rounded_box(Vector3(0.1, 0.05, 0.2), 0.01)` AABB equals the size centred on the origin (±1e-5).
  - `rod_transform(a, b)` maps local `(0, ±0.5·len, 0)` to `a` and `b`.
  - `gear_outline(0.04, 0.051, 11)` has 44 points with radii alternating in pairs.
  - Baker: a tree with 3 meshes in 2 materials plus a `Wheel0` pivot with 1 mesh → result has 2 `MeshInstance3D` at the root (one per material) and a `Wheel0` `Node3D` with the same transform holding 1 mesh; the total vertex count is preserved; the merged mesh's AABB equals the union of the inputs in root space.
- [ ] Helpers are static and pure (no scene tree, no autoloads) and use no randomness.
- [ ] A short ADR in `docs/adr/` (`0006-procedural-unit-meshes.md`): procedural geometry in code instead of imported glTF models, the triangulation-with-holes method, baking per material with kept pivots.
- [ ] Agent visual check (optional): temporarily add a bevelled extrusion to a debug scene or a unit and take a screenshot to confirm the faces are lit from outside (not inverted), then remove it.

## Playtest (for the human)

Nothing visible changes in this task (it is a library). Optionally open the editor after TASK-031 to inspect the baked tank.

## Out of scope

- Using the kit in the unit models (TASK-031 … TASK-033), UV generation (camo uses object-space position), `TubeGeometry` along a curve (TASK-031 can approximate the fender tube with rods).

## Implementation notes

_Filled in by the agent when done._

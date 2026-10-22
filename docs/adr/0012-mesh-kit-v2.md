# ADR 0012: Mesh kit v2 – procedural unit geometry from one shared kit with vertex masks

- **Status**: accepted
- **Date**: 2026-10-22

## Context

The six real-unit models are built in code with `ModelParts` / `VehicleFrame` helpers: sharp boxes, prisms and lathes with flat normals and no vertex data beyond position and normal. The model detail study of 2026-10-21 (`docs/design/showcase/`) showed what removes the "toy" look – chamfers on every part, soft shapes for cloth and bags, many small parts, and paint that looks used (wear on edges, dark cavities, per-part tint variation). Both study models (M1A2, infantry squad) carried their own copy of the same mesh builder (`Kit` / `Kits`), and the weathering paint (`showcase_paint.gdshader.txt`) read its vertex colours. The next model reworks (TASK-067 infantry v3, TASK-069 tank v3) and the surface wear task (TASK-062) need that builder as shared, tested code, with one meaning of the vertex colours. ADR 0011 excludes downloaded (CC0) unit models, so unit geometry stays procedural (TASK-053).

## Decision

- **Procedural geometry in code** stays the way unit models are made: real dimensions from the unit catalog, built by GDScript, no imported meshes and no UVs (camo uses object-space position).
- **One shared kit**: `MeshKit` (`src/presentation/models/parts/mesh_kit.gd`) is the mesh builder for one material – `tri`, `poly`, `poly_auto`, `cbox` (chamfered box), `pillow` (superellipsoid), `slab` / `pair`, `lathe`, `rod`, `bolt`, `stack`, `loft`, `plate`, `profile`, `sweep` (elliptic rings with parallel-transport frames), `tube`, `commit`; an optional `VehicleFrame` + `Transform3D` maps vehicle metres into a pivot. `MeshKits` (`mesh_kits.gd`) holds one kit per material role and adds one `MeshInstance3D` per material through `ModelParts.add` (works with `ModelParts.cached`; moving pivots get their own `MeshKits`). It merges the two study kits; `tests/unit/test_mesh_kit.gd` covers winding, normals, closedness, sizes, sweep frames and masks. New primitives go into the kit with a test, not into model files.
- **Vertex masks are the contract between geometry and paint** (`ARRAY_COLOR`, written by every primitive, 8-bit): `r` = chamfer / edge (1 on chamfer bands, corners, rims, short diagonal lathe segments, tube caps) for paint wear; `g` = openness (1 open, lower in cavities – set per part by the model, lowered automatically on a lathe's inner wall) for cavity darkening; `b` = per-part tint seed (hash of the part centre, constant per primitive call, no RNG). Shaders may rely on exactly this meaning; changing it needs a new ADR.
- **Chamfers live in the geometry**, not in normal maps: a chamfer is a real band of triangles with its own normal, so it catches light at any distance and carries the `r` flag for wear. No baked normal or AO maps.
- `ModelParts` / `VehicleFrame` stay as they are; existing models move onto the kit in their own reworks (TASK-062 / TASK-067 / TASK-069).

## Consequences

- (+) Chamfered, soft, weathered models without per-model helper code; one tested place for the geometry rules (front faces clockwise, normals from the inverse transpose, mirrored vehicle frames handled).
- (+) The paint shader gets wear, cavity and tint information for free from any model built with the kit.
- (+) The re-port check reproduced both studies exactly (32 586 and 25 406 triangles) and built them faster than the study kits (no per-vertex array allocations).
- (−) Chamfers cost triangles (a chamfered box is 44 triangles instead of 12) and GDScript build time; ADR 0010's budgets (40 000 triangles per vehicle, ≤ 500 ms cold build) still apply.
- (−) Meshes are unindexed triangle lists (flat and smooth parts mixed); vertex count is 3 × triangles. Indexing can come later if memory matters.
- (−) Colours are 8-bit, so the tint seed has 256 levels and `g` steps of 1/255.

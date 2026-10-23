# ADR 0010: Unit model budgets – 40 000 triangles per vehicle and a cold build time limit

- **Status**: accepted
- **Date**: 2026-10-21

## Context

TASK-036 set the model contract budgets (≤ 25 000 triangles per vehicle, ≤ 20 000 per squad, ≤ 24 body `MeshInstance3D`) as a guard with headroom over the models of the time (~14 000 triangles); the number was never measured against a limit. A detail study of the M1A2 SEPv3 (procedural, same toolkit: chamfered parts, bolts, cables, track shoes, a weathering shader) showed:

- The maximum-detail version had ~104 000 triangles, 75 % of them in the tracks and running gear, mostly hidden behind the skirts. Removing what the camera never sees brought it to ~32 600 triangles with no visible difference.
- The GPU cost of that is small: even 50 such vehicles are ~1.6 M triangles (×2 with shadows); merging parts per material cut the mesh instances from 51 to 20.
- The real cost is the GDScript mesh generation when a unit type first appears: 17 ms for the current M1A2, 980 ms for the maximum version, ~320 ms after the cuts. Several such types make a noticeable hitch at battle start.

## Decision

- Vehicles: **≤ 40 000 triangles** (was 25 000). Squads stay at ≤ 20 000, body mesh instances at ≤ 24.
  - Amended by TASK-067 (infantry v3, smooth MeshKit soldiers): squads **≤ 40 000 triangles**, counting the hidden `Stand` variants of the kneelers (7 figures per squad).
- New check: a model's **cold build** (empty `ModelParts` mesh cache, `ModelParts.clear_mesh_cache()`) takes **≤ 500 ms** (`test_unit_model_contract.gd`, `MAX_BUILD_MSEC`).
- Modelling rule (unit-modeler): spend triangles where the camera sees them; parts hidden behind skirts, wheels or the hull get the simplest shape.

## Consequences

- (+) Room for chamfers, small parts and individual track shoes on visible areas.
- (+) The budget now guards the cost that actually hurts (build time), not only a triangle count.
- (−) The build time check measures wall-clock time: a very slow machine could fail it although the model did not change. The limit has a wide margin (current models build in ~20 ms).
- (−) If many detailed unit types appear in one battle, building them up front (e.g. behind a loading screen) or off the main thread becomes a follow-up.

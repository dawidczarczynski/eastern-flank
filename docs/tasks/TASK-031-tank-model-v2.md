# TASK-031: First detailed tank model (from the v2 design, adjusted to a real tank)

- **Status**: done (superseded, closed 2026-10-22) – the goal was reached by `/model-unit` runs instead of this task: `m1a2_sepv3.gd` and `t72b3.gd` (catalog status `modeled`), shared running gear in `models/parts/tracked_running_gear.gd`, turret / gun pivots via `VehicleFrame.add_turret` / `add_gun`. Built with `ModelParts` / `VehicleFrame`, not the original MeshKit. Detail beyond that (chamfers, weathering) moves to TASK-062 and the tank v3 rework (TASK-069).
- **Layers**: presentation (`src/presentation/models/<unit_id>.gd`, shared parts in `model_parts.gd`; contract test in `tests/unit/test_unit_models.gd`)
- **Depends on**: **TASK-036**, **TASK-029**, **TASK-030**, TASK-025 (locomotion pivots). Soft: TASK-039a (which real tank), TASK-037 (its catalog entry). Reference: `docs/design/v2/game_screen.scene.js` lines 207–266 (`makeTank`), portraits `docs/design/v2/shots/01-v2-units.jpg`, `hover.jpg`.
- **Agent**: `unit-modeler`, run via `/model-unit <unit_id>`
- **Model**: opus

## Goal

The first tank in the game gets a detailed model with the v2 design's construction and level of detail, adjusted to the real vehicle from its catalog entry. It also produces the reusable tank parts (tracks with road wheels, sprocket, idler, grousers, skirts, cupola, smoke dischargers, gun barrel) that every later tank model reuses.

## Port

Port `makeTank` part by part with `MeshKit` (`prof` → `extrude_profile`, `plan` → `extrude_plan`, `rbox` → `rounded_box`, `lathe`, `taper`, `rod`, `gear` → `gear_outline`), +X forward:

- **Hull**: lower/upper hull profiles (lines 209–210), glacis with vision blocks, engine deck grille, rear plate, lights, tow hooks, stowage boxes, fender tube (rods if no tube helper).
- **Running gear per side**: track (hull-of-circles outline with a hole, lines 211–213) + grousers; road wheels (lathe) with rubber tyres; return rollers; rear sprocket (gear + discs + hub); front idler; side skirts; faction accent plate.
- **Turret** (pivot `Turret`): tapered plan outline (line 247), mantlet, gun barrel lathe (line 249), gunner sight, commander cupola with vision blocks, smoke dischargers, side boxes with accent plates, antennas, rear basket.
- **Adjust to the real tank** from `docs/design/units/units/<unit_id>/unit.json` (`silhouette_features`, dimensions, images): e.g. number and size of road wheels, turret shape, gun length, presence of a bustle basket. The design gives the style; the catalog decides the shape.
- **Reusable parts** go to `model_parts.gd` (or `models/parts/tracked_running_gear.gd`) with parameters (wheel count, spacing, radius, track length), so the next tank is mostly parameters + hull/turret.
- **Mechanisms** (if TASK-041/043 are done first – recommended): the catalog entry declares `wheels` and `turret_traverse`; build the registry pivots `Turret`, `Turret/Gun` (hinge at the trunnions, level when built) and `Turret/Gun/Muzzle`, and copy the entry's `mechanisms` into `MECHANISMS` (`ModelParts.declare_mechanisms`). The turret animation itself is TASK-047.

## Acceptance criteria (testable)

- [ ] Contract test passes for the model × every faction (pivots `Turret`, `Wheel*`; upright; footprint; sharing; budgets). Triangles / mesh instances and the old model's triangle count recorded in the notes.
- [ ] Locomotion tests pass (wheels spin, hull tilt).
- [ ] Final render sheet (`tools/render_unit.sh <unit_id>`) and a battle screenshot listed in the notes; AABB within ±10 % of the catalog dimensions (miniature exaggerations named).
- [ ] Running gear is a parameterised shared part (a second call with other parameters builds without code changes – tested).
- [ ] Catalog entry status set to `modeled`; `blueprint.md` written.
- [ ] `tools/check.sh` passes.

## Playtest (for the human)

1. Zoom in on the tank: tracks with road wheels and grousers, skirts, turret with cupola and smoke dischargers; compare with the photos in the catalog (Model review screen).
2. Compare the two factions: same tank, different camouflage.
3. Move it: wheels spin, the hull rocks and tilts on slopes; rotate the camera – no holes or inverted faces.
4. Write remarks into the catalog's feedback box; they go to the next `/model-unit` run.

## Out of scope

- Other tanks (one `/model-unit` run per catalog entry), turret traverse toward targets, track tread animation.

## Implementation notes

Closed as superseded (2026-10-22). Models: `src/presentation/models/m1a2_sepv3.gd`, `t72b3.gd`; blueprints in `docs/design/units/units/<id>/blueprint.md`. Not done from this spec: `MECHANISMS` metadata (TASK-043) and the catalog's `turret_traverse` (TASK-047).

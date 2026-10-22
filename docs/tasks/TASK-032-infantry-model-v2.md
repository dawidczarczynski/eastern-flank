# TASK-032: First detailed infantry squad (from the v2 design) + reusable soldier

- **Status**: done (superseded, closed 2026-10-22) – reached by `/model-unit` runs: `pl_mech_infantry.gd`, `ru_motor_rifle.gd` (catalog `modeled`), shared soldier kit `models/parts/soldier.gd`, carry poses from TASK-068. The next step is TASK-067 (infantry v3).
- **Layers**: presentation (`src/presentation/models/<unit_id>.gd`, soldier parts in `model_parts.gd` / `models/parts/`; contract test)
- **Depends on**: **TASK-036**, **TASK-029**, **TASK-030**, TASK-025 (march animation per soldier). Soft: TASK-039a, TASK-037. Reference: `docs/design/v2/game_screen.scene.js` lines 267–299 (`rifleGeo`, `soldier`, `makeInf`).
- **Agent**: `unit-modeler`, run via `/model-unit <unit_id>`
- **Model**: opus

## Goal

The first infantry squad reads as five soldiers with helmets, vests, packs and rifles, one with an anti-tank launcher – and the soldier is built as a **parameterised kit** (helmet type, vest type, rifle profile, launcher type), so the infantry of every other country is mostly a new parameter set.

## Port

- **Soldier** (port of `soldier(m, kneel, at)`): capsule legs (standing and kneeling poses, lines 272–273) with boots; torso capsule; vest and pack; neck; head; helmet (partial sphere); capsule arms with hands; rifle from the extruded side profile (`rifleGeo`, line 268); AT soldier with a lathe launcher over the shoulder, rifle slung.
- **Kit parameters** (`models/parts/soldier_kit.gd` or in `model_parts.gd`): `helmet` (profile/shape), `vest` (plate carrier / chest rig), `rifle_profile` (2D outline), `launcher` (tube / RPG-style with conical warhead), uniform camo from the faction. The first squad uses the design's set, adjusted to its catalog entry.
- **Squad**: the existing `SQUAD` layout (5 soldiers, kneeling flags), soldier scale 1.5, soldier 1 = AT soldier (`ATLauncher` node), yaw `(hash(i, 3, 1) − 0.5)·0.6`.
- **Materials**: uniform camo (S 70, dirt 0.03, roughness 0.95), vest colour, `SKIN`, `BOOT`, `GUN`, `AT_TUBE`.
- **Pivots**: `Soldier0…4` with `Rig`; kneelers' `Kneel`/`Stand` poses baked separately.

## Acceptance criteria (testable)

- [ ] Contract test passes for the model × every faction; ≤ 8 `MeshInstance3D` per soldier pose; exactly one `ATLauncher`.
- [ ] `pose_infantry` tests (TASK-025) pass.
- [ ] A second squad built from the kit with different parameters (other helmet, rifle profile, launcher) builds without code changes (tested) – the render sheet shows the difference.
- [ ] Battle screenshot: at default zoom the squad still reads as five figures, not noise.
- [ ] Catalog entry `modeled`, `blueprint.md` written; `tools/check.sh` passes.

## Playtest (for the human)

1. Zoom in on infantry: helmets, vests, backpacks; two kneel; one launcher.
2. Move a squad: soldiers march, kneelers stand up and kneel again on arrival.
3. Compare the factions: different uniform camouflage.

## Out of scope

- Infantry of other countries (one `/model-unit` run each), firing animations, losing soldiers with HP.

## Implementation notes

Closed as superseded (2026-10-22). Models: `src/presentation/models/pl_mech_infantry.gd`, `ru_motor_rifle.gd`, kit `models/parts/soldier.gd`.

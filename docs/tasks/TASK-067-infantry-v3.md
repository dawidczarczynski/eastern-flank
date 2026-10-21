# TASK-067: Infantry v3 – smooth procedural soldiers (swept bodies, soft gear, chamfered weapons)

- **Status**: ready
- **Layers**: presentation (`models/parts/soldier.gd`, `models/pl_mech_infantry.gd`, `models/ru_motor_rifle.gd`, `ModelParts` / `MeshKit`), tests (`test_unit_model_contract.gd`, `test_unit_models.gd`). Roles: **presentation-engineer** (kit primitives), **unit-modeler** (both squads, render-compare).
- **Depends on**: **TASK-030** (`MeshKit` – the primitives below belong there), **TASK-062** (weathering paint with the vertex-colour masks). Soft: TASK-068 (carry poses), TASK-063 (markings replace the sleeve patch colour).
- **Model**: opus (organic shapes, many parts, budget)

## Goal

Soldiers look like soldiers, not box mannequins, when the player zooms in or looks at a unit portrait – without losing the squad contract, the poses or the march animation.

## Reference

`docs/design/showcase/infantry_showcase.gd.txt` (study, 2026-10-21) and the images next to it. It builds the same squad layout, poses and kits as `pl_mech_infantry` from: `sweep` (smooth elliptic rings along a polyline – torso, limbs, neck), `pillow` (superellipsoid – plates, pouches, pack, gloves, boots, knee pads, head), chamfered boxes (weapons, magazine pouches, soles), lathes (helmet, band, barrels, optic), `tube` (straps, chin strap, sling, antenna), and the showcase paint shader with uniform-scale camo (`pattern_scale` ≈ 80, mud on boots and knees).

## Design

- **Kit**: `sweep(path, radii: Array[Vector2], sides, side0)`, `pillow(centre, size, basis, exponent, rings, sides)`, `tube(path, r, sides)` join TASK-030's `MeshKit` (chamfered box and lathe are already there); all write the TASK-062 vertex-colour masks.
- **Body** (`soldier.gd`): torso as one sweep (pelvis, waist, chest, shoulders, neck base) with deltoid pillows; legs and arms as sweeps with knee/elbow and calf shaping; neck, head (ellipsoid, jaw, nose, ears), gloves, boots with soles, knee pads, thigh pockets. Proportions of a 1.82 m man; `SOLDIER_SCALE` unchanged.
- **Kits** (model files): plate carrier as front/back pillows + cummerbund sweep + shoulder straps; pouches, radio, IFAK, belt, pack with lid and straps; helmet lathe with cover band, NVG shroud, chin strap; weapons from chamfered parts with round barrels and optics. Russian kit analogous (6B45 with collar, 6B47 helmet, AK family).
- **Budget**: squad ≤ **40 000 triangles** (raise `MAX_TRIANGLES_SQUAD`; the study was 25 400 without the hidden `Stand` variants of the two kneelers, ~35 000 with them), cold build ≤ 500 ms (ADR 0010). Keep per-soldier sides low (limbs 10–12, torso 16).
- Contract unchanged: `Soldier0…4`, `Rig`, kneelers `Kneel` + hidden `Stand`, carry poses (TASK-068), `LABEL_HEIGHT`.

## Acceptance criteria (testable)

- [ ] Both squads pass the contract for every faction with `MAX_TRIANGLES_SQUAD = 40000`; triangle counts and cold build times recorded in the implementation notes.
- [ ] No `BoxMesh` / `CylinderMesh` in the soldier bodies (test: the body roles of a built soldier are `ArrayMesh` from the kit) – the weapons may still use chamfered boxes.
- [ ] Locomotion and pose tests (`test_locomotion.gd`, kneel/stand) pass unchanged.
- [ ] `tools/render_unit.sh pl_mech_infantry` / `ru_motor_rifle` sheets and a battle crop (`SCREENSHOT_CAMERA=1,-40,5`) attached in the notes; `docs/images/gameplay.png` re-rendered.

## Playtest (for the human)

1. Zoom in on both squads: rounded bodies, gloves, boots, helmet bands, plate carriers with pouches; no box torsos.
2. Move a squad: the march looks as before, kneelers stand up and kneel again.
3. Zoom out to the normal camera: the squads read at least as well as before.

## Player manual

None (visual only).

## Out of scope

- Skeletal animation, cloth folds, faces (needs sculpted or third-party meshes – TASK-053 decision).
- New poses (TASK-068) and markings (TASK-063).

## Implementation notes

_Filled in by the agent when done._

# TASK-067: Infantry v3 – smooth procedural soldiers (swept bodies, soft gear, chamfered weapons)

- **Status**: done (revised 2026-10-22: the kit primitives are now built by TASK-030, the paint with masks by TASK-062)
- **Layers**: presentation (`models/parts/soldier.gd`, `models/pl_mech_infantry.gd`, `models/ru_motor_rifle.gd`, `ModelParts` / `MeshKit`), tests (`test_unit_model_contract.gd`, `test_unit_models.gd`). Roles: **presentation-engineer** (kit primitives), **unit-modeler** (both squads, render-compare).
- **Depends on**: **TASK-030** (mesh kit v2: `sweep`, `pillow`, `tube`, chamfered box, lathe – already ported from this study), **TASK-062** (weathering paint with the RGB vertex masks). Soft: TASK-068 (carry poses), TASK-063 (markings replace the sleeve patch colour).
- **Model**: opus (organic shapes, many parts, budget)

## Goal

Soldiers look like soldiers, not box mannequins, when the player zooms in or looks at a unit portrait – without losing the squad contract, the poses or the march animation.

## Reference

`docs/design/showcase/infantry_showcase.gd.txt` (study, 2026-10-21) and the images next to it. It builds the same squad layout, poses and kits as `pl_mech_infantry` from: `sweep` (smooth elliptic rings along a polyline – torso, limbs, neck), `pillow` (superellipsoid – plates, pouches, pack, gloves, boots, knee pads, head), chamfered boxes (weapons, magazine pouches, soles), lathes (helmet, band, barrels, optic), `tube` (straps, chin strap, sling, antenna), and the showcase paint shader with uniform-scale camo (`pattern_scale` ≈ 80, mud on boots and knees).

## Design

- **Kit**: use TASK-030's `MeshKit` / `MeshKits` as they are (`sweep`, `pillow`, `tube`, `cbox`, `lathe`); missing primitives are added to the kit with a test, not to the model files. Paint: TASK-062's `camo.gdshader` with the study's uniform-scale camo (`pattern_scale` ≈ 80 for cloth) and mud on boots and knees.
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

Implemented 2026-10-23 (unit-modeler), not committed, to playtest.

- **Soldier** (`src/presentation/models/parts/soldier.gd`, rewritten): every soldier is one `MeshKits` (base scale 0.1, built in metres) per material role, generated once per variant `<unit>:<kit>:<carry>:<kneel>` through `ModelParts.cached_meshes` (faction independent) and added with `MeshKits.add_meshes`. Body as in the study: torso sweep (16 sides) with deltoids and shirt collar, legs as one sweep each (10 sides) with knee / calf shaping, thigh pockets, knee pads, boots (shaft, upper, chamfered sole), neck, head (skull, jaw, nose, ears), arms (10 sides), gloves, accent sleeve patch. Shared kit helpers: `helmet_frame` / `helmet` (lathe + chin strap), `part` (chamfered box in a weapon frame), `bore_lathe`, `sling`, `rpg7`, `pg7`. The `dress` hook now gets the `MeshKits` (`func(k, up, kit, kneel, carry)`); squad pivots, poses, carry angles, `SOLDIER_SCALE` and `LABEL_HEIGHT` unchanged.
- **Kits**: `pl_mech_infantry.gd` – wz. 2005 helmet with band, NVG shroud, chin strap, glasses; KKZ carrier (front / back pillows, cummerbund sweep, shoulder straps, 3 magazine pouches with flaps, radio, IFAK), belt, assault pack with lid, straps and bottle; Grot C, UKM-2000 from chamfered parts with round barrels, optic and slings. `ru_motor_rifle.gd` – 6B47 with band and chin strap; 6B45 (thicker front / back, cummerbund, straps, high collar as a lathe ring, groin flap, 3 MOLLE pouches, side pouch), belt; AK-74M / RPK-74M with a stock and banana magazine as `plate`s, gas tube rod, round barrel and muzzle brake, GP-30, bipod, sling; rocket carrier pillow with three PG-7 lathes.
- **Paint**: uniform camo `ModelParts.CAMO_UNIFORM` scale 70 → **80**, mud height 0.03 → 0.015 (15 cm; 30 cm turned the legs brown to the knee). Boots, gloves, knee pads, belts, straps and slings use the new `Soldier.GEAR_PAINT` (camo shader, one colour: wear on chamfers, mud on the boots and a kneeling knee) via the new `ModelParts.weathered_paint(key, values)`; `VehicleFrame.weathered` now delegates to it (same values). Vest stays a plain `StandardMaterial3D` in `vest_color` (existing test); skin / gun stay PBR. The glasses use the GUN material (no extra role / draw call).
- **Kit**: no new MeshKit primitive was needed (`sweep`, `pillow`, `tube`, `cbox`, `lathe`, `rod`, `plate` cover everything).
- **Numbers** (7 figures per squad incl. the 2 hidden `Stand` variants, 42 mesh instances, all under `Soldier*`):

  | Squad / faction | Triangles | Cold build |
  |---|---|---|
  | pl_mech_infantry / poland | 28 804 | 108–113 ms |
  | pl_mech_infantry / russia | 28 804 | 108 ms |
  | ru_motor_rifle / poland | 27 672 | 102 ms |
  | ru_motor_rifle / russia | 27 672 | 102 ms |

  (before: ~10–11 k triangles). AABB after the model scale 0.62 × 0.45 × 0.35 (PL), 0.65 × 0.47 × 0.35 (RU), min y 0.0000.
- **Tests**: `MAX_TRIANGLES_SQUAD` 20 000 → 40 000 (`test_unit_model_contract.gd`; ADR 0010 amended). New `test_soldier_bodies_are_smooth_kit_meshes` (both squads: no `PrimitiveMesh`; the uniform / skin / gear meshes are un-indexed MeshKit `ArrayMesh`es with vertex masks, uniform and skin > 70 % smooth-shaded vertices). `test_infantry_torso_uses_fine_uniform_camo` checks the patterned materials against `CAMO_UNIFORM` and requires the gear paint; `test_hit_reset_works_on_camo_surfaces` now checks the material is the same object after the reset instead of a hard-coded pattern scale. Locomotion / kneel tests unchanged and green.
- **Renders**: `.screenshots/units/pl_mech_infantry_poland_sheet.png`, `.screenshots/units/ru_motor_rifle_russia_sheet.png` (per-view PNGs next to them); battle crop `.screenshots/task067_crop.png` (`SCREENSHOT_CAMERA=1,-40,5`; the camera clamps to its minimum distance, so 5 is already the closest game zoom); `docs/images/gameplay.png` re-rendered.
- **Deviations**: the kneeler's back ankle moved from y 0.17 to 0.22 (the study's toes-down boot sole reached 5 cm below the ground). The task asks for radio, IFAK and NVG shroud although the catalog's `skip` lists radios / small pouches / NVG mounts – kept small (no antenna), noted in the blueprint. Russians carry no assault pack (only the assistant's rocket carrier), as before. `.claude/agents/unit-modeler.md` still says "≤ 20 000 per squad" (outside the modeler's scope).

# TASK-068: Squad readability at battle zoom – mixed weapon carries and facings

- **Status**: done
- **Layers**: presentation (`models/parts/soldier.gd`, `models/pl_mech_infantry.gd`, `models/ru_motor_rifle.gd`), tests (`test_unit_models.gd`)
- **Depends on**: –
- **Model**: sonnet

## Goal

From the battle camera a soldier is ~40 px and seen from above, so a squad reads through its silhouette and poses, not its geometry detail (`docs/design/showcase/README.md`). Today three of the five soldiers hold their weapon the same way and all face forward ±17°, so the squad looks like copies of one figure. Mixed carries and a flank watcher make it read as a squad of people.

## Design

- A squad layout entry may carry two optional values: `[x, z, kneeling, kit, carry, yaw]`. `carry` is `Soldier.READY` (default – the kit's own angle), `Soldier.AIM` (weapon level at the shoulder, `AIM_ANGLE` −0.03 rad) or `Soldier.LOW` (muzzle well down, `LOW_ANGLE` −0.85 rad); `yaw` (rad) replaces the hashed ±0.3 rad jitter.
- `dress` hooks receive `carry` and turn it into the weapon angle with `Soldier.carry_angle(carry, kneel, ready_stand, ready_kneel)`. The merged-mesh cache key includes the carry.
- Layouts: the point man aims; the rear rifleman (Polish) / assistant grenadier (Russian) carries low and watches the right flank (yaw 0.7 / 0.6); the kneeling rifleman aims and covers the left (yaw −0.5). RPG and MG gunners unchanged.
- Considered and not done: a silhouette outline (conflicts with the realism direction in the GDD); lighter vests/packs for contrast from above (changes `vest_color` in the faction data – the human's call, see Open question).

## Acceptance criteria (testable)

- [x] `Soldier.carry_angle`: READY → the kit's standing / kneeling angle, AIM → `AIM_ANGLE`, LOW → `LOW_ANGLE`.
- [x] In both squads Soldier0 (aiming) and Soldier3 (low carry or assistant) do not share their first mesh.
- [x] Contract, locomotion and pose tests pass; triangle counts unchanged (12 880 / 14 296).
- [x] Battle crop (`SCREENSHOT_CAMERA=1,-40,5`) and `docs/images/gameplay.png` re-rendered.

## Playtest (for the human)

1. Zoom in on both squads: the leader aims, the rear man holds his weapon low and looks to the right, the kneeling rifleman aims to the left.
2. Move a squad: the march looks as before (the flank watcher walks slightly turned); kneelers stand up and kneel again.
3. Normal zoom: the squads look less like five copies of one figure.

## Open question (human)

- Should the Polish vest/pack colour (`vest_color` in `data/factions/poland.tres`) contrast more with the Pantera uniform (e.g. coyote instead of olive), so squads read better from above? The Russian tan already does.

## Player manual

None (visual only).

## Out of scope

- New body geometry (TASK-067), markings (TASK-063), animated aiming.

## Implementation notes

- Done 2026-10-21 together with the detail study (`docs/design/showcase/`). `soldier.gd` gained `READY` / `AIM` / `LOW`, `AIM_ANGLE`, `LOW_ANGLE`, `carry_angle()`; `squad()` reads the optional carry and yaw; the `dress` signature has a fifth parameter `carry`. Both model files use it; the Russian MG keeps its own angles.
- Playtested by the human 2026-10-21: poses, march and kneel/stand correct in game.
- Before/after battle crops: `.screenshots/showcase/inf_old_game_crop.png` / `inf_pose_game_crop.png` (local, not committed).

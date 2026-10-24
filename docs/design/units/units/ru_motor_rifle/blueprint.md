# Russian motor rifle squad (Ratnik kit) – model blueprint

Model: `src/presentation/models/ru_motor_rifle.gd` (squad kind: `Soldier0..4`, each with a
`Rig`; kneelers have `Kneel` + hidden `Stand`, see `UnitModels.pose_infantry`). The soldier
(soldier v4, TASK-085: `SoldierPose` with ANSUR II proportions, stances, two-bone IK and cheek
weld; the anatomical body; baked AO; RPG-7, helmet and weapon helpers) is the shared
`src/presentation/models/parts/soldier.gd`, also used by `pl_mech_infantry` – see its blueprint
for the body; this file adds the Ratnik kit through the `dress(k: MeshKits, pose: SoldierPose)`
hook (`STANCES`: the RPG on the shoulder, everyone else shoulders the rifle). References:
`side_1.jpg` (kneeling RPK-74 gunner – helmet shape, 6B45 front, AK profile with the curved
magazine, bipod), `front_1.jpg` (AK-74M at the shoulder, 6B45 with front pouches and groin flap),
`three_quarter_1.jpg` (6B47 helmet, collar).

## Scale

Same as the Polish squad: each soldier is built in **metres** at real size (1.80 m to the helmet
top, catalog `height` 180 cm) and converted with `M = 0.1` model units per metre; the `SoldierN`
pivot scales it by **`SOLDIER_SCALE = 1.75`** (0.32 model units tall) so it reads at game zoom
and matches the other squads. The render's `Real` line therefore reads about +75 % – proportions
within a soldier are real.

## Squad size: 5 figures (crew 6)

The real squad dismounts 6 (fire group: leader, RPG-7 gunner, assistant, machine gunner;
manoeuvre group: 2 riflemen with GP-30). The model shows **5**: `UnitModels.pose_infantry` poses
only `Soldier0..4` (`SQUAD_SIZE = 5`), so a sixth figure would stand still (and a sixth kneeler
would not stand up) when the squad moves; 5 also keeps the same footprint as the other squads.
The leader carries the second GP-30, so every role of the squad is still visible.

Layout (model units) `[x, z, kneeling, kit, carry, yaw]`; without a yaw, ±0.3 rad from
`TerrainNoise.hash`; carries as in TASK-068:

| Soldier | Position | Pose | Kit |
|---|---|---|---|
| 0 leader | (0.13, 0.0) | standing, aiming | AK-74M + GP-30 |
| 1 RPG gunner | (-0.03, 0.16) | standing, aiming | RPG-7V on the right shoulder |
| 2 machine gunner | (-0.03, -0.15) | kneeling (as in `side_1.jpg`) | RPK-74M, bipod down |
| 3 assistant grenadier | (-0.19, 0.06) | standing, low carry, watching right (yaw 0.6) | AK-74M + rocket carrier with 3 PG-7 rounds |
| 4 rifleman | (-0.16, -0.13) | kneeling, aiming left (yaw −0.5) | AK-74M + GP-30 |

Kneelers differ from the Polish squad (gunner + rifleman instead of RPG + rifleman), so the
two squads also differ in their group silhouette.

## Parts of one soldier (metres)

Shared body: see the Polish blueprint (`pl_mech_infantry/blueprint.md`) – anatomical torso, legs,
boots, arms, gloved hands, neck and head from `SoldierPose` joints (hip 0.94, knee 0.52, ankle
0.11; thigh 0.42, shin 0.41, upper arm 0.30, forearm 0.26), the pose per stance and carry, baked AO.

| Part | Size / position | Material | Built with |
|---|---|---|---|
| 6B47 helmet | turned shell (16 sides), outer ~0.31 long × 0.285 wide (`oval` 1.01 × 0.93 of a 0.153 radius), crown 0.133 above the rim plane, full cut curving in to the rim 3.6 cm below the plane (deep over the ears and neck), no flared brim; lip and inside as a cavity; rim plane at head-pivot (0, 0.07), tilted 0.14 rad back; mounting band, chin strap | uniform camo (EMR cover), gear paint | `loft_rings` (`Soldier.oval_rings`), `tube` |
| 6B45 armour | shell around the torso from y 0.99 to 1.43, 5 cm off the chest, 4.5 cm off the back, 3 cm at the sides, 0.1 lower at the sides – thicker than the Polish carrier; shoulder pads 0.15 × 0.018 × 0.06 | vest paint | `Soldier.torso_shell`, `Soldier.shoulder_pads` |
| High collar | lathe ring r 0.088 inside / 0.135 outside, 0.12 high from y 1.42 (chest frame), tilted back 0.15 rad | vest paint | `lathe` |
| Groin flap | 0.04 × 0.16 × 0.19 below the belt at the front | vest paint | `pillow` on `Soldier.on_torso` |
| MOLLE pouches | three magazine pouches 0.065 × 0.15 × 0.09 with flaps on the front section at y 1.15 (following the chest); side pouch on the right | vest paint | `cbox`, `pillow` |
| Belt | shell 0.955–0.995 | gear paint | `torso_shell` |
| AK-74M | 0.95 m in the shoulder pocket (`SoldierPose.shouldered`), muzzle 0.4 rad down at the ready (kneeler 0.2), level when aiming: stock plate with the AK drop, receiver, lower handguard, **gas tube**, front sight, barrel with muzzle brake, **curved magazine**, pistol grip, sling; support hand on the handguard (0.56 along) | gun paint, gear paint (sling) | `plate`, `cbox`, `rod`, `lathe`, `tube` |
| GP-30 | 40 mm tube r 0.024 × 0.26 under the handguard + trigger housing (leader, rifleman) | gun paint | `rod`, `cbox` |
| RPK-74M | AK profile with a 0.2 m longer barrel, 45-round magazine, bipod down when kneeling; 0.08 rad down kneeling (0.35 standing) | gun paint | same builder with `rpk = true`, `tube` legs |
| RPG-7V | shared `Soldier.rpg7` on `SoldierPose.launcher()` (grips ahead of the shoulder), head on the sight | gun paint tube, vest (olive) warhead | `lathe`, `cbox` |
| Rocket carrier | bag 0.16 × 0.34 × 0.30 on the back section of the assistant, three PG-7 warheads standing out of it | uniform camo bag, vest warheads | `pillow`, `Soldier.pg7` lathes |

Materials as in the Polish squad (all read the vertex masks: uniform fabric camo with AO, vest /
gun / gear / accent weathered paints, the skin shader). Each soldier variant is generated once per
kit, carry, posture and (relaxed poses) slot (`ModelParts.cached_meshes`) and added as one mesh
instance per material; no meshes outside the `Soldier*` pivots. Squad: 38 304 triangles (7
figures incl. the 2 hidden `Stand` variants), cold build ~240 ms.

## Silhouette features

1. **Rounded 6B47 helmet** – fuller, deeper shell without the PASGT brim flare, low over the ears,
   in the uniform camo (EMR cover).
2. **Bulky 6B45 armour with MOLLE pouches and a high collar** – thick shell around the torso,
   three pouches on the front, the collar ring around the neck, groin flap below the belt.
3. **AK profile** – curved banana magazine, gas tube over the barrel, AK stock drop, muzzle brake;
   GP-30 tube under two rifles.
4. **RPG-7V with the conical warhead** – the standing gunner aiming it from the shoulder; the
   assistant's carrier shows three more warheads over his back.
5. **EMR camouflage** – the faction uniform camo shader on uniform, helmet and rocket bag.

Details: RPK-74M (the catalog photo's gun) on the kneeling gunner. Skipped per the catalog:
radios and antennas, patches / armbands (the shared accent sleeve patch is the faction marker),
small pouches; also goggles, elbow pads, eyes, mouth and fingers (the face reads by its shape and
the baked AO, TASK-085).

# Polish mechanised infantry squad – model blueprint

Model: `src/presentation/models/pl_mech_infantry.gd` (squad kind: `Soldier0..4`, each with a
`Rig`; kneelers have `Kneel` + hidden `Stand`, see `UnitModels.pose_infantry`). Since TASK-085
(soldier v4) the soldier is the shared `parts/soldier.gd`: a `SoldierPose` (`parts/soldier_pose.gd`:
ANSUR II proportions, stances, two-bone IK, cheek weld), the anatomical body around it
(`parts/soldier_body.gd`: `MeshKit.sweep_profile` / `loft_rings` of anatomical cross-sections) and
ambient occlusion baked into the vertex masks (`parts/occlusion_bake.gd`). This file adds the
Polish kit through the `dress(k: MeshKits, pose: SoldierPose)` hook and says how each kit holds its
weapon (`STANCES`). References: `detail_1.jpg` (Grot profile, full-body stance),
`three_quarter_2.jpg` (full-body soldier next to a Rosomak), `three_quarter_1.jpg` and
`side_1.jpg` (helmet shape, plate carrier, pack, shaded face under the helmet), `detail_2.jpg`
(RPG-7 gunner).

## Scale

Each soldier is built in **metres** (x forward, y up, z right, boot soles on y = 0) at real size
(a 1.75 m body in 3 cm boots, helmet top ~1.80 m standing with soft knees) and converted with
`M = 0.1` model units per metre. The `SoldierN` pivot scales it by **`SOLDIER_SCALE = 1.75`** – at
true scale a soldier would be 0.24 world units tall on a 1.0 hex and unreadable at game zoom;
1.75 keeps the on-screen size of the earlier squads. The render's `Real` line therefore reads
about +71 % on the soldier height – the proportions within a soldier are real.

Squad layout (model units): `[x, z, kneeling, kit, carry, yaw]` = `[0.12, 0, no, rifle, aim]`,
`[-0.03, 0.15, yes, RPG-7]`, `[-0.04, -0.15, no, UKM-2000]`, `[-0.19, 0.06, no, rifle, low, 0.7]`,
`[-0.16, -0.13, yes, rifle, aim, -0.5]`; without a yaw, ±0.3 rad from `TerrainNoise.hash`.
Stances: rifle = shouldered, RPG = launcher on the shoulder, UKM = at the hip.

## Shared soldier (soldier v4, metres)

Proportions (ANSUR II male means scaled to 1.75 m + boots): hip joints at 0.94 (± 0.088), knee
joint 0.52, ankle joint 0.11; shoulder joints (−0.005, 1.435, ±0.172), acromion ~1.47; neck base
1.50, head pivot 1.60, chin 1.562, scalp 1.776. Segments (joint to joint, fixed): thigh 0.42, shin
0.41, upper arm 0.30, forearm 0.26, wrist to grip 0.075. Head + helmet = 0.24 of a ~1.78 m figure
(7.4 heads; test ≥ 7).

| Part | Shape / size | Material | Built with |
|---|---|---|---|
| Pose | standing: bladed stance for rifle and RPG (left foot forward, hips turned 0.4 rad right, chest 0.2 back towards the weapon, forward lean), GPMG squarer; weight shift + pelvis / shoulder roll per slot when not aiming (contrapposto), feet turned out; the pelvis lowers until both legs reach with soft knees. Kneeling: right knee on the ground (knee pad at y 0), right foot behind on its toes (pitched until the toe touches), left foot planted forward | – | `SoldierPose` |
| Arms / legs | two-bone IK from shoulder to grip / hip to ankle with the fixed lengths; elbows towards poles down and back (firing elbow out when aiming), knees over the toes | – | `SoldierPose.two_bone` |
| Head pose | relaxed: turned per slot (± 0.35 rad), slightly down; aiming: pitch / roll solved so the right eye lies on the sight line (cheek weld, max 0.45 / 0.3 rad); RPG: eye on the launcher's sight | – | `SoldierPose._cheek_weld` |
| Torso | 13 sections (20 points) from the crotch to the collar: pelvis with glutes (half width 0.18), waist 0.165, chest 0.178 with pectorals and shoulder blades, shoulders 0.19, trapezius slope, collar; bent and twisted along the spine | uniform camo | `loft_rings` |
| Legs | trouser sections (12 points): thigh 0.098 / 0.078 (lateral / medial) tapering to the knee (patella bump), calf belly behind, bloused over the boot top (folds), tucked in; cargo pocket 0.15 × 0.11 on the outer thigh; knee pad 0.11 × 0.09 | uniform camo, gear paint (pads) | `sweep_profile`, `pillow` |
| Boots | upper from a last profile (heel, instep 0.066 high, ball 0.104 wide, rounded toe cap, flat bottom), shaft to 0.16 above the ankle, sole plate 3 cm following the outline (+7 mm, chamfered) | gear paint (mud to 12 cm) | `sweep_profile`, `sweep`, `plate` |
| Arms | sleeve sections (12 points): deltoid 0.07 lateral, biceps / triceps, elbow (bunched), forearm tapering to the cuff 0.034 | uniform camo | `sweep_profile` |
| Hands | glove mitten: palm 0.084 wide, fingers curled around the grip (curl direction from the kit), separate thumb | gear paint | `sweep_profile`, `tube` |
| Neck, head | one loft (20 points, crowded to the face): neck r ~0.056, jaw and chin, mouth, nose (2–3 cm bump), cheekbones, eye sockets under the brow ridge, forehead, crown; head 0.193 long × 0.156 wide; ears; short hair over the back and sides | skin shader, gear paint (hair) | `loft_rings`, `pillow` |
| Sleeve patch | 0.045 × 0.058 on each upper sleeve (flag position) | faction accent paint | `cbox` |

Ambient occlusion: capsule / sphere proxies for pelvis, belly, chest, thighs, shins, boots, upper
arms, forearms, neck, skull, brow ridge, nose and mouth, plus the kit's pack and pouch row, and a
cap under each helmet rim; `OcclusionBake` multiplies COLOR.g (openness) of the uniform, skin and
vest meshes (indexed, each shared vertex once): dark under the helmet and in the eye sockets,
armpits, crotch and inner thighs, under the pouches and the pack.

## Polish kit (this file)

| Part | Size / position | Material | Built with |
|---|---|---|---|
| wz. 2005 helmet | turned shell (16 sides), outer 0.32 long × 0.29 wide (`oval` 1.03 × 0.93 of a 0.157 rim radius), crown 0.128 above the rim plane, short flared brim, the lip and inside as a cavity; rim plane at head-pivot (0.004, 0.07), tilted 0.24 rad back – rim at the brow, low over the ears and neck; cover band, NVG shroud, chin strap | uniform camo (Pantera cover), gear paint | `loft_rings` (`Soldier.oval_rings`), `cbox`, `tube` |
| KKZ plate carrier | shell around the torso from y 1.04 to 1.42, 3.6 cm off the chest, 3.4 cm off the back, 1.6 cm at the sides, 0.15 lower at the sides (armholes); shoulder pads 0.13 × 0.012 × 0.05 | vest paint | `Soldier.torso_shell`, `Soldier.shoulder_pads` |
| Pouches | three magazine pouches 8 × 13 × 4.5 cm with flaps on the front plate at y 1.18 (following the chest), radio (left) and IFAK (right) on the cummerbund | vest paint | `cbox`, `pillow` on `Soldier.on_torso` frames |
| Belt | shell 0.975–1.02, 1.2 cm off the body, buckle | gear paint | `torso_shell`, `cbox` |
| Assault pack | 0.14 × 0.32 × 0.27 on the back plate, lid, compression straps, side bottle | vest paint, gear paint | `pillow`, `tube`, `lathe` |
| MSBS Grot C | 0.93 m in the shoulder pocket (`SoldierPose.shouldered`: butt centre in the pocket, bore 3.5 cm above): stock, receiver, **long top rail**, handguard, magazine, pistol grip, barrel with muzzle device, red dot, sling; support hand under the handguard (0.53 along), firing hand on the grip | gun paint, gear paint (sling) | `cbox`, `lathe`, `tube` |
| UKM-2000 | at the hip (stock under the right forearm), 0.06 rad up: stock, receiver, feed cover, handle, barrel with flash hider and gas block, folded bipod, ammunition box, sling over the left shoulder | gun paint, vest (ammo box) | `cbox`, `lathe`, `tube` |
| RPG-7 | shared `Soldier.rpg7` on `SoldierPose.launcher()` (tube's middle 0.21 ahead of the shoulder so the grips are in front of it): tube 1.0 m, heat shield, venturi flare, **PG-7 warhead**, grips, sight on the left | gun paint, vest (olive) warhead | `lathe`, `cbox` |

Materials (all read the vertex masks): uniform = faction camo with `ModelParts.CAMO_UNIFORM`
(pattern scale 150 – blotches ~5–15 cm –, contrast 0.72, fade 0.22, `fabric` creases / weave bump
and sheen, `mask_ao` 1: COLOR.g also as the AO output), vest = weathered paint in the faction
`vest_color` (per-part tint 0.55, light wear, dust), gun = weathered dark paint (edge wear), gear =
`Soldier.GEAR_PAINT`, accent = weathered paint in the faction colour, skin = `assets/shaders/skin.gdshader`
(AO, subsurface scattering on Forward+). Each soldier variant is generated once per kit, carry,
posture and (for relaxed poses) squad slot (`ModelParts.cached_meshes`; an aiming kneeler's hidden
`Stand` shares the standing aimer's meshes) and added as one mesh instance per material; no meshes
outside the `Soldier*` pivots. Squad: 38 844 triangles (7 figures incl. the 2 hidden `Stand`
variants), cold build ~240 ms.

## Silhouette features

1. **PASGT-like wz. 2005 helmet** – real outer size, low on the head (rim at the brow, over the
   ears), short flared brim, Pantera cover.
2. **Bulky plate carrier with front pouches** – shell following the chest, pouches on the front
   plate, pack on the back plate.
3. **Grot C** – conventional layout with the full-length top rail and red dot, butt in the shoulder
   pocket, head on the stock when aiming.
4. **RPG-7** – kneeling gunner (Soldier1) with the tube on the shoulder and the conical warhead.
5. **Pantera camouflage** – fine-grained faction uniform camo on uniform and helmet.

Details: UKM-2000 on Soldier2, assault packs on everyone. Skipped per the catalog: antennas,
insignia (the accent patch stands in for the flag patch), most small pouches, NVG (a small shroud
only); also eyes, mouth and fingers (out of scope of TASK-085: the face reads by its shape and AO).

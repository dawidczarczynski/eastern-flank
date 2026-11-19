# Polish mechanised infantry squad – model blueprint

Model: `src/presentation/models/pl_mech_infantry.gd` (squad kind: `Soldier0..4`, each with a
`Rig`; kneelers have `Kneel` + hidden `Stand`, see `UnitModels.pose_infantry`). Since TASK-085
(soldier v4) the soldier is the shared `parts/soldier.gd`: a `SoldierPose` (`parts/soldier_pose.gd`:
ANSUR II proportions, stances, two-bone IK, cheek weld), the anatomical body around it
(`parts/soldier_body.gd`: `MeshKit.sweep_profile` / `loft_rings` of anatomical cross-sections) and
ambient occlusion baked into the vertex masks (`parts/occlusion_bake.gd`). This file adds the
Polish kit through the `dress(k: MeshKits, pose: SoldierPose)` hook and says how each kit holds its
weapon (`STANCES`). References: the one-soldier reference GLB (`reference_views/glb_*.png`: a
Polish rifleman aiming a Grot in a wide bladed stance – plate carrier, helmet with ear defenders,
knee pads, boots; compared with `tools/compare_silhouette.sh pl_mech_infantry --soldier=0
--soldier-yaw=16`, see below), `detail_1.jpg` (Grot profile, full-body stance),
`three_quarter_2.jpg` (full-body soldier next to a Rosomak), `three_quarter_1.jpg` and
`side_1.jpg` (helmet shape, plate carrier, pack, shaded face under the helmet), `detail_2.jpg`
(an RPG-7 gunner of an earlier exercise; the squad's anti-tank launcher is now the Carl Gustaf M4).

## Scale

Each soldier is built in **metres** (x forward, y up, z right, boot soles on y = 0) at real size
(a 1.75 m body in 3 cm boots, helmet top ~1.80 m standing with soft knees) and converted with
`M = 0.1` model units per metre. The `SoldierN` pivot scales it by **`SOLDIER_SCALE = 1.75`** – at
true scale a soldier would be 0.24 world units tall on a 1.0 hex and unreadable at game zoom;
1.75 keeps the on-screen size of the earlier squads. The render's `Real` line therefore reads
about +71 % on the soldier height – the proportions within a soldier are real.

Squad layout (model units): `[x, z, kneeling, kit, carry, yaw]` = `[0.12, 0, no, rifle, aim]`,
`[-0.03, 0.15, yes, AT launcher]`, `[-0.04, -0.15, no, UKM-2000]`, `[-0.19, 0.06, no, rifle, low, 0.7]`,
`[-0.16, -0.13, yes, rifle, aim, -0.5]`; without a yaw, ±0.3 rad from `TerrainNoise.hash`.
Stances: rifle = `ASSAULT` (shouldered in the wide, crouched assault stance of the GLB), anti-tank launcher =
launcher on the shoulder, UKM = at the hip.

## Shared soldier (soldier v4, metres)

Proportions (ANSUR II male means scaled to 1.75 m + boots): hip joints at 0.94 (± 0.088), knee
joint 0.52, ankle joint 0.11; shoulder joints (−0.005, 1.435, ±0.172), acromion ~1.47; neck base
1.50, head pivot 1.60, chin 1.562, scalp 1.776. Segments (joint to joint, fixed): thigh 0.42, shin
0.41, upper arm 0.30, forearm 0.26, wrist to grip 0.075. Head + helmet = 0.24 of a ~1.78 m figure
(7.4 heads; test ≥ 7).

| Part | Shape / size | Material | Built with |
|---|---|---|---|
| Assault stance (`SoldierPose.ASSAULT`, Polish riflemen) | from the GLB, in its aim frame: pelvis at x −0.04, yawed 0.45 rad right, chest 0.26 back and leaning 0.32 rad (+0.05 aiming) over the front foot; ankles left (0.36, −0.30), right (−0.22, 0.35) – ~0.6 m apart along the aim and across –, legs at 0.95 of their reach (bent knees, hips ~0.81 m); aimed butt 4 cm higher in the pocket (`high_butt`), both shoulders 2.5 cm up (`shrug`), the head sinking between them | – | `SoldierPose.STANDS` |
| Pose | standing: bladed stance for rifle and anti-tank launcher (left foot forward, hips turned 0.4 rad right, chest 0.2 back towards the weapon, forward lean), GPMG squarer; weight shift + pelvis / shoulder roll per slot when not aiming (contrapposto), feet turned out; the pelvis lowers until both legs reach with soft knees. Kneeling: right knee on the ground (knee pad at y 0), right foot behind on its toes (pitched until the toe touches), left foot planted forward | – | `SoldierPose` |
| Arms / legs | two-bone IK from shoulder to grip / hip to ankle with the fixed lengths; elbows towards poles down and back (firing elbow out when aiming), knees over the toes | – | `SoldierPose.two_bone` |
| Head pose | relaxed: turned per slot (± 0.35 rad), slightly down; aiming: pitch / roll solved so the right eye lies on the sight line (cheek weld, max 0.45 / 0.3 rad, 3/4 of the pitch in the neck base so the head goes forward and down onto the stock – `WELD_NECK`); anti-tank launcher: eye on its sight | – | `SoldierPose._cheek_weld` |
| Torso | 13 sections (20 points) from the crotch to the collar: pelvis with glutes (half width 0.18), waist 0.165, chest 0.178 with pectorals and shoulder blades, shoulders 0.19, trapezius slope, collar; bent and twisted along the spine | uniform camo | `loft_rings` |
| Legs | full cargo trouser sections (10 points, matched to the GLB front view): thigh 0.126 / 0.094 (lateral / medial, ~0.24 m across) rumpled (folds), knee 0.10 / 0.074 (patella bump, the medial side within 8 cm of the joint), shin tapering to 0.09 / 0.08, bloused ~0.2 m wide over the boot top (s 1.42–1.5) and tucked into the shaft (s 1.58); cargo pocket 0.16 × 0.12 on the outer thigh; round knee pad 0.13 × 0.11 facing the knee front (away from the hip–ankle chord) | uniform camo, gear paint (pads) | `sweep_profile`, `pillow` |
| Boots | slim combat boot: upper from a last profile (`BOOT`, 8 points: heel counter, instep rising to the laced front, ball 0.096 wide, low toe cap, flat bottom), 0.29 m long with the sole; shaft (`SHAFT`) narrow at the ankle bone (0.078 across), laced front standing forward, up to 0.175 above the ankle (~0.29 m above the ground) with a collar; flat 2.4 cm forefoot sole from x 0.03 to the toe, separate 3 cm heel block, the arch open between them | gear paint (black, light mud to 12 cm) | `sweep_profile`, `sweep`, `plate`, `cbox` |
| Arms | loose blouse sleeve sections (12 points): deltoid 0.078 lateral, biceps / triceps (rumpled), elbow (bunched), forearm tapering to the cuff 0.038 | uniform camo | `sweep_profile` |
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
| Ear defenders | electronic headset cups under the rim: turned cup r 0.042, 0.036 deep, centre head-pivot (−0.008, 0.035, ±0.112) – they widen the head in the front view like the GLB's | gear paint | `lathe` |
| wz. 2005 helmet | turned shell (16 sides), outer 0.32 long × 0.29 wide (`oval` 1.03 × 0.93 of a 0.157 rim radius), crown 0.128 above the rim plane, short flared brim, the lip and inside as a cavity; rim plane at head-pivot (0.004, 0.07), tilted 0.24 rad back – rim at the brow, low over the ears and neck; cover band, NVG shroud, chin strap | uniform camo (Pantera cover), gear paint | `loft_rings` (`Soldier.oval_rings`), `cbox`, `tube` |
| KKZ plate carrier | shell around the torso from y 1.02 to 1.42, 5 cm off the chest, 4.6 cm off the back, 2.6 cm at the sides (cummerbund), 0.16 lower at the sides (armholes); shoulder pads 0.14 × 0.016 × 0.06 | uniform camo (carrier in the Pantera print, as on the GLB) | `Soldier.torso_shell`, `Soldier.shoulder_pads` |
| Pouches | three double magazine pouches 15 × 8.5 × 6 cm with flaps on the front plate at y 1.16 (following the chest), admin pouch 10 × 19 cm above them, radio 17 × 9 (left) and IFAK 13 × 9 (right) on the cummerbund, utility pouches 13 × 11 × 7 on both hips (belt, y 0.97), dump pouch 12 × 20 × 6 at the back of the belt | vest paint | `cbox`, `pillow` on `Soldier.on_torso` frames |
| Belt | shell 0.95–1.0, 1.4 cm off the body, buckle | gear paint | `torso_shell`, `cbox` |
| Hydration pack | 0.06 × 0.30 × 0.20 on the back plate (no assault pack: the GLB carries none) | vest paint | `pillow` |
| MSBS Grot C | 0.93 m in the shoulder pocket (`SoldierPose.shouldered`: butt centre in the pocket, bore 3.5 cm above): stock, receiver, **long top rail**, handguard, magazine, pistol grip, barrel with muzzle device, red dot, sling held close under the rifle; support hand under the handguard (0.53 along), firing hand on the grip | gun paint, gear paint (sling) | `cbox`, `lathe`, `tube` |
| UKM-2000 | at the hip (stock under the right forearm), 0.06 rad up: stock, receiver, feed cover, handle, barrel with flash hider and gas block, folded bipod, ammunition box, sling over the left shoulder | gun paint, vest (ammo box) | `cbox`, `lathe`, `tube` |
| Anti-tank launcher | shared `parts/at_launcher.gd`, kind `AT_LAUNCHER_KIND = carl_gustaf` (Carl Gustaf M4) on `SoldierPose.launcher()` (tube's middle 0.21 ahead of the shoulder): tube 0.95 m r 0.045 with the muzzle bell (r 0.052) and the venturi cone (r 0.066) at the rear, front grip (+0.17) and rear trigger grip (−0.04), shoulder rest (−0.2), sight block on the left of the top; nodes `AtLauncher` and its child `Muzzle` (x along the bore) on the gunner's posture nodes | gun paint | `lathe`, `cbox` |

Materials (all read the vertex masks): uniform = faction camo with `ModelParts.CAMO_UNIFORM`
(pattern scale 150 – blotches ~5–15 cm –, contrast 0.72, fade 0.22, `fabric` creases / weave bump
and sheen, `mask_ao` 1: COLOR.g also as the AO output), vest = weathered paint in the faction
`vest_color` (per-part tint 0.55, light wear, dust), gun = weathered dark paint (edge wear), gear =
`Soldier.GEAR_PAINT`, accent = weathered paint in the faction colour, skin = `assets/shaders/skin.gdshader`
(AO, subsurface scattering on Forward+). Each soldier variant is generated once per kit, carry,
posture and (for relaxed poses) squad slot (`ModelParts.cached_meshes`; an aiming kneeler's hidden
`Stand` shares the standing aimer's meshes) and added as one mesh instance per material; no meshes
outside the `Soldier*` pivots. Squad: 39 612 triangles (7 figures incl. the 2 hidden `Stand`
variants; budget 40 000), far_triangles 9 237 (max 20 000), 42 mesh instances inside the
`Soldier*` pivots.

## Silhouette features

1. **PASGT-like wz. 2005 helmet** – real outer size, low on the head (rim at the brow, over the
   ears), short flared brim, Pantera cover.
2. **Bulky plate carrier with front pouches** – camo shell following the chest, double magazine
   and admin pouches on the front plate, radio / IFAK on the cummerbund, hip and dump pouches on
   the belt, a low hydration pack on the back plate.
3. **Loose uniform, wide assault stance** – baggy trousers and sleeves, knee pads, tall black
   boots; the riflemen crouch with the feet ~0.6 m apart, chest over the front foot, head down on
   the stock between raised shoulders; ear defenders under the helmet.
4. **Grot C** – conventional layout with the full-length top rail and red dot, butt in the shoulder
   pocket, head on the stock when aiming.
5. **Carl Gustaf M4** – kneeling anti-tank gunner (Soldier1) with the long smooth tube on the
   shoulder, the venturi cone behind him and the muzzle bell in front.
6. **Pantera camouflage** – fine-grained faction uniform camo on uniform and helmet.

Details: UKM-2000 on Soldier2, hydration packs on everyone. Skipped per the catalog: antennas,
insignia (the accent patch stands in for the flag patch), most small pouches, NVG (a small shroud
only); also eyes, mouth and fingers (out of scope of TASK-085: the face reads by its shape and AO).

## One-soldier comparison with the reference GLB

`tools/compare_silhouette.sh pl_mech_infantry --soldier=0 --soldier-yaw=16 --min-iou=0.80`
compares the point rifleman alone (other soldiers hidden, at the origin, turned 16° left like the
GLB's figure, scaled to the GLB's height – the GLB is normalised so its *crouched* bounding box is
1.82 m, so it compares shapes, not sizes); `tools/render_unit.sh pl_mech_infantry --soldier=0
--soldier-yaw=16 --reference=docs/design/units/units/pl_mech_infantry/reference_views/glb_side.png`
renders him next to the GLB. After 4 rounds: `IoU side=0.55 front=0.80 top=0.63`; after the
fuller trousers and slim boots (3 more rounds): `IoU side=0.56 front=0.83 top=0.64` (before: side
0.55, front 0.39, top 0.53 with the old narrow, upright figure and no height match). Remaining
side mismatch: the model's rifle is ~10 % longer relative to the figure (the GLB's figure is
larger than the ANSUR 1.75 m body), so the bounding-box centring pushes the model's legs back; the
GLB's front knee also reaches further forward than our 0.83 m legs allow at this hip height.

## Look round (human feedback: "as close to the GLB as possible", judged in the unit catalog)

- Materials: `LOOK = {"khaki": 0.7, "light": #b3ab94}` – `Soldier.materials` mixes the faction's
  camo colours 70 % towards the wz. 93 Pantera tan (`Soldier.PANTERA_COLORS`: tan ground,
  olive-brown and near-black blotches) and the vest colour towards `KHAKI_VEST`; the new role
  `light` holds the gloves and the white-grey knee pads; `GEAR_PAINT` is black, slightly glossy
  leather (roughness 0.42) with no mud – boots, belts, ear defenders, webbing, glove cuffs;
  `CAMO_UNIFORM` scale 135, contrast 0.88, fade 0.14 (bigger, darker blotches).
- Carrier in khaki nylon with a pouch grid (3 double magazine pouches, 3 smaller pouches above),
  two black webbing rows; NVG shroud plate and mount on the helmet; ear defender cups.
- Grot C 0.84 m to the muzzle (10 % shorter), low top rail, small red dot.
- Assault stance: lean 0.38, front ankle (0.42, −0.29), shrug 0.045.
- Budget: torso 16 sides, head 18, arms and legs 10, boots 8; squad 39 472 triangles.
- One-soldier IoU (`--soldier=0 --soldier-yaw=10`, the yaw that lines the rifles up):
  side 0.66, front 0.84, top 0.79.

## Helmet round (high-cut helmet, Polish-specific)

`_helmet` in the model file (the shared `Soldier.helmet` stays the Russian 6B47 / PASGT bowl): a
dome of radius 0.157 (oval 1.03 × 0.95 → 0.32 × 0.30 m) rising 0.13 above the rim plane, rim at
head-pivot (0.008, 0.062), tilted 0.06 rad back; `rim_height(a)` keeps the rim at the brow in
front, cuts it 5 cm up over the ears (from 0.55 to 1.05 rad off the front) and drops it to −2.8 cm
at the nape; 7 dome rings + lip and inner wall as a cavity (16 sides), uniform camo cover with a
khaki elastic band; black side rails along the cut, NVG shroud plate and mount, chin strap from
behind the ears, goggles (three lenses) over the eyes; ear defender cups r 0.037 below the cut.

## Weapons round

- **MSBS Grot C** (`_rifle`), 0.84 m to the muzzle, matched to the GLB's rifle: folding skeleton
  stock (butt plate, top bar, angled strut), modular receiver (upper with a black ejection port,
  lower with the magazine well), top rail 0.38 m over receiver and handguard with a small red dot
  (r 1.1 cm), handguard 0.18 m with a bottom rail and the front sight post, raked pistol grip,
  curved three-segment polymer magazine with its base plate, exposed barrel and a 6 cm muzzle
  brake; support hand under the handguard.
- **Anti-tank launcher – visual kind per country, shared behaviour.** `parts/at_launcher.gd`
  builds the launcher of a kind (`carl_gustaf` here, `rpg7` for ru_motor_rifle) from one table:
  tube profile, grips, shoulder rest, sight; every kind is held in the same
  `SoldierPose.AT_LAUNCHER` stance and records the same nodes – `AtLauncher` (launcher frame) and
  its child `Muzzle` at the tube's front, x along the bore – under the gunner's `Kneel` and
  `Stand` nodes (`SoldierPose.markers`, `Soldier.add_markers`). TASK-188b fires from `Muzzle`
  whatever the kind. Kit constant: `AT_LAUNCHER` (was `RPG`).

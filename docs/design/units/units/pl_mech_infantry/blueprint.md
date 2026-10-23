# Polish mechanised infantry squad – model blueprint

Model: `src/presentation/models/pl_mech_infantry.gd` (squad kind: `Soldier0..4`, each with a
`Rig`; kneelers have `Kneel` + hidden `Stand`, see `UnitModels.pose_infantry`). Since TASK-067
(infantry v3) the soldier is the shared smooth `parts/soldier.gd` built with `MeshKit` (`sweep`,
`pillow`, `tube`, `cbox`, `lathe`, `plate`) in metres with a 0.1 base scale; this file adds the
Polish kit through the `dress(k: MeshKits, up, kit, kneel, carry)` hook. References: `detail_1.jpg` (Grot profile, full-body
stance), `three_quarter_2.jpg` (full-body soldier next to a Rosomak), `three_quarter_1.jpg` and
`side_1.jpg` (helmet shape, plate carrier, pack), `detail_2.jpg` (RPG-7 gunner).

## Scale

Each soldier is built in **metres** (x forward, y up, z right, feet on y = 0) at real size
(1.82 m to the helmet top) and converted with `M = 0.1` model units per metre. The `SoldierN`
pivot then scales it by **`SOLDIER_SCALE = 1.75`** – at true scale a soldier would be 0.24 world
units tall on a 1.0 hex and unreadable at game zoom; 1.75 matches the on-screen size of the
generic `infantry` squad (0.32 model units, 0.42 world units) so squads of different factions stay
comparable. The render's `Real` line therefore reads +74 % on the soldier height (3.2 m) – the
proportions within a soldier are real.

Squad layout (model units, same footprint as the generic squad): `[x, z, kneeling, kit, carry,
yaw]` = `[0.12, 0, no, rifle, aim]`, `[-0.03, 0.15, yes, RPG-7]`, `[-0.04, -0.15, no, UKM-2000]`,
`[-0.19, 0.06, no, rifle, low, 0.7]`, `[-0.16, -0.13, yes, rifle, aim, -0.5]`; without a yaw,
±0.3 rad from `TerrainNoise.hash`. Carries (TASK-068): aim = weapon level, low = muzzle −0.85 rad,
otherwise the kit's ready angle.

## Parts of one soldier (metres)

Shared body (`parts/soldier.gd`, all smooth kit meshes, no box / cylinder primitives):

| Part | Size / position | Material | Built with |
|---|---|---|---|
| Legs (standing) | hip 0.92 at z ±0.10, knee 0.50, ankle 0.12; left leg 0.06 forward, right 0.06 back; one sweep per leg (10 sides, 8 rings): thigh r 0.095 → knee 0.066, calf bulge 0.07 → ankle 0.05 | uniform camo | `sweep` |
| Legs (kneeling) | hip 0.55; left knee up (0.44, 0.55), right knee on the ground (0.06, 0.09), right foot behind on its toes (ankle (−0.36, 0.22), toes down 0.75 rad) | uniform camo | `sweep` |
| Thigh pockets, knee pads | pocket 0.11 × 0.15 × 0.04 on the outer thigh; pad 0.05 × 0.12 × 0.10 in front of the knee (on the ground when kneeling) | uniform / gear paint | `pillow` |
| Boots | shaft r 0.06, rounded upper 0.28 × 0.10 × 0.11, chamfered sole 0.29 × 0.03 × 0.115 on y = 0 | gear paint (mud up to 12 cm) | `sweep`, `pillow`, `cbox` |
| Torso | one sweep (16 sides) pelvis 0.84 → waist 1.02 → chest 1.27 (half widths 0.19 × 0.125) → shoulders 1.37 → neck base 1.47; deltoids 0.14 × 0.13 × 0.13 at (0, 1.405, ±0.2); shirt collar | uniform camo | `sweep`, `pillow` |
| Neck, head | neck r 0.05; skull ellipsoid 0.19 × 0.23 × 0.16 at (0.035, 1.625), jaw, nose, ears | SKIN | `sweep`, `pillow`, `cbox` |
| Arms, gloves | shoulder (0, 1.41, ±0.21), elbow between shoulder and grip pushed down / out; sweep r 0.064 → 0.036 at the wrist; glove 0.10 × 0.05 × 0.085 | uniform camo, gear paint | `sweep`, `pillow` |
| Sleeve patch (flag position) | 0.06 × 0.04 on each upper sleeve | faction accent | `cbox` |

Polish kit (this file):

| Part | Size / position | Material | Built with |
|---|---|---|---|
| wz. 2005 helmet | lathe (18 sides) r 0.155 at the crown base, flaring to r 0.172 at the rim 5.5 cm below; crown 0.175 above the base at y 1.635; tilted 0.16 rad back; cover band, NVG shroud, chin strap | uniform camo (Pantera cover), gear paint | `lathe`, `cbox`, `tube` |
| Ballistic glasses | 0.03 × 0.035 × 0.15 in front of the eyes | GUN (dark gloss) | `cbox` |
| Plate carrier (KKZ) | front plate 0.075 × 0.34 × 0.33 at (0.11, 1.26), back 0.07 × 0.36 × 0.33 at (−0.115, 1.28), cummerbund sweep r 0.19 × 0.135 (y 1.07–1.18), padded shoulder straps r 0.022 | vest | `pillow`, `sweep`, `tube` |
| Pouches | three magazine pouches 0.05 × 0.12 × 0.075 with flaps on the front at y 1.15; radio (left) and IFAK (right) on the sides | vest | `cbox`, `pillow` |
| Belt | sweep r 0.178 × 0.122 at y 0.96–1.0, buckle | gear paint | `sweep`, `cbox` |
| Assault pack | 0.15 × 0.32 × 0.27 at x −0.24, y 1.25; lid 0.17 × 0.07 × 0.28; two compression straps; side bottle | vest, gear paint | `pillow`, `tube`, `lathe` |
| MSBS Grot C | 0.93 m: stock 0.24, receiver 0.30, **long top rail 0.54**, handguard 0.26, magazine, pistol grip (chamfered boxes), round barrel with muzzle device, red-dot tube, sling; butt in the right shoulder at (0.12, 1.34, 0.11) | GUN, gear paint (sling) | `cbox`, `lathe`, `tube` |
| UKM-2000 | at the hip, butt at (−0.12, 1.10, 0.22), 0.05 rad up: stock, receiver, feed cover, carrying handle, round barrel with flash hider and gas block, folded bipod, olive ammunition box, sling over the shoulder | GUN, vest (ammo box) | `cbox`, `lathe`, `tube` |
| RPG-7 | shared `Soldier.rpg7`: tube 1.0 m (r 0.02, heat shield r 0.034, venturi flare r 0.046) on the right shoulder; **PG-7 warhead** r 0.0425 with the conical nose; grips, sight | GUN tube, vest (olive) warhead | `lathe`, `cbox` |

Materials: uniform = faction camo (`ModelParts.CAMO_UNIFORM`, pattern scale 80, mud 15 cm), vest =
faction vest colour, skin / gun = PBR palette, gear = `Soldier.GEAR_PAINT` (weathered dark paint:
wear on chamfers, mud on boots and a kneeling knee), accent = faction colour. Each soldier variant
(kit × carry × kneeling) is generated once (`ModelParts.cached_meshes`, key
`pl_mech_infantry:<kit>:<carry>:<kneel>`) and added as one mesh instance per material (6); no
meshes outside the `Soldier*` pivots. Squad: ~28 800 triangles (7 figures incl. the 2 hidden
`Stand` variants).

## Silhouette features

1. **PASGT-like wz. 2005 helmet** – the lathed helmet with a flared rim, tilted back (short brim
   at the front, skirt over the ears), in the uniform camo like the Pantera cover.
2. **Bulky plate carrier with front pouches** – vest box wider and deeper than the torso, with the
   pouch row standing out at the front.
3. **Grot C** – conventional layout with the full-length top rail, red dot and polymer stock.
4. **RPG-7** – kneeling gunner (Soldier1) aiming it with the bulbous conical warhead forward and
   the venturi flare behind.
5. **Pantera camouflage** – the faction uniform camo shader on uniform and helmet.

Details: UKM-2000 on Soldier2, assault packs on everyone. Skipped per the catalog: antennas,
insignia (the accent patch stands in for the flag patch as the faction marker), most small
pouches; also face and fingers. TASK-067 added a few of the small pieces the catalog lists as
skipped (radio pouch without antenna, IFAK, NVG shroud) because the task's design asks for them;
they are a few centimetres and only show in close-ups.

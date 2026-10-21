# Polish mechanised infantry squad – model blueprint

Model: `src/presentation/models/pl_mech_infantry.gd` (squad kind: `Soldier0..4`, each with a
`Rig`; kneelers have `Kneel` + hidden `Stand`, see `UnitModels.pose_infantry`). Shared helpers:
`ModelParts` (faction materials, primitive / lathe meshes, `merged_mesh`) and
`VehicleFrame.axis_basis` for the rods. References: `detail_1.jpg` (Grot profile, full-body
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

| Part | Size / position | Material | Built with |
|---|---|---|---|
| Legs (standing) | hip 0.92 at z ±0.10, knee 0.50, ankle 0.12; left leg 0.06 forward, right 0.06 back; thigh r 0.10→0.082, shin 0.078→0.062, knee ball r 0.08 | uniform camo | `_rod` (8-sided tapered cylinders), sphere |
| Legs (kneeling) | hip 0.55; left knee up (0.44, 0.55), right knee on the ground (0.06, 0.08), right foot behind on its toes | uniform camo | same |
| Boots | 0.27 × 0.11 × 0.10, soles on y = 0 | DARK | box |
| Hips / torso | 0.24 × 0.18 × 0.34 at 0.96; torso 0.22 × 0.42 × 0.38 at 1.22 | uniform camo | box |
| Plate carrier (KKZ-01) | 0.32 × 0.38 × 0.40 at 1.26 (2 cm forward), belt / cummerbund 0.28 × 0.07 × 0.37 at 1.0 | vest | box |
| Front pouch row | 0.08 × 0.14 × 0.34 on the vest front at 1.15 | vest | box |
| Assault pack | 0.14 × 0.30 × 0.27 at x −0.23, y 1.25, lid 0.16 × 0.05 × 0.28 | vest | box |
| Shoulders, arms, gloves | shoulder balls r 0.075 at (0, 1.42, ±0.20); upper arm r 0.065, forearm 0.056→0.045 to the weapon's grips, elbow pushed down / out; gloves r 0.045 | uniform camo, DARK gloves | rods, spheres |
| Shoulder patch (flag position) | 0.08 × 0.055 on each upper sleeve | faction accent | box |
| Head, neck | head r 0.10 at (0.03, 1.60); neck r 0.055 | SKIN | sphere, rod |
| wz. 2005 helmet | lathe r 0.155 at the crown base, flaring to r 0.172 at the rim 5.5 cm below; crown 0.175 above the base at y 1.635; tilted 0.16 rad back so the front edge clears the eyes and the skirt covers ears and neck | uniform camo (Pantera cover) | `ModelParts.lathe_mesh` (16 segments) |
| MSBS Grot C | 0.93 m: polymer stock 0.24, receiver 0.30, **long top rail 0.54**, handguard 0.26, red dot, curved magazine, pistol grip, barrel + muzzle device; butt in the right shoulder at (0.12, 1.34, 0.11), muzzle 0.45 rad down (low ready; kneeler 0.25) | GUN | boxes, rods |
| UKM-2000 | 1.2 m at the hip, butt at (−0.12, 1.10, 0.22), 0.05 rad up: stock, receiver, feed cover, long barrel with gas tube and flash hider, carrying handle, folded bipod, olive 7.62 mm ammunition box on the left | GUN, vest (ammo box) | boxes, rods |
| RPG-7 | tube 1.0 m (r 0.02, heat shield r 0.033, venturi flare r 0.046) on the right shoulder at (0.02, 1.49 − kneel drop, 0.16); **PG-7 warhead** r 0.0425 with the conical nose, 0.37 m; two pistol grips, sight | GUN tube, vest (olive) warhead | two `lathe_mesh`es, boxes |

Each soldier variant (kit × kneeling) is one merged mesh per material (uniform, vest, skin, dark,
gun, accent: 5–6 mesh instances), cached by `pl_mech_infantry:<kit>:<kneel>:<material>`; the
body outside the `Soldier*` pivots has no meshes.

## Silhouette features

1. **PASGT-like wz. 2005 helmet** – the lathed helmet with a flared rim, tilted back (short brim
   at the front, skirt over the ears), in the uniform camo like the Pantera cover.
2. **Bulky plate carrier with front pouches** – vest box wider and deeper than the torso, with the
   pouch row standing out at the front.
3. **Grot C** – conventional layout with the full-length top rail, red dot and polymer stock.
4. **RPG-7** – kneeling gunner (Soldier1) aiming it with the bulbous conical warhead forward and
   the venturi flare behind.
5. **Pantera camouflage** – the faction uniform camo shader on uniform and helmet.

Details: UKM-2000 on Soldier2, assault packs on everyone. Skipped per the catalog: radios and
antennas, insignia (the accent patch stands in for the flag patch as the faction marker), small
pouches, NVG mounts; also face, fingers and knee pads.

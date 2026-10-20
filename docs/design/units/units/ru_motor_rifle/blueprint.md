# Russian motor rifle squad (Ratnik kit) – model blueprint

Model: `src/presentation/models/ru_motor_rifle.gd` (squad kind: `Soldier0..4`, each with a
`Rig`; kneelers have `Kneel` + hidden `Stand`, see `UnitModels.pose_infantry`). The skeleton
(squad pivots, legs, hips, torso, head, arms with the accent sleeve patch, RPG-7, helpers) is the
shared `src/presentation/models/parts/soldier.gd`, also used by `pl_mech_infantry`; this file adds
the Ratnik kit through the `dress` hook. References: `side_1.jpg` (kneeling RPK-74 gunner – helmet
shape, 6B45 front, AK profile with the curved magazine, bipod), `front_1.jpg` (AK-74M at the
shoulder, 6B45 with front pouches and groin flap), `three_quarter_1.jpg` (6B47 helmet, collar).

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

Layout (model units) `[x, z, kneeling, kit]`, yaw ±0.3 rad from `TerrainNoise.hash`:

| Soldier | Position | Pose | Kit |
|---|---|---|---|
| 0 leader | (0.13, 0.0) | standing | AK-74M + GP-30 |
| 1 RPG gunner | (-0.03, 0.16) | standing, aiming | RPG-7V on the right shoulder |
| 2 machine gunner | (-0.03, -0.15) | kneeling (as in `side_1.jpg`) | RPK-74M, bipod down |
| 3 assistant grenadier | (-0.19, 0.06) | standing | AK-74M + rocket carrier with 3 PG-7 rounds |
| 4 rifleman | (-0.16, -0.13) | kneeling | AK-74M + GP-30 |

Kneelers differ from the Polish squad (gunner + rifleman instead of RPG + rifleman), so the
two squads also differ in their group silhouette.

## Parts of one soldier (metres)

Shared (`parts/soldier.gd`): legs (hip 0.92, knee 0.50, ankle 0.12; kneeling hip 0.55), boots
0.27 × 0.11 × 0.10, hips 0.24 × 0.18 × 0.34, torso 0.22 × 0.42 × 0.38, shoulder balls r 0.075,
neck, head r 0.10 at y 1.60, arms to the weapon's grips, gloves, accent sleeve patch.

| Part | Size / position | Material | Built with |
|---|---|---|---|
| 6B47 helmet | lathe, crown base at y 1.63: r 0.168 at the base, full cut curving in through r 0.158 at −0.07 to r 0.145 at the rim (−0.075), no flared brim, dome 0.19 high; tilted 0.08 rad back – rounder and deeper than the wz. 2005 | uniform camo (EMR cover) | `Soldier.helmet` (lathe, 16 segments) |
| 6B45 armour | 0.36 × 0.40 × 0.42 at (0.02, 1.21), top at 1.41 just under the shoulders – 4 cm deeper and 2 cm wider than the Polish carrier | vest | box |
| High collar | tapered ring r 0.14 → 0.12 from y 1.37 to 1.53 around the neck (1 cm back), standing 12 cm above the armour | vest | rod (10 sides) |
| Front pouches (MOLLE) | three magazine pouches 0.08 × 0.15 × 0.10 at x 0.22, y 1.14, z −0.12 / 0 / 0.12 | vest | boxes |
| Cummerbund / belt | 0.32 × 0.08 × 0.42 at y 0.99 | vest | box |
| Groin protector | 0.05 × 0.16 × 0.20 at (0.15, 0.89) | vest | box |
| AK-74M | 0.94 m, butt in the right shoulder at `Soldier.RIFLE_BUTT` (0.12, 1.34, 0.11), muzzle 0.4 rad down (kneeler 0.2): stock prism with the AK drop, receiver 0.30, lower handguard, **gas tube over the barrel**, front-sight block, muzzle brake, **curved magazine** (prism banana outline), pistol grip | GUN | `prism_mesh`, boxes, rods |
| GP-30 | 40 mm tube r 0.024 × 0.26 under the handguard + trigger housing (leader, rifleman) | GUN | rod, box |
| RPK-74M | AK profile with a 0.2 m longer barrel (1.06 m), longer 45-round curved magazine, bipod hinged at the muzzle brake (1.15 m from the butt; legs splayed 0.3 m down when kneeling, folded back under the barrel standing); aimed 0.08 rad down (standing variant 0.35) | GUN | same builder with `rpk = true` |
| RPG-7V | shared `Soldier.rpg7`: tube 1.0 m with heat shield and venturi, **conical PG-7 warhead**, grips, sight; on the right shoulder (`Soldier.rpg7_shoulder`: (0.02, 1.49, 0.16), 0.04 rad up) of a standing gunner | GUN tube, vest (olive) warhead | two lathes, boxes |
| Rocket carrier | 0.16 × 0.34 × 0.30 at (−0.27, 1.22) on the assistant, three PG-7 warheads standing out of it (tops at y ~1.7) | uniform camo bag, vest (olive) warheads | box, `Soldier.pg7_profile` lathes |

Each soldier variant (kit × kneeling) is one merged mesh per material (uniform, vest, skin, dark,
gun, accent), cached by `ru_motor_rifle:<kit>:<kneel>:<material>`; no meshes outside the
`Soldier*` pivots.

## Silhouette features

1. **Rounded 6B47 helmet** – fuller, deeper lathe without the PASGT brim flare, in the uniform camo
   (EMR cover).
2. **Bulky 6B45 armour with MOLLE pouches and a high collar** – larger vest box, three pouches
   standing out at the front, the collar ring around the neck, groin flap below the belt.
3. **AK profile** – curved banana magazine, gas tube over the barrel, AK stock drop, muzzle brake;
   GP-30 tube under two rifles.
4. **RPG-7V with the conical warhead** – the standing gunner aiming it from the shoulder; the
   assistant's carrier shows three more warheads over his back.
5. **EMR camouflage** – the faction uniform camo shader on uniform, helmet and rocket bag.

Details: RPK-74M (the catalog photo's gun) on the kneeling gunner. Skipped per the catalog:
radios and antennas, patches / armbands (the shared accent sleeve patch is the faction marker),
small pouches; also goggles, knee / elbow pads, slings, face, fingers.

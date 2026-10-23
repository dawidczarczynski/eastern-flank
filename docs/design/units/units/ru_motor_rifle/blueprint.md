# Russian motor rifle squad (Ratnik kit) – model blueprint

Model: `src/presentation/models/ru_motor_rifle.gd` (squad kind: `Soldier0..4`, each with a
`Rig`; kneelers have `Kneel` + hidden `Stand`, see `UnitModels.pose_infantry`). The soldier
(squad pivots, smooth MeshKit body – swept legs, torso and arms, deltoids, head, gloves, boots,
knee pads, thigh pockets, the accent sleeve patch –, RPG-7, helmet and weapon helpers) is the
shared `src/presentation/models/parts/soldier.gd` (TASK-067), also used by `pl_mech_infantry`;
this file adds the Ratnik kit through the `dress(k: MeshKits, up, kit, kneel, carry)` hook. References: `side_1.jpg` (kneeling RPK-74 gunner – helmet
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

Shared body: see the Polish blueprint (`pl_mech_infantry/blueprint.md`) – legs hip 0.92, knee
0.50, ankle 0.12 (kneeling hip 0.55) as smooth sweeps, boots with soles on y = 0, torso sweep,
deltoids, head 0.19 × 0.23 × 0.16 at y 1.625, arms to the weapon's grips, gloves, sleeve patch.

| Part | Size / position | Material | Built with |
|---|---|---|---|
| 6B47 helmet | lathe (18 sides), crown base at y 1.63: r 0.168 at the base, full cut curving in through r 0.158 at −0.07 to r 0.145 at the rim (−0.075), no flared brim, dome 0.19 high; tilted 0.08 rad back; mounting band, chin strap | uniform camo (EMR cover), gear paint | `lathe`, `tube` |
| 6B45 armour | front section 0.10 × 0.38 × 0.36 at (0.12, 1.24), back 0.09 × 0.40 × 0.36 at (−0.125, 1.26) – thicker and wider than the Polish carrier; cummerbund sweep r 0.205 × 0.145 (y 1.03–1.17); padded shoulder straps r 0.028 | vest | `pillow`, `sweep`, `tube` |
| High collar | lathe ring r 0.088 inside / 0.135 outside, 0.13 high from y 1.39, tilted back 0.15 rad (higher at the back) | vest | `lathe` |
| Groin flap | 0.05 × 0.17 × 0.20 at (0.15, 0.89) | vest | `pillow` |
| MOLLE pouches | three magazine pouches 0.07 × 0.15 × 0.09 with flaps at x 0.2, y 1.13, z −0.11 / 0 / 0.11; side pouch on the right | vest | `cbox`, `pillow` |
| Belt | sweep r 0.178 × 0.122 at y 0.95–0.99 | gear paint | `sweep` |
| AK-74M | 0.95 m, butt in the right shoulder at `Soldier.RIFLE_BUTT` (0.12, 1.34, 0.11), muzzle 0.4 rad down (kneeler 0.2): stock plate with the AK drop (3.5 cm thick), receiver 0.30, lower handguard, **gas tube** rod over the barrel, front-sight block, round barrel with muzzle brake, **curved magazine** (banana outline plate), pistol grip, sling | GUN, gear paint (sling) | `plate`, `cbox`, `rod`, `lathe`, `tube` |
| GP-30 | 40 mm tube r 0.024 × 0.26 under the handguard + trigger housing (leader, rifleman) | GUN | `rod`, `cbox` |
| RPK-74M | AK profile with a 0.2 m longer barrel, longer 45-round curved magazine, bipod hinged at the muzzle (legs splayed 0.3 m down when kneeling, folded back standing); aimed 0.08 rad down (standing variant 0.35) | GUN | same builder with `rpk = true`, `tube` legs |
| RPG-7V | shared `Soldier.rpg7`: tube with heat shield and venturi, **conical PG-7 warhead**, grips, sight; on the right shoulder of a standing gunner | GUN tube, vest (olive) warhead | `lathe`, `cbox` |
| Rocket carrier | bag 0.16 × 0.34 × 0.30 at (−0.27, 1.22) on the assistant with two shoulder straps, three PG-7 warheads standing out of it (tops at y ~1.7) | uniform camo bag, vest (olive) warheads, gear straps | `pillow`, `Soldier.pg7` lathes, `tube` |

Materials as in the Polish squad (uniform camo pattern scale 80, gear paint with mud on boots and
the kneeling knee). Each soldier variant (kit × carry × kneeling) is generated once
(`ModelParts.cached_meshes`, key `ru_motor_rifle:<kit>:<carry>:<kneel>`) and added as one mesh
instance per material; no meshes outside the `Soldier*` pivots. Squad: ~27 700 triangles (7
figures incl. the 2 hidden `Stand` variants).

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
small pouches; also goggles, elbow pads, face, fingers (knee pads and slings came with TASK-067).

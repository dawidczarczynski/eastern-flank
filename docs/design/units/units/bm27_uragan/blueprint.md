# 9K57 Uragan (9P140 on ZIL-135LM) – model blueprint

Model: `src/presentation/models/bm27_uragan.gd`. References: `side_1.jpg` (parade, travel order,
slight front three-quarter – proportions read with the wheel diameter as a ruler), `three_quarter_1..4`
(launcher elevated / travel from the front; `three_quarter_3/4` show the cab nose, headlights and
grilles), `drawing_1.jpg` (DIA painting, firing).

Since TASK-073 (v3) the truck is built with `MeshKit` / `MeshKits` (ADR 0012) like the v3 tanks:
chamfered plates and lathes with the weathering vertex masks, small parts (bolts, hinges, handles,
hydraulic lines), the shared `WheeledRunningGear` for the wheels. All geometry is faction independent
and cached once (`ModelParts.cached_meshes`, keys `bm27_uragan:*`); only the materials differ.

## Scale

Truck 9.4 m bumper to rear lights (catalogue hull 9.3 m; overall 9.63 m), 2.8 m wide, 3.225 m high.
Uniform `K = 0.093` model units per metre (1 unit = 10.75 m): 0.874 × 0.26 × 0.30 units before
`MODEL_SCALE` (1.141 × 0.348 × 0.389 after, length budget 1.15). The render's `Real` line shows
about −7 % per axis because of this scale.

All parts use `vehicle_frame.gd` (`Frame`, origin at x = 4.7 m; `vehicle_frame()`): `x` from the
front bumper, `h` above ground, `z` across.

## Materials

`materials(faction)` = `Frame.kit_tank_materials` with the faction **truck** camo as `&"body"`:
`body` (truck camo), `dark` (weathered dark paint), `steel`, `glass`, `lens`, `rubber` (tyres),
`accent` (faction colour).

## Parts (metres; model units = × 0.093)

| Part | x | h | half width / z | Material | Built with |
|---|---|---|---|---|---|
| Wheels ×8 (`Wheel0..7`) | axles 2.30, 4.715, 6.225, 8.64 (ZIL-135: 2.415 + 1.51 + 2.415) | r 0.67 | tyre 0.42, z ±1.10 | rubber tyre (16 directional lugs), camo dished disc with 10 bolts, dark central tyre-inflation hub with air line | `WheeledRunningGear` (`running_gear()`: 18 sides, `inflation_hub`), one mesh set per side shared by its 4 wheels |
| Cab (side profile prism, chamfer 0.06) | 0.16–2.70 | 1.10–2.60, windscreen raked back from 2.04 | 1.22 | camo | `MeshKit.profile` + roof slab 2.58–2.68 (chamfer 0.05) |
| Windscreen | 0.48–0.62 | 2.06–2.60 | 3 panes z −0.78 / 0 / 0.78 | glass panes, camo frame posts and bars (raked 0.236 rad), dark wipers | `cbox` rotated about z |
| Doors | 1.60–2.63 | 1.20–2.56 | z ±1.22 | dark seams, glass window 1.75–2.5 × 2.05–2.52 in a camo frame, steel hinges and handle, faction plate 1.8–2.45 × 1.5–1.85 | slabs, rods, tubes |
| Mirrors, grab handles, roof lamps, antenna | 1.28 / 2.66 / 0.68 / 2.45 | 2.4 / 1.5–2.3 / 2.71 / 2.72–3.1 | ±1.39 / ±1.27 / ±1.05 / +0.95 | dark / steel / camo + lens | tubes, cbox, rods |
| Nose | 0.10–0.50 | bonnet bulge 1.45–2.02 | 0.44 | camo, dark grille with 5 camo slats | chamfered slab (0.09) |
| Headlights, indicators | 0.14 | 1.60 | z ±0.95 / ±1.19 | camo housings r 0.15, dark bezel, lens, steel wire guards | rods, tubes |
| Front bumper | 0.0–0.4 | 0.85–1.28 | 1.30 | camo (chamfer 0.06), steel towing cable on top with eyes, dark brackets + steel tow hooks underneath, faction plate on the face | slab, tubes, arcs |
| Engine compartment (twin engines) | 2.70–4.55 | 1.20–2.16, roof 2.22 | 1.18 | camo; per side two tall grilles (dark recessed panel, camo frame, 9 slanted slats) and a louvre | slabs, cbox |
| Fuel tanks | 3.25–3.95 | centre 0.98, r 0.22 | z ±0.88 | camo drums, dark straps, steel filler caps | lathes, arcs |
| Exhaust outlet | 3.15 | 1.0 | z −1.2 | dark pipe and outlet (open), camo heat shield | tube, rod |
| Rear deck, turntable base | 4.55–9.30 / 4.4–9.2 | 1.30–1.55 / 1.55–1.60 | 1.16 / 0.7 | camo / dark; rub rails and tie-down eyes along the deck edges | slabs |
| Arched fenders (3 arches: axle 1, axles 2+3, axle 4) | 1.5–3.1 / 3.9–7.04 / 7.84–9.35 | top 1.5, ends r 0.55 | z ±1.12, hw 0.26 (front arch from \|z\| 1.0) + valance lip at \|z\| 1.38 | camo | smooth swept `plate` bands (6 steps per quarter) |
| Frame rails, cross members, axle housings, differentials, cab underside | 0.4–9.2 | 0.67–1.2 | rails z ±0.45 | dark | simplest shapes (mostly hidden) |
| Steps behind the front arch, lockers between axles 3 and 4 | 2.75–3.15 / 7.1–7.8 | 0.85–1.1 / 0.85–1.45 | ±1.1 / ±1.0 | dark / camo lockers with dark seams, steel hinges, dark latches | slabs, rods |
| Rear bumper, tail lights, pintle, mudflaps | 9.1–9.43 | 0.7–1.3 | – | camo, lens + steel guards, steel pintle under the bumper, dark mudflaps | slabs, tubes |
| **Stabiliser jacks ×2** (`Stabiliser0/1`) | 8.95, rear of the frame, z ±0.62 | leg 0.45–1.25 + chamfered round foot pad r 0.16 at 0.35–0.45 (stowed), collar; fixed in the hull: dark bracket 0.85–1.15, round sleeve 0.6–1.3 with a top collar, steel hydraulic line | leg r 0.06 | steel (pivot), dark (hull) | rod slides down 0.35 m: `deployed` = pivot translated −0.35 m, pad on y = 0 (unchanged from TASK-045) |
| **Blast shields ×5** (`BlastShield0..2` windscreen panes z −0.78 / 0 / 0.78, `BlastShield3/4` door windows z ∓1.245) | hinge at pane bottom (0.489, 2.106) / door window top (2.125, 2.54) | plates 0.5 × 0.74 and 0.8 × 0.52, 0.05 thick, chamfered, with stiffener ribs, 3 hinge knuckles and a handle | – | camo | built = open (windscreen plates lie on the nose ledge; door plates stand out as awnings), `deployed` = closed: windscreen plates rotated 90° + 0.23 rad rake about the hinge onto the glass, door plates hanging over the window (unchanged from TASK-045) |
| **Launcher** (`Launcher`): turntable ring r 0.95 with 20 bolts, upper carriage (side profile with sloped front, bolted cover plates), side girders, trunnion brackets with bolts and bosses, hydraulic lines | centre 6.0 | 1.55–2.55 | 0.85 | camo / dark | `MeshKits` on `Launcher` |
| **Pod** (`Launcher/Pod`): 16 tubes r 0.13 (6 + 6 + 4) | 2.80–8.42 | rows 2.50 / 2.76 / 3.02; columns ±0.135, ±0.405, ±0.675 (top row the inner four) | – | camo; open muzzles: rim r 0.142, dark bore r 0.112 for 0.3 m, then closed | lathes: 0.5 m muzzle section (16 sides, inside the muzzle frame) + plain rest of the tube (14 sides; the 4 inner middle-row tubes 8 sides) |
| Muzzle frame (stepped box) | 2.88–3.38 | 2.28–3.22 | 0.88 low, 0.61 top | camo, bolts on the side plates, dark lifting eyes | slabs |
| Clamp bands with tension lugs | 5.6, 8.0 | – | 0.83 / 0.56 | camo + bolts | slabs |
| Cradle beams, cross beam, trunnion axle, hydraulic lines along the cradle | 3.3–8.25 | 2.18–2.34 | beams z ±0.5 | dark | slabs, rod, tubes |
| Faction band on the muzzle-frame sides | 2.95–3.3 | 2.45–2.8 | z ±0.88 | accent | slabs |
| Elevation actuators ×2 | base 6.3/1.75 on the turntable, mount 5.85/2.25 under the pod | – | z ±0.5, cylinder 1.45 (dark, gland ring, base clevis, port and line) + piston 1.35 (steel, end eye) | dark / steel | `Actuator<i>`, `ActuatorRod<i>`, `ActuatorMount<i>`; span 0.67 stowed, 2.6 at 55°: 0.2 overlap |

Pivots: `Launcher` at the turntable centre (6.0, 1.55); `Pod` hinge on the trunnions near the
bundle's rear end (8.3, 2.33), no rotation – its +X runs forward along the tubes, so elevation raises
the muzzles. `Mouth0..15` 0.1 m in front of the muzzles (pod-local x equal for all 16). The tubes
are stowed facing forward: the `launcher` mechanism declares `stowed: front`, with a traverse of
±30° and 55° maximum elevation (UnitModels.launcher_aim / launcher_elevation). Everything that
elevates is under `Pod`, everything that only traverses under `Launcher`; the hull holds only the
fixed turntable base.

Anchors (`Marker3D` under `Model`, TASK-064): `Exhaust` at the outlet under the left engine side
(3.15, 0.95, −1.28), `Dust_L` / `Dust_R` behind the rear tyres (9.11, 0.02, ∓1.1).

## Hidden geometry and clearance (TASK-073)

- `HULL_INTERIOR = [AABB((0.75, 1.35, −0.95), (1.8, 0.85, 1.9))]` – inside the cab; no triangle lies
  in it. The front fender, which runs into the cab, stops at |z| = 1.0 for this.
- Cut: plain inner wheel halves (≈ 15 % of a wheel's triangles face inwards), lugs only on the outer
  shoulder and crown, frame / axles as plain boxes and 8-sided rods, nothing inside the cab or the
  engine compartment, the four tubes hidden in the middle of the bundle as 8-sided shells (their
  muzzles are detailed like the others).
- `LAUNCHER_CLEARANCE_H = 2.24` m: the lowest `Pod` vertex outside the turntable ring at 55° is the
  trunnion axle (2.241 m at every traverse); the highest hull vertex inside the pod's swept circle
  (reach 3.06 m from the turntable centre) is the engine roof hatch seam at 2.221 m. To get there the
  sweep check exposed that the bundle's rear end (and the cradle beams) swung down to 2.03 m at full
  elevation, below the 2.22 m engine roof: the tubes now end at **x 8.42** (was 8.7, 0.12 m behind the
  trunnions), the cradle beams just in front of the trunnions, and the old engine-roof handles were
  dropped. The side silhouette (bundle over axles 2–4, trunnions over axle 4) is unchanged.

## Numbers (before → after TASK-073, both factions identical)

| | before (v2, merged primitives) | after (v3, MeshKit) |
|---|---|---|
| Triangles (russia / poland) | 9 096 / 9 096 | 36 516 / 36 516 |
| Mesh instances (all / body outside `Wheel*`) | 53 / 21 | 46 / 22 |
| Wheels | 4 instances each, `ModelParts.wheel` | 3 instances each (body, rubber, dark), shared per side, 1 836 triangles |
| Cold build (contract test) | 25 ms | 94 ms |
| Contract size (model units after scale) | 0.966 × 0.361 × 0.329 | 0.967 × 0.361 × 0.329 |
| `Stats` AABB (m) | 8.8 × 3.3 × 3.0 | 8.8 × 3.3 × 3.0 |
| `Real` diff | −8.8 % / +17.2 % / −7.1 % | −8.7 % / +17.2 % / −7.1 % |

Triangle split (after): wheels 14 688, hull 11 308, launcher 1 504, pod 5 752 (tubes ≈ 4 600),
actuators 984, jacks 640, shields 1 712.

## Silhouette features

1. **Long ZIL-135 8×8 with the launcher over the rear half** – four big wheels in two widely spaced
   pairs at the ends with the close middle pair (2.415 / 1.51 / 2.415 m), three arched fenders, the
   engine block right behind the cab, turntable and carriage over axles 2–4.
2. **16 tubes in three banks** – individual lathed tubes (two rows of six, top row of four) with open
   dark muzzles in a stepped, bolted muzzle frame, two clamp bands; top at 3.22 m.
3. **Travel order** – all references (side_1, three_quarter_3/4 and the elevated three_quarter_1)
   show the bundle pointing **forward**, muzzles just behind/above the cab, trunnions over axle 4.
   The catalogue's "traversed to point rearward over the tail, muzzles under a sheet-metal cover"
   does not match the photos; the model follows the photos. No cover modelled (the parade photos
   show red caps / open muzzles).
4. **Forward cab with blast shields** – five hinged `BlastShield` plates, one per window (three
   windscreen panes, two door windows): open in travel, closed over the glass when deployed
   (`--pose=fire`). Jacks and shields share the deploy step (`UnitModels.pose_deployables`).

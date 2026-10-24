# 9K57 Uragan (9P140 on ZIL-135LM) – model blueprint

Model: `src/presentation/models/bm27_uragan.gd`. References: `side_1.jpg` (parade, travel order,
slight front three-quarter – proportions read with the wheel diameter as a ruler), `three_quarter_1..4`
(launcher elevated / travel from the front), `drawing_1.jpg` (DIA painting, firing).

## Scale

Truck 9.4 m bumper to rear lights (catalogue hull 9.3 m; overall 9.63 m), 2.8 m wide, 3.225 m high.
Uniform `K = 0.093` model units per metre (1 unit = 10.75 m): 0.874 × 0.26 × 0.30 units before
`MODEL_SCALE` (1.141 × 0.348 × 0.389 after, length budget 1.15). The render's `Real` line shows
about −7 % per axis because of this scale.

All parts use `vehicle_frame.gd` (`Frame`, origin at x = 4.7 m): `x` from the front bumper, `h` above
ground, `z` across.

## Parts (metres; model units = × 0.093)

| Part | x | h | half width / z | Material | Built with |
|---|---|---|---|---|---|
| Wheels ×8 (`Wheel0..7`) | axles 2.30, 4.715, 6.225, 8.64 (ZIL-135: 2.415 + 1.51 + 2.415) | r 0.67 | tyre 0.42, z ±1.10 | rubber, camo hub | `ModelParts.wheel` |
| Cab (side profile prism) | 0.16–2.70 | 1.10–2.62, windscreen raked back from 2.04 | 1.22 | truck camo | `Frame.profile` |
| Folded blast shield on the nose ledge | 0.05–0.62 | 1.99–2.05 | 1.18 | truck camo | slab |
| Front bumper | 0.0–0.4 | 0.85–1.28 | 1.30 | truck camo | slab |
| Engine compartment (twin engines) | 2.70–4.55 | 1.20–2.22 | 1.18 | truck camo, dark grilles both sides | slabs |
| Rear deck | 4.55–9.30 | 1.30–1.55 | 1.16 | truck camo | slab |
| Arched fenders (3 arches: axle 1, axles 2+3, axle 4) | 1.5–3.1 / 3.9–7.04 / 7.84–9.35 | top 1.5, r 0.55 | z ±1.12, hw 0.26 | truck camo | `_arch` tilted strips |
| Frame rails, cab underside, mudflaps, mirrors | – | – | – | dark | merged |
| Windscreen (3 panes), door windows | 0.5 / 1.75–2.5 | 2.05–2.55 | – | glass | merged |
| Headlights, rear lights | nose / rear | – | – | steel | merged |
| Accent plates: cab doors both sides, bumper; muzzle-frame sides both sides | – | – | – | faction accent | merged |
| **Launcher** turntable (dark ring r 0.95) + upper carriage, side girders, trunnion brackets | centre 6.0 | 1.55–2.55 | 0.85 | camo / dark | `Launcher` node |
| **Pod**: 16 tubes r 0.13 (6 + 6 + 4) | 2.80–8.70 | rows 2.50 / 2.76 / 3.02; columns ±0.135, ±0.405, ±0.675 (top row the inner four) | – | truck camo | `Frame.drum` ×16 |
| Muzzle frame (stepped box) | 2.88–3.38 | 2.28–3.22 | 0.88 low, 0.61 top | truck camo | slabs |
| Clamp bands | 5.6, 8.0 | – | – | truck camo | slabs |
| Muzzle openings, cradle beams, trunnion axle | – | – | – | dark | merged |
| Elevation actuators ×2 | base 6.3/1.75 on the turntable, mount 5.85/2.25 under the pod | – | z ±0.5, cylinder 1.45 + piston 1.35 (span 0.67 stowed, 2.6 at 55°: still 0.2 overlap; stowed surplus hidden in the tube bundle / carriage) | dark / steel | `Actuator<i>`, `ActuatorRod<i>`, `ActuatorMount<i>` |

Pivots: `Launcher` at the turntable centre (6.0, 1.55); `Pod` hinge on the trunnions at the bundle's
rear end (8.3, 2.33), no rotation – its +X runs forward along the tubes, so elevation raises the
muzzles. `Mouth0..15` 0.1 m in front of the muzzles (pod-local x ≈ 0.6). The tubes are stowed
facing forward: the `launcher` mechanism declares `stowed: front` (Homar-K's default is `rear`),
with a traverse of ±30° and 55° maximum elevation (UnitModels.launcher_aim / launcher_elevation).

Mesh instances: 14 body (5 hull materials, 2 turntable, 3 pod, 4 actuator parts) + 4 per wheel;
7 296 triangles.

## Silhouette features

1. **Long ZIL-135 8×8 with the launcher over the rear half** – four big wheels in two widely spaced
   pairs at the ends with the close middle pair (2.415 / 1.51 / 2.415 m), three arched fenders, the
   engine block right behind the cab, turntable and carriage over axles 2–4.
2. **16 tubes in three banks** – individual cylinders (two rows of six, top row of four) in a stepped
   muzzle frame, two clamp bands, dark muzzle openings; top at 3.22 m.
3. **Travel order** – all references (side_1, three_quarter_3/4 and the elevated three_quarter_1)
   show the bundle pointing **forward**, muzzles just behind/above the cab, trunnions over axle 4.
   The catalogue's "traversed to point rearward over the tail, muzzles under a sheet-metal cover"
   does not match the photos; the model follows the photos. No cover modelled (the parade photos
   show red caps / open muzzles).
4. **Forward cab with blast shield** – modelled folded on the nose ledge under the windscreen
   (travel); raising it for firing would need an extra pivot (not in the contract).

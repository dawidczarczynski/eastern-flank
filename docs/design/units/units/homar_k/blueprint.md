# Homar-K (K239PL) – model blueprint

Model: `src/presentation/models/homar_k.gd`. Reference: `side_1.png` (clean side view, measured at
~61 px/m: 670 px = 11 m bumper to rear).

## Scale

Real 11 × 2.8 × 3.3 m. At the nominal 1 unit = 10 m the length would be 1.1 × `MODEL_SCALE` 1.3 =
1.43, over the 1.15 footprint budget, so the whole truck is scaled **uniformly** by
`K = 0.078` model units per metre (1 unit = 12.8 m): 0.858 × 0.218 × 0.262 units before
`MODEL_SCALE` (1.115 × 0.284 × 0.341 after). Proportions stay true; the render's `Real` line shows
about −20 % on every axis because of this.

All parts are written in photo metres (`x` from the front bumper, `h` above ground, `z` across) and
converted by `_p()` / `_slab()`.

## Parts (metres; model units = × 0.078)

| Part | x (from front) | h | half width | Material | Built with |
|---|---|---|---|---|---|
| Wheels ×8 (`Wheel0..7`) | axles 1.85, 3.69, 7.95, 9.46 | r 0.70 | tyre 0.45 wide, centre z ±1.17 | rubber, camo hub, dark cap | `ModelParts.wheel` (new, shared) |
| Cab (armoured, cab-over) | 0.10–3.15 | 1.45–3.12 (+roof cap to 3.25) | 1.27 | truck camo | merged `homar_k:body` |
| Cab underside between wheels | 0.30–3.10 | 1.00–1.45 | 0.86 | truck camo | merged |
| Equipment block + air-filter drums | 3.15–4.40 | 1.50–2.85 | 0.98 (drums r 0.27 at z ±1.06) | truck camo | merged |
| Exhaust stack | 4.47 | 1.6–3.3 | r 0.08, z +0.9 | dark | merged `homar_k:dark` |
| Middle module | 4.60–6.50 | 1.30–2.85 | 1.20 | truck camo | merged |
| Lockers | 4.85–7.00 | 0.85–1.30 | 1.05 | truck camo | merged |
| Rear deck (over rear axles) | 7.00–10.60 | 1.45–1.66 | 1.38 | truck camo | merged |
| Frame rails | 0.40–10.80 | 1.00–1.50 | 0.50 | dark | merged |
| Bumpers, grille, steps, mirrors, door seams, louvres, mudflaps, stabiliser housings | – | – | – | dark | merged |
| Stabiliser jacks `Stabiliser0/1` (rear, z ±1.1 m, x 10.51 m): steel leg + dark foot disc, slide down 0.45 m (`deployed` meta) out of the fixed housing | 0.07 m leg r, 0.2 m foot r | pivots at the rear corners | – | steel, dark | pivot children |
| Launcher base / turntable | 6.80–10.40 | 1.66–2.00 | 1.05 | dark | merged |
| Windows (2 per side + 2 windscreen panes) | 0.5–1.26, 1.97–2.7 / front | 2.35–2.95 | – | glass | merged `homar_k:glass` |
| Accent plates (doors both sides + cab front) | 0.55–1.20 | 1.72–2.05 | – | faction accent | merged `homar_k:accent` |
| **Pod** launcher box (2 pods under one cover) | 6.52–10.95 | 2.00–3.36 | 1.40 | truck camo | `Pod` node, merged `homar_k:pod` |
| Tilted front face | 6.25–6.55, top leaning 0.2 rad forward | 2.05–3.22 | 1.36 | truck camo | in `homar_k:pod` |
| Rear face, centre seam, bottom rail | – | – | – | dark | `homar_k:pod_trim` |
| Accent band on the pod sides | 9.55–9.85 | 2.1–3.34 | – | faction accent | `homar_k:pod_band` |
| Tube caps 12 × r 0.17 | rear face | rows 2.38 / 2.96, columns ±0.42 around pod centres z ±0.7 | – | steel | `homar_k:pod_caps` |

`Launcher` pivot: turntable centre (x 8.6, h 2.0); it traverses about its Y before a volley.
`Pod` pivot (child of `Launcher`): on the front-bottom edge of the launcher box (x 6.52, h 2.0),
turned 180° about Y so its +X runs to the rear (stowed tube ends face the rear). `Mouth0..11` sit
0.1 m behind the tube caps (pod-local x ≈ 0.36 > 0.2). Before a volley the pod rises about its
local Z (to its `max_elevation_deg` 40°, `UnitModels.launcher_elevation`) on two hydraulic actuators (|z| 0.85: dark cylinder
`Actuator<i>` from the turntable anchor x 7.25 / h 1.92, steel piston `ActuatorRod<i>` from
`ActuatorMount<i>` under the pod at x 8.9 / h 2.0, each 1.1 m, r 0.13 / 0.07), then the turntable
turns the tube ends towards the target; after the salvo both return.

Each material is one merged mesh (`ModelParts.merged_mesh`), so the body has 8 mesh instances
(budget 24); wheels add 4 each under their pivots.

## Silhouette features

1. **Long, low deck with two box pods behind the cab** – one flat-topped launcher box over the rear
   two axles, top at 3.36 m (just above the cab roof 3.25 m), rear overhang past axle 4; a dark
   centre seam on the top marks the two pods.
2. **Pods retracted under a flat cover** – plain box, no rails; only the tilted front face, the dark
   base below and the tube caps on the rear face.
3. **Armoured three-seat cab-over cab** – tall flat-fronted box over axles 1–2, small windows, two
   windscreen panes, steps under the doors and in front of axle 1, mirrors.
4. **8×8, wheels grouped 2 + 2 with a gap** – axles at 1.85 / 3.69 and 7.95 / 9.46 m; the gap holds
   the equipment block with drums, the exhaust stack, the middle module and lockers.

# Homar-K (K239PL) – model blueprint

Model: `src/presentation/models/homar_k.gd` (v3, TASK-073: MeshKit, shared wheeled running gear).
Reference: `side_1.png` (clean side view, measured at ~61 px/m: 670 px = 11 m bumper to rear).

## Scale

Real 11 × 2.8 × 3.3 m. At the nominal 1 unit = 10 m the length would be 1.1 × `MODEL_SCALE` 1.3 =
1.43, over the 1.15 footprint budget, so the whole truck is scaled **uniformly** by
`K = 0.078` model units per metre (1 unit = 12.8 m): 0.858 × 0.218 × 0.262 units before
`MODEL_SCALE`. Proportions stay true; the render's `Real` line shows about −20 % on every axis
because of this.

All parts are written in photo metres (`x` from the front bumper, `h` above ground, `z` across)
through `vehicle_frame()` = `Frame.new(K, LENGTH_M / 2)` and `MeshKit` (chamfered boxes, side
profiles, lathes, tubes, bolts; vertex masks for the paint shader, ADR 0012).

## Before / after (TASK-073)

| | Before (merged slabs) | After (MeshKit v3) |
|---|---|---|
| Triangles (poland / russia) | 6 328 / 6 328 | 30 972 / 30 972 |
| Mesh instances (all / body, budget 24) | 48 / 16 | 45 / 21 |
| Cold build (contract test) | 14.8 ms | ~77 ms (warm-cache build ~1.3 ms) |
| Contract size (x × y × z, after scale) | 0.947 × 0.251 × 0.291 | 0.956 × 0.250 × 0.293 |
| Model-space AABB (units) | 0.8611 × 0.2644 × 0.2278 | within 1 % on every axis |
| `Stats` AABB | 8.6 × 2.3 × 2.6 m | 8.7 × 2.3 × 2.7 m |
| `Real` diff (l / w / h) | −21.7 % / −18.7 % / −19.9 % | −21.0 % / −18.9 % / −19.3 % |

Where the triangles go: wheels 14 688 (1 836 each: 18-sided carcass, 2 × 16 chamfered lugs,
dished disc with 10 bolts, inflation hub), hull 11 476 (cab frames, hinges, handles, steps,
grilles, drums, bolts), launcher 4 388 (of which the pod 2 784: 12 rimmed tube caps, rivets,
seams), jacks 420.

## Parts (metres; model units = × 0.078)

| Part | x (from front) | h | half width / z | Material | Built with |
|---|---|---|---|---|---|
| Wheels ×8 (`Wheel0..7`) | axles 1.85, 3.69, 7.95, 9.46 | r 0.70 | tyre 0.45 wide, centre z ±1.17 | rubber, camo disc, dark inflation hub | `WheeledRunningGear` (key `homar_k`, 18 sides, 16 lugs, 10 bolts, `inflation_hub`) – one mesh set per side, shared by the 4 pivots and both factions |
| Mudflaps | behind axle 4 at 10.3 | 0.42–1.46 | z ±1.17 | rubber + dark bracket | `Gear.add_hull_parts` into the hull kits |
| Cab (armoured, cab-over) | 0.10–3.15 | 1.45–3.25 | 1.27 | camo | one chamfered side profile (raked windscreen, rounded roof edges) |
| Cab front | windscreen 2 panes in thick frames, wipers, grille slats, faction plate, bumper profile with headlights in wire guards, tow hooks, number plate, bolt row | 0.95–2.97 | – | camo, glass, dark, steel, lens, accent | kit parts |
| Cab sides | 2 doors per side (seams, 2 hinges, handle), windows flush in thick frames, accent plate on the front door, grab handles, armour seam, door step, mirror on a tube arm | – | ±1.27 | camo, dark, steel, glass, accent | kit parts |
| Cab roof | hatch with hinge, plate seam, two antenna bases with stubs | 3.25–3.37 | – | camo, dark, steel | kit parts |
| Steps | in front of axle 1 (0.22–0.84) and between axles 1–2 (2.62–2.96): tread plates with ribs on brackets | 0.8–1.4 | z ±1.18 | dark | `_step` |
| Equipment block | 3.15–4.40 | 1.50–2.90 | 0.98 | camo | chamfered slab |
| Air-filter drums | x 3.5, h 2.45, z ±1.06 | r 0.27 | ribbed lathe, end nut, clamp band and foot | camo, dark, steel | lathe + tube |
| Engine grilles | 3.7–4.3 | 1.75–2.35 | sides ±0.98 | dark (cavity) + slanted slats, camo frame | kit parts |
| Exhaust stack + heat shield | 4.47 | 1.6–3.3 (+ rain cap) | z +0.9 | dark pipe, camo shield, steel clamps, dark brackets | rod, lathe |
| **Middle module** | 4.60–6.02 (flat top 4.70–5.42, rear slope 5.42 @ 2.85 → 6.02 @ 1.95) | 1.30–2.85 | 1.20 | camo; louvres, access panel seams, hinges, latches | chamfered side profile |
| Lockers under the module | 4.85–7.00 | 0.85–1.30 | 1.05 | camo, door seams, steel hinges and latch handles | kit parts |
| Frame rails | 0.40–10.80 | 1.00–1.50 | 0.50 | dark | one box (hidden geometry rule) |
| Axle housings, suspension blocks, cross members | per axle, 4.4, 7.3 | 0.6–1.45 | – | dark | 8-sided rods, slabs |
| Rear deck | 7.00–10.60 | 1.45–1.66 | 1.38 | camo, steel tie-down rings | slab, tubes |
| Turntable bearing ring (fixed) | centre 8.6, r 1.0 | 1.66–1.70 | – | dark, 20 bolts | lathe |
| Stabiliser housings | 10.38–10.64 | 0.90–1.55 + collar | z ±1.1 | dark, 2 hydraulic lines each | slab, rod, tubes |
| Rear bumper / light bar | 10.60–10.98 | 1.10–1.48 | 1.30 | dark; red + white lenses, steel towing pintle | slab, rods, tube |

### Launcher (`Launcher`, traverses only)

| Part | Where | Material |
|---|---|---|
| Turntable top plate | centre 8.6, r 0.88, h 1.70–1.82 | dark |
| Upper carriage: two side girders (z ±1.1), front and rear cross beams, floor plate | 6.70–10.50, h 1.70–2.00 | dark, bolts, a hydraulic line along each girder |
| Hinge brackets with pins (the pod's elevation axis) | x 6.42–6.70, z ±1.26, pin at (6.52, 2.0) | dark |
| `Actuator0/1` cylinders (from the anchor x 7.25, h 1.92, z ±0.85): r 0.13, 1.1 m, gland and collar rings, base eye, hydraulic line | – | dark |
| `ActuatorRod0/1` pistons (from `ActuatorMount<i>` at x 8.9, h 2.0): r 0.07, 1.1 m, end eye | – | steel |

Cylinder and piston reach (1.1 m each) are unchanged, so they overlap up to the 40° max elevation
(`test_launcher_pose.gd`). Both actuators share their meshes (built in the pivot's space).

### Pod (`Launcher/Pod`, elevates)

| Part | Where | Material |
|---|---|---|
| Launcher box (2 pods under one cover) | 6.52–10.95, h 2.00–3.36, ±1.40; front-top edge bevelled 0.16 m | camo, chamfered profile |
| Centre seam between the pods (top and rear face), 3 cover seams, 3 side seams per side | – | dark / camo |
| Cover rivets (10 per edge), 4 lifting eyes | top | camo bolts, steel |
| Bottom rails | 6.62–10.85, h 2.0–2.1, sides | dark |
| Accent band | 9.55–9.85, both sides | faction accent |
| Rear frames (one per pod) and 12 tube caps (r 0.17, rimmed lathes, rows h 2.38 / 2.96, columns ±0.42 around z ±0.7) | x 10.95–11.02 | dark, steel |
| Actuator clevises under the pod | x 8.9, z ±0.85 | dark |

`Pod` pivot: on the front-bottom edge of the box (x 6.52, h 2.0), turned 180° about Y so its +X
runs to the rear. `Mouth0..11` sit 0.15 m behind the rear face, 0.08 m beyond the caps, on each
tube's axis. Before a volley the pod rises about its local Z to `max_elevation_deg` 40°, then the
turntable traverses (full); after the salvo both return.

### Stabilisers (`Stabiliser0/1`)

At x 10.51, z ±1.1: a chamfered steel leg (r 0.07, collar at the bottom) with a dark round foot pad
(r 0.2, chamfered, flat underside at h 0.45 stowed) sliding out of the fixed housing; `deployed`
meta lowers the pivot by 0.45 m (feet on y = 0). Both jacks share their meshes. Motion and
positions as built by TASK-045.

## Hidden geometry cut

- Wheels: plain inner tyre half and inner disc (no lugs, bolts or hub detail inside).
- Frame rails one box, axle housings 8-sided, nothing under the cab floor but one slab.
- `HULL_INTERIOR` (no triangle fully inside; `test_mlrs_models.gd`):
  cab `AABB((0.5, 1.7, −0.95), (2.3, 1.3, 1.9))`, pod box `AABB((7.0, 2.2, −1.15), (3.4, 0.95, 2.3))`
  (at rest). The air tanks under the lockers of the first v3 draft were removed (only noise below
  the lockers in the side view).

## Launcher clearance (`LAUNCHER_CLEARANCE_H` = 2.0 m, `TURNTABLE_RING_R` = 1.0 m)

The sweep test exposed a real collision in the old layout: raising the pod about its front-bottom
hinge tips its front face forward, and the old middle module (x 4.6–6.5, top 2.85 m) and the old
forward-leaning pod front (top at x 6.25) went through each other at 40° – and the hinge edge
(2.08–2.51 m from the turntable axis at h 2.0) swept through the module's rear corners (2.4 m)
when traversing. Fixes, without changing the silhouette features:

- The pod's front face is vertical at x 6.52 with a 0.16 m bevel on its top edge (it leaned
  forward to 6.25 before).
- The middle module ends at x 6.02 below h 1.95 and its rear slopes back to x 5.42 at the top
  (2.85 m), so at any traverse angle the module stays outside the circle the raised pod sweeps at
  each height (the front face leans 40° forward when raised: at height h the pod reaches
  sqrt((2.08 + 0.84 (h − 2))² + 1.4²) m from the axis).
- The fixed launcher base under the pod is now only the low bearing ring (h ≤ 1.70) inside the
  ring; the carriage that fills the gap under the pod traverses with the `Launcher`.

The lowest raised-pod vertex outside the ring is the hinge edge at 2.0 m; every hull vertex the
raised pod passes over stays ≥ 0.01 m below the pod parts at its distance from the axis.

## Anchors

`Exhaust` (stack outlet x 4.47, h 3.32, z +0.9), `Dust_L` / `Dust_R` (x 10.09 – behind the
rear axle's tyres, h 0.02, z ∓1.17), `Marker3D` children of `Model` for `MotionFx`.

## Silhouette features

1. **Long, low deck with two box pods behind the cab** – one flat-topped launcher box over the rear
   two axles, top at 3.36 m (just above the cab roof 3.25 m), rear overhang past axle 4; a dark
   centre seam on the top marks the two pods.
2. **Pods retracted under a flat cover** – plain box with seams and rivets, no rails; the dark
   carriage below and the tube caps on the rear face.
3. **Armoured three-seat cab-over cab** – tall flat-fronted box over axles 1–2 with rounded edges,
   small windows in thick frames, two windscreen panes, steps under the doors and in front of
   axle 1, mirrors on arms.
4. **8×8, wheels grouped 2 + 2 with a gap** – axles at 1.85 / 3.69 and 7.95 / 9.46 m with lugged
   tyres; the gap holds the equipment block with drums, the exhaust stack, the middle module and
   lockers.

## Remaining differences

- The real pod front leans forward at the top; here it is vertical with a bevel (needed for the
  raised pod to clear the module, see above), and the module's rear slope leaves a wider notch
  between module and pod than in the photo.
- Small details from the photo not modelled: the ladder-like post behind the equipment block, the
  Topaz fire-control boxes, pod-side warning plates.

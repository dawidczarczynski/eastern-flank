# T-72B3 obr. 2011 – model blueprint

Model: `src/presentation/models/t72b3.gd`, built with `MeshKit` / `MeshKits` (TASK-069, ADR 0012:
chamfered primitives, RGB vertex masks for the weathering paint); shared running gear
`src/presentation/models/parts/tracked_running_gear.gd` (kit options `detailed_wheels`,
`track_shoe_pitch`, `detailed_skirts`, plus the T-72 options added in TASK-069 stage 2:
`skirt_bottom_profile`, `skirt_front_top_drop` / `skirt_front_top_run`, `track_pads`,
`wheel_rim_bolts`); metre -> model conversion `src/presentation/models/parts/vehicle_frame.gd`
(`vehicle_frame()` in the model). Materials: `Frame.kit_tank_materials` (faction camo `body`,
faction `accent` and `cloth`, weathered `dark` / `track`, PBR `steel` / `rubber` / `glass`, `lens`,
`red_lens`).

Reference: `drawing_1.jpg` (side, front and rear line drawing). Measured on the side view at
~162 px/m (road wheel spacing 0.82 m = 133 px; wheel 0.75 m = 120 px; ground at y 456). The drawing
shows a T-72B with Kontakt-1 bricks on the turret and skirts; for the obr. 2011 the catalog's
silhouette features win: Kontakt-5 wedges on the turret, plain rubber skirts. Positions and
proportions (wheels, turret, bins, gun, drums, skirt outline) come from the drawing.

## Scale

Real 9.53 m (gun forward) + 0.53 m of rear fuel drums = 10.06 m × 3.59 × 2.226 m. Scaled
**uniformly** by `K = 0.087` model units per metre (1 unit = 11.5 m, almost the Abrams' 0.088 so
the two tanks keep their real size ratio): 0.875 × 0.31 × 0.24 units before `MODEL_SCALE`
(contract test: 0.965 × 0.347 × 0.266 after). The render's `Real` line (at 10 m/unit) therefore
shows about −13 % on length and width; the true proportions are kept.

Origin: model x = 0 sits at x = (6.86 + 0.53 − 2.67) / 2 = 2.36 m from the hull front, so muzzle
to drums is centred. Parts are in vehicle metres (`x` from the glacis nose backwards, `h` above
the ground, `z` positive = right).

Deliberate deviations: roof add-ons (Sosna-U visor, NSVT, IR lamp, wind mast) reach 2.78 m (the
2.226 m figure is the turret roof); the fuel drums sit at h 1.37 (drawing ~1.48) so a level gun
(sleeve underside 1.69 m) clears them when the turret is turned to the rear (turret sweep test);
no L-4 "Luna" IR searchlight beside the gun (removed in the obr. 2011 rebuild with the thermal
Sosna-U); RMSh track pitch drawn at 0.19 m (real 0.137 m) to stay in the triangle budget; the
unditching log uses the weathered `track` paint (no wood material).

## Pivots and anchors

| Node | Where | Notes |
|---|---|---|
| `Wheel0..11` | road wheels x 1.27, 2.12, 2.94, 3.80, 4.62, 5.44; h 0.49; z ±1.395 (right side first) | one mesh set per side shared by its 6 pivots |
| `Wheel12..13` / `Wheel14..15` | idlers x 0.42, h 0.72 / sprockets x 6.25, h 0.72 | spin about local Z |
| `Turret` | ring centre x 3.35, deck h 1.5; ring radius `TURRET_RING_R` 1.08 | turns about local Y |
| `Turret/Gun` | trunnions x 2.25, h 1.8 (level) | holds the dust cover, collar, coax block |
| `Turret/Gun/Barrel` | identity at the gun pivot | barrel, fume extractor, sleeve clamp bands, bore (TASK-048 recoil) |
| `Turret/Gun/Muzzle` | x −2.72, h 1.8 | 0.05 m in front of the barrel end |
| `Exhaust` (Marker3D) | x 5.75, h 1.62, z −1.56 | top of the louvred exhaust outlet on the left rear fender |
| `Dust_L` / `Dust_R` | x 6.25 (sprockets), h 0.02, z ∓1.395 | bottom of the track at the rear |

`HULL_INTERIOR` = x 1.5–5.8, h 0.7–1.35, z ±0.9 (4.3 × 0.65 × 1.8 m); `TURRET_CLEARANCE_H` = 1.53
(the dome rim). Everything on the hull inside the turret's sweep stays under the turret part that
passes over it: deck ≤ 1.52 within 1.42 m of the ring centre, ≤ 1.56 under the gun's dust cover,
fender boxes / exhaust duct / tow cables ≤ 1.64 under the bins and fume extractor, drums and log
≤ 1.68 under the thermal sleeve.

## Parts (metres)

| Part | x (from front) | h | z / half width | Material | Built with |
|---|---|---|---|---|---|
| Road wheels 6 per side | as above, r 0.375, 0.5 wide | centre 0.49 | ±1.395 | camo dished disc + hub cap, 6 hub bolts, 8 rim bolts (`wheel_rim_bolts`), rubber tyre; inner half a plain rubber drum | `TrackedRunningGear` kit wheel, `wheel_sides` 14 |
| Idler / sprocket | 0.42 r 0.26 / 6.25 r 0.33, 12 teeth, 6 hub bolts | 0.72 | ±1.395 | camo + steel | kit idler / sprocket |
| Road arms, idler arms, 3 return rollers per side (1.7, 3.37, 5.03, h 0.92, r 0.1) | | | inner half of the track | dark | kit suspension (plain shapes behind the skirts) |
| Track: individual all-steel RMSh shoes, pitch 0.19 (chamfered body + grouser bar, `track_pads` false) | loop around the wheels | 0.08 thick | 0.58 wide | weathered `track` | kit shoes; **none on the top run between x 1.1 and 6.43** (behind the skirts) |
| Rubber skirts, 6 panels per side | 0.6–6.93 | 0.8–1.4 | outer face ±1.79; 0.03 thick, front panel 0.06 | camo plates with chamfered rims, rubber edge strip 0.07 along every bottom edge, top bolt row, stiffener, hinge knuckles, top rail; 2 × 3 bolts on the front panel | `detailed_skirts` |
| – skirt outline | front panel: bottom rake 0.25, top drops 0.12 over its first 0.4 m (follows the glacis); rear: bottom rises from 0.8 at x 4.8 to 0.98 at 6.6 and curves up to the tip (6.76 / 1.04, 6.85 / 1.12, 6.9 / 1.24) | | | | `skirt_bottom_profile`, `skirt_front_top_drop` (human feedback: the rear slope) |
| Faction accent plate | skirt panel 2 | ~1.1 | ±1.79 | faction accent | kit skirts |
| Upper hull (chamfered profile) | nose 0 (h 1.02–1.1), glacis to 1.2 (h 1.47), deck 1.5 to 6.7, rear 6.86 (h 1.3–1.4); bottom rises from 1.02 at 5.8 to 1.3 at the rear | 1.02–1.52 | ±1.7 | camo | `MeshKit.profile` |
| Lower hull (chamfered profile) + dark engine compartment side under the raised rear fenders | 0.02–6.84 / 5.8–6.84 | 0.46–1.05 / 1.0–1.36 | ±1.08 | camo / dark | profile, slab |
| Kontakt-5 glacis pack | 0–1.0, 0.14 thick | 1.1–1.54 | ±1.25 | camo base + 3 × 8 chamfered lids along the slope, dark step at x 1.0 | profile, cbox |
| Driver's hatch + lid + handle, TNPO periscope | 1.55, r 0.29 / 1.12–1.27 | 1.47–1.57 | 0 | camo / steel / glass | rods, slab |
| Headlights on brackets with wire guards | 0.2–0.42 | 1.18–1.46 | ±1.5 | camo / dark / lens / steel | slab, rods, tube |
| Front mudguards: curved band over the idler | 0.26–0.62 (arc r 0.27–0.36 around (0.62, 0.92)) | 0.92–1.28 | ±1.7…1.79 | camo | `plate` |
| Self-entrenching blade, 9 bolts on the lower front plate, front rubber flaps, tow hooks | 0.05–0.64 | 0.49–1.02 | | camo / rubber / dark / steel | profile, bolts, tubes |
| Engine deck: 2 louvred radiator grilles (9 slats each) with raised frames and handles, 2 bolted access plates | 5.68–6.66 / 4.78–5.65 | ≤ 1.56 | z ±0.62 / ±1.2 | dark / camo / steel | slabs, cboxes, tubes |
| Fender stowage: 3 fuel tanks (right rear, filler caps, straps), 2 boxes (left rear), 2 front boxes, all with lid seams and latches | 4.42–6.62 / 1.35–2.2 | 1.5–1.6 | ±1.555 | camo / dark / steel | slabs |
| Exhaust outlet with 7 louvres | 5.38–6.12 | 1.5–1.6 | −1.56 | camo / dark | slabs, cboxes |
| Tow cables with eyes and clamps, lifting eyes | 2.3–4.35 / 0.75, 6.55 | ~1.53 | ±1.64 / ±1.6 | steel / dark | `tube`, arcs |
| 200 l fuel drums ×2 (axis across): rims, two rolling hoops, filler bung, two straps, brackets | 7.11, r 0.28, 0.85 long | 1.37 | ±0.5 | camo / steel / dark | `lathe` (16 sides), arcs |
| Unditching log on two chains | 6.99, r 0.125 | 0.97 | ±1.55 | weathered track / steel | lathe, arcs |
| Tail lights (red + white lens) with guards, rear tow hooks | 6.81–6.98 | 0.78–1.47 | ±1.48 / ±0.72 | camo / red_lens / lens / steel / dark | slabs, tubes |
| **Turret** – cast dome (oval lathe, 32 sides, 13 profile rings: superellipse `1 − ρ³`^0.45, rim undercut, no floor) | centre 3.5, ±1.25 (2.25–4.75) | rim 1.53, roof 2.2 | ±1.05 (narrower than the ±1.7 hull) | camo | `MeshKit.lathe(..., oval)` (new `oval` stretch, test in `test_mesh_kit.gd`) |
| Turret ring collar, 3 lifting eyes | r 1.02 | 1.5–1.53 | | dark | rod, arcs |
| Kontakt-5 wedges, 2 rows × 4 chamfered blocks per side, 0.04 gaps, 2 bolts each | front edge (1.95, z 0.32) → (2.6, z 1.25), swept back 35° | front row 1.6–1.89 (sharp 1.74 front edge), back row 1.6–2.06, +0.03 per block outwards | both sides of the gun | camo | `plate` of the row sections along the edge |
| Sosna-U head: armoured box, round front barrel r 0.23, round window (dark bezel r 0.15–0.2, glass r 0.15), opened armoured visor on two hinges, bolted roof, seam | 2.5–3.16 | 1.9–2.57 | z 0.36–0.84 | camo / dark / glass / steel | slabs, rod, lathe ring (human feedback: round, not square) |
| Commander's cupola (base down into the dome), hatch lid with hinge, 4 vision blocks, TKN-3MK block with window | 3.6, r 0.42 / 3.18–3.38 | 1.94–2.42 | z +0.52 | camo / glass / steel | rods, slabs, cboxes |
| OU-3GA2M IR lamp on its bracket | 3.13–3.34, r 0.11 | 2.52 | z +0.24 | camo / lens / dark | rods |
| NSVT 12.7 mm: pintle, cradle, receiver, barrel with flash hider (1.07 m), ammo box, sight | 2.38–3.98 | 2.28–2.67 | z +0.52…+0.77 | dark / steel / camo | rods, slabs, lathe |
| Gunner's hatch + lid + handle + hinge, periscope, backup 1A40-1 sight head | 3.62, r 0.34 / 2.88–3.3 | 1.94–2.3 | z −0.55 | camo / glass / steel / dark | rods, slabs |
| Grab rails on the dome shoulders | 3.3–3.7 | ~1.95 | ±0.9 | steel | tubes |
| Side bins (outer face leaning out 0.12), lids, lid seams, 2 ribs, 2 latches, hinges, handle | 3.62–4.8 | 1.66–2.04 | z ±0.6…±1.42 | camo / dark / steel | `loft` |
| **Rear bin** (rear face raked back 0.12), lid, seam, 2 ribs, 2 latches, hinges, handle | 4.45–5.115 | 1.74–2.1 | ±0.635 | camo / dark / steel | `loft` (human feedback: bin on the turret rear) |
| OPVT snorkel tube on the left bin, two straps | 3.66–4.78, r 0.125 | 2.17 | z −1.06 | camo / dark | lathe, arcs |
| Wind sensor mast + box head (DVE-BS) | 4.3 | 2.1–2.78 | 0 | steel / dark | tube, cbox |
| Radio antenna base + whip stub on the left bin | 4.45 | 2.04–2.6 | z −1.1 | dark / steel | rod, tube |
| 902B smoke launchers on brackets: 8 left (2 rows), 4 right, aimed forward/up/out | 3.0–3.62 | 1.7–2.1 | ±1.18…±1.5 | dark | lathes (recessed muzzles) |
| **Gun** – canvas dust cover with 6 folds, steel collar, coax PKTM block + port | 1.63–2.35, r 0.235 | 1.57–2.04 | 0 / z +0.31 | faction cloth / steel / camo / dark | lathe, rod, slab |
| **Barrel** – 2A46M-5: fume extractor r 0.15 (x 0.45–1.21), thermal sleeve r 0.088–0.104, muzzle lip r 0.09, 4 steel clamp bands, bore | 1.69 → −2.67 | 1.8 | 0 | camo / steel / dark | lathe (16 sides), rods |

## Triangles and instances (TASK-069 stage 2)

| | Before (TASK-062 helpers) | After (MeshKit) |
|---|---|---|
| Triangles, every faction (russia, poland) | 20 988 | 37 126 (hull 17 774, wheels 10 488, turret 7 092, gun 716, barrel 1 056) |
| Body mesh instances (outside `Wheel*`) | 14 | 21 (hull 9, turret 5, gun 4, barrel 3) |
| Mesh instances total | 46 | 53 |
| Cold build (`test_every_model_builds_cold_within_the_time_budget`) | 40.9 ms | 135.4 ms |
| Render `Stats` AABB | 8.8 × 3.1 × 2.4 m | 8.8 × 3.2 × 2.4 m (contract 0.964 × 0.345 × 0.266 → 0.965 × 0.347 × 0.266) |
| `Real` diff | −8.0 % / −12.7 % / +8.7 % | −8.0 % / −12.2 % / +8.7 % |

Hidden geometry cut: no track shoes on the top run between the skirt ends (x 1.1–6.43 above the
road-wheel tops), inner road-wheel halves as plain rubber drums, return rollers and road arms as
the simplest shapes behind the skirts, no turret floor (the dome lathe stops at its rim undercut),
nothing inside the hull shell (`HULL_INTERIOR`), the Sosna / cupola / hatch bases and the gun
dust cover end inside the dome instead of closing under it, no faces behind the glacis lids.

## Silhouette features

1. **Low rounded cast turret with sharp Kontakt-5 wedges on both sides of the long gun** – a
   smooth oval dome with sloping shoulders, clearly narrower than the hull; in front of its front
   slope two wedge packs of two rows of four chamfered blocks each (gaps, bolts), their front
   edges swept back 35° from the gun to the turret sides (arrow-head plan), tops sloping down to
   a sharp front edge, stepping up outwards so the front view shows a shallow V with the canvas
   gun cover in the notch.
2. **Sosna-U head sticking out of the roof** – armoured box on the right front roof with a round
   front barrel and a big round dark window under an opened visor (human feedback: round, not
   square), in front of the commander's cupola.
3. **Wind sensor mast** – thin steel mast with a dark box head at the turret rear centre, 0.6 m
   above the roof.
4. **Low hull with rubber skirts over the upper track run** – skirts hang only to 0.8 m, i.e. the
   wheel tops, so the six large road wheels show almost entirely (unlike the Abrams); the front
   panel follows the glacis down to a curved mudguard, the bottom edge rises from the fifth wheel
   and curves up to a tip at the rear plate (human feedback: the rear slope).
5. **Details** – six large dished road wheels with hub and rim bolts, individual steel track
   shoes, rear sprocket, front idler; K-5 lid grid on the glacis, dozer blade under the nose, NSVT
   on the commander's cupola, U of stowage bins around the turret rear with the rear bin across
   the back (human feedback), smoke launchers on the turret sides, two fuel drums and the
   unditching log on the rear plate.

## History

Rework 1 (coordinator review "turret reads as an angular box"): dome lowered at the shoulders and
narrowed; K-5 wedges as low blocks forming a shallow V. Rework 2 / 2b (human feedback): U-shaped
bins, rear skirt slant, round Sosna window, more turret detail, rubber skirt edge strip.

Rework 3 (TASK-069 stage 2, MeshKit): everything rebuilt with chamfered kit primitives and the
weathering masks; the shared running gear with detailed wheels, individual steel shoes and kit
skirts; the skirt outline follows the drawing (gentle rise behind the fifth wheel, curved rear
tip, front top following the glacis, curved mudguard); the rear bin made a separate box across
the turret rear with a raked rear face, ribs, latches and handle; the Sosna-U given a round front
barrel with a big round window and an opened visor; added the gunner's 1A40-1 head, vision
blocks, hatch handles and hinges, grab rails, lifting eyes, bolts on the K-5 blocks, the canvas
dust cover, glacis K-5 lids, tow cables, fender fuel tanks and boxes, exhaust louvres, drum
straps and the unditching log; `Barrel` pivot and `Exhaust` / `Dust_L` / `Dust_R` anchors.

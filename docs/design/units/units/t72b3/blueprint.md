# T-72B3 obr. 2011 – model blueprint

Model: `src/presentation/models/t72b3.gd`; shared running gear
`src/presentation/models/parts/tracked_running_gear.gd`; metre -> model conversion and the
profile / loft / merged-instance helpers `src/presentation/models/parts/vehicle_frame.gd`.
Reference: `drawing_1.jpg` (side, front and rear line drawing). Measured on the side view at
~158 px/m (hull rear plate to muzzle 1538 px = 9.53 m; hull 6.86 m; road wheel 118 px = 0.75 m).
The drawing shows a T-72B with Kontakt-1 bricks on the turret and skirts; for the obr. 2011 the
catalog's silhouette features win: Kontakt-5 wedges on the turret, plain rubber skirts. Positions
and proportions (wheels, turret, gun, drums) come from the drawing.

## Scale

Real 9.53 m (gun forward) + 0.53 m of rear fuel drums = 10.06 m × 3.59 × 2.226 m. Scaled
**uniformly** by `K = 0.087` model units per metre (1 unit = 11.5 m, almost the Abrams' 0.088 so
the two tanks keep their real size ratio): 0.875 × 0.31 × 0.24 units before `MODEL_SCALE`
(contract test: 1.139 × 0.408 × 0.315 after). The render's `Real` line (at 10 m/unit) therefore
shows about −13 % on length and width; the true proportions are kept.

Origin: model x = 0 sits at x = (6.86 + 0.53 − 2.67) / 2 = 2.36 m from the hull front, so muzzle
to drums is centred. Parts are in vehicle metres (`x` from the glacis nose backwards, `h` above
the ground, `z` positive = right).

Deliberate deviations: roof add-ons (Sosna-U, NSVT, IR lamp, wind mast) reach 2.78 m (the
2.226 m figure is the turret roof); no bevels (MeshKit/TASK-030 not landed); no unditching log;
no L-4 "Luna" IR searchlight beside the gun (removed in the obr. 2011 rebuild with the thermal
Sosna-U).

## Parts (metres)

| Part | x (from front) | h | z / half width | Material | Built with |
|---|---|---|---|---|---|
| Road wheels 6 per side (`Wheel0..11`) | 1.27, 2.12, 2.94, 3.80, 4.62, 5.44 (from the drawing) | centre 0.49, r 0.375 | track centre ±1.395, 0.5 wide | camo disc + rubber tyres | `TrackedRunningGear` |
| Idler (`Wheel12..13`) | 0.42 | 0.72, r 0.26 | ±1.395 | camo + steel | same |
| Sprocket (`Wheel14..15`) | 6.25 | 0.72, r 0.33, 12 teeth | ±1.395 | dark + camo hub | same |
| Return rollers 3 per side | 1.7, 3.37, 5.03 | 0.92, r 0.10 | inner half of the track | steel | same |
| Track loop + grousers | hull of all wheels | 0.08 thick, grousers every 0.2 | 0.58 wide | track | same |
| Rubber skirts 6 panels per side | 0.6–6.78 | 0.8–1.4 (down to the wheel tops) | outer face ±1.79; 0.03 thick, front panel 0.06 with a 0.25 rake; last panel's bottom edge slants up 0.45 m over its last 0.95 m (over the sprocket) | camo | same, `skirt_rear_rake` / `skirt_rear_rise` |
| Skirt accent plate | panel 2 | ~1.1 | ±1.79 | faction accent | same |
| Upper hull (profile prism) | nose 0 (h 1.02–1.1), glacis to 1.2 (h 1.47), deck 1.5 to 6.7, rear 6.86 (h 1.3–1.4); bottom rises from 1.02 at 5.8 to 1.3 at the rear (over the sprocket) | 1.02–1.52 | ±1.7 | camo | `Frame.profile` |
| Lower hull (profile prism) | lower front plate 0.02–0.75, belly 0.46–0.48 | 0.46–1.05 | ±1.08 | camo | same |
| Kontakt-5 glacis pack | 0–1.0, 0.14 thick on the glacis | 1.1–1.54 | ±1.25 | camo + 3 dark seams | profile prisms |
| Dozer blade | on the lower front plate 0.17–0.64 | 0.49–0.88 | ±1.15 | camo | profile prism |
| Fender fuel tanks / boxes 3 per side | 4.05–6.53 | 1.5–1.64 | z ±1.5, ±0.18 | camo | boxes |
| 200 l fuel drums ×2 (axis across) | 7.11, r 0.28 | 1.42 | z ±0.5, 0.85 long | camo | cylinders |
| Drum bracket, deck grille slats ×6, exhaust (left fender), driver's hatch, headlights, tow hooks | – | – | – | dark / glass | boxes, cylinder |
| **Turret** pivot | ring centre 3.35 | deck 1.5 | 0 | – | `Turret` node |
| Cast dome (lathe, stretched) | centre 3.5, ±1.25 (2.25–4.75), rounded front and rear | 1.5–2.2; flat roof only within 30 % of the radius, shoulders slope down to the base | ±1.05 (narrower than the ±1.7 hull) | camo | `ModelParts.lathe_mesh`, scaled basis |
| Kontakt-5 wedges, 2 rows × 4 blocks per side | front edge (1.95, z 0.32) → (2.6, z 1.25), swept back 35°; front row 0.37 m deep, back row 0.24 m | front row: sharp 1.74 front edge rising to 1.89; back row 1.95–2.06; +0.03 per block outwards (shallow V from the front) | both sides of the gun | camo | prisms of the two row cross-sections, rotated along the edge |
| Sosna-U sight housing | 2.62–3.12, front corners chamfered 0.12 | 1.8–2.5 | z 0.36–0.84 (right, in front of the cupola) | camo | `frame.loft` |
| Sosna-U round window: collar r 0.2, dark rim r 0.16, glass r 0.12 | on the front face | centre 2.22 | z +0.6 | camo / dark / glass | stacked cylinders along x |
| Commander's cupola + hatch lid | 3.6, r 0.4; lid r 0.3 | 2.11–2.34 | z +0.52 | camo | cylinders |
| TKN-3MK sight block + window | 3.18–3.36 | 2.26–2.42 | z +0.52 | camo / glass | boxes |
| OU-3GA2M IR lamp (round, facing forward) + bracket | 3.11–3.33, r 0.11 | centre 2.52 | z +0.24 | camo / glass / dark | cylinders |
| NSVT 12.7 mm (pintle, slim receiver, cradle arm, camo ammo box, barrel 1.1 m forward) | 2.38–3.98 | 2.28–2.54 | z +0.4…+0.78 | dark / camo / steel | cylinders + boxes |
| Gunner's hatch + lid + periscope | 3.62, r 0.34 / 0.24 | 2.13–2.22 | z −0.55 | camo / glass | cylinders, box |
| Rear stowage bin (wide box on the rear wall, rear corners chamfered 0.23) | 4.45–5.18 | 1.6–2.08 | ±1.05 | camo + 2 dark latches | `frame.loft` |
| Side stowage bins (U with the rear bin) | 3.82–4.6, front corner chamfered | 1.6–1.98 | z ±0.8…±1.2 | camo | `frame.loft` |
| OPVT snorkel tube, stowed fore-aft on the left rear | 3.95–5.25, r 0.13 | centre 2.2 | z −0.62 | camo | cylinder |
| Radio antenna base | 4.25 | 1.97–2.09 | z −1.0 | dark | cylinder |
| Wind sensor mast + head | 4.35 | 2.12–2.78 | 0 | dark | cylinders |
| 902B smoke launchers: 8 on the left (2 rows), 4 on the right | 3.25–3.64 | 1.84 / 1.97, aimed forward/up/out | ±0.94 / −0.89 | dark | cylinders |
| Turret ring collar | r 1.0 | 1.5–1.56 | – | dark | cylinder |
| **Gun** pivot (trunnions) | 2.25 | 1.8 | 0 | – | `Turret/Gun`, level |
| 2A46M-5 barrel (lathe): dust-cover collar r 0.23 (x 1.63–2.4), fume extractor r 0.15 (x 0.47–1.3), thermal sleeve r 0.09–0.1 with bands at x −0.4, −1.35, −2.0, muzzle r 0.09 | 2.4 → muzzle −2.67 | 1.8 | 0 | camo | `ModelParts.lathe_mesh` |
| Bore, coaxial PKTM port | – | – | – | dark | |
| `Turret/Gun/Muzzle` | −2.72 | 1.8 | 0 | – | marker node |

Mesh instances: 14 outside the wheel pivots (hull 3, running gear 5, turret 4, gun 2), 2 per wheel
pivot; 15 544 triangles (budget 25 000). The faction accent is the plate on the second skirt
panel of each side (no flat turret surface to carry one).

Rework 1 (coordinator review "turret reads as an angular box"): dome lowered at the shoulders and
narrowed to ±1.05 m, rounded front and rear (no rear stowage step); side/rear stowage boxes, K-5
roof plates and the old 1A40 sight box removed so only the cupola + NSVT, Sosna-U and mast rise
above the dome; K-5 wedges rebuilt as low blocks sloping down to a sharp front edge, forming a
shallow V from the front.

Rework 2 (human feedback): U-shaped stowage bin around the turret rear (wide rear box + side
boxes) with the snorkel tube stowed on top of the left side; the last skirt panel's bottom edge
slants up over the sprocket (new shared `skirt_rear_rake` / `skirt_rear_rise` parameters of
`TrackedRunningGear.Spec`, default off) and the skirts run back to 6.78 m; the Sosna-U housing
got chamfered front corners and a round window (collar, dark rim, glass); the turret got more
detail – K-5 wedges as two rows of four blocks, cupola hatch lid, TKN-3MK block, round OU-3GA2M
IR lamp, slimmer NSVT receiver with a camo ammo box, gunner's hatch lid and periscope, 8 + 4
smoke launchers, antenna base, bin latches.

Rework 2b (coordinator: the rear slant must read in the side view): a 0.07 m dark rubber strip
runs along every skirt bottom edge including the slant (shared `skirt_edge`, default 0); the
upper hull's bottom edge rises from 1.02 m at x 5.8 to 1.3 m at the rear plate, so the
sprocket and the track run over it show through the cut, with a dark engine-compartment side
(x 5.8–6.84, h 1.0–1.36, ±1.08) behind them. The turret bins got dark lid seam bands 0.08–0.12 m
under their lids and dark hinge strips on the front edges of their lids, so they read as separate
boxes from the side and from above. 15 544 triangles, 14 body mesh instances (+1 skirt edge strip).

## Silhouette features

1. **Low rounded cast turret with sharp Kontakt-5 wedges on both sides of the long gun** – a
   stretched lathe dome with sloping shoulders, clearly narrower than the hull; in front of its
   front slope two wedge packs of two rows of four blocks each, their front edges swept back 35° from the
   gun to the turret sides (arrow-head plan), tops sloping down to a sharp front edge, stepping
   up outwards so the front view shows a shallow V with the gun collar in the notch.
2. **Sosna-U housing sticking out of the roof** – 0.5 × 0.48 m camo housing with chamfered front
   corners, 0.3–0.6 m above the dome on the right roof in front of the commander's cupola, with a
   round dark-rimmed window facing forward (human feedback: round, not square).
3. **Wind sensor mast** – thin dark mast with a small head at the turret rear centre, 0.6 m above
   the roof.
4. **Low hull with rubber skirts over the upper track run** – skirts hang only to 0.8 m, i.e. the
   wheel tops, so the six large road wheels show almost entirely (unlike the Abrams); thin
   panels, thicker raked front panel, rear panel cut at a slant over the sprocket.
5. **Details** – six large road wheels with small even gaps, three return rollers hidden behind
   the skirts, rear sprocket, front idler; K-5 on the glacis, dozer blade under the nose, NSVT on
   the commander's cupola, two fuel drums on the rear plate.

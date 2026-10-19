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

Deliberate deviations: roof add-ons (Sosna-U, NSVT, wind mast) reach 2.78 m (the 2.226 m figure
is the turret roof); no bevels (MeshKit/TASK-030 not landed); no unditching log, no snorkel tube.

## Parts (metres)

| Part | x (from front) | h | z / half width | Material | Built with |
|---|---|---|---|---|---|
| Road wheels 6 per side (`Wheel0..11`) | 1.27, 2.12, 2.94, 3.80, 4.62, 5.44 (from the drawing) | centre 0.49, r 0.375 | track centre ±1.395, 0.5 wide | camo disc + rubber tyres | `TrackedRunningGear` |
| Idler (`Wheel12..13`) | 0.42 | 0.72, r 0.26 | ±1.395 | camo + steel | same |
| Sprocket (`Wheel14..15`) | 6.25 | 0.72, r 0.33, 12 teeth | ±1.395 | dark + camo hub | same |
| Return rollers 3 per side | 1.7, 3.37, 5.03 | 0.92, r 0.10 | inner half of the track | steel | same |
| Track loop + grousers | hull of all wheels | 0.08 thick, grousers every 0.2 | 0.58 wide | track | same |
| Rubber skirts 6 panels per side | 0.6–6.6 | 0.8–1.4 (down to the wheel tops) | outer face ±1.79; 0.03 thick, front panel 0.06 with a 0.25 rake | camo | same |
| Skirt accent plate | panel 2 | ~1.1 | ±1.79 | faction accent | same |
| Upper hull (profile prism) | nose 0 (h 1.02–1.1), glacis to 1.2 (h 1.47), deck 1.5 to 6.7, rear 6.86 (h 1.4) | 1.02–1.52 | ±1.7 | camo | `Frame.profile` |
| Lower hull (profile prism) | lower front plate 0.02–0.75, belly 0.46–0.48 | 0.46–1.05 | ±1.08 | camo | same |
| Kontakt-5 glacis pack | 0–1.0, 0.14 thick on the glacis | 1.1–1.54 | ±1.25 | camo + 3 dark seams | profile prisms |
| Dozer blade | on the lower front plate 0.17–0.64 | 0.49–0.88 | ±1.15 | camo | profile prism |
| Fender fuel tanks / boxes 3 per side | 4.05–6.53 | 1.5–1.64 | z ±1.5, ±0.18 | camo | boxes |
| 200 l fuel drums ×2 (axis across) | 7.11, r 0.28 | 1.42 | z ±0.5, 0.85 long | camo | cylinders |
| Drum bracket, deck grille slats ×6, exhaust (left fender), driver's hatch, headlights, tow hooks | – | – | – | dark / glass | boxes, cylinder |
| **Turret** pivot | ring centre 3.35 | deck 1.5 | 0 | – | `Turret` node |
| Cast dome (lathe, stretched) | centre 3.5, ±1.25 (2.25–4.75), rounded front and rear | 1.5–2.2; flat roof only within 30 % of the radius, shoulders slope down to the base | ±1.05 (narrower than the ±1.7 hull) | camo | `ModelParts.lathe_mesh`, scaled basis |
| Kontakt-5 wedges, 3 blocks per side | front edge (1.95, z 0.32) → (2.6, z 1.25), swept back 35°; 0.55 m deep | top 2.02 at the back sloping to a sharp 1.74 front edge; +0.04 per block outwards (shallow V from the front) | both sides of the gun | camo | prism of the wedge cross-section, rotated along the edge |
| Sosna-U sight housing + window | 2.62–3.12 | 1.95–2.55 | z +0.6 (right, in front of the cupola), ±0.24 | camo / glass | box |
| Commander's cupola | 3.6, r 0.4 | 2.11–2.29 | z +0.52 | camo | cylinder |
| NSVT 12.7 mm (pintle, receiver, ammo box, barrel 1.1 m forward) | 2.4–4.0 | 2.33–2.54 | z +0.52 | dark / steel | cylinders + boxes |
| Gunner's hatch | 3.62, r 0.34 | 2.16 | z −0.55 | camo | cylinder |
| Wind sensor mast + head | 4.35 | 2.12–2.78 | 0 | dark | cylinders |
| 902B smoke launchers 4 per side | 3.3–3.7 | 1.84, aimed forward/up/out | ±0.92 | dark | cylinders |
| Turret ring collar | r 1.0 | 1.5–1.56 | – | dark | cylinder |
| **Gun** pivot (trunnions) | 2.25 | 1.8 | 0 | – | `Turret/Gun`, level |
| 2A46M-5 barrel (lathe): dust-cover collar r 0.23 (x 1.63–2.4), fume extractor r 0.15 (x 0.47–1.3), thermal sleeve r 0.09–0.1 with bands at x −0.4, −1.35, −2.0, muzzle r 0.09 | 2.4 → muzzle −2.67 | 1.8 | 0 | camo | `ModelParts.lathe_mesh` |
| Bore, coaxial PKTM port | – | – | – | dark | |
| `Turret/Gun/Muzzle` | −2.72 | 1.8 | 0 | – | marker node |

Mesh instances: 13 outside the wheel pivots (hull 3, running gear 4, turret 4, gun 2), 2 per wheel
pivot; 13 976 triangles (budget 25 000). The faction accent is the plate on the second skirt
panel of each side (no flat turret surface to carry one).

Rework 1 (coordinator review "turret reads as an angular box"): dome lowered at the shoulders and
narrowed to ±1.05 m, rounded front and rear (no rear stowage step); side/rear stowage boxes, K-5
roof plates and the old 1A40 sight box removed so only the cupola + NSVT, Sosna-U and mast rise
above the dome; K-5 wedges rebuilt as low blocks sloping down to a sharp front edge, forming a
shallow V from the front.

## Silhouette features

1. **Low rounded cast turret with sharp Kontakt-5 wedges on both sides of the long gun** – a
   stretched lathe dome with sloping shoulders, clearly narrower than the hull; in front of its
   front slope two wedge packs of three blocks each, their front edges swept back 35° from the
   gun to the turret sides (arrow-head plan), tops sloping down to a sharp front edge, stepping
   up outwards so the front view shows a shallow V with the gun collar in the notch.
2. **Boxy Sosna-U housing sticking out of the roof** – 0.5 × 0.48 × 0.46 m camo box with a dark
   window on the right roof in front of the commander's cupola, the tallest box on the turret.
3. **Wind sensor mast** – thin dark mast with a small head at the turret rear centre, 0.6 m above
   the roof.
4. **Low hull with rubber skirts over the upper track run** – skirts hang only to 0.8 m, i.e. the
   wheel tops, so the six large road wheels show almost entirely (unlike the Abrams); thin
   panels, thicker raked front panel.
5. **Details** – six large road wheels with small even gaps, three return rollers hidden behind
   the skirts, rear sprocket, front idler; K-5 on the glacis, dozer blade under the nose, NSVT on
   the commander's cupola, two fuel drums on the rear plate.

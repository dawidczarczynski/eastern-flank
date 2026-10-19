# M1A2 SEPv3 Abrams – model blueprint

Model: `src/presentation/models/m1a2_sepv3.gd`; shared running gear
`src/presentation/models/parts/tracked_running_gear.gd`; metre -> model conversion
`src/presentation/models/parts/vehicle_frame.gd`. Reference: `side_1.jpg` (two SEPv3s side-on,
measured on the right tank at ~73 px/m: 580 px = 7.93 m hull). Wheel and turret positions not
readable in the photo come from published Abrams data (road wheel 635 mm, track 635 mm wide, ground
contact ~4.6 m, gun overhang 1.84 m).

## Scale

Real 9.77 (incl. gun) × 3.7 × 2.4 m. At the nominal 1 unit = 10 m the length would be 0.977 ×
`MODEL_SCALE` 1.3 = 1.27, over the 1.15 budget, so the tank is scaled **uniformly** by
`K = 0.088` model units per metre (1 unit = 11.4 m): 0.86 × 0.326 × 0.23 units before
`MODEL_SCALE` (contract test: 1.132 × 0.426 × 0.302 after). The render's `Real` line (at 10 m/unit)
therefore shows about −12 % on length and width; the true proportions are kept.

Origin: model x = 0 sits at x = (7.93 − 1.84) / 2 = 3.045 m from the hull front, so the hull plus
gun is centred. All parts are written in vehicle metres (`x` from the glacis nose backwards, `h`
above the ground, `z` positive = right) and converted by `vehicle_frame.gd`.

Deliberate deviations (miniature): the roof add-ons (CITV, CROWS-LP, M240 shield, antenna stubs)
are capped at h 2.64 m, so the overall height is 2.64 m (+10 % over the 2.4 m turret-roof figure);
the antennas are short stubs instead of 3 m whips; no bevels (MeshKit/TASK-030 not landed yet).

## Parts (metres)

| Part | x (from front) | h | z / half width | Material | Built with |
|---|---|---|---|---|---|
| Road wheels 7 per side (`Wheel0..13`) | 1.72 … 6.04, pitch 0.72 | centre 0.44, r 0.32 | track centre ±1.44, 0.58 wide | camo disc lathe + rubber tyres | `TrackedRunningGear` |
| Idler (`Wheel14..15`) | 0.62 | 0.76, r 0.30 | ±1.44 | camo + steel rims | same |
| Sprocket (`Wheel16..17`) | 7.30 | 0.80, r 0.36, 11 teeth | ±1.44 | dark gear rings + camo hub | same (`gear_outline` prisms) |
| Return rollers 2 per side | 2.75, 4.95 | 1.02, r 0.10 | inner half of the track | steel | same |
| Track loop + grousers | hull of all wheels | 0.08 thick, grousers 0.04 every 0.25 | 0.63 wide | track | `circle_hull` + `band_mesh` |
| Skirts 7 panels per side | 0.12–7.05 | 0.62–1.24 | outer face ±1.85; front 2 panels 0.12 thick, rest 0.05; front-bottom corner raked 0.4 | camo | same (prisms) |
| Skirt accent plate | panel 2 | 0.9–1.1 | ±1.85 | faction accent | same |
| Upper hull (profile prism) | nose 0 (h 1.14–1.27), glacis to 2.25 (h 1.6), deck 1.62 to 7.8, rear 7.93 | 1.14–1.62 | ±1.72 | camo | `ModelParts.prism_mesh` |
| Lower hull (profile prism) | lower front plate 0.04–0.95, belly 0.48–0.52 | 0.48–1.2 | ±1.12 | camo | prism |
| Rear stowage boxes | 7.25–7.9 | 1.62–1.82 | ±1.32 | camo | box |
| Rear grille box + 5 louvres | 7.89–8.0 | 0.95–1.5 | ±1.05 | dark | boxes |
| Deck grille slats ×7 | 6.05–7.65 | 1.62 | ±1.05 | dark | boxes |
| APU exhaust box + pipe | 7.5–7.95 | 1.62–1.78 | z −1.34 (rear left) | dark | box + cylinder |
| Driver's hatch, 3 periscopes, headlights, tow hooks, tail lights | front / rear | – | – | dark / glass | boxes |
| **Turret** pivot | ring centre 3.95 | deck 1.62 | 0 | – | `Turret` node |
| Turret front block (loft) | bottom 1.85–5.0, top 2.5–5.0 (wedge front) | 1.62–2.36 | bottom ±1.66 (front edge ±0.75), top ±1.56 | camo | `ModelParts.loft_mesh` |
| Bustle (loft), overhangs the deck | 4.95–6.35 | 1.8–2.36 (gap above the deck) | ±1.66 → ±1.52 | camo | loft |
| Bustle side boxes + accent plates | 5.0–6.1 | 1.86–2.3 | ±1.66 / plates ±1.72 | camo / accent | boxes |
| Bustle rack (floor, posts, rails) + 3 bags | 6.35–7.15 | 1.82–2.32 | ±1.45 | dark / faction cloth | boxes |
| Gunner's primary sight doghouse | 2.6–3.3 | to 2.58 | z +0.95 (right) | camo + glass | box |
| CITV pedestal + head | 3.12–3.45 | to 2.64 | z −0.85 (left front) | camo + glass | cylinder + box |
| Commander's cupola ring + CROWS-LP (base, cradle, sight, ammo box, M2) | 3.0–4.6 | 2.36–2.64 | z +0.82 | camo / dark / steel | cylinders + boxes |
| Loader's hatch ring, M240 on pintle, armoured shield | 3.0–4.35 | 2.36–2.63 | z −0.82 | camo / dark | cylinders + box |
| M250 smoke dischargers 2 × 3 per side | 2.95–3.37 | 2.06 / 2.19 | ±1.62, angled out/up/forward | dark | cylinders |
| **Gun** pivot (trunnions) | 2.3 | 1.98 | 0 | – | `Turret/Gun`, level |
| Mantlet / gun shield | 1.8–2.55 | 1.8–2.17 | ±0.32 | camo | box |
| M256 barrel (lathe): collar r 0.17, thermal sleeve r 0.10–0.12 with 2 bands, muzzle r 0.10, no fume extractor | 1.8 → muzzle −1.84 | 1.98 | 0 | camo | `ModelParts.lathe_mesh` |
| Bore, muzzle reference sensor, coax port | – | – | – | dark | |
| `Turret/Gun/Muzzle` | −1.89 | 1.98 | 0 | – | marker node |

Mesh instances: 15 outside the wheel pivots (hull 3, running gear 4, turret 6, gun 2), 2 per wheel
pivot; 14 184 triangles (budget 25 000).

## Silhouette features

1. **Low, flat, wide angular turret with a sloped wedge front and a long bustle** – two lofts: the
   front block's roof starts 0.65 m behind its base (sloped wedge front, angled cheeks in plan), the
   bustle's underside is 0.18 m above the engine deck so the overhang reads as a shadow line; the
   bustle rack with bags extends it to 7.15 m.
2. **Long 120 mm gun without fume extractor, 1.84 m beyond the hull** – plain lathe barrel with two
   thermal-sleeve bands, muzzle reference sensor box near the muzzle.
3. **Low CROWS RWS on the commander's position, loader's M240 shield** – dark cradle/sight block with
   a steel M2 on the right-rear ring; flat armoured shield with the M240 on the left.
4. **7 road wheels + 2 return rollers, rear sprocket, front idler, deep skirts** – shared running
   gear; skirts hang to 0.62 m, so only the lower half of the wheels and the hubs show (as in the
   photo); two thicker armoured front panels with a raked front-bottom corner.
5. **Long, flat, low hull, near-horizontal deck, box-like rear grille** – one profile prism: shallow
   glacis (1.27 → 1.6 m over 2.25 m), flat deck to the rear; dark grille box with louvres on the rear
   plate.
6. **Smoke dischargers on both turret sides, APU exhaust rear left** – 2 × 3 dark tubes on each
   turret cheek; small dark box + pipe at the rear left of the deck.

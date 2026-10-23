# M1A2 SEPv3 Abrams – model blueprint

Model: `src/presentation/models/m1a2_sepv3.gd` (v3, TASK-069: built with `MeshKit` / `MeshKits`
after the detail study `docs/design/showcase/m1a2_showcase.gd.txt`); shared running gear
`src/presentation/models/parts/tracked_running_gear.gd` with the kit options on; metre -> model
conversion `src/presentation/models/parts/vehicle_frame.gd`. Reference: `side_1.jpg` (two SEPv3s
side-on, measured on the right tank at ~73 px/m: 580 px = 7.93 m hull) and the study's target look
`docs/design/showcase/m1a2_cut_hero.jpg`. Wheel and turret positions not readable in the photo come
from published Abrams data (road wheel 635 mm, track 635 mm wide, ground contact ~4.6 m, gun
overhang 1.84 m).

## Scale

Real 9.77 (incl. gun) × 3.7 × 2.4 m. At the nominal 1 unit = 10 m the length would be 0.977 ×
`MODEL_SCALE` 1.3 = 1.27, over the 1.15 budget, so the tank is scaled **uniformly** by
`K = 0.088` model units per metre (1 unit = 11.4 m). The render's `Real` line (at 10 m/unit)
therefore shows about −10 % on length and width; the true proportions are kept.

Origin: model x = 0 sits at x = (7.93 − 1.84) / 2 = 3.045 m from the hull front, so the hull plus
gun is centred (`vehicle_frame()`). All parts are written in vehicle metres (`x` from the glacis
nose backwards, `h` above the ground, `z` positive = right).

Deliberate deviations (miniature): the roof add-ons (CITV, CROWS-LP, gunner's sight, LAGS shield,
met mast, antenna stubs) are capped at `ROOF_CAP` = 2.64 m (+10 % over the 2.4 m turret-roof
figure), so the study's 3 m whips are short stubs and its CROWS / CITV / LAGS are flattened to fit;
the study's Polish checkerboard is left out (markings are TASK-063, and the model is per faction:
the faction accent plates stay instead); the rear stowage boxes and the APU box are 12 cm lower
than in the study and the deck grille handles moved back, so the turret (bustle rack, front cheeks)
sweeps over them (`TURRET_CLEARANCE_H`).

## Parts (metres)

All parts are chamfered `MeshKit` primitives (chamfer bands carry vertex `r` = 1 for paint wear,
recesses lower `g`); the geometry is faction independent and generated once
(`ModelParts.cached_meshes`).

| Part | x (from front) | h | z / half width | Material | Built with |
|---|---|---|---|---|---|
| Road wheels 7 per side (`Wheel0..13`) | 1.72 … 6.04, pitch 0.72 | centre 0.44, r 0.32 | track centre ±1.44, 0.58 wide | camo dished disc + hub cap + 6 bolts, rubber tyre; inner half a plain rubber drum | `TrackedRunningGear` `detailed_wheels` (one mesh set per side, shared by all 7 pivots) |
| Idler (`Wheel14..15`) | 0.62 | 0.76, r 0.30 | ±1.44 | camo detailed outer half + 6 hub bolts, steel inner drum | same |
| Sprocket (`Wheel16..17`) | 7.30 | 0.80, r 0.36, 11 teeth | ±1.44 | two chamfered steel toothed rings, camo discs and hub, 10 steel hub bolts | same |
| Road arms, idler arms, 2 return rollers | arms trail 0.42 m to the hull | rollers 1.02, r 0.10 | arms ±1.09 | dark (weathered) | same (simplest shapes, behind the skirts) |
| Track: individual shoes every 0.193 m | loop around all wheels | shoe body 0.045–0.065 m off the loop, rubber pad to the ground | 0.63 wide | track (weathered: worn edges, mud) + rubber | `track_shoe_pitch` – no shoes on the top run between x 0.52 and 6.65 (behind the skirts) |
| Skirts 7 panels per side | 0.12–7.05 | 0.62–1.24 | outer face ±1.85; front 2 panels 0.13 thick (bolt grid 3 × 4), rest 0.05 (rubber edge strip, top bolt row, stiffener); front-bottom corner raked 0.4 | camo, rubber, steel hinge knuckles, top rail | `detailed_skirts` |
| Skirt accent plate | panel 2 | 0.9–1.1 | ±1.86 | faction accent | same |
| Upper hull (profile) | nose 0 (h 1.14–1.27), glacis to 2.25 (h 1.6), deck 1.62 to 7.8, rear 7.93 | 1.14–1.62 | ±1.72 | camo | `MeshKit.profile`, chamfer 0.035 |
| Lower hull (profile) | lower front plate 0.04–0.95, belly 0.48–0.52 | 0.48–1.14 | ±1.12 | camo | profile, chamfer 0.03 |
| Front | 0–2.3 | 0.88–1.6 | – | camo / dark / glass / lens / steel / rubber | driver's hatch in its recess + 3 periscopes, glacis seam, splash strip, headlight clusters (2 lenses, guard cage), mud flaps, tow shackles, 8 bolts on the lower front plate |
| Engine deck | 4.95–7.7 | 1.62–1.73 | ±1.32 | camo / dark / steel | 3 grille doors (frames, 12 louvres each, 2 handles), 2 access plates with bolt rows |
| Rear | 7.18–8.10 | 0.82–1.76 | ±1.62 | camo / dark / steel / lens / red lens / rubber | exhaust grille with 8 louvres and frame, tail lights with guards, tow hooks and pintle, sagging tow cable with eyes, fender stowage boxes (top 1.755) with latches and hinges, APU box (rear left, top 1.75) with louvres and rearward exhaust stub, mud flaps |
| Ring guard | ring centre 3.95 | 1.62–1.68 | r 1.15 (`TURRET_RING_R`) | dark (cavity) | rod |
| **Turret** pivot | ring centre 3.95 | deck 1.62 | 0 | – | `Turret` node |
| Turret front block + 2 cheeks (lofts) | block 2.3–5.0, cheeks 1.85–3.0 (top from 2.08) with the gun recess between ±0.46 | 1.67–2.36 | ±1.66 → ±1.58 | camo, dark module seams | `MeshKit.loft`, chamfer 0.04 |
| Bustle (loft), overhangs the deck | 4.95–6.35 | 1.8–2.36, dark gap filler 1.76–1.81 | ±1.66 → ±1.44 | camo | loft |
| Roof | 2.5–6.2 | 2.36–2.64 | – | camo / dark / glass / steel | gunner's sight doghouse (doors, window, guard rods), CITV (pedestal, head, window, rain shield), loader's hatch with 3-plate LAGS shield and M240, blowout panels with frames and 24 bolts, lifting eyes, met mast, 2 antenna stubs on spring bases |
| CROWS-LP | cupola ring at (4.3, ±0.82 right) | 2.36–2.64 | r 0.48 | camo / dark / glass / steel | ring with 8 vision blocks, turntable, cradle arms, receiver, M2 lathe with handle, sight box with window, ammo box with handle, feed chute |
| Bustle rack + stowage | 6.3–7.18 | 1.78–2.5 | ±1.48 | steel rails / dark slatted floor / faction cloth bags (3 pillows, tarp roll with 3 straps) / camo ammo cans and jerrycan / dark cargo straps | tubes, slabs, `pillow`, lathe |
| Turret sides | 2.85–6.22 | 1.77–2.32 | ±1.62–1.92 | camo / dark / steel / accent | bustle side boxes with lids, latches, hinges and faction plate; M250 2 × 3 smoke tubes on a base plate; 4 grab handles; 2 tie rings |
| **Gun** pivot (trunnions) | 2.3 | 1.98 | 0 | – | `Turret/Gun`, level |
| Gun shield + mantlet cover | 1.8–2.44 | 1.74–2.24 | ±0.43 | camo with 4 bolts / faction cloth with 3 folds | on `Gun` |
| Coax M240 port, ammunition data link box | 1.77–2.3 | 1.9 / 2.22–2.3 | 0.27 / −0.22 | dark | on `Gun` |
| **Barrel** pivot (identity at the gun pivot, TASK-048 recoil) | – | – | – | – | `Turret/Gun/Barrel` |
| M256 barrel (lathe): collar r 0.13, thermal sleeve sections r 0.094–0.122, muzzle lip r 0.1 | 1.8 → muzzle −1.84 | 1.98 | 0 | camo + 3 steel clamp bands | on `Barrel` |
| Bore (cavity), muzzle reference sensor | −1.84 / −1.72…−1.54 | 1.98 / 2.06–2.14 | 0 | dark | on `Barrel` |
| `Turret/Gun/Muzzle` | −1.89 | 1.98 | 0 | – | marker node |
| `Exhaust` / `Dust_L` / `Dust_R` anchors | 7.98 / 7.3 / 7.3 | 1.35 / 0.02 / 0.02 | 0 / −1.44 / +1.44 | – | `Marker3D` under the model root (MotionFx) |

Mesh instances: 21 outside the wheel pivots (hull 9: body, dark, track, rubber, steel, accent, glass,
lens, red lens; turret 6: body, dark, glass, steel, cloth, accent; gun 3: body, cloth, dark; barrel
3: body, dark, steel), 2 per wheel pivot (body + rubber / steel). Materials:
`VehicleFrame.kit_tank_materials` – faction camo, weathered one-colour `dark` and `track` (camo
shader: wear, dust, mud), plain PBR steel / rubber / glass, lens colours, faction cloth.

Triangles: **35 682** for every faction (was 21 460 after TASK-062, 14 184 before): hull 16 608
(body 4 528, track shoes 4 224, steel 3 128, dark 2 596, rubber 1 768), turret + gun 9 970, wheel
pivots 9 104 (road wheel 404 each, idler 364, sprocket 1 360). Cold build ~120–135 ms (was
~31–34 ms); a second faction reuses the cached geometry (~1.3 ms).

Hidden-geometry cuts: no track shoes on the top run behind the skirts; inner road-wheel / idler
halves are plain drums; road arms, idler arms and return rollers are plain boxes / rods; the study's
fender lip and fender brackets (behind the skirt top) are left out; the lower hull ends at the upper
hull's floor (h 1.14) instead of overlapping into it; nothing is built inside the shell
(`HULL_INTERIOR` = x 1.5–5.8, h 0.7–1.45, z ±0.9 m is empty; `test_tank_models.gd`).

## Silhouette features

1. **Low, flat, wide angular turret with a sloped wedge front and a long bustle** – the study's
   lofts: main block with the two armour cheeks ahead of it (gun recess between them), chamfered
   roof edges; the bustle's underside is 0.18 m above the engine deck (dark gap filler) so the
   overhang reads as a shadow line; the bustle rack with bags extends it to 7.18 m.
2. **Long 120 mm gun without fume extractor, 1.84 m beyond the hull** – lathe barrel with thermal
   sleeve sections, three clamp bands, muzzle reference sensor near the muzzle.
3. **Low CROWS RWS on the commander's position, loader's M240 shield** – CROWS-LP with vision blocks,
   cradle, M2 and sight box on the right; three-plate LAGS shield with the M240 on the left.
4. **7 road wheels + 2 return rollers, rear sprocket, front idler, deep skirts** – shared running
   gear with kit detail; skirts hang to 0.62 m, so only the lower half of the wheels and the hubs
   show (as in the photo); two bolted armoured front panels with a raked front-bottom corner.
5. **Long, flat, low hull, near-horizontal deck, box-like rear grille** – chamfered profiles
   (shallow glacis 1.27 → 1.6 m over 2.25 m, flat deck to the rear), grille doors on the deck,
   louvred exhaust grille with the tow cable on the rear plate.
6. **Smoke dischargers on both turret sides, APU exhaust rear left** – 2 × 3 capped tubes on each
   turret side; APU box with louvres and a rearward exhaust stub at the rear left of the deck.

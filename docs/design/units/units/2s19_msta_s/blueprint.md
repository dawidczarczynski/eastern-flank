# 2S19 Msta-S – model blueprint

Model: `src/presentation/models/2s19_msta_s.gd`, built with `MeshKit` / `MeshKits` like the K9
Thunder (chamfered primitives, vertex masks for the weathering paint); shared running gear
`src/presentation/models/parts/tracked_running_gear.gd` (kit options `detailed_wheels`,
`track_shoe_pitch`, all-steel shoes `track_pads = false`; no skirts: `skirt_panels = 0`; front idler
`idler_arm_dir = 1`, rear drive sprocket); metre -> model conversion `parts/vehicle_frame.gd`.
Materials: `Frame.kit_tank_materials` (faction camo `body`, faction `accent`, weathered `dark` /
`track`, PBR `steel` / `rubber` / `glass`, `lens`, `red_lens`).

Reference: the Meshy GLB `reference.glb` (not in git), normalised to 12.0 m by
`tools/analyze_glb.sh` (scale 6.31): `reference_views/glb_*.png`, `measurements.json`. Its
camouflage is ignored: the faction camo comes from `ModelParts`.

## Scale

Real 12.0 m overall (muzzle to the rear unditching log, gun level) × 3.38 m × 2.99 m (catalog).
Scaled uniformly by `K = 0.073` model units per metre (same as the K9: the 47-calibre gun makes it
as long): 0.876 × 0.247 × 0.22 units before `MODEL_SCALE` (1.139 long at 1.3; budget 1.15).

Origin: model x = 0 at x = (7.6 − 4.4) / 2 = 1.6 m from the hull nose, so muzzle (x −4.4) to the
log (x 7.6) is centred. Parts are in vehicle metres (`x` from the hull nose backwards, `h` above the
ground, `z` positive = vehicle's right).

Widths: the GLB is 3.86 m wide, 14 % more than the catalog's 3.38 m; every half width from
`measurements.json` is scaled by 3.38 / 3.86 = 0.875 (hull 1.884 -> 1.66, turret 1.827 -> 1.56,
track centre 1.52 -> 1.36, track 0.58 -> 0.56). Heights: the GLB's turret roof is 3.25 m, the
catalog's 2.99 m wins (roof at 3.0 m); hull, wheels and track keep the reference's heights.

## Constants: source

| Constant | Value (m) | Source |
|---|---|---|
| `DECK_H` | 1.63 | measurements.json (0.66) |
| `GUN_OVERHANG` | 4.4 | measurements.json 4.385 (0.8), gun level instead of 6.6° up |
| hull rear plate `REAR_X` / log | 7.15 / 7.6 | catalog hull length; GLB `HULL_LENGTH` 7.61 incl. the rear log |
| `UPPER_HW`, `TURRET_HW`, `track_z`, `track_width` | 1.66, 1.56, 1.36, 0.56 | measurements.json × 0.875 |
| `TURRET_FRONT` / `TURRET_REAR` | 2.05 / 6.15 | measurements.json 2.0 / 6.2 (0.6) |
| `TURRET_X` | 4.1 | measurements.json 4.098 |
| `ROOF_H` | 3.0 | catalog height (GLB 3.25, confidence 0.45, incl. MG / hatches) |
| `TRUNNION` | (2.85, 2.45) | by eye: GLB barrel meets the mantlet at (2.1, 2.53) with the gun 6.6° up; the trunnion lies ~0.75 m behind, the level bore a bit lower |
| road wheels | x 1.29, 2.19, 3.34, 4.2, 4.9, 5.71; r 0.33; h 0.41 | measurements.json `ROAD_WHEELS` x without its first (0.45 = idler) and last (6.57 = sprocket) entry; r / h by eye (T-80 wheel 0.67 m) |
| idler / sprocket | x 0.45 h 0.7 r 0.27 / x 6.55 h 0.72 r 0.31 | GLB side view by eye |
| `NOSE_H`, `GLACIS_X`, `SPONSON_H` | 1.12, 1.2, 0.98 | `profiles.hull` / side view by eye |
| fume extractor, muzzle brake | 1.06–1.99 m ahead of the nose; brake 0.62 m | side view by eye |

## Pivots and anchors

| Node | Where | Notes |
|---|---|---|
| `Wheel0..11` | road wheels (above), z ±1.36 | one mesh set per side |
| `Wheel12..13` | idlers x 0.45 (front) | |
| `Wheel14..15` | drive sprockets x 6.55 (rear) | |
| `Turret` | ring centre x 4.1, deck h 1.63 | turns about local Y |
| `Turret/Gun` | trunnions x 2.85, h 2.45 (level) | mantlet, cradle sleeve, recoil cylinders |
| `Turret/Gun/Barrel` | identity at the gun pivot | barrel, fume extractor, muzzle brake (recoil 0.5 m) |
| `Turret/Gun/Muzzle` | x −4.45, h 2.45 | 0.05 m in front of the muzzle brake |
| `Exhaust` | x 7.19, h 1.35, z 0 | exhaust louvres on the rear plate (T-80 family) |
| `Dust_L` / `Dust_R` | x 6.55, h 0.02, z ∓1.36 | track bottom at the sprockets |

Mechanisms (copied from the catalog): `wheels`, `turret_traverse` (full, −4..68°), `gun_recoil`
(0.5 m).

Turret sweep: turret floor 1.72 m; the farthest turret corner is 2.6 m from the ring (the rear
conveyor 3.1 m); everything on the deck inside that radius stays at or under 1.71 m (stowage bins
1.70, grilles 1.69).

## Parts (metres)

- **Upper hull**: side profile (0.02, 0.98) – nose (0, 1.12) – glacis to (1.2, 1.63) – deck to
  (6.9, 1.63) – rear drop (7.15, 1.5) – (7.15, 0.98), half width 1.66; fender lips at the sponson
  bottom (z ±1.64) with a dark rubber flap strip. **Lower hull** (0.06, 1.05) – (0.85, 0.42) –
  (6.85, 0.42) – (7.1, 0.72) – (7.1, 1.1), half width 1.05.
- **Front**: V splash board on the glacis, headlights at z ±1.38, tow hooks, bolt row on the lower
  plate, the travel lock folded on the glacis (A-frame + clamp).
- **Deck**: driver's hatch low on the glacis front left (x 0.95, z −0.62) with 3 periscopes,
  bolted access plate front right, two louvred engine grilles behind the turret (x 6.2–6.85).
- **Sides**: faction accent plate (x 2.6–3.3, h 1.15–1.5) on both hull sides, low stowage bins on
  the deck edges, grab handles.
- **Rear**: exhaust louvres, tail lights, tow hooks, the unditching log (r 0.15, 2.9 m) on brackets
  at x 7.45, h 1.25.
- **Turret**: tapered loft, floor 1.72, roof 3.0; floor plan front x 2.05 (face ±0.85, cheeks
  chamfered back to full width ±1.56 at x 2.55) to rear x 6.15; roof plan x 2.5 (±0.75) to 6.1,
  half width 1.42 (walls lean in, face raked back); dark ring gap r 1.3; gun port recess.
- **Roof**: commander's cupola (x 3.95, z +0.25, r 0.42) with vision blocks and the remote **NSVT
  12.7 mm** on a pedestal (axis h 3.62, barrel 1.5 m forward); loader's hatch (x 4.85, z −0.45);
  gunner's sight head (x 3.22, z −0.95); vent dome, periscope box, bolted plate over the breech,
  lifting eyes; a short antenna whip (1 m) at x 4.65, z +0.75 instead of the GLB's 4 m mast.
- **Turret sides**: left side door with hinges and handle, grab rails, 6-tube smoke grenade
  launchers on both front corners, faction accent plate (x 3.5, h 2.25) on both walls, direct-fire
  sight box on the front face.
- **Ammunition conveyor** (folded, rear of the turret): two side rails (parallelogram (5.7, 3.45)
  – (7.15, 2.55) – (6.9, 1.95) – (5.95, 3.0)) at z 0.15 ± 0.5, a dark belt plate, 6 rungs, hinge
  bracket and two struts down to the bustle.
- **Gun** (`Turret/Gun`): box mantlet 0.6 × 0.66 × 0.84 around the bore at the front face, cradle
  sleeve r 0.2 out to x 0.95 with a steel collar, two recoil cylinders r 0.09 above (h +0.3).
- **Barrel** (`Turret/Gun/Barrel`): lathe r 0.17 at the breech end, r 0.13 tube, fume extractor
  r 0.17 between 1.06 and 1.99 m ahead of the nose, r 0.12 to the muzzle, 4-baffle muzzle brake
  r 0.175 (0.62 m) with 3 dark ports, dark bore, steel collar 0.12 m ahead of the nose.

## Silhouette features

1. Large, tall, flat-sided turret with rear bustle at the rear of the hull: the loft covers x
   2.05–6.15 of a 7.15 m hull, almost the full hull width, 1.28 m tall; the folded conveyor makes
   the rear outline.
2. Long L/47 barrel with multi-baffle brake and mid-barrel fume extractor: 7.25 m lathe from the
   trunnion, 4.4 m beyond the nose; the extractor and the brake are the two thick sections.
3. Tracked hull, 6 road wheels per side, rear drive sprocket (T-80 running gear): 6 kit wheels with
   the gap between the 2nd and 3rd, front idler, rear sprocket, all-steel shoes.
4. NSVT on the roof: on the commander's cupola, the highest point of the model (3.62 m).
5. Low driver position front left: hatch with periscopes on the glacis at z −0.62.

## Budget

27 916 triangles, 19 body mesh instances (51 with the wheel pivots), far_triangles 14 702,
cold build ~145 ms.

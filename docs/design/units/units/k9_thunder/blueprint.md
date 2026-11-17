# K9 Thunder (K9PL) – model blueprint

Model: `src/presentation/models/k9_thunder.gd`, built with `MeshKit` / `MeshKits` like the T-72B3
and M1A2 (chamfered primitives, vertex masks for the weathering paint); shared running gear
`src/presentation/models/parts/tracked_running_gear.gd` (kit options `detailed_wheels`,
`track_shoe_pitch`; no skirts: `skirt_panels = 0`; new option `idler_arm_dir = -1` for a rear
idler whose arm runs forward); metre -> model conversion `parts/vehicle_frame.gd`. Materials:
`Frame.kit_tank_materials` (faction camo `body`, faction `accent`, weathered `dark` / `track`, PBR
`steel` / `rubber` / `glass`, `lens`, `red_lens`).

References: `side_1.png` (orthographic side render of the Meshy AI model, gun to +X) and the full
Meshy model `k9.glb` (kept outside the repo), measured by vertex slices at 6.3 m per glb unit
(its hull length 7.4 m matches the catalog's 7.44 m). The reference camouflage is ignored: the
faction camo comes from `ModelParts`.

## Scale

Real 12.0 m overall (muzzle to the turret rear basket, gun level) × 3.4 m × 2.73 m. Scaled
uniformly by `K = 0.073` model units per metre: 0.876 × 0.248 × 0.2 units before `MODEL_SCALE`
(1.139 × 0.32 × 0.26 after; length budget 1.15). An SPH with a 52-calibre barrel is much longer
than a tank, so it is drawn smaller per metre than the T-72B3 (`K` 0.087) to fit the footprint.

Origin: model x = 0 at x = (7.94 − 4.06) / 2 = 1.94 m from the hull front, so muzzle (x −4.06)
to rear basket (x 7.94) is centred. Parts are in vehicle metres (`x` from the hull nose
backwards, `h` above the ground, `z` positive = vehicle's right).

Heights: the Meshy model is ~4 % too tall (turret roof 2.85 m); the catalog's 2.73 m wins, so the
turret roof is at 2.72 m and the hull, wheels and track keep the reference's heights.

## Pivots and anchors

| Node | Where | Notes |
|---|---|---|
| `Wheel0..11` | road wheels x 1.57, 2.47, 3.34, 4.24, 5.12, 5.99; h 0.42; z ±1.375 | one mesh set per side |
| `Wheel12..13` | idlers x 6.99 (rear), h 0.74 | |
| `Wheel14..15` | drive sprockets x 0.6 (front: the K9's power pack is front right), h 0.72 | |
| `Turret` | ring centre x 5.2, deck h 1.82 | turns about local Y |
| `Turret/Gun` | trunnions x 3.94, h 2.22 (level) | mantlet, cradle / recoil sleeve |
| `Turret/Gun/Barrel` | identity at the gun pivot | barrel, bore evacuator, muzzle brake (recoil 0.5 m) |
| `Turret/Gun/Muzzle` | x −4.11, h 2.22 | 0.05 m in front of the muzzle brake |
| `Exhaust` | x 1.6, h 1.62, z +1.66 | exhaust grille on the right hull side by the engine |
| `Dust_L` / `Dust_R` | x 6.99, h 0.02, z ∓1.375 | track bottom at the rear |

Mechanisms (copied from the catalog): `wheels`, `turret_traverse` (full, −8..20°), `gun_recoil`
(0.5 m).

Turret sweep: the turret floor is at 1.88 m, everything on the deck inside its sweep radius
(2.8 m around x 5.2, i.e. x 2.4 – 7.94) stays under 1.87 m.

## Parts (metres)

| Part | x (from front) | h | z / half width | Material | Built with |
|---|---|---|---|---|---|
| Upper hull (sponsons over the tracks, long low glacis) | nose 0 → glacis to 2.5 → deck → rear plate 7.1 | 1.2 – 1.82 (nose 1.35 – 1.47) | ±1.65 | body | `profile` |
| Lower hull between the tracks | 0.05 – 7.1, belly from x 0.65 to 6.9 | 0.42 – 1.35 | ±1.08 | body | `profile` |
| Track | loop from the sprocket front (x 0.19) to behind the idler (x 7.37) | 0 – 1.15 | z ±1.375, 0.55 wide | track | gear kit shoes, pitch 0.2 |
| Road wheels ×6 per side, dual, rubber tyres | see pivots | r 0.34 | 0.5 wide | body / rubber | gear kit |
| Return rollers ×3 per side | 2.0, 3.8, 5.55 | h 0.98, r 0.09 | | dark | gear kit |
| Turret box (tapered loft: sides lean in, front corners chamfered, front face raked back) | floor 3.24 – 7.54, roof 3.7 – 7.5 | 1.88 – 2.72 | ±1.5 floor, ±1.36 roof, front face ±0.55 | body | `loft` |
| Rear basket (stowage cage) | 7.54 – 7.94 | 2.0 – 2.6 | ±1.1 | dark / steel | slabs + tube frame |
| Mantlet | 3.0 – 3.4 | 1.98 – 2.46 | ±0.36 | body | `slab` on `Gun` |
| Cradle / recoil sleeve | 3.1 → 0.15 | axis 2.22 | r 0.19 | dark | `rod` on `Gun` |
| Barrel | trunnion −0.6 → muzzle −4.06 | | r 0.125 → 0.11 | body | `lathe` on `Barrel` |
| Bore evacuator | −0.26 … −0.96 | | r 0.2 | body | in the barrel lathe |
| Double-baffle muzzle brake | −3.46 … −4.06 | | r 0.17, two baffles, dark slots | body / dark | lathe + slot boxes |
| Commander's cupola + K6 12.7 mm MG | 6.6, z +0.75 | 2.72 – 2.95 | r 0.38 | body / dark / steel | rods, lathe |
| Gunner's hatch, panoramic sight | 5.4, z +0.6 / 4.2, z −0.75 | 2.72 – 2.95 | | body / glass | rods, slabs |
| Loader's hatch | 6.4, z −0.8 | 2.72 – 2.78 | r 0.3 | body | rods |
| Turret left side door | 5.3 – 6.3 | 2.0 – 2.6 | z −1.5 face | body / dark seam | slabs |
| Antennas | 7.35, z ±1.15 | to 4.4 | whip r 0.015 | dark / steel | tube |
| Smoke launchers (4 per side) | 3.6 – 3.95 front corners | 2.35 | | dark | lathe |
| Driver's hatch (front left) with periscopes | 1.45, z −0.95 | 1.65 – 1.72 | r 0.33 | body / glass | rods |
| Engine grilles (front right) | 0.9 – 2.3, z +0.35 … +1.45 | on the glacis | | dark louvres | slabs / cbox |
| Exhaust grille | 1.2 – 2.0 | 1.45 – 1.75 | right side face | dark | slabs |
| Headlights, tow hooks, front plate bolts | 0 – 0.3 | 0.9 – 1.6 | | body / lens / steel | rods, arcs |
| Travel lock (folded down on the glacis) | 0.25 – 1.3 | | z 0 | dark / steel | tubes |
| Large rear door (ammunition resupply) | rear plate 7.1 | 0.6 – 1.68 | ±0.6 | body / steel hinges | slabs |
| Tail lights, rear tow hooks | 7.1 | 1.0 – 1.6 | | red_lens / steel | slabs, arcs |
| Faction plate (Polish flag position) | 1.9 – 2.45 | 1.42 – 1.66 | hull side z ±1.65 | accent | slab pair |

## Silhouette features

1. **Large tall box turret at the rear with a flat bustle**: the turret loft covers 53 % of the
   hull length from x 3.24 to 7.54 and overhangs the rear plate by 0.44 m, plus the rear basket
   to 7.94; 0.84 m tall over a 1.82 m deck, nearly the full hull width.
2. **Long 52-calibre barrel with a double-baffle muzzle brake, overhanging the hull front**:
   4.06 m of overhang, the thick dark recoil sleeve, the bore evacuator band and the brake with
   two slotted baffles.
3. **Low short hull front, driver front left, engine right**: the long 12° glacis from the deck
   down to the nose at 1.47 m, driver's hatch on the left, louvred engine grilles on the right.
4. **Six dual road wheels, three return rollers**: shared gear with exposed top run (no skirts);
   drive sprocket at the front (real K9: front power pack). The catalog text says "rear drive
   sprocket" – the reference model and the real vehicle have the toothed wheel at the front.
5. **Commander and gunner hatches on the turret right with the roof MG, door on the left**:
   cupola with the K6 on the right rear roof, gunner's hatch ahead of it, loader's hatch on the
   left, a door outline on the left turret wall.
6. **Large rear hull door**: a framed door with hinges over most of the rear plate.

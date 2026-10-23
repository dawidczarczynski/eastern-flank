# TASK-069: Tank v3 – rework `m1a2_sepv3` / `t72b3` after the M1A2 study (chamfers, small parts, hidden geometry cut, ≤ 40k)

- **Status**: ready (specified 2026-10-23; waits for TASK-062 – the paint the kit masks drive)
- **Layers**: presentation (`models/m1a2_sepv3.gd`, `models/t72b3.gd`, `models/parts/tracked_running_gear.gd`, `MeshKit` / `MeshKits` only if a primitive is missing), tests (`test_unit_model_contract.gd`, `test_unit_models.gd`, new `test_tank_models.gd`), docs (both `blueprint.md`). Roles: **unit-modeler** (both tanks, render-compare, via `/model-unit <id>` as a rework); **presentation-engineer** only if a kit primitive or the shared running gear needs new options.
- **Depends on**: **TASK-030** (mesh kit v2, ADR 0012 – done), **TASK-062** (weathering paint on the RGB vertex masks, chamfers in the old helpers). Soft: TASK-063 (`Marking_*` / `Number_*` anchors – add them here if 063 is done first), TASK-034 (portraits show the tanks close up), TASK-047 / TASK-048 (turret traverse / gun recoil use the pivots kept and added here).
- **Model**: opus (two large models plus the shared running gear, triangle and build-time budgets, pivot contract)

## Goal

The two main battle tanks look like used steel vehicles instead of plastic box kits when the player zooms in or looks at a unit portrait – rounded edges that catch the light, bolts, hinges, cables, rails, track shoes – while they read exactly as before from the battle camera and still cost no frame rate and no noticeable hitch at battle start.

## Reference

- `docs/design/showcase/m1a2_showcase.gd.txt` – the M1A2 SEPv3 study after the cuts (~32 600 triangles, ~320 ms cold build with the study kit; ADR 0012: the re-port on `MeshKit` reproduced 32 586 triangles and built faster). Same measurements and constants as today's `m1a2_sepv3.gd`. Sections: hull (profile with chamfered rims, engine deck, rear grille, front), running gear (outer wheel halves detailed, inner halves plain drums, road arms), track (individual "lite" shoes, no shoes on the top run behind the skirts), skirts (plates with chamfered rims, bolt grids on the armoured panels, rubber edge strips, hinge knuckles, top rail), turret (front block, roof, CROWS-LP with vision blocks, bustle with rack and bags, side boxes), gun (mantlet, M256 with thermal sleeve). Materials per role: `body`, `dark`, `steel`, `rubber`, `track`, `cloth`, `glass`, `lens`, `red_lens`, `white`, `red`.
- `docs/design/showcase/m1a2_cut_hero.jpg` (target look), `m1a2_max_hero.jpg` / `m1a2_max_rear.jpg` (the 104k maximum – what the cut version must still look like), `README.md` (findings: chamfers + small parts + used paint remove the toy look; hidden geometry is where triangles go).
- ADR 0010 (≤ 40 000 triangles per vehicle, cold build ≤ 500 ms, spend triangles where the camera looks), ADR 0012 (one shared kit, vertex mask meaning `r` edge / `g` openness / `b` tint seed, chamfers in geometry).
- Catalog: `docs/design/units/units/m1a2_sepv3/` (`unit.json` – dimensions 7.93 / 9.77 × 3.7 × 2.4 m, silhouette features; `side_1.jpg`; `blueprint.md` – part table, K = 0.088, deliberate deviations) and `docs/design/units/units/t72b3/` (`unit.json` – 6.86 / 9.53 × 3.59 × 2.226 m; `drawing_1.jpg`; `blueprint.md`, K = 0.087). The T-72B3 has no study: apply the same techniques to its blueprint.
- `docs/design/units/mechanisms.json` – `turret_traverse` (pivots `Turret`, `Turret/Gun`, `Turret/Gun/Muzzle`) and `gun_recoil` (pivot `Turret/Gun/Barrel`).
- Tools: `tools/render_unit.sh <id> [--faction] [--reference]` (sheet + `Stats` / `Real` lines), `/model-unit <id>` (rework flow: unit-modeler, verify, reviewer).

## Current state (before)

| Model | Triangles | Body mesh instances | Wheel pivots | Cold build |
|---|---|---|---|---|
| `m1a2_sepv3` | 14 184 | 15 | 18 (`Wheel0..17`) | record before starting |
| `t72b3` | 15 544 | 14 (+1 skirt edge strip) | 16 (`Wheel0..15`) | record before starting |

Both build from `VehicleFrame` / `ModelParts` parts merged per material plus the shared `TrackedRunningGear` (a single track loop band with grousers, lathe wheels, prism skirts). After TASK-062 those helpers already chamfer and write masks; this task replaces the coarse parts with the study's parts and cuts what is hidden. Neither model has `Exhaust` / `Dust_L` / `Dust_R` anchors yet (TASK-064 left them for a model rework; `MotionFx` falls back to the model bounds).

## Design

- **Kit and paint**: build both tanks through `MeshKits` (one kit per material role per pivot; ADR 0012). No own copy of the study's `Kit` / `Kits` classes and no `showcase_paint` shader – the paint is TASK-062's `camo.gdshader`; the study's per-material parameters (wear, metallic, dust, mud on the track) go into the tank materials (`VehicleFrame.tank_materials` or the model's material dictionary) as shader parameters. Missing primitives go into `MeshKit` with a test in `test_mesh_kit.gd`, not into the model files.
- **Shared running gear**: both tanks keep using `TrackedRunningGear` (`Spec`), extended with the study's parts as options with defaults that leave other users unchanged: detailed outer wheel half (dished disc, tyre, hub cap, bolt ring) + plain inner drum, road arms, idler and sprocket with hub bolts, return rollers as plain rods, individual track shoes (steel body + rubber pad, step from the spec, e.g. 0.193 m for the Abrams) on the visible runs only, skirt panels as chamfered plates with bolt grids / edge strips / hinge knuckles / top rail. One road-wheel mesh per side is built once and shared by every road-wheel pivot (build time). The `Wheel*` pivot layout and spin stay as today (counts 18 / 16).
- **M1A2 SEPv3**: port the study section by section onto `MeshKits`, keeping today's constants (`HULL_LENGTH`, `K`, `TURRET_X`, `DECK_H`, `ROOF_H`, `TRUNNION`, half widths) and the blueprint's deliberate deviations (roof add-ons capped at 2.64 m, antenna stubs). Faction accent plate and faction cloth for the bags as today.
- **T-72B3** (no study, same rules): rounded cast turret dome from smooth primitives (`pillow` / `loft` / `lathe`, no faceted box), Kontakt-5 wedge blocks as chamfered boxes with bolt rows and visible gaps, Sosna-U housing with window and armoured doors, NSVT on its mount, IR lamp, wind sensor mast, snorkel tube, rear and side stowage bins with lids and latches, fender fuel tanks, unditching log and the two rear fuel drums (lathes with rims and ribs), K-5 on the glacis, front mudguard flap, rubber skirts over the top run as thin plates with a rubber edge. Six large road wheels show mostly uncovered – detail them (dished disc, hub, bolts) and keep the inner halves plain.
- **Small parts** (both, where the camera sees them): bolts and hinges on hatches and panels, grab handles and rails on the turret, tow cables on the hull (`tube`), tow hooks, headlight guards, periscopes / vision blocks, smoke dischargers as tubes with caps, antenna bases.
- **Hidden geometry cut** (ADR 0010 rule, study findings): no track shoes on the top run between the skirt ends, inner wheel halves as plain drums, return rollers and suspension behind the skirts as the simplest shape, nothing inside the hull or turret shell, no faces under parts that sit flush on another part. Each tank declares `HULL_INTERIOR: AABB` (vehicle metres: x from the front, h, z) – a box strictly inside its armour shell, at least 4.0 m × 0.6 m × 1.6 m (x × h × z) – used by the hidden-geometry test.
- **Mechanisms**: pivots as today – `Turret` at the ring centre turning about its local Y, `Turret/Gun` at the trunnions (hinge = local Z, level as built), `Turret/Gun/Muzzle` at the barrel end. New: the barrel parts (thermal sleeve, muzzle, bore, muzzle reference sensor) go under a `Turret/Gun/Barrel` `Node3D` (identity transform at the gun pivot origin) so TASK-048 can slide it back; mantlet and coax stay on `Gun`, `Muzzle` stays where the test expects it. Each tank declares `TURRET_CLEARANCE_H` (metres: the lowest turret / bustle / rack underside outside the turret ring) for the sweep test below.
- **Anchors** (TASK-064 pass): `Exhaust` (M1A2: rear grille centre, ~x 7.95, h 1.2, z 0; T-72B3: the exhaust on the left fender from its blueprint) and `Dust_L` / `Dust_R` (bottom of the track at the rear, under the sprockets) as `Marker3D` children of `Model`. If TASK-063 is done first, also its `Marking_*` / `Number_*` anchors per its spec.
- **Budget**: ≤ 40 000 triangles per tank for every faction (study: ~32 600), ≤ 24 body mesh instances, cold build ≤ 500 ms (contract) with a target of ≤ 350 ms each to keep headroom on slower machines (ADR 0010 consequence). If a tank goes over, cut detail where the camera never looks first (track shoe step, inner parts, bolt counts on hidden faces, lathe sides of small parts), never the silhouette.
- **Silhouette and scale unchanged**: same `K`, same origin, same `LABEL_HEIGHT`; the battle-camera read must not change.

## Acceptance criteria (testable)

- [ ] **Contract**: `test_unit_model_contract.gd` passes unchanged (limits as today: `MAX_TRIANGLES_VEHICLE = 40000`, `MAX_BODY_MESH_INSTANCES = 24`, `MAX_BUILD_MSEC = 500`, ground / centre / length / width / label checks, no waivers added) for both tanks and every faction in `data/factions/`; `test_m1a2_sepv3_gun_pivots_and_all_wheels_spin` (18 wheels) and `test_t72b3_gun_pivots_and_all_wheels_spin` (16 wheels) pass unchanged.
- [ ] **Triangles** (from `Stats` of `tools/render_unit.sh` and the contract print): each tank ≤ 40 000 and ≥ 22 000 (the rework actually adds the study's detail); before/after per faction recorded in the notes and in both `blueprint.md` files.
- [ ] **Cold build**: `test_every_model_builds_cold_within_the_time_budget` passes; both times (before/after) recorded in the notes; target ≤ 350 ms each – if over, the notes say where the time goes.
- [ ] **Built with the kit**: every `MeshInstance3D` of both tanks holds an `ArrayMesh` (no `BoxMesh` / `CylinderMesh` / `PrismMesh` / other `PrimitiveMesh`); every mesh whose material is not glass / lens has `ARRAY_COLOR`, with at least one vertex `r ≥ 0.99` (chamfer bands present) and all `g`, `b` in [0, 1] (new `test_tank_models.gd`).
- [ ] **No interior geometry**: with turret and gun at rest, no triangle of either tank (any mesh, transformed into model space) has all three vertices inside its `HULL_INTERIOR` box (converted with the model's `VehicleFrame`); the box is at least 4.0 × 0.6 × 1.6 m.
- [ ] **No track shoes behind the skirts**: on each side, the track-material triangles whose centroid lies in x ∈ [`skirt_x0` + 0.5, `skirt_x1` − 0.5] m and h > the road-wheel tops (`road_wheel_h` + `road_wheel_radius`) number ≤ 24 (none or one plain band).
- [ ] **Plain inner wheel halves**: for every road-wheel pivot, the triangles whose normal points towards the hull centre line (inward z component > 0.5 in model space) are ≤ 40 % of the pivot's triangles.
- [ ] **Turret sweep clearance** (turret traverse, TASK-047): no vertex of a mesh outside the `Turret` and `Wheel*` pivots that lies within the turret's swept circle (radius = the largest horizontal distance of any `Turret` vertex from the ring centre) and outside the turret ring is higher than `TURRET_CLEARANCE_H`; and `TURRET_CLEARANCE_H` > the highest such vertex by ≥ 0.01 m – tested for both tanks. Rotating `Turret` by 90° / 180° / 270° changes no hull mesh and keeps the model's ground check (`min_y` within ±0.005).
- [ ] **Gun and recoil pivot**: `Turret/Gun/Barrel` exists on both tanks, is a `Node3D` with identity transform, holds ≥ 1 mesh, and its meshes reach the muzzle (the front end of the barrel meshes' AABB is within 0.1 m – in vehicle metres, i.e. 0.1 × `K` model units – of `Turret/Gun/Muzzle`'s x; the muzzle marker sits 0.05 m beyond the barrel today); `Turret/Gun` itself still holds the mantlet mesh(es); the gun is level when built.
- [ ] **Anchors**: both tanks have `Exhaust`, `Dust_L`, `Dust_R` `Marker3D` nodes under `Model`, inside the model AABB; `Dust_L` has negative z, `Dust_R` positive z (model space); `Exhaust` x is in the rear 25 % of the hull length for the M1A2.
- [ ] **Silhouette unchanged**: the `Stats` AABB of each tank differs from the pre-rework AABB by ≤ 3 % on every axis; the `Real` diff stays within ±2 percentage points of the values in the blueprints; `LABEL_HEIGHT` unchanged (label test passes).
- [ ] **Shared meshes**: `test_same_faction_shares_meshes_other_faction_other_camo` and `test_cached_copies_have_independent_node_trees` pass; the road-wheel pivots of one side share one mesh resource (test).
- [ ] **Running gear options are opt-in**: `test_tracked_running_gear_builds_from_other_parameters` and `test_skirt_rear_rake_and_edge_are_opt_in` pass unchanged; a `Spec` with default values builds the same child count as before the task.
- [ ] **Render compare** (unit-modeler, sheet paths in the notes, all four views side / front / top / three_quarter):
  - `tools/render_unit.sh m1a2_sepv3 --faction=poland --reference=docs/design/units/units/m1a2_sepv3/side_1.jpg` and `--reference=docs/design/showcase/m1a2_cut_hero.jpg`;
  - `tools/render_unit.sh t72b3 --faction=russia --reference=docs/design/units/units/t72b3/drawing_1.jpg`;
  - each tank also once with the other faction (camo still reads);
  - checked on the sheets: chamfered edges catch light, worn edges lighter, cavities darker, track shoes and bolts visible on the visible runs and panels, no holes, no inverted faces, no floating parts, silhouette features 1–6 of each blueprint still recognisable.
- [ ] **Battle**: `tools/screenshot.sh` with a close-up crop (`SCREENSHOT_CAMERA=1,-40,5`) and the default camera read; the render stats of the screenshot probe recorded (triangles drawn, FPS on the Windows build) – no drop below 60 FPS with all units on screen. `docs/images/gameplay.png` re-rendered with `tools/readme_screenshot.sh`, Read, committed with the change.
- [ ] **Docs**: both `blueprint.md` files updated (part table, triangles, mesh instances, the hidden-geometry cuts, the `Barrel` pivot, anchors; drop the "no bevels" deviation); catalog `status` stays `modeled`.

## Playtest (for the human)

1. Start a battle: no noticeable hitch when the first M1A2 and T-72B3 appear (compare with before).
2. Zoom in on an M1A2: rounded hull and turret edges with highlights, worn paint on corners, bolts on the front skirt panels, individual track shoes under the skirts, CROWS with vision blocks, bustle rack with bags, tow cables; nothing looks like a plain box.
3. Zoom in on a T-72B3: rounded cast turret, sharp Kontakt-5 wedges with gaps, Sosna-U box, fuel drums with rims, large road wheels with bolts, rubber skirts.
4. Orbit the camera around both, low and high: no holes, no see-through gaps where hidden parts were removed (look under the skirts from a low angle, at the wheel backs from the front), no flickering.
5. Move both tanks: wheels spin, the hull rocks, dust and exhaust come from the right places (M1A2 rear grille, T-72 left side).
6. Zoom out to the normal battle camera: both tanks read the same as before (silhouette, size, camo).
7. Hover a tank for the unit popup portrait (if TASK-034 is done): the detail shows there.
8. FPS counter with all units on screen: still 60 FPS.

## Player manual

None (visual only – unit stats, rules and controls do not change).

## Out of scope

- Turret traverse and gun elevation animation (TASK-047), recoil and muzzle flash (TASK-048) – this task only keeps and adds their pivots.
- Markings and tactical numbers (TASK-063 – only its anchors if 063 lands first), burnt wrecks (TASK-065), per-faction weathering presets.
- Animated track shoes (the track stays a static loop), suspension travel, crew figures, opening hatches.
- Other vehicles (Homar-K, BM-27 Uragan) and infantry (TASK-067); building models up front or off the main thread (ADR 0010 follow-up).

## Implementation notes

_Filled in by the agent when done: triangle counts and cold build times before/after per faction, render sheet paths, hidden-geometry cuts, deviations from the study._

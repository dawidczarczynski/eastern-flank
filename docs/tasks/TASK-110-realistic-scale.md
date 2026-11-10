# TASK-110: Realistic scale – units, trees, grass, textures, effects and camera at real size (study first)

- **Status**: done
- **Layers**: study + presentation (`MapScale`, a `true` `VisualScale` preset, screenshot/measurement runs) + docs (ADR, GDD, follow-up task files by `game-designer`)
- **Depends on**: – (soft: TASK-108b – it introduces `MapScale`; if 110 goes first, it introduces it; priority: after the operational core loop 092 → 094 → 095, before TASK-108b … 108e)
- **Model**: opus (cross-cutting: every view system, camera, performance, readability)
- **Topic**: Visual realism

## Goal

The human decided (2026-10-31): **everything in the battle scene at its real size** – unit models, buildings, roads, rivers, trees, bushes, grass, textures and effects – true to the real hex size (250 m between hex centres on real maps). Today the scene mixes several scales. This task measures what real scale means for each system, prototypes it in screenshots, puts the readability and performance trade-offs to the human, and splits the work into implementation tasks. TASK-108b … 108e already use real metres via `MapScale`, so they don't wait for this task.

## Current scales (inventory to verify and complete in the study)

One world unit (`TerrainField.HEX_SIZE` = 1, centre to corner) = **144.3 m** on every tactical map: real maps (`ImportedMap.metres_per_world_unit()`, 250 m hexes, ADR 0018) and generated maps (the same 250 m hex, `MapScale.DEFAULT_METRES_PER_UNIT`, decided 2026-10-31, GDD Map).

## Decisions already taken (the human, 2026-10-31)

- **Real-size units, no enlarged-unit compromise.** Readability comes from **fixed-pixel on-screen unit markers** (icon + label) and a **much closer minimum camera distance** – implemented by **TASK-111** (after this study); this study sets their targets (marker look, minimum distance, pitch at close range).
- **Roads and rivers keep a 1.5 px minimum on-screen width** (TASK-108b / 108c).
- **Generated maps use the 250 m hex.**
- **To decide in this study, from its screenshots**: how a company is shown (one real-size vehicle or a small group, e.g. 3–4 vehicles / 3 squads spread in the hex) and the relief exaggeration (keep 1.5× or go to 1.0×). Present both with screenshots and a recommendation; the human picks.

| System | Today | Real size at 144.3 m / unit | Factor today |
|---|---|---|---|
| Unit models | built in metres × 0.078 × `unit_model_scale` 1.1 = 0.0858 units / m (Abrams 9.8 m → 0.84 units) | 0.00693 units / m (Abrams → 0.068) | **≈ 12.4×** |
| Trees | `TREE_HEIGHT` 0.3 × `tree_scale` 1.8 = 0.54 units ≈ 78 m | 20–25 m → 0.14–0.17 | ≈ 3–4× |
| Bushes, rocks, scrub | `bush_scale` 1.4, `rock_scale` 1.0 | – | to measure |
| Grass clumps | 0.07 × 0.05 × `grass_scale` 1.4 ≈ 0.1 units ≈ 14 m | 0.3–1.5 m | ≈ 10–40× |
| Ground textures | repeat as if 1 unit = 7.7 m (`TerrainGround.METRES_PER_UNIT`) | 144.3 m | ≈ 19× |
| Terrain mesh | 4 vertices / unit = 36 m spacing | – | resolution limit |
| Elevation | 1.5 × true vertical scale on real maps (`--exaggeration`, ADR 0018) | 1.0× | 1.5× |
| Roads / rivers | 0.10 / 0.15 units = 14 / 22 m (TASK-108) | 5 / 8 m (+ verges/banks) | fixed by 108b / 108c |
| Ground marks | tread strips 0.42 wide ≈ 60 m | ~3.5 m | ≈ 17× |
| Effects | muzzle flash, dust, exhaust, salvo plumes, smoke, craters, wrecks in world units | – | to measure |
| Camera | distance 7–46 units (1.0–6.6 km), FOV 40°: 1 px ≈ 1.0 / 3.5 / 6.7 m at 720p (closest / default / farthest) | – | – |

`VisualScale` presets (`current`, `balanced`, `realistic`, TASK-059) only change units vs. trees; even `realistic` keeps units ~10× too large for the map.

## What real scale implies (to quantify in the study)

- **Readability** (decided: markers + closer camera, TASK-111): at the default zoom a real tank is ~3 px long and a soldier sub-pixel. The study sets the marker look (class icon next to today's fixed-pixel tag) and the minimum camera distance (proposal ~0.4 units ≈ 58 m, a tank ~170 px at 720p) and checks them on the prototype screenshots.
- **A unit is a company** (GDD "Vision decisions", to decide here from screenshots): 10–14 vehicles or ~100 soldiers over ~250 m. One true-size vehicle per hex is as unrealistic as a giant one. Options: one model (today), or a small formation (e.g. 3–4 vehicles / 3 squads) spread within the hex.
- **Camera and terrain detail**: close zoom needs a finer terrain mesh near the camera (36 m vertices look like folded paper at 1 m / px), texture repeats in real metres, grass at real size and density only near the camera.
- **Scatter density and performance**: a real forest hex holds ~2 000 trees (5.4 ha × ~400 / ha); Suwałki's 126 forest hexes ≈ 250 000 trees – far beyond today's instance and frame budgets (Suwałki is already 23.8 ms on the RX 580). Needs impostors / canopy shells / distance budgets (overlap with TASK-072).
- **Everything sized in world units**: rings, outlines, path dots, hover ring stay hex-sized (map-level UI); unit labels, attack tag, decals, particles, movement speed (0.26 s per 250 m tile ≈ 3 400 km/h – fine as a game convention, but noted), salvo trajectories, camera shake, picking (clicking a 3 px tank → pick by hex as today).
- **Vertical scale** (to decide here from screenshots): real 1.0× makes the Suwałki relief look flat at 144 m / unit; keep 1.5× or go to 1.0×.

## Deliverables

1. **Inventory** completed for every presentation system (the table above plus scatter, effects, HUD anchors), with real target sizes.
2. **Prototype** (code, small): `MapScale` (if 108b has not added it) and a `true` `VisualScale` preset computed from `MapScale` (units, trees, bushes, rocks, grass at 1:1), selectable by `tools/screenshot.sh` (`SCREENSHOT_SCALE_PRESET=true`) and a temporary camera distance override; no default change.
3. **Screenshots** of Suwałki and the default battle at `balanced` and `true`, at distances 46 / 24 / 7 and the closest distance that shows a tank at ≥ 40 px, plus frame times (`SCREENSHOT_MEASURE_FRAMES`) on the Windows build.
4. **Options for the human** on the two open points – company representation and vertical scale – plus the performance plan, each with screenshots and the agent's recommendation, recorded in GDD Open questions; the confirmed targets for TASK-111 (marker look, minimum camera distance, close-range pitch) written into TASK-111. After the decision an **ADR** and the **follow-up task split** (`game-designer`: task files + BACKLOG rows; expected areas: unit models / formations at real size (after TASK-111), terrain LOD near the camera, vegetation at real scale + impostors, textures + decals + effects).

## Acceptance criteria (testable)

- [x] `MapScale.metres_per_unit` = 144.34 (± 0.01) for `suwalki_battle`, 250 / √3 for generated maps (shared with TASK-108b's test if it exists).
- [x] `VisualScale.preset(&"true")` (computed from `MapScale`): the Abrams model's length in world units = 9.8 m / 144.34 (± 2 %); a tree's height = its species height in metres / 144.34 (± 5 %); `balanced` stays the default and unchanged.
- [x] `tools/screenshot.sh` accepts `SCREENSHOT_SCALE_PRESET=true` and the camera distance override; the screenshots and frame times of deliverable 3 are listed in the implementation notes and Read by the agent.
- [x] Inventory recorded; company representation and vertical scale presented with screenshots and a recommendation (GDD Open questions "Realistic scale") and the human's decision recorded; TASK-111's targets confirmed in its task file; ADR written; follow-up tasks in BACKLOG.md.

## Playtest (for the human)

1. Look at the screenshot pairs (`balanced` vs. `true`) at the three zoom levels. Judge: can you still find and read units? Does the map look like the real place?
2. Decide the open points: company representation (one vehicle or a small group), vertical scale (1.5× or 1.0×), performance trades. Confirm the marker and minimum-distance targets for TASK-111.

## Player manual

None for the study (no default changes). The follow-up tasks change the manual (camera range, unit markers, unit look).

## Out of scope

- Changing the default scale or camera (follow-up tasks after the decision).
- Rule changes; hex size changes in the core (`HEX_SIZE` stays 1).
- TASK-108b … 108e (they already use real metres).

## Implementation notes

### Summary

The study is complete. Delivered: `MapScale` metres per unit per map, the `true` `VisualScale` preset (no default change), screenshot/measurement options (`SCREENSHOT_SCALE_PRESET`, `SCREENSHOT_MIN_DISTANCE`, `SCREENSHOT_TIME_LIMIT`), the inventory and measurements below, the human's decisions, [ADR 0021](../adr/0021-real-scale-visuals.md), updated TASK-111 and follow-up tasks TASK-134 (terrain LOD + real-metre ground), TASK-135 (vegetation, overlaps TASK-072), TASK-136 (company group), TASK-137 (effects, decals, tracks), TASK-138 (wire `MapScale`, `true` default). Known limitations: `MapScale.apply_map_id` is not wired into the battle yet (TASK-138); at `true` forests look sparse until TASK-135; the camera override exists only for screenshots (TASK-111 makes it real). Still for the human: look at the screenshots in `.screenshots/scale/`.

### Decisions (human, 2026-11-10)

- **Option A adopted**: a unit stays a company (no rule / AI / balance change); it is drawn as 3–4 real-size vehicles or squads ~50–80 m apart around the hex centre, model count following strength (HP 10 → 4, HP 5 → 2), wrecks for destroyed ones; the group only below ~3 units camera distance, above it the TASK-111 fixed-pixel marker.
- **Option B** (platoon as tactical unit) not adopted; kept as an open question in the GDD.
- **Relief stays 1.5×.**
- **Minimum camera distance ~1.0 units (≈ 144 m)**, close-range pitch / clearance ∝ (d / 7)² / look-at on the ground as in the prototype; markers: class icon next to the fixed-pixel tag, anchored to the unit instead of 90 m above it. Written into TASK-111 (plus a 3-unit group-drawing hook).

### Prototype (code + measurement part, 2026-11-10, presentation-engineer)

- `MapScale.for_map_id` / `apply_map_id`: metres per world unit of a BattleSetup map (tactical layer / imported map → its own `metres_per_world_unit()`, generated → 250 / √3). Suwałki = 144.34, generated = 144.34; not wired into the battle yet (both equal the default today).
- `VisualScale.preset(&"true")` (no default change, `balanced` stays): computed from `MapScale` and `VisualScale.TRUE_HEIGHTS_M` (pine 25, spruce 28, birch 20, oak 22, alder 18, shrub 3, undergrowth 0.8, mixed-forest mean 24, bush 2.5, boulder 1.2, grass clump 0.5 m). Unit models are sized one by one (`UnitModels.model_scale`: 1 / (m × the model's `K`), squads `SOLDIER_SCALE` × 0.1), trees per species and variant (`VisualScale.tree_size`, LOD0 AABB height), bushes / rocks / grass by one multiplier each. Values at 144.34 m/unit: unit_model_scale 0.089 (Abrams 0.079, 14× smaller than `balanced`; squads 0.040), tree_scale 0.55 (3.2×), bush_scale 0.157 (8.9×), rock_scale 0.083 (12×), grass_scale 0.069 (20×).
- Camera: `SCREENSHOT_MIN_DISTANCE` (CameraRig.set_min_distance_override, screenshot only) lets the debug camera go below 7; below 7 it looks at the ground under the target and the ground clearance shrinks with (d / 7)² (the fixed 1.5-unit clearance forced a top-down close-up). `SCREENSHOT_TIME_LIMIT` raises the 60 s run limit (Suwałki needs ~65–120 s).
- Tests: test_map_scale (Suwałki / generated), test_visual_scale (Abrams length ±2 %, every species × variant height ±5 %, bush / grass real size, `balanced` default), test_camera_rig, test_screenshot_options.

### Screenshots (Windows build, RX 580, HIGH, 1280×720; `.screenshots/scale/`, camera on the Abrams, unit 2, yaw −40°)

`<scenario>_<preset>_<distance>.png` for default / suwalki × balanced (46, 24, 7) / true (46, 24, 7, 1.5, 1.2, 0.6). Observations:

- **46 / 24**: units are only their labels and hex rings in both presets (balanced models are ~10–20 px blobs at 24). With `true`, forest hexes turn into brown ground with sparse 2–4 px dots – today's 30 trees per forest hex at real size cover ~1 % of the ground instead of a closed canopy; forests stop reading as forests. Open ground looks the same (grass is invisible either way at this range).
- **7** (today's closest): `balanced` shows the models and trees as today. `true`: the Abrams is a ~3 px speck, infantry invisible, trees look like a sparse savanna (default battle) or an open pine park (Suwałki).
- **1.5**: Abrams ~30–35 px (default) / ~20 px (Suwałki, steeper terrain pitch); the label floats off-screen (anchored 0.62 units = 90 m above the unit). Ground texture blurry, grass invisible, hex ring band ~15 m wide fills the frame.
- **1.2**: the farthest distance with the tank ≥ 40 px (default battle ~45 px, a readable turret and hull). On Suwałki the same tank is a ~35 px dark, flat blob – it looks partly sunk: at real size (2.4 m = 0.017 units tall) any gap between the unit's tile height and the drawn 36 m terrain mesh buries it; real-size units must sample the drawn surface exactly.
- **0.6**: Abrams ~95 px; the ground is a smeared, low-resolution camouflage-like pattern (texture repeat sized for 7.7 m/unit, terrain mesh 36 m), no visible grass (0.5 m clumps at today's density are a few px and sparse), trees look right-sized next to the tank.

### Frame times (SCREENSHOT_MEASURE_FRAMES=120, avg / max ms)

| Shot | 46 | 24 | 7 | 1.5 | 1.2 | 0.6 |
|---|---|---|---|---|---|---|
| default balanced | 9.6 / 10.1 | 14.5 / 14.9 | 14.0 / 14.3 | – | – | – |
| default true | 8.9 / 9.4 | 11.2 / 11.5 | 11.9 / 13.3 | 10.6 / 11.0 | 10.4 / 12.9 | 9.7 / 10.1 |
| suwalki balanced | 15.0 / 35.0 | **22.7 / 46.3** | **19.0 / 40.3** | – | – | – |
| suwalki true | 13.1 / 35.6 | **17.8 / 35.3** | **17.0 / 38.8** | 14.6 / 35.5 | 14.0 / 33.2 | 12.8 / 13.4 |

`true` is 1–5 ms cheaper with the *same* instance counts (smaller crowns: less overdraw and shadow area). A real forest density (~2 000 trees per forest hex vs. 30 today, ~65×) is not affordable as instanced trees: Suwałki is already over budget at the default view.

### Inventory: scatter, effects, HUD anchors (today in world units → real target at 144.34 m/unit)

| System | Today | Real target | Factor |
|---|---|---|---|
| Forest trees (ScatterPlanner.FOREST_TREES) | 30 per forest hex, 0.54 units ≈ 78 m tall | ~2 000 per hex (5.4 ha × 400/ha), 18–28 m (0.12–0.19) | density ×65, height ÷3.2 |
| Young trees / edge shrubs / ground cover / meadow scrub | tree units × tree_scale 1.8 (shrub model 0.099 → 26 m, undergrowth 0.084 → 22 m) | shrub 3 m (0.021), undergrowth 0.8 m (0.0055) | ÷9 / ÷27 |
| Bushes (FoliageMeshes.bush 0.184 × BUSH_HEIGHT 0.6 × 1.4 × planned scale) | ~0.15 units ≈ 22 m | 2.5 m (0.017) | ÷9 (true bush_scale 0.157) |
| Rocks (radius 0.05 × 0.5–1.7) | 7–25 m | boulders 0.5–2 m | ÷12 |
| Grass clumps (0.07 × 0.05 × 1.4) | ~10 × 7 m | 0.3–1.5 m | ÷20; real density only within ~100 m of the camera |
| Backdrop canopy (BackdropCanopy.HEIGHT 0.22 × tree_scale) | 57 m shell | 24 m | ÷2.4 |
| Tree LOD ranges (TreeField.LOD_DISTANCE 30, LOD2 46, scrub 12/22) | world units | must scale with the tree size / screen size, else LOD0 is spent on sub-pixel trees | – |
| Muzzle flash (BASE_SIZE 0.2 × unit scale) | ~26 m | ~3–5 m | ÷12 (follows unit_model_scale) |
| Dust / exhaust (MotionFx 0.05→0.38 / 0.03→0.26, side 0.4, height 0.6) | dust ≤ 55 m | dust 5–15 m | ÷4–12 (dust partly follows unit scale) |
| Wreck smoke (WreckView 0.25→0.8, rise 0.55–0.7) | 36–115 m puffs | 5–20 m puffs, column 50–100 m | ÷5 |
| Craters (GroundMarks radius 0.10–0.16, spread 0.35) | 15–23 m, 50 m apart | 155 mm: 2–5 m (0.015–0.035) | ÷6 |
| Scorch (impact 0.25, death 0.35, wreck burnt 0.95) | 36 / 50 / 137 m | 5 / 10 / 20 m | ÷7 |
| Tracks (TANK_WIDTH 0.42) | 60 m strip | 3.7 m (0.026) | ÷17 |
| Rockets (RocketVolley 4 m × 0.078 × unit scale, apex 0.7–3.2 units) | rocket ~0.34 units ≈ 50 m, apex 100–460 m | rocket 4–8 m, apex 3–30 km (off-screen) | ÷12; trajectories stay a stylised arc |
| Launch flash / glow (0.16 / 0.05) | 23 / 7 m | 5–10 m | ÷3 |
| Unit labels (UnitModels.LABEL_HEIGHT 0.5 / 0.62) | 2D tag anchored 72–90 m above the feet | anchor at model top (~3 m, 0.02) or a fixed pixel offset | marker work → TASK-111 |
| Hex rings / fill / hover / path dots (UnitView RING 0.6–0.8, lift 0.03) | hex-sized | stay hex-sized (map-level UI); band 0.12 units = 17 m dominates close-ups → thin to a pixel width when close | – |
| Camera (CameraMath MIN 7 / MAX 46, GROUND_CLEARANCE 1.5, look-at y 0.4) | 1.0–6.6 km | close range needs MIN ≈ 1.2 (tank ≥ 40 px) to 0.6 (~95 px), look-at on the ground, clearance ∝ distance | → TASK-111 |
| Camera shake (SHAKE_MAX 0.03, near 6 / far 25) | 4 m | fine as is | – |
| Movement (EventQueue.SECONDS_PER_TILE 0.8) | 250 m in 0.8 s ≈ 1 100 km/h | game convention | – |
| Ground texture (TerrainGround.METRES_PER_UNIT 7.7 × REPEAT_SCALE 4) | 1 repeat per ~0.25 unit … smeared at < 2 | repeats in real metres + detail texture near the camera | ÷19 |
| Terrain mesh (MapView.RESOLUTION 4/unit) | 36 m vertices | ~2–5 m near the camera (LOD / clipmap) | ×10 near |


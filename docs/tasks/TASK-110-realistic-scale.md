# TASK-110: Realistic scale – units, trees, grass, textures, effects and camera at real size (study first)

- **Status**: ready
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

- [ ] `MapScale.metres_per_unit` = 144.34 (± 0.01) for `suwalki_battle`, 250 / √3 for generated maps (shared with TASK-108b's test if it exists).
- [ ] `VisualScale.preset(&"true")` (computed from `MapScale`): the Abrams model's length in world units = 9.8 m / 144.34 (± 2 %); a tree's height = its species height in metres / 144.34 (± 5 %); `balanced` stays the default and unchanged.
- [ ] `tools/screenshot.sh` accepts `SCREENSHOT_SCALE_PRESET=true` and the camera distance override; the screenshots and frame times of deliverable 3 are listed in the implementation notes and Read by the agent.
- [ ] Inventory recorded; company representation and vertical scale presented with screenshots and a recommendation (GDD Open questions "Realistic scale") and the human's decision recorded; TASK-111's targets confirmed in its task file; ADR written; follow-up tasks in BACKLOG.md.

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

_Filled in by the agent when done: what was done, decisions, known limitations._

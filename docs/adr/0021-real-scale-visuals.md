# ADR 0021: Real-scale visuals – real-size models and vegetation, markers, close camera, company as a group

- **Status**: accepted
- **Date**: 2026-11-10
- **Task**: TASK-110 (study); implemented by TASK-111, TASK-134 … TASK-138

## Context

One world unit = 144.3 m (250 m hex, ADR 0018; generated maps use the same hex). Unit models are about 12× too large for the map, trees 3–4×, grass 10–40×, ground textures 19×, tread marks 17×. The human decided on 2026-10-31 to draw everything at real size. The TASK-110 study built a `true` `VisualScale` preset (computed from `MapScale`) and measured it on Suwałki and the default battle.

## Decision

1. **Real size.** Unit models, trees, bushes, rocks and grass at 1 : 1 with the 144.34 m / unit scale (`MapScale`, `VisualScale.preset(&"true")`; values: unit_model_scale 0.089, tree_scale 0.55, bush 0.157, rock 0.083, grass 0.069). No enlarged-unit compromise. `balanced` stays the default until the follow-ups land (TASK-138 switches it).
2. **Readability through markers and a close camera (TASK-111).** A real tank is ~3 px at the default zoom, so units get a fixed-pixel marker (class icon + today's tag) anchored to the unit's ground point. The minimum camera distance drops from 7 to **~1.0 units (≈ 144 m)**; the pitch, ground clearance (∝ (d / 7)²) and look-at height scale with the distance as in the prototype. Picking stays hex-based.
3. **A company is drawn as a group (Option A, human 2026-11-10).** The tactical unit stays a company (no rule, AI or balance change). Below ~3 units camera distance it is drawn as 3–4 real-size vehicles or squads ~50–80 m apart, the count following strength (HP 10 → 4, HP 5 → 2), with wrecks for the destroyed; above it the marker carries readability. **Option B** (platoon as tactical unit, 3–4× more units, changes BattleSetup / AI / balance) is **rejected for now**, kept in the GDD open questions.
4. **Relief stays 1.5×** (human 2026-11-10): strictly real 1.0× looks flat at this scale.
5. **Real-size units must sample the drawn surface exactly.** At 1.2 units a tank 0.017 units tall sinks into the 36 m terrain mesh on Suwałki; the group drawing places models on the displayed terrain, not on the tile height (TASK-136), supported by the terrain LOD (TASK-134).

### Performance plan

The measured evidence (RX 580, HIGH, 1280×720, `SCREENSHOT_MEASURE_FRAMES=120`, avg / max ms; Suwałki is already over budget today):

| Shot | 46 | 24 | 7 | 1.5 | 1.2 | 0.6 |
|---|---|---|---|---|---|---|
| default balanced | 9.6 / 10.1 | 14.5 / 14.9 | 14.0 / 14.3 | – | – | – |
| default true | 8.9 / 9.4 | 11.2 / 11.5 | 11.9 / 13.3 | 10.6 / 11.0 | 10.4 / 12.9 | 9.7 / 10.1 |
| Suwałki balanced | 15.0 / 35.0 | 22.7 / 46.3 | 19.0 / 40.3 | – | – | – |
| Suwałki true | 13.1 / 35.6 | 17.8 / 35.3 | 17.0 / 38.8 | 14.6 / 35.5 | 14.0 / 33.2 | 12.8 / 13.4 |

`true` is 1–5 ms cheaper than `balanced` at the **same instance counts** (smaller crowns: less overdraw and shadow area). But at 30 trees per forest hex real-size forests cover ~1 % of the ground and stop reading as forests (brown ground, sparse dots). A real density is ~2 000 trees per forest hex (×65; Suwałki: 126 forest hexes ≈ 250 000 trees), far beyond the instance and frame budgets. Therefore:

- **Vegetation (TASK-135, relates to TASK-072):** distance budgets per chunk; far forests as canopy shells / textured canopy surfaces, mid-range as impostors (billboards), full 3D trees only within a short range scaled to tree size; LOD ranges (`TreeField.LOD_DISTANCE` 30 / 46, scrub 12 / 22) re-expressed in metres / screen size, so LOD0 is not spent on sub-pixel trees. Grass at real density only within ~100 m of the camera.
- **Terrain (TASK-134):** a finer mesh near the camera (LOD / clipmap, 36 m → ~2–5 m vertices), ground textures repeating in real metres plus a detail texture, instead of the smeared 7.7 m / unit pattern.
- **Effects (TASK-137):** rescaled by one factor each (flash ÷12, dust ÷4–12, smoke ÷5, craters ÷6, tracks ÷17), with fixed-pixel fallbacks where they would vanish.
- **Rule:** each task keeps Suwałki and the default battle at or below the numbers above; the final switch to `true` (TASK-138) needs 60 FPS (16.7 ms) at the default view or an explicit human decision.

## Consequences

- (+) Units, trees and ground match the real map; the group of 3–4 models gives a company a believable footprint without touching the rules.
- (+) No rule / AI / replay change: all of this is presentation (plus `MapScale` wiring).
- (−) Zoomed out, units are only markers; forests rely on impostors / shells to look dense.
- (−) Option A shows 3–4 models for one unit with one HP bar; players may expect each model to be targetable. The marker and the group count follow strength to keep this readable.
- (−) Real-size work is spread over five tasks and the default look changes only at the end (TASK-138).
- Movement speed (250 m in 0.8 s) and trajectories stay game conventions, unchanged.

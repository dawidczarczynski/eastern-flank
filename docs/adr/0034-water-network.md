# ADR 0034: Water network – one hydrologically consistent model of rivers and lakes, water first, terrain second

- **Status**: proposed
- **Date**: 2026-11-28
- **Task**: follow-up of TASK-216 (river widths); replaces the river geometry of TASK-108c and the lake depth of ADR 0018 for real-data maps

## Context

Rivers will be a key tactical mechanic (crossing them), so they must look and behave like real rivers. Playtests of TASK-216 on Suwałki (hex 47,45 of the theatre) showed errors the current model cannot fix by tuning:

1. **The course is reconstructed, not real.** The importer keeps a river only as links between neighbouring 250 m hexes (`river_rows`); `FeatureRibbonPlanner` rebuilds a line through hex centres and adds noise meanders. The real OSM course is lost.
2. **Water follows the terrain instead of the terrain following the water.** Elevation is one DEM value per hex, blended between centres; valleys narrower than a hex do not exist. The channel is dug into that surface afterwards, so the water surface rose and fell with it (rivers running uphill) or cut through hills.
3. **Every lake lies on one global plane (y = 0)** with its bed at `water_elevation` -0.4 – a pit hundreds of metres deep at true scale, whatever the real lake level. River mouths end in a step or a bowl.
4. **No single source of truth.** Width, depth and banks are derived separately in the importer, the ribbon planner, `river.gdshader` and `RiverChannel`; nothing checks that they agree.

The look target (two reference frames from another game, not stored): a calm, flat, sky-reflecting water surface whose **shoreline is where the terrain cuts it**; an asymmetric valley – steep cut bank with exposed soil on the outer side of a bend, a low floodplain on the inner side; bank material by slope; a dark riparian belt of trees and scrub between water and fields; islands and side arms; bridges spanning the whole water width; from the gameplay camera the river reads at once as a barrier.

The hex grid is being removed in favour of free movement within a unit's range (human decision 2026-11-28), so nothing in this model may depend on hexes.

## Decision

1. **`WaterNetwork` (`src/core/`, pure, immutable after build) is the one source of truth** for rendering and rules. It is a graph of:
   - **river reaches**: a real polyline in world metres (OSM, simplified to ~10–20 m), downstream direction, and per vertex the water width, the water-surface height, bed depth, bank height and steepness on each side, bed type and current;
   - **water bodies** (lakes, ponds, wide-river areas, islands as holes): a polygon and one surface level;
   - **junctions**: confluences, lake inflows / outflows, with the shared level;
   - **crossings**: bridges (span, deck height) and fords from OSM.
2. **Water first, terrain second.** The order of the build is: water surface profile → terrain conditioning → everything else.
   - Downstream direction = the OSM way direction (the OSM convention for `waterway`), not a guess from heights.
   - Lake level from the DEM along the shore (or OSM `ele`); a river's surface is sampled from the DEM along the real line, smoothed, forced **non-increasing downstream**, and pinned to the lake level at inflows and outflows and to the main river at confluences.
   - The terrain is then shaped by the network: channel and bed under the water, banks and floodplain beside it. Valley shape follows curvature: steep cut bank on the outer side of a bend (height from the DEM above the water), low point bar / floodplain on the inner side. Lakes are flattened to their level with a shore slope.
3. **A finer render heightfield** (~25–50 m, chunked, independent of any grid) carries the conditioned terrain. 250 m cells cannot show a valley, a cut bank or a floodplain. It is render-only data; rules that need heights read the same field.
4. **Rendering**:
   - each river reach and each water body gets its own flat water-surface mesh at its own level, wider than the channel – **the terrain defines the shoreline**; the global plane stays only for the sea. The ribbon's painted water edge goes;
   - bank material by slope and context: exposed soil / clay above ~30°, grass on gentle banks, reeds only on flat shallow banks; sand only where the data says so (beaches, point bars);
   - a riparian belt (willow, alder, reed, scrub) placed on the GPU (ADR 0033, docs/GPU_SCATTER_PATTERNS.md); fields, meadows and buildings stop before it;
   - shape from data, smoothed with curves; noise only as small bank detail seen up close, never as the meander;
   - readability: water colour and brightness contrast with every land cover from the default gameplay camera (a screenshot acceptance criterion).
5. **Validators – the ruleset.** `WaterNetwork.validate()` returns every violation with its world position; it runs in tests on every shipped map and as a devtools overlay:
   - the surface never rises downstream;
   - a tributary's surface at the confluence equals the main river's (± ε); inflow / outflow levels equal the lake's;
   - under the water the bed is at least the minimum depth below the surface; along the shoreline the bank is above it; no dry ground inside a water body, no water outside it;
   - width changes smoothly except at junctions and islands;
   - a bridge spans the whole water width with clearance above the surface;
   - water never lies on a slope (a reach's surface gradient stays below a maximum).
6. **Crossing mechanics read the same parameters** (rules to be written in the GDD by the game-designer): a unit's movement path that crosses a reach's water polygon is a crossing; its cost / possibility follows width, depth (vs the vehicle's fording depth), current and bank height / steepness on the exit side (a steep bank blocks leaving even at a ford); bridges and fords are explicit crossing points. No hex edges.
7. **Data**: the importer writes the network (polylines, polygons, attributes, bridges, fords) with the theatre and the tactical layer; Suwałki is re-imported (approved 2026-11-28). The old `river_rows` / `river_width_rows` stay readable until the hex grid goes.

## Consequences

- (+) What the player sees is what the rules compute: one model, checked by validators.
- (+) Errors are listed by the validator and the overlay instead of being found by eye.
- (+) Independent of hexes, so it survives the move to free movement.
- (−) Large: importer, core model, heightfield, terrain mesh, water meshes, riparian layer, rules. Phased (validators first, so the current errors are measured before the rewrite).
- (−) The finer heightfield costs memory and load time; it must be measured (`ChunkManager.stats()`) and stay within the 60 FPS budget.
- (−) The stop-gap of 2026-11-28 (monotone river level in `RiverChannel`) is replaced, not extended; a shallow-lake stop-gap was tried and reverted (it broke the close-camera clearance and the grass ring), so lakes stay deep pits until phase 4.

## Phases (TASK-223a … TASK-223g)

Order: 223a and 223b in parallel → 223c → 223d → 223e → 223g; 223f after the hex-free movement design and 223c.

1. TASK-223a: Validators + devtools overlay on the current data (measure).
2. TASK-223b: Importer: real polylines with flow direction, water polygons, bridges, fords, lake levels; re-import Suwałki.
3. TASK-223c: `WaterNetwork` build: surface profiles, junction levels.
4. TASK-223d: Render heightfield + terrain conditioning (channel, banks, cut bank / floodplain, lake shores).
5. TASK-223e: Rendering: per-body water meshes, bank materials, bridges.
6. TASK-223f: Crossing rules (GDD by the game-designer, then implementation) – after the hex-free movement design.
7. TASK-223g: Riparian belt and details.

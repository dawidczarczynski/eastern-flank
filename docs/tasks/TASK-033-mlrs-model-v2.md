# TASK-033: First detailed rocket artillery model (from the v2 design) + reusable truck parts

- **Status**: ready – target: the Polish **Homar-K** (`homar_k`): Jelcz 8×8 chassis (**4 axles**, not the design's 3), armoured cab-over cab, two closed K239 launcher pods – the design's closed pod style fits; the Russian 9K57 Uragan (ZIL-135 8×8, open bank of 16 tubes) follows via `/model-unit bm27_uragan` from the same parts. Until TASK-039a adds the definition, the model is built under the current id `rocket_artillery` and renamed with TASK-039a
- **Layers**: presentation (`src/presentation/models/<unit_id>.gd`, truck parts in `model_parts.gd` / `models/parts/`; contract test)
- **Depends on**: **TASK-036**, **TASK-029**, **TASK-030**, TASK-011/rocket volley (`Pod` / `Mouth*`). Soft: TASK-039a, TASK-037. Reference: `docs/design/v2/game_screen.scene.js` lines 300–350 (`makeMLRS`), portrait `docs/design/v2/shots/02-v2-units.jpg`.
- **Agent**: `unit-modeler`, run via `/model-unit <unit_id>`
- **Model**: opus

## Goal

The first rocket artillery gets the v2 design's detailed truck with a launcher pod, adjusted to the real vehicle in its catalog entry, and the truck is built from reusable parts (chassis with N axles, wheels with lugs, mudguards, cab types, launcher types) for later wheeled vehicles.

## Port

- **Chassis**: frame rails with cross-members; axles (design: `x = 0.27, −0.06, −0.23`), per side a torus tyre (z-scale 1.4) with lugs, lathe hub, mudguard over every wheel (lines 306–307).
- **Cab**: bevelled cab profile (line 312) over a dark block; windows, tilted windscreen, door seams, accent plates, headlights, mirrors, grille, bumper, roof hatch, exhaust.
- **Rear**: bed plate, turntable, hydraulic rams, stabiliser legs, tail lights.
- **Pod** (pivot `Pod`, elevation 0.32): launcher box with ribs and a front face with a tube grid (design 3 × 4 rings + holes); `Mouth*` nodes just in front of the openings.
- **Adjust to the real vehicle** from its catalog entry (cab-over vs bonneted cab, axle count, closed pod vs open tube bank, tube count).
- **Reusable parts** with parameters: `wheeled_chassis(axles, track_width, tyre)`, `cab(kind)`, `launcher(kind, rows, cols)` – an Uragan-like configuration (4 axles, cab ahead of the engine, open bank of 16 tubes on a rotating mount) must be buildable from parameters (tested).

- **Mechanisms** (TASK-041 … TASK-045): the launcher part builds the `launcher` pivots for the unit's declared params (stowed `rear` / `front`, actuators that reach `max_elevation_deg`), optional `Stabiliser<i>` jacks with a `deployed` pose; the model copies the entry's `mechanisms` into `MECHANISMS`. The Uragan (`/model-unit bm27_uragan`) needs TASK-042 (verified entry), TASK-044 (front-stowed, limited traverse) and TASK-045 (jacks) first.

## Acceptance criteria (testable)

- [ ] Contract test passes for the model × every faction (pivots `Pod`, ≥ 6 `Mouth*` on the pod front face, `Wheel*`); the old six-mouth test is replaced by the contract check.
- [ ] `test_vehicles_use_wheel_locomotion` and `test_rocket_volley.gd` pass; with more mouths the volley keeps its rocket count and cycles through them (documented).
- [ ] A second configuration (Uragan-like: open 16-tube bank) builds from parameters without code changes (tested), render sheet in the notes.
- [ ] Final render sheet and battle screenshot in the notes; AABB within ±10 % of the catalog dimensions.
- [ ] Catalog entry `modeled`, `blueprint.md` written; `tools/check.sh` passes.

## Playtest (for the human)

1. Zoom in on the rocket artillery: cab, axles with lugged tyres, raised pod with tube openings.
2. Move it: wheels spin, the truck tilts on slopes.
3. Fire: rockets leave from the tube openings, not from inside the pod or cab.

## Out of scope

- Other wheeled vehicles (one `/model-unit` run each), stabiliser animation. (Raising and traversing the pod before firing is done for the Homar-K: `UnitModels.pose_launcher`.)

## Implementation notes

_Filled in by the agent when done._

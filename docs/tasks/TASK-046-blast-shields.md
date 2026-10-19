# TASK-046: `blast_shields` mechanism – cab window shields lowered before a volley

- **Status**: idea – becomes `ready` when the `bm27_uragan` catalog entry has a **verified** `blast_shields` mechanism (TASK-042 research: does the 9K57 Uragan lower armoured shields over its cab windows before firing? (?)). If the research doesn't confirm it for any catalog unit, park this task.
- **Layers**: presentation (`UnitModels.DEPLOYABLE_PREFIXES`), `mechanisms.json`, tests; the Uragan model (`/model-unit bm27_uragan`) builds the shields
- **Depends on**: **TASK-045** (deploy step), TASK-042 (verified catalog entry)
- **Model**: sonnet

## Goal

A launcher that fires over its own cab closes armoured shields over the cab windows before the volley and opens them afterwards, like the real vehicle.

## Design

- `BlastShield<i>` pivots (direct children of the model, contiguous from 0) with meta `"deployed"` (closed pose); the built pose is open. Added to `UnitModels.DEPLOYABLE_PREFIXES`, so they move in the same deploy / stow steps as the jacks (same timing, no extra duration).
- Registry: `blast_shields` → `implemented`; pivots `[{"path": "BlastShield{i}", "min": 1, "meta": ["deployed"]}]`, owns `BlastShield{i}`; no params.
- `_volley_event_duration`'s `deploy` flag is true for models with shields only, too (`has_deployables`).
- The geometry (one hinged plate per window, closed pose in front of the glass) is built by the `unit-modeler` with the Uragan; until then the mechanism is tested on synthetic models.

## Acceptance criteria (testable)

- [ ] Synthetic model with `BlastShield0` (built rotation 0, `deployed` rotated −80° about local Z): `pose_deployables(t = 1)` → deployed transform, `t = 0` → built; a model with only shields `has_deployables()`.
- [ ] Contract helper: `BlastShield0` without `deployed` meta → violation; a model with a `BlastShield0` pivot but no declared `blast_shields` → owned-pivot violation.
- [ ] `_volley_event_duration` for a shields-only launcher includes `2 × DEPLOY_DURATION`.
- [ ] `tools/check.sh` passes.

## Playtest (for the human)

1. (After `/model-unit bm27_uragan`) fire with the Uragan: while the jacks go down the window shields close; they open again when the jacks come up.
2. `tools/render_unit.sh bm27_uragan --pose=fire`: shields closed over the windows.

## Player manual

None (presentation only).

## Out of scope

- Other cab details (crew hatches, camouflage nets).

## Implementation notes

_Filled in by the agent when done._

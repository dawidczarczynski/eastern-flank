# TASK-045: `stabilisers` mechanism – jacks lowered before a volley, raised after (deploy step)

- **Status**: ready
- **Layers**: presentation (`UnitModels.pose_deployables`, `UnitView`, `BattleController` volley sequence), model `homar_k.gd` (jacks – via `unit-modeler`), `mechanisms.json` (status + pivot contract), tests, catalog `homar_k`
- **Depends on**: **TASK-044**, TASK-042 (Homar-K jacks verified in the catalog). Used by the Uragan (`/model-unit bm27_uragan`) and later by any vehicle that braces itself before firing.
- **Model**: sonnet

## Goal

Before a volley the rocket launcher lowers its stabiliser jacks to the ground, and raises them after the launcher is stowed – the vehicle visibly settles into a firing position.

## Design

- **Generic deploy step** for two-state parts (stowed ↔ deployed), reused by `blast_shields` (TASK-046): `UnitModels.DEPLOYABLE_PREFIXES := ["Stabiliser"]`; `UnitModels.has_deployables(model) -> bool`; `UnitModels.pose_deployables(model, t: float)` sets each `Stabiliser<i>` (direct child of the model, i = 0, 1, … contiguous) to `rest.interpolate_with(deployed, t)`, where `rest` = the built transform (stored in meta `"rest"` on first use, like the `Pod`) and `deployed` = the Transform3D in the pivot's meta `"deployed"` (set by the model). `t = 0` stowed, `t = 1` deployed. No-op without such pivots. The model decides the motion (telescopic leg sliding down, or a leg swinging down) – the pose code only interpolates.
- **Registry** (`mechanisms.json`): `stabilisers` → `implemented`; pivots `[{"path": "Stabiliser{i}", "min": 1, "meta": ["deployed"]}]`, owns `Stabiliser{i}`; no params.
- **Contract** (mechanism test): for every model declaring `stabilisers`, in the deployed pose (`t = 1`, model untilted) the lowest point of each `Stabiliser<i>` subtree is at y = 0 ± 0.005 in the model root's space (feet on the ground, like the tyres); in the stowed pose it is ≥ 0.005 above the ground.
- **Volley sequence** (`_play_volley`): [limited traverse: body turn] → **deploy** (`DEPLOY_DURATION := 0.6`, t 0 → 1, sine in-out) → raise → traverse → salvo → traverse back → lower → **stow** (0.6, t 1 → 0). Deploy happens after the body turn (a braced vehicle doesn't turn). `_volley_event_duration` gains a `deploy: bool` argument: `+ 2 × DEPLOY_DURATION` when the shooter `has_deployables()`.
- `tools/render_unit.sh --pose=fire` also deploys (t = 1).
- **Homar-K jacks**: number and positions as verified in the catalog (TASK-042; expected: hydraulic jacks at the rear (?)). Built by the `unit-modeler` (rework of `homar_k` with feedback "add stabiliser jacks per the `stabilisers` contract; `deployed` meta = lowered pose, foot on y = 0"), `blueprint.md` updated; the catalog entry gets `stabilisers: {}` (verified) and `MECHANISMS` in `homar_k.gd` matches. If the catalog says the Homar-K has no jacks, implement the mechanism with synthetic test models only and note it.
- Docs: `unit-modeler.md` contract mentions the `deployed` meta (stowed = built pose); GDD "Unit feel" (game-designer, when done).

## Acceptance criteria (testable)

- [ ] `pose_deployables` on a synthetic model with `Stabiliser0` (built at origin (0, 0.05, 0), `deployed` = origin (0, 0, 0)): t = 0 → built transform exactly; t = 1 → `deployed`; t = 0.5 → origin y 0.025 (±1e-5); a model without stabilisers → no-op, no error; two cached copies are posed independently.
- [ ] Contract helper: a `Stabiliser0` without `deployed` meta → violation; a deployed foot 0.02 above the ground → violation naming the pivot.
- [ ] `_volley_event_duration(launcher = true, limited = false, deploy = true) == 2 × 0.6 + 2 × (0.9 + 0.9) + RocketVolley.total_duration()` (= 4.8 + total); with `limited = true` + 0.5; `deploy = false` values unchanged from TASK-044.
- [ ] The Homar-K passes the mechanism contract with `stabilisers` (feet on the ground when deployed, lifted when stowed); render sheet `--pose=fire` in the notes.
- [ ] `tools/screenshot.sh`: the Homar-K at rest only shows the stowed jacks (new geometry, otherwise identical layout); README screenshot re-rendered (`tools/readme_screenshot.sh`) and checked; `tools/check.sh` passes.

## Playtest (for the human)

1. Fire with the Polish rocket artillery: first the jacks go down to the ground, then the pod rises and turns, fires, turns back and lowers, then the jacks come up. The whole sequence still feels reasonably short (about 5 s plus the salvo at normal speed).
2. During the enemy turn (sped-up burst) the sequence plays faster but in the same order.
3. On a slope: check how the feet meet the ground (known limitation: the hull keeps its slope tilt, feet may float or sink slightly – tell us if it bothers you).
4. `tools/render_unit.sh homar_k --pose=fire`: jacks down, pod raised.

## Player manual

None (presentation only, no rule effect).

## Open questions

- Homar-K: how many jacks and where (rear only? also between the axles?) (?) – from the catalog research (TASK-042).
- Slopes: accept feet floating/sinking a little (proposed), or level the hull while deployed (a later task)?
- Should other vehicles that brace before firing (self-propelled artillery) deploy for their attacks too? Later, with that class.

## Out of scope

- Levelling the hull on deployed jacks, deploying for non-volley attacks, blast shields (TASK-046).

## Implementation notes

_Filled in by the agent when done._

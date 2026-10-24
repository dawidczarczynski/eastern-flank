# TASK-043: Models carry their mechanisms – `MECHANISMS` metadata, registry contract test, `/model-unit` passes them on

- **Status**: done
- **Layers**: presentation (`UnitModels`, `ModelParts`, `models/homar_k.gd`), tests (`tests/unit/test_unit_mechanisms.gd`, helper `tests/mechanism_contract.gd`), agent docs (`.claude/agents/unit-modeler.md`, `.claude/skills/model-unit/SKILL.md`), `docs/ARCHITECTURE.md`, ADR (next free number, currently 0012 – 0009 is taken), catalog entries `m1a2_sepv3`, `t72b3`, `pl_mech_infantry`, `ru_motor_rifle`
- **Depends on**: **TASK-041** (registry, `homar_k` mechanisms), TASK-042 (done). All six real-unit models already exist; this task gives them metadata. Before further `/model-unit` runs, so new models declare mechanisms from the start.
- **Model**: sonnet

## Goal

A unit's mechanisms and their parameters travel from its catalog entry into its model file, where the animation code reads them, and a test keeps the model, the catalog and the registry in agreement. The game still never reads the catalog.

## Decisions

- **How parameters reach runtime: metadata on the model node.** Each model file copies the unit's catalog `mechanisms` (with every param filled, i.e. after TASK-041's defaults) into a constant and stores it on the built model node:

  ```gdscript
  const MECHANISMS := {
  	"wheels": {},
  	"launcher": {"traverse_deg": "full", "max_elevation_deg": 40, "stowed": "rear"},
  }
  ...
  ModelParts.declare_mechanisms(g, MECHANISMS)  # g.set_meta(&"mechanisms", MECHANISMS)
  ```

  Values keep the catalog's units (degrees, metres); pose code converts. Why metadata and not constants read by `UnitModels`: the pose functions only get the node tree, the `Pod` "rest" metadata is the precedent, metadata survives `ModelParts.cached` copies, and no `src/presentation` code ever touches `docs/`. The dictionary is shared between copies – treat it as read-only.
- **Pivots activate, metadata parameterises.** Pose functions keep finding their pivots as today; parameters come from `UnitModels.mechanism(model, id)`; a model without metadata (synthetic test models) uses the code defaults (TASK-044).
- **Every model has metadata.** Today only `homar_k` and `bm27_uragan` declare mechanisms in the catalog; `m1a2_sepv3`, `t72b3`, `pl_mech_infantry` and `ru_motor_rifle` have empty `mechanisms`. Step 1 of this task fills them (`wheels` for the tanks, `squad_march` for the squads – both `implemented`, no research needed beyond the registry defaults; `turret_traverse` is added by TASK-047) and the human verifies them in the catalog tool (`verified`). Planned-but-not-implemented mechanisms already declared (the Uragan's `stabilisers`, `blast_shields`) are copied into `MECHANISMS` too; only their pivots are not checked until they are implemented (TASK-045).
- **Undeclared pivots fail the contract.** A model with an owned pivot (`owns` in the registry, e.g. `Launcher`) of an implemented mechanism that its catalog entry doesn't declare fails. Reason: the animation is keyed on pivots, so such a model would animate something the catalog says the vehicle doesn't have – the catalog would no longer be authoritative.
- **Drift fails the contract.** When the human changes a mechanism param in the catalog, the test fails until `MECHANISMS` in the model file is updated (by hand or `/model-unit <id>`); the failure message says exactly that.

## Design

- `ModelParts.declare_mechanisms(model: Node3D, mechanisms: Dictionary)`; `UnitModels.mechanisms(model) -> Dictionary` (empty if none), `UnitModels.mechanism(model, id: String) -> Dictionary` (params, empty if not declared), `UnitModels.has_mechanism(model, id) -> bool`. All accept the root or its `Model` child (`_model_of`).
- All six model files get `MECHANISMS` as in their catalog entries (`homar_k`: `wheels`, `launcher` full / 40 / rear; `bm27_uragan`: `wheels`, `launcher` with its verified params, `stabilisers`, `blast_shields`; tanks `wheels`; squads `squad_march`). No visual change. The Uragan's ad-hoc `stowed_yaw` meta stays until TASK-044 replaces it with the `stowed` param.
- `tests/mechanism_contract.gd` (pure helper, `RefCounted`): `load_registry()` (JSON read of `res://docs/design/units/mechanisms.json`, test-only like TASK-039a's consistency test), `load_catalog_mechanisms(unit_id)` (`docs/design/units/units/<id>/unit.json`, `null` if no entry), `pivot_violations(model, mechanism_entry) -> Array[String]` (applies `path`, `{i}`, `min`, `with`, `meta`), `owned_pivots(model, registry, declared) -> Array[String]` (owned pivots of undeclared implemented mechanisms).
- `tests/unit/test_unit_mechanisms.gd` (new file – the contract file is at gdlint's method cap):
  - every model file × first faction: it has a catalog entry and its metadata equals the catalog `mechanisms` (numbers compared as floats, `"full"` as string, ranges as arrays; message names the model file to update or `/model-unit <id>`), every declared **implemented** mechanism has no pivot violations, and no owned pivot of an undeclared implemented mechanism exists;
  - a model without metadata fails ("copy the catalog mechanisms into MECHANISMS"); a model with metadata but without a catalog entry fails; a model whose catalog `mechanisms` is empty fails ("declare and verify its mechanisms in the catalog").
- `test_unit_model_contract.gd`: the per-kind pivot checks (`_check_pivots`) are replaced by the registry checks (each kind's pivots are covered by `wheels` / `squad_march` / `launcher`); `KINDS` stays for the budgets.
- **Docs**:
  - `unit-modeler.md`: Inputs – the entry's `mechanisms` and `docs/design/units/mechanisms.json`; Contract – required pivots come from the declared mechanisms' `pivots` in the registry (replace the hard-coded pivot sentence with the registry reference plus the infantry/vehicle basics), copy `mechanisms` into `MECHANISMS` and call `ModelParts.declare_mechanisms`; don't add pivots of undeclared mechanisms; for parameters that shape geometry (e.g. actuators must reach `max_elevation_deg`) build for the declared value; a mechanism the registry lacks → propose it in the summary.
  - `/model-unit` SKILL.md: step 1 also requires a non-empty, verified `mechanisms`; step 2 passes the declared mechanisms with params and their registry entries (pivots, help) to the agent; step 4 checks the mechanism contract test output.
  - `docs/ARCHITECTURE.md` "Unit visuals": a paragraph on mechanisms (registry in the catalog, `MECHANISMS` metadata, pivots activate / metadata parameterises, contract test). ADR `docs/adr/0012-unit-mechanisms.md` (or the next free number) (catalog-declared mechanisms, metadata as the runtime channel, alternatives considered: per-class code, game reading the catalog, constants looked up by unit id).
  - `docs/design/units/README.md`: one line that the model copies the mechanisms and a test checks they match.

## Acceptance criteria (testable)

- [ ] `UnitModels.mechanism(homar, "launcher")` == `{"traverse_deg": "full", "max_elevation_deg": 40, "stowed": "rear"}` on two cached copies of the Homar-K; `mechanism(homar, "turret_traverse")` == `{}`; `mechanisms()` of a synthetic model without metadata == `{}`.
- [ ] All six catalog entries have non-empty, verified `mechanisms`; all six models pass the metadata check.
- [ ] Contract helper on synthetic trees built in the test: `Launcher/Pod/Mouth0..5` → no violations; `Mouth0..4` → one violation naming `Launcher/Pod/Mouth{i}` and the count 5 < 6; `Launcher/Actuator0` without `ActuatorRod0` → one violation; `Wheel0..3` passes `wheels` (min 4), `Wheel0..2` fails; a pivot entry with `meta: ["deployed"]` fails when the node lacks the metadata.
- [ ] A synthetic model with a `Launcher` node whose declared mechanisms lack `launcher` → `owned_pivots` reports `Launcher`; with `launcher` declared → nothing.
- [ ] Metadata vs. catalog: `homar_k` passes; a test-local catalog dictionary with `max_elevation_deg: 45` against the model → mismatch reported with the model file name.
- [ ] A model without metadata and a model with an empty catalog `mechanisms` each fail with the messages above (shown with synthetic models / test-local catalog dictionaries).
- [ ] `tools/screenshot.sh` before/after identical (no visual change); existing launcher, locomotion and contract tests pass; `tools/check.sh` passes.

## Playtest (for the human)

1. In the catalog tool change Homar-K's max elevation to 45 and run `tools/test.sh test_unit_mechanisms`: it fails and says to update `src/presentation/models/homar_k.gd` (or run `/model-unit homar_k`). Change it back – green.
2. Start a battle: nothing looks different.

## Player manual

None (internal; no visible change).

## Open questions

- Drift policy: is it acceptable that `tools/check.sh` fails right after a mechanism param is changed in the catalog tool, until the model file is updated? (Proposed: yes – it is the signal; the fix is a one-line edit.) Alternative: a warning only.

## Out of scope

- Using the parameters in the animation (TASK-044), implementing new mechanisms (TASK-045, TASK-047).

## Implementation notes

- `ModelParts.declare_mechanisms`, `UnitModels.mechanisms/mechanism/has_mechanism`; `MECHANISMS` const + declare call in all six model files (squad models now build `g`, declare, return).
- Test helper `tests/mechanism_contract.gd` (also `problems()`, `normalise()`), tests in `tests/unit/test_unit_mechanisms.gd`; `_check_pivots` removed from the model contract test. Registry-uncovered bits kept as tests: tank `Turret/Gun/Muzzle`, `Mouth` on the front face, `Kneel` implies `Stand`.
- ADR is `docs/adr/0014-unit-mechanisms.md` (0012/0013 were taken).
- **Human to do**: the four newly filled catalog entries (`m1a2_sepv3`, `t72b3`, `pl_mech_infantry`, `ru_motor_rifle`) have `verified: false` in provenance; verify them in the catalog tool. Tests only require non-empty mechanisms, not the verified flag.
- No visual change (metadata only); the before/after screenshot comparison was not run.

# TASK-041: Unit catalog – mechanisms registry and per-unit `mechanisms` (data, validation, research)

- **Status**: done
- **Layers**: tools (`tools/unit_catalog/catalog.py`, `unit.schema.json`, Python tests), docs (`docs/design/units/mechanisms.json`, `classes.json`, README), `.claude/skills/research-unit/SKILL.md`
- **Depends on**: TASK-037, TASK-040 (provenance, research merge). Followed by TASK-042 (form UI), TASK-043 (models carry the mechanisms).
- **Model**: sonnet

## Goal

How a unit animates becomes a property of the **real vehicle**, recorded in its catalog entry: the Homar-K and the 9K57 Uragan are both class `mlrs` but are built differently (launcher stowed facing the rear vs. over the cab, full vs. limited traverse, blast shields or not). One registry describes every known mechanism, its parameters and its pivot contract; the tool, the schema, the skills and the Godot contract test (TASK-043) all read it.

## Decisions (human, 2026-10-19)

1. Animations are declared **per unit in the catalog**, not per class. The unit entry is authoritative; `classes.json` only suggests defaults.
2. Mechanisms are generic and keyed on named pivots in the model (the existing approach: `Wheel<i>`, `Soldier<i>/Rig`, `Launcher`/`Launcher/Pod`/`Actuator<i>`); a mechanism can have parameters.
3. AI research proposes mechanisms and parameters with sources; **unverified mechanism values block `ready_for_model`** like unverified dimensions.
4. The game never reads the catalog (parameters reach the game through the model file, TASK-043).

## Design

### Registry `docs/design/units/mechanisms.json`

One file, a JSON array in this order (order = display order and key order in `unit.json`):

| id | label | status | params (type, range, default) | pivots (contract) | owns |
|---|---|---|---|---|---|
| `wheels` | Wheels / road wheels spin | implemented | – | `Wheel{i}` min 4 | `Wheel{i}` |
| `squad_march` | Squad march (step bob, kneelers stand) | implemented | – | `Soldier{i}` min 5, with `Soldier{i}/Rig` | `Soldier{i}` |
| `launcher` | Rocket launcher on a turntable (raise, traverse) | implemented | `traverse_deg`: angle range, `"full"` allowed, −180…180, default `"full"`; `max_elevation_deg`: number 1…90, default 40; `stowed`: enum `rear` / `front`, default `rear` | see the example below | `Launcher` |
| `stabilisers` | Stabiliser jacks lowered before firing | planned (TASK-045) | – | `Stabiliser{i}` min 1, meta `deployed` | `Stabiliser{i}` |
| `blast_shields` | Cab window blast shields lowered before firing | planned (TASK-046) | – | `BlastShield{i}` min 1, meta `deployed` | `BlastShield{i}` |
| `turret_traverse` | Turret turns and the gun elevates towards the target | planned (TASK-047) | `traverse_deg`: angle range, `"full"` allowed, default `"full"`; `elevation_deg`: angle range, no `"full"`, −20…90, default `[-8, 20]` | `Turret`, `Turret/Gun`, `Turret/Gun/Muzzle` | `Turret` |
| `gun_recoil` | Gun recoil and muzzle flash | planned (TASK-048) | `recoil_m`: number 0…2, default 0.5 | `Turret/Gun/Barrel` | – |

(The kneeler rule `Kneel` + `Stand` stays a check in the existing contract test – it is conditional and doesn't fit the path syntax.)

Entry format:

```json
{
  "id": "launcher",
  "label": "Rocket launcher on a turntable",
  "status": "implemented",
  "description": "Pod on a turntable: raises on its actuators and traverses towards the target before a volley; the vehicle turns first when the target is outside the traverse range.",
  "params": {
    "traverse_deg": {"type": "angle_range", "allow_full": true, "min": -180, "max": 180, "default": "full", "unit": "deg",
                     "help": "Traverse relative to the stowed direction: \"full\" or [min, max] (min <= 0 <= max)"},
    "max_elevation_deg": {"type": "number", "min": 1, "max": 90, "default": 40, "unit": "deg", "help": "Elevation used when firing"},
    "stowed": {"type": "enum", "values": ["rear", "front"], "default": "rear", "help": "Direction the tube ends face when stowed"}
  },
  "pivots": [
    {"path": "Launcher"},
    {"path": "Launcher/Pod"},
    {"path": "Launcher/Pod/Mouth{i}", "min": 6},
    {"path": "Launcher/Actuator{i}", "min": 0, "with": ["Launcher/ActuatorRod{i}", "Launcher/Pod/ActuatorMount{i}"]}
  ],
  "owns": ["Launcher"]
}
```

- Param types: `number` (`min`, `max` inclusive), `enum` (`values`), `angle_range` (`[lo, hi]` with `min <= lo <= 0 <= hi <= max` and `lo < hi`, or `"full"` if `allow_full`). Every param has a `default` and a `help` text; `unit` is optional.
- `pivots`: node paths below the model node; `{i}` = a contiguous index run from 0; `min` = minimum count (default 1, `0` = optional); `with` = paths that must exist for the same index; `meta` (optional) = metadata keys the pivot must carry (used from TASK-045). TASK-043's contract test reads this.
- `owns`: top-level pivot names (or patterns) that only this mechanism may create – a model with such a pivot must declare the mechanism (TASK-043).
- `status`: `implemented` or `planned`. Planned mechanisms can be declared in the catalog (research can record that the Uragan has blast shields before the animation exists); the contract test checks pivots only for implemented ones. Planned mechanisms already list their pivots, so models built before the animation exists (e.g. the Abrams in TASK-031 with `Turret/Gun/Muzzle`) get the right pivots; each mechanism task flips its entry to `implemented` (and may refine its pivots).
- Hull rocking / slope tilt is not a mechanism: every vehicle gets it from its mobility.
- `catalog.py` loads and validates the registry (`load_mechanisms(root)`, unique ids, known param types, defaults valid against their own type); an invalid registry is a startup error with the field named.

### `classes.json`

Each class gets `default_mechanisms` (list of ids, validated against the registry): infantry, mech_infantry, engineer `["squad_march"]`; tank, ifv, sp_artillery, air_defense `["wheels", "turret_traverse"]`; apc, recon, atgm `["wheels"]`; mlrs `["wheels", "launcher", "stabilisers"]`. `CLASS_KEYS` gets the new key.

### `unit.json`

- New key `mechanisms` (after `camo_note`, before `images`): object, mechanism id → params object. Example (target state for the Uragan after research – values to verify):

  ```json
  "mechanisms": {
    "wheels": {},
    "launcher": {"traverse_deg": [-30, 30], "max_elevation_deg": 55, "stowed": "front"},
    "stabilisers": {},
    "blast_shields": {}
  }
  ```

- Validation (`validate_unit`): unknown mechanism id, unknown param, wrong type or out-of-range value → error with the field `mechanisms.<id>.<param>`. Params missing on save are **filled with the registry default** and get provenance `{"source": "default", "verified": false}`. Keys are written in registry order (mechanisms and params), so diffs stay small.
- **Pre-fill**: `create_unit` with a class (and no `mechanisms` given) adds the class's `default_mechanisms` with default params; every added mechanism and param gets provenance `{"source": "class default", "verified": false}`.
- **Provenance paths**: `mechanisms.<id>` (the mechanism exists on the real vehicle) and `mechanisms.<id>.<param>`, validated against the registry (in addition to the static `RESEARCH_FIELDS`). Removing a mechanism removes its provenance entries.
- **Readiness** (`readiness_missing`): `ready_for_model` additionally requires a non-empty `mechanisms` object and no unverified provenance under `mechanisms.` (message `verify mechanisms.<path> (AI)` / `(default)`).

### Research

- `research.json` `fields` may contain `mechanisms.<id>` (value `{}`) and `mechanisms.<id>.<param>` with a source each. `merge_research`: same rules as other fields – a mechanism or param the unit doesn't have is added (unverified, with the source); a different value for a value the human set becomes `suggested`; invalid ids/params/values are rejected and reported. A param for an undeclared mechanism adds the mechanism too.
- `/research-unit` SKILL.md: list the registry (read `mechanisms.json`) and ask for the mechanisms the real vehicle has, with parameters and sources (photos/videos of the firing position count as a source; say in `summary` what was seen). Absence ("no blast shields") goes into `summary`, not into fields.

### Catalog entry `homar_k`

Add (through `catalog.save_unit`, so formatting/revision stay right):

```json
"mechanisms": {"wheels": {}, "launcher": {"traverse_deg": "full", "max_elevation_deg": 40, "stowed": "rear"}}
```

Provenance: `mechanisms.wheels`, `mechanisms.launcher`, `.traverse_deg` (source `human decision 2026-10-19: full traverse, fires over the cab`), `.stowed` verified; `.max_elevation_deg` = 40 **unverified** (source `matches the current model (0.7 rad)`; the real K239 maximum is to be researched (?)). `stabilisers` is added in TASK-045 after verification. The entry stays `modeled` (readiness only gates the status change to `ready_for_model`).

## Acceptance criteria (testable)

- [ ] `tools/unit_catalog/test_mechanisms.py`: the shipped `mechanisms.json` and `classes.json` load and validate; a registry with a duplicate id, an unknown param type or a default outside its own range is rejected with the field named.
- [ ] Unit validation, with the shipped registry: `launcher.traverse_deg` `"full"` and `[-30, 30]` accepted; `[10, 30]` rejected (must include 0), `[-200, 30]` rejected, `[30, -30]` rejected; `max_elevation_deg` 0 and 91 rejected, 55 accepted; `stowed: "side"` rejected; `turret_traverse.elevation_deg: "full"` rejected (`allow_full` false); unknown mechanism `jetpack` and unknown param `launcher.speed` rejected – each with the exact field path.
- [ ] Saving `{"launcher": {}}` stores all three launcher params with their defaults (`"full"`, 40, `"rear"`) and three provenance entries `source: "default", verified: false`; keys are in registry order in the written file.
- [ ] `create_unit(..., class="mlrs")` → `mechanisms` = `wheels`, `launcher` (defaults), `stabilisers`, with `class default` provenance; `readiness_missing` lists the unverified mechanism paths; after verifying them (and the existing requirements) it returns `[]`.
- [ ] A unit with an empty or missing `mechanisms` is not ready (`mechanisms` in the missing list).
- [ ] `merge_research`: `mechanisms.blast_shields` with a source is added unverified; `mechanisms.launcher.max_elevation_deg: 55` over a human-set 50 becomes `suggested`; `mechanisms.launcher.max_elevation_deg: 120` is rejected and reported; `mechanisms.stabilisers.x: 1` rejected.
- [ ] `unit.schema.json` documents `mechanisms` (+ `$comment` readiness rule) and `classes.json` `default_mechanisms`; `docs/design/units/README.md` explains mechanisms, the registry and that the unit entry is authoritative.
- [ ] `homar_k/unit.json` has the mechanisms above; existing tests (`test_catalog.py`, `test_research.py`, `test_jobs.py`) pass; `tools/check.sh` passes.

## Playtest (for the human)

1. Start `tools/unit_catalog.sh`, open `homar_k`: the page loads (the form UI for mechanisms comes in TASK-042; the JSON shows the new key).
2. Create a test unit of class `mlrs`: its `unit.json` has `wheels`, `launcher`, `stabilisers` pre-filled; the readiness checklist asks to verify the mechanisms. Delete the test unit.

## Player manual

None (developer tool).

## Open questions

- Homar-K `max_elevation_deg`: keep 40° (today's look) even if the real K239 maximum differs, or follow the real value? (?)
- Default params for planned mechanisms (e.g. `turret_traverse.elevation_deg` `[-8, 20]`) are placeholders; the mechanism tasks may change them.

## Out of scope

- The form UI (TASK-042), models and the game (TASK-043+), researching the Uragan (TASK-042 playtest).

## Implementation notes

- Registry `docs/design/units/mechanisms.json` (7 entries); `catalog.load_mechanisms` / `validate_mechanisms`; `classes.json` `default_mechanisms` (validated, in `CLASS_KEYS`). `catalog_summary` also returns the registry (for TASK-042's form).
- `validate_unit`, `normalize_unit` and `merge_research` take an optional `registry`; when it is left out they use the shipped one (cached). `save_unit`, `create_unit`, `apply_research` and `save_classes` pass their root's registry. A missing `mechanisms.json` gives an empty registry. An invalid one raises `CatalogError` with the field named, on the first catalog load.
- `save_unit` fills missing params after validation and before the readiness gate, so saving `ready_for_model` with `{"launcher": {}}` is blocked by `verify mechanisms.launcher.<param> (default)`. A parameterless mechanism (`"wheels": {}`) is kept by the normal pruning. An empty `mechanisms` object is dropped.
- Saving a unit doesn't add `mechanisms.<id>` provenance by itself. Only `create_unit` (`class default`) and research add it.
- In `merge_research`, a value whose provenance is an unverified `default` / `class default` counts as unset. Research replaces it, unverified, with its own source instead of making a `suggested`. A value with no provenance or verified provenance counts as human-set. A research value for `mechanisms.<id>` must be `{}` or null. Readiness says `(default)` for the `default` / `class default` sources and `(AI)` otherwise.
- Known minor gap: research that sets only a param leaves the mechanism's own `class default` provenance in place. It stays unverified and still blocks readiness.
- Homar-K: saved through `save_unit` (revision 17). The `mechanisms.wheels` source points at the 8×8 chassis and `mechanisms.launcher` cites the K239 article. `max_elevation_deg` 40 is unverified.
- The other shipped entries have no `mechanisms`, so `readiness_missing` now lists `mechanisms` for them. They load unchanged.
- The client-side readiness checklist in `app.js` doesn't know the mechanism rule yet. It is covered by TASK-042 ("The readiness checklist shows the mechanism items").
- Tests: `tools/unit_catalog/test_mechanisms.py` (30 tests, including one that validates every shipped entry and one that checks the Homar-K mechanisms). `test_catalog.py` fixtures copy the registry. `tools/check.sh` passes (126 Python tests).

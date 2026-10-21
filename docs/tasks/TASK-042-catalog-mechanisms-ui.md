# TASK-042: Unit catalog – edit mechanisms in the unit form; research and verify the Uragan

- **Status**: done
- **Layers**: tools (`tools/unit_catalog/app.js`, `index.html`, `style.css`, `server.py`, Python tests)
- **Depends on**: **TASK-041**
- **Model**: sonnet

## Goal

The human sees and edits a unit's mechanisms in the catalog tool like every other field: tick the mechanisms the real vehicle has, fill in their parameters, see which values came from AI research or class defaults and verify them. With it the Homar-K and the 9K57 Uragan entries get verified mechanisms, ready for the models (TASK-043 …, `/model-unit bm27_uragan`).

## Design

- `GET /api/catalog` also returns the registry (`mechanisms`: the parsed `mechanisms.json`); the unit form builds its Mechanisms section from it (no ids or types hard-coded in `app.js`).
- **Mechanisms section** in the unit form (after Silhouette features): one checkbox row per registry mechanism, in registry order, with its label, a `planned` tag for planned ones, and the description as a tooltip. Ticking adds the mechanism with default params; unticking removes it (and its params/provenance on save).
- **Parameter fields** under a ticked mechanism, from the param type: `number` → number input with min/max/step 1 and the unit; `enum` → select; `angle_range` → two number inputs (min, max) plus a "full" checkbox when `allow_full` (checked disables the two inputs). The `help` text is shown under the field.
- **AI / default markers**: the existing provenance UI applies per path (`mechanisms.<id>` on the row, `mechanisms.<id>.<param>` on each field): yellow marker with the source (`AI` with link, or `default` / `class default`), "✓ Verified", editing clears it, suggestions with "Use" / "Dismiss".
- **"Apply class defaults"** button: adds the class's `default_mechanisms` that are missing (never removes anything).
- Server-side validation errors (TASK-041) are shown next to the field like other field errors.
- The readiness checklist shows the mechanism items from `readiness_missing`.

## Acceptance criteria (testable)

- [ ] `test_catalog.py` / `test_mechanisms.py`: `GET /api/catalog` contains the registry; `PUT /api/units/<id>` with `mechanisms.launcher.traverse_deg = [10, 30]` → 400 with the field `mechanisms.launcher.traverse_deg`; a valid PUT round-trips unchanged (keys in registry order, `revision` + 1); removing a mechanism removes its provenance entries.
- [ ] `app.js` has no mechanism id or param name literals (checked by a small Python test that greps `app.js` for the registry ids – `wheels`, `launcher`, `traverse_deg` … must not occur).
- [ ] **Uragan entry**: the human runs "Research with AI" on `bm27_uragan` (playtest step 3), verifies the values; the result is committed with this task. Expected after verification (all values are to be checked against sources – (?) = not known to the designer):
  - `wheels: {}`;
  - `launcher`: `stowed: "front"` (tubes over the cab when travelling (?)), `traverse_deg` limited (the human's working example is `[-30, 30]`; real value (?)), `max_elevation_deg` 55 (?);
  - `stabilisers: {}` – rear jacks (?);
  - `blast_shields: {}` – armoured window shields lowered over the cab before firing (?); if the research doesn't confirm them, leave the mechanism out and note it in the implementation notes (TASK-046 stays `idea`).
- [ ] **Homar-K entry**: `max_elevation_deg` verified or corrected by the human (research of the real K239 maximum (?)); whether it has stabiliser jacks (how many, where) is recorded in `notes` for TASK-045 (?).
- [ ] `tools/check.sh` passes.

## Playtest (for the human)

1. `tools/unit_catalog.sh`, open `homar_k`: the Mechanisms section shows Wheels and Launcher ticked, Launcher with "full" checked, max elevation 40 marked `AI`/unverified, stowed `rear`.
2. Untick and re-tick Launcher: params return to defaults; save; the JSON keeps the registry order.
3. Open `bm27_uragan`, click "Research with AI". After the job: mechanisms proposed with sources and marked; check them against photos/videos of the firing position (stowed direction, traverse limits, jacks, window shields), correct and verify.
4. Enter traverse `[10, 30]`: the form shows the error "must include 0".
5. Create a test `mlrs` unit: Wheels, Launcher, Stabilisers are pre-ticked and marked `class default`; delete it.

## Player manual

None (developer tool).

## Out of scope

- Models and animation (TASK-043 …); editing `mechanisms.json` from the UI (it is edited by agents with the mechanism tasks).

## Implementation notes

- Server side needed no change: TASK-041's `catalog_summary` already returns the registry, and `save_unit` validates and prunes mechanism provenance. New HTTP tests in `test_mechanisms.py` (`TestMechanismsHttp`) cover it through the real handler: the registry in `GET /api/catalog`, a 400 for `[10, 30]` with the field `mechanisms.launcher.traverse_deg`, a round-trip in registry order with `revision` + 1, and stale provenance pruned after a removal.
- `TestAppHasNoRegistryLiterals` reads every id and param name from the shipped `mechanisms.json` and fails if one occurs in `app.js` as a quoted literal or a whole word. A future registry name that is also an ordinary word in `app.js` (e.g. `height`) will need an exception there.
- `app.js` builds the Mechanisms section (after "For the modeler") from `catalog.mechanisms` only. It handles the param types `number`, `enum` and `angle_range` (with `allow_full`).
  - Ticking a mechanism adds its params with `default` unverified provenance, the same as the server's fill-in. "Apply class defaults" adds the missing ones with `class default` provenance.
  - Unticking removes `mechanisms.<id>` and `mechanisms.<id>.*` provenance.
  - The provenance UI (`field()`) labels the `default` / `class default` sources as "default" instead of "AI".
  - Server `mechanisms.*` errors are shown under the row or field, and they survive re-renders of the section.
  - The client readiness checklist mirrors `readiness_missing`: at least one mechanism, plus "Verify mechanisms.<path> (AI|default)".
- Unticking "full" on an angle range gives `[registry min, registry max]`. Clearing a number input stores `""`, which the server rejects with a field error.
- A mechanism ticked by hand gets no row-level provenance, so no row marker. Its params do get markers.
- No JS unit tests exist (the tool has no JS test harness). The UI was checked by reading the code and `node --check` only, and needs the playtest.
- **Playtest, 2026-10-21 (human)**: the form works after one fix. The section's rows were passed to `replaceChildren` as an array and showed as `[object HTMLDivElement]`; they are now spread.
- **Uragan** (research + human verification, all from FAS 9P140, cross-checked with ru.wikipedia):
  - `wheels`;
  - `launcher` with `traverse_deg` `[-30, 30]`, `max_elevation_deg` 55 and `stowed` `rear`. The FAS text says "during travel the launcher assembly is oriented rearward", which matches the silhouette features. The task had guessed `front` (?).
  - `stabilisers`: two hydraulic jacks at the rear.
  - `blast_shields`: a cab blast shield raised for firing. **TASK-046 is moved from `idea` to `ready`.**
  - A research suggestion for `dimensions.height` (3.223 vs 3.225) is left pending.
- **Homar-K**: the human verified `max_elevation_deg` 40, but its source still reads "the real K239 maximum is to be researched (?)". `notes` doesn't record stabiliser jacks, so TASK-045 has to research them.
- `TestShippedEntries` now checks that every mechanism path of both entries is verified, and checks the Uragan's values.

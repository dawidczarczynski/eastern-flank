# TASK-183: Batch mode and pilot: several units from GLBs in one run

- **Status**: in progress
- **Layers**: tooling (presentation tools, no game rules)
- **Depends on**: TASK-182
- **Sections**: ADR 0010 (budgets), ADR 0014 (mechanisms), docs/TOOLS.md (render_unit, unit_catalog)
- **Model**: sonnet

## Goal

Many units quickly: all new GLBs are analysed in one go and the units modelled one after another with the measured data ready.

## Acceptance criteria (testable)

- [ ] `tools/analyze_glb.sh --all` analyses every unit that has a `reference.glb` and no fresh `measurements.json` (skips unchanged by hash); prints a table of warnings per unit.
- [ ] `/model-unit --queue` takes the next `ready_for_model` unit with a GLB after each finished one (one unit per agent run, as before).
- [ ] Pilot: three units of different kinds (a squad, a tank, a launcher) modelled this way; time and token cost per unit written in Implementation notes next to the earlier procedural-only runs (`tools/task_cost.py`).
- [ ] `docs/AGENTIC_WORKFLOW.md` describes the GLB workflow.

## Playtest (for the human)

1. Drop GLBs for two units, run the batch analysis, then `/model-unit --queue`.
2. Check both render sheets and the IoU report.

## Player manual

none

## Out of scope

- Shipping the GLB in the game or importing it as an asset: it is a reference only (the game model stays procedural, MeshKit). GLBs live outside git; `measurements.json` and reference renders are committed.

## Implementation notes

Done (tooling):
- `tools/analyze_glb.sh --all [--force] [--no-measure]`: analyses every unit with a `reference.glb` whose `measurements.json` / `normalisation.json` is missing or stale (sha256 stamp `reference.glb.sha256` per unit, committed; without a stamp an older `measurements.json` counts as stale); prints a table of normalisation + measurement warnings per unit; exit 1 if a unit failed. Success is judged by the `Render saved:` line, because the Windows Godot build exits 5 on leaked-resource noise after a good render (also true for the single-unit call; not changed). Verified on the two existing GLBs (2s19_msta_s, k9_thunder): skip path and forced path.
- `/model-unit --queue` added to `.claude/skills/model-unit/SKILL.md` (one unit per agent run, max 3 units per session).
- GLB workflow described in docs/AGENTIC_WORKFLOW.md and docs/TOOLS.md.

**Open – pilot (acceptance criterion 3)**: needs GLBs for a squad, a tank and a launcher; only 2 GLBs exist (self-propelled howitzers 2s19_msta_s, k9_thunder, both already modelled) and the modelling runs are long agent sessions started by the human. Time / token cost per unit (`tools/task_cost.py`) to be filled in after the pilot.

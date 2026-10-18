# TASK-036: Unit model pipeline – model per unit, faction camo, `tools/render_unit.sh`, contract test, `/model-unit`

- **Status**: ready
- **Layers**: presentation + tools (registry, render script options and contract tested in `tests/unit/`)
- **Depends on**: **TASK-030** (`MeshKit`, baker), **TASK-029** (materials move into `ModelParts`), **TASK-038** (faction data for camo). Soft: TASK-037 (catalog – the render tool and skill read it when present). Agent: `.claude/agents/unit-modeler.md`; skill: `.claude/skills/model-unit/SKILL.md`.
- **Model**: sonnet

## Goal

Prepare the ground for many units and many factions: every unit has its own model file, the faction only supplies the camouflage, and the `unit-modeler` agent can render a single model from fixed angles next to a reference image to compare it. Nothing changes visually yet.

## Design

- **Folder** `src/presentation/models/`:
  - `model_parts.gd` (`class_name ModelParts`, static): the mesh/material caches and helpers that are in `UnitModels` today (`_material`, `_box`, `_cyl`, `_add`, mesh caches), the TASK-029 camo materials `camo(faction: FactionDefinition, preset)` and PBR palette, `accent(faction)`, `vest(faction)`, and the bake-and-cache wrapper `cached(key, builder: Callable) -> Node3D` (returns a copy sharing meshes; key = unit id + faction id).
  - One file per unit model, named after the unit id: `infantry.gd`, `cavalry.gd`, `rocket_artillery.gd` today (TASK-039 renames them to real unit ids). Each: `static func build(faction: FactionDefinition) -> Node3D`, loaded with `load("res://src/presentation/models/%s.gd" % id)` and cached. Shared sub-assemblies (a soldier body, a truck chassis) go into `model_parts.gd` or `models/parts/*.gd`.
- **Registry** in `UnitModels`: `build(definition_id, owner_id)` resolves the owner's faction (TASK-038), loads the model script for the unit id, keeps root/`Model`/`MODEL_SCALE`/facing, and falls back to the magenta placeholder with a warning when no model file exists (new units can be playable before they're modeled). Locomotion choice by `is_vehicle` stays until TASK-039 introduces `mobility`.
- **Scale constant** `UnitModels.METERS_PER_UNIT := 10.0` (1 model unit = 10 m before `MODEL_SCALE`).
- **`tools/render_unit.sh <unit_id> [--faction=<id>] [--views=side,front,top,three_quarter] [--reference=path] [--out=path]`** (+ `tools/render_unit.gd`, options in a pure `tools/render_unit_options.gd` like `screenshot_options.gd`):
  - Scene with only the model: background `#5a5d55`, battle sun direction and sky ambient (TASK-026), shadows, ground plane with a grid in model space (faint every 0.1 unit = 1 m, stronger every 0.5 = 5 m).
  - Orthographic `side` (+X to the right), `front` (looking along −X), `top` (+X to the right), all at the **same scale**, framed on the AABB with 10 % margin; `three_quarter` perspective FOV 24° framed like the TASK-034 portrait.
  - Default reference: the first `side` (or `drawing`) image from `docs/design/units/units/<unit_id>/unit.json` when the catalog has one; `--reference` overrides.
  - Writes per-view PNGs and a **sheet** (2 × 2 views + the reference scaled to the side view's height next to it), default `.screenshots/units/<unit_id>_<faction>_sheet.png` (the catalog's "Model review" screen shows it).
  - Last stdout lines: `Render saved: <sheet>` and `Stats: aabb_m=<L>x<W>x<H> triangles=<n> mesh_instances=<n> pivots=<names>`; when the catalog entry has dimensions, also `Real: <L>x<W>x<H> m, diff: <±%>`.
  - Exit codes and timeout as `tools/screenshot.sh`; needs a display.
- **Contract test** – `tests/unit/test_unit_models.gd` loops over every model file × every faction in `data/factions/` and checks: stands on y ≈ 0 (±0.005), centred in x/z (±0.05); footprint after `MODEL_SCALE` length ≤ 1.15, width ≤ 0.8; required pivots by kind (vehicles `Wheel*` ≥ 4; tanks `Turret`; rocket artillery `Pod` with ≥ 6 `Mouth*` on its front face; infantry `Soldier0…4` with `Rig`, kneelers `Kneel` + `Stand`); two builds with the same faction share meshes, different factions use different camo materials; budgets: ≤ 25 000 triangles per vehicle, ≤ 20 000 per squad, ≤ 24 `MeshInstance3D` outside `Wheel*`/`Soldier*` pivots (numbers printed). Existing specific tests (locomotion, facing, hit reset, unknown id) keep passing.
- **Skill `/model-unit <unit_id> [--faction=<id>]`** (file already drafted in `.claude/skills/model-unit/SKILL.md`; adjust it to the final tool flags).

## Acceptance criteria (testable)

- [ ] `src/presentation/models/` with `model_parts.gd` and one file per current unit; `unit_models.gd` has no mesh-building code (registry, build, facing, pose functions only).
- [ ] Contract test runs for all models × factions and passes with the current models.
- [ ] `tests/unit/test_render_unit_options.gd`: defaults (first faction in the unit's operators or `poland`, all four views, default out path), `--faction=russia`, `--views=side,top`; unknown faction / unknown view / missing id → error code 2.
- [ ] `tools/render_unit.sh cavalry --faction=russia` produces the sheet and the stats line; the agent reads the sheet and confirms the three ortho views are at the same scale on the grid. Two runs give identical PNGs.
- [ ] A unit id without a model file builds the placeholder (test) instead of crashing.
- [ ] `CLAUDE.md` "Commands" and `docs/AGENTIC_WORKFLOW.md` document `tools/render_unit.sh` and `/model-unit`.
- [ ] Visual check: `tools/screenshot.sh` before/after identical (pure refactor).

## Playtest (for the human)

1. Run `tools/render_unit.sh rocket_artillery --reference=<any image>` and open the sheet: side, front, top on a grid, three-quarter view, your image next to the side view.
2. Start a battle: all units look exactly as before.

## Out of scope

- New models (TASK-031 … TASK-033, then `/model-unit` per catalog entry).

## Implementation notes

_Filled in by the agent when done._

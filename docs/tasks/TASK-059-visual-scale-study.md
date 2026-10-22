# TASK-059: Visual scale study – units vs. trees vs. hexes (realism vs. readability decision)

- **Status**: done (produces material for the human's decision (b); the final values are set by the human)
- **Layers**: presentation (scale constants gathered in one place, screenshot hook), tools (`tools/screenshot.gd` env var), tests
- **Depends on**: soft **TASK-052** (judge with the new camera), soft **TASK-051**. Blocks TASK-060 (tree size) and informs TASK-057/058/063/064.
- **Model**: sonnet

## Goal

Decide how large units are relative to trees and hexes. Today a tank (≈ 10 m real) is ≈ 1.14 world units long – two thirds of a hex – while a tree is 0.2–0.35 units tall (crown mesh ≈ 0.27 × instance scale 0.7–1.3), i.e. ≈ 1.5–2.7 m at the unit scale (1 unit ≈ 7.7 m) – roughly a seventh of a real 15–20 m tree next to the vehicles. That reads well but looks like a toy. The human picks a compromise from side-by-side screenshots.

## Open questions / decision needed (human)

- **(b) Realism vs. readability.** Target: a Steel Division / Combat Mission-like compromise – realistic terrain, clean minimal UI, units still easy to find and click. Candidate presets (starting points):

  | preset | `UnitModels.MODEL_SCALE` | tree scale × | bush scale × | note |
  |---|---|---|---|---|
  | `current` | 1.3 | 1.0 | 1.0 | today |
  | `balanced` | 1.1 | 1.8 | 1.4 | units still dominant, forests read as forests |
  | `realistic` | 0.9 | 2.6 | 1.8 | trees ≈ 6–10 m at the unit scale (about half real height); units can hide in forests |

- If `realistic`-like trees are chosen, units inside forests may be hidden → a follow-up for an occlusion silhouette (units drawn as an outline through foliage) is likely needed; and the unit label/marker becomes more important.
- Does grass (TASK-057) and decal size follow the unit scale or the world (hex) scale? Proposed: world scale = the same real metres as the trees.

## Design

- Gather the visual scale constants in one presentation file (`src/presentation/visual_scale.gd`, `class_name VisualScale`, static constants + `preset(name) -> Dictionary`): `unit_model_scale` (today `UnitModels.MODEL_SCALE`), `tree_scale`, `bush_scale`, `rock_scale`. `UnitModels`, `ScatterPlanner`/`MapView` scatter read them from there; the default remains `current` so the game is unchanged after this task.
- Debug hook: `SCREENSHOT_SCALE_PRESET=<name>` (read by `tools/screenshot.gd`, like `SCREENSHOT_SELECT_UNIT`) applies a preset before the battle is built.
- Produce screenshots for each preset at two framings (default distance and close-up `tools/readme_screenshot.sh` framing) into `.screenshots/scale/<preset>_{default,close}.png`, plus one with a unit next to a forest edge. Read them and describe the differences in the implementation notes for the human (which units are hard to see, clicking areas, how forests read).
- The model-size contract (`tests/unit/test_unit_model_contract.gd`, "≤ 1.15" length check in the model files' comments) must take the scale from `VisualScale` – if a preset changes it, the contract follows.

## Acceptance criteria (testable)

- [ ] `tests/unit/test_visual_scale.gd`: `preset("current")` equals today's values (1.3 / 1.0 / 1.0 / 1.0); `preset("balanced")`, `preset("realistic")` have the table values; unknown name → `current` with a warning.
- [ ] With the default preset all existing tests pass unchanged (scatter positions, model sizes, unit picking).
- [ ] A test builds a unit with `unit_model_scale = 0.9` and checks its AABB shrinks proportionally; a tree instance transform scales with `tree_scale`.
- [ ] Screenshots for the 3 presets exist (paths in the notes) and the notes describe them.
- [ ] `docs/images/gameplay.png`: unchanged (default preset); re-render and commit only after the human has chosen a different preset (that change is a one-line constant edit + re-render, done in this task if the decision arrives in the same session, otherwise in a follow-up).

## Playtest (for the human)

1. Look at the 6 screenshots in `.screenshots/scale/` (or run `SCREENSHOT_SCALE_PRESET=balanced tools/run_windows.sh` if the hook also works for the game).
2. For each: can you spot all units at the default zoom within a second? Do forests look like forests? Does a tank next to a forest look plausible?
3. Pick a preset (or mixed values) and record the decision in GDD "Visual direction: realism".

## Player manual

None now. If the chosen preset changes how units hide in forests, a later task adds a note.

## Out of scope

- Occlusion silhouettes, changing hex size, changing unit counts per hex.

## Implementation notes

- `src/presentation/visual_scale.gd` (`VisualScale`): presets `current` / `balanced` / `realistic` from the table, `preset(name)` (copy; unknown → `current` + warning), static active preset with `apply()` / `reset()` / `apply_values()` (the last one for tests and experiments) and accessors `unit_model_scale()`, `tree_scale()`, `bush_scale()`, `rock_scale()`. Default `current` → the game is unchanged.
- `UnitModels.MODEL_SCALE` removed; `UnitModels.build()` uses `VisualScale.unit_model_scale()`. The model contract test scales its length/width limits by `unit_model_scale() / 1.3`. The model files' "x unit scale 1.3" comments describe the `current` preset.
- `MapView`: `_tree_transforms(trees, size_multiplier)` scales instances about their base (trees + trunks × `tree_scale`, bushes × `bush_scale`, rocks × `rock_scale`); `ScatterPlanner` and scatter positions are untouched (larger presets let crowns overlap more).
- Hook: `SCREENSHOT_SCALE_PRESET=<name>` in `tools/screenshot.gd` (passed to the Windows build via `tools/screenshot.sh`). **Only the screenshot tool reads it** – `SCREENSHOT_SCALE_PRESET=… tools/run_windows.sh` does nothing in the game.
- Tests: `tests/unit/test_visual_scale.gd` (preset values, unknown-name fallback, default active preset, unit AABB at 0.9 is 0.9/1.3 of the one at 1.3, tree transform scales with `tree_scale` keeping its position).

### Screenshots (`.screenshots/scale/`)

`<preset>_default.png` (default framing), `<preset>_close.png` (README framing: `SCREENSHOT_SELECT_UNIT=2 SCREENSHOT_CAMERA=2,-40,11`), `<preset>_forest.png` (`SCREENSHOT_CAMERA=7,200,9`: Russian infantry, T-72B3 and BM-27 at the east forest edge). Reproduce: `SCREENSHOT_SCALE_PRESET=balanced SCREENSHOT_CAMERA=7,200,9 tools/screenshot.sh out.png`.

- **current**: all 9 units easy to spot at the default zoom. Forests are a carpet of toy trees; infantry and tanks are taller than the trees, and the BM-27 is as tall as the conifers. Units are never hidden, and their click areas are the largest (≈ ⅔ of a hex).
- **balanced**: forests read as dense stands. Polish units on open ground stay clear. The T-72B3 at the forest edge is about crown height, with a crown overlapping its front. Russian infantry inside the forest is almost fully hidden, so you find it by its label. Close-up: the Homar is partly covered by trees on the neighbouring hex. Click areas are ≈ 15 % smaller, and some are covered by foliage.
- **realistic**: the east forest is a solid canopy. Units in or next to it (T-72B3, BM-27, infantry) show only as labels and fragments of their hex outline. Trees are 2–3× tank height, so they look plausible, but the units can't be seen or clicked well. This preset needs the occlusion-silhouette follow-up.
- Labels and hex outlines stay readable in all three presets. Clicking was not tested; the click-area remarks come from sizes and overlap in the screenshots.

**Decision (human, 2026-10-22): `balanced`.** `VisualScale.DEFAULT_PRESET = &"balanced"`; an unknown preset name now falls back to the default (`balanced`). Tests updated (`test_default_active_preset_is_balanced`; the proportional-shrink test pins `current` first). Recorded in GDD "Visual direction: realism", and the open question was removed. `docs/images/gameplay.png` re-rendered: trees now reach tank height, and the Homar is slightly covered by one conifer. The model files' "x unit scale 1.3" comments describe the pre-decision `current` scale that the contract limits are written for.

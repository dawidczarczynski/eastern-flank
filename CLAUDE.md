# Eastern Flank – turn-based 3D strategy (Godot 4, GDScript)

Vision: docs/VISION.md · Game design: docs/GDD.md · Player manual: docs/MANUAL.md · Architecture: docs/ARCHITECTURE.md · Agent workflow: docs/AGENTIC_WORKFLOW.md · Tasks: docs/tasks/

## Commands

- `tools/check.sh` – lint + all tests. **Run it before reporting that a task is done.**
- `tools/test.sh [--verbose] [filter]` – headless tests only (e.g. `tools/test.sh test_commands`); prints only failures and the summary, full log in `.test.log`
- `tools/lint.sh [--fix]` – gdformat + gdlint
- `tools/backlog.py [--fix]` – checks/fixes `blocked`/`ready` in docs/tasks/BACKLOG.md against dependencies, and that each row's status equals its task file's Status line; run after any status change
- `tools/doc.py gdd|architecture [heading]` – print one section of a big doc instead of the whole file (no heading = list headings with line numbers); `tools/backlog.py --ready` lists ready tasks. **docs/GDD.md (~120 KB), ARCHITECTURE.md and BACKLOG.md must never be read whole.**
- `docs/CODEMAP.md` – generated one-line-per-file map of `src/` (class name + purpose): **Grep it** to find where something lives instead of exploring; kept current by `tools/check.sh`.
- `tools/screenshot.sh [out.png]` – render the battle scene to `.screenshots/battle.png`; Read it to check visual changes
- `tools/readme_screenshot.sh` – re-render `docs/images/gameplay.png`
- `tools/simulate.sh N [--seed=S] [--scenario=…]` – headless AI-vs-AI matches (balancing)
- Other tools (devtools hub, backlog view, task_cost, run/run_windows, render_unit, teaser, import_map, unit_catalog) and all options: **docs/TOOLS.md** – read it before using one of them.

## Hard architecture rules

1. **`src/core/` and `src/ai/` are pure logic**: only `RefCounted`/`Resource`, no `Node`, scenes, `Input`, `get_tree()`, autoloads or `await`. This keeps everything testable headless.
2. **Game state is changed only by commands** (`src/core/commands/`, extending `Command`), executed through `GameSimulation.execute()`. The player, the AI and (later) network/replay all use the same path.
3. **The presentation layer (`src/presentation/`, `scenes/`) only reads state and reacts to events** from `GameSimulation.event_emitted`. No game rules in the view layer.
4. **Randomness only through `GameState.rng`** (seed stored in the state) – the simulation must be deterministic.
5. **Balance data lives in resources** (`data/**/*.tres`, classes in `src/core/data/`), not in constants in code.
6. Every new game rule = a test in `tests/unit/` (TDD: first a failing test).

## Conventions

- Static typing everywhere (`var x: int`, `:=`, return types). The `untyped_declaration` warning is enabled.
- Tab indentation. Files `snake_case.gd`, classes `PascalCase` via `class_name`. Private members prefixed with `_`.
- Events are a `Dictionary` with a `"type"` key (StringName, e.g. `&"unit_moved"`) – add new types to the table in docs/ARCHITECTURE.md.
- **Visual work follows the Claude Design mockups** in `docs/design/` (layout, shapes, colours, fonts, sizes): read the mockup for the component, reuse existing HUD parts from `src/presentation/ui/` (grep CODEMAP) instead of inventing a look, and compare your screenshot with the mockup before reporting; state any deviation and why. **A new element with no mockup and no similar component** (grep `docs/design/` and CODEMAP) is not improvised: run `/design-ui` first and implement only the variant the human picks; minor tweaks to an existing component need no new design.
- Everything in English: code, identifiers, comments, documentation, commit messages and UI text.
- Tests: file `tests/unit/test_*.gd`, `extends TestCase`, methods `test_*`, shared data in `tests/fixtures.gd`. A `MapView` build costs ~0.7–3 s: tests that only read one share it via `before_all`/`after_all` and `static var` (`Fixtures.map_view`, `Fixtures.reset_map_view`), see `tests/unit/test_map_view_backdrop.gd`.

## Performance budget

- The game must hold **60 FPS** on the target GPU (HIGH quality, focused window). Never trade frame rate for visuals: a new effect, shader or scatter layer that drops below 60 FPS must be optimised or put behind a quality level, not accepted.
- `FramePacing` caps a focused window at 60 FPS and a background one at 5 FPS (src/presentation/frame_pacing.gd) – keep it so an idle game stays quiet.

## Godot files (.tscn / .tres)

- They are text files – you may edit them, but carefully: don't invent `uid=`, keep `id`s consistent in `ext_resource`/`sub_resource`.
- Prefer building complex node trees in code, or ask the human to do it in the editor.
- Never edit `.godot/` (generated cache) or `*.import` files.

## Verification limits

The agent cannot see the game window. After changes to the visual layer, describe in the summary **exactly what the human should check in the game** (playtest steps). Don't claim something "looks good" if you haven't seen it.

## When a task is done

1. `tools/check.sh` passes.
2. Update the status in docs/tasks/BACKLOG.md **and** in the task file's `- **Status**:` line, and fill its "Implementation notes" section (`tools/backlog.py` fails when the two statuses differ); after any status change run `tools/backlog.py --fix` (status icons, and unblocked tasks move from `blocked` to `ready`).
3. If the task is player-facing, docs/MANUAL.md is updated (by `game-designer`).
4. Record architectural decisions as ADRs in docs/adr/.
5. If the change is visible in the battle scene (presentation, shaders, HUD, unit models, terrain, scenario), re-run `tools/readme_screenshot.sh` (it also refreshes the main menu backdrops `assets/menu/*.png`), Read `docs/images/gameplay.png` to check it still looks good, and commit the images with the change.

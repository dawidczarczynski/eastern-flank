# Eastern Flank – turn-based 3D strategy (Godot 4, GDScript)

Game design: docs/GDD.md · Player manual: docs/MANUAL.md · Architecture: docs/ARCHITECTURE.md · Agent workflow: docs/AGENTIC_WORKFLOW.md · Tasks: docs/tasks/

## Commands

- `tools/check.sh` – lint + all tests. **Run it before reporting that a task is done.**
- `tools/test.sh [--verbose] [filter]` – headless tests only (e.g. `tools/test.sh test_commands`); prints only failures, script errors and the summary, the full Godot log is in `.test.log`; without a filter the test files run in up to 4 parallel Godot processes (`JOBS=N` overrides, `TEST_TIMES=1` prints per-test times)
- `tools/lint.sh [--fix]` – gdformat + gdlint
- `tools/backlog.py [--fix]` – checks (or fixes) `blocked`/`ready` in docs/tasks/BACKLOG.md and the task files against the hard dependencies; run by `tools/check.sh`
- `tools/run.sh [--editor]` – run the game / editor (needs a GUI; usually done by the human)
- `tools/run_windows.sh [--editor] [--import]` – run with the Windows Godot build from WSL (GPU rendering; the WSLg build falls back to slow software rendering)
- `tools/screenshot.sh [out.png] [--frames=N] [--windows|--linux]` – render the battle scene to a 1280×720 PNG (default `.screenshots/battle.png`) and read it with the Read tool to check visual changes (HUD states: `SCREENSHOT_SHOTS=hover:2,select:2,toast,targeting,banner` captures several in one run as `<out>_<state>.png` – one ~30 s run instead of one per state; more debug variables are listed in the header of tools/screenshot.gd); under WSL it uses the Windows Godot console build (GPU, D3D12, Forward+ with SSAO – what the human sees) when found, `--linux` forces the WSLg software renderer (Compatibility look)
- `tools/readme_screenshot.sh` – re-render the README gameplay shot `docs/images/gameplay.png` (fixed close-up framing, same requirements as `tools/screenshot.sh`)
- `tools/render_unit.sh <unit_id> [--faction=<id>] [--views=side,front,top,three_quarter] [--reference=path] [--out=sheet.png] [--windows|--linux]` – render one unit model alone on a 1 m model-space grid (orthographic side/front/top at the same scale + three-quarter) next to a reference image into `.screenshots/units/<id>_<faction>_sheet.png`; last stdout lines are `Render saved`, `Stats` (AABB in m, triangles, mesh instances, pivots) and `Real` (vs. the unit catalog); used by `/model-unit`; renders with the same Godot build choice as `tools/screenshot.sh`
- `tools/simulate.sh N [--seed=S] [--max-turns=T] [--factions=P0,P1] [--verbose]` – N headless AI-vs-AI matches: win rates and average match length (balancing); `--factions` picks the players' factions (default `poland,russia`)
- `tools/unit_catalog.sh [--port=8765]` – local web tool (Python stdlib, 127.0.0.1 only) for the human to collect real-unit references (facts, dimensions, images, factions) into `docs/design/units/`; it can run `/research-unit` and `/model-unit` as headless Claude Code jobs (ADR 0008); Python tests run in `tools/check.sh`

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
2. Update the status in docs/tasks/BACKLOG.md and in the task file ("Implementation notes" section); after any status change run `tools/backlog.py --fix` (status icons, and unblocked tasks move from `blocked` to `ready`).
3. If the task is player-facing, docs/MANUAL.md is updated (by `game-designer`).
4. Record architectural decisions as ADRs in docs/adr/.
5. If the change is visible in the battle scene (presentation, shaders, HUD, unit models, terrain, scenario), re-run `tools/readme_screenshot.sh`, Read `docs/images/gameplay.png` to check it still looks good, and commit it with the change.

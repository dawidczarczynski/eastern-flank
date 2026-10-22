# Agentic development – proposal

## The main problem and our answer to it

An AI agent cannot see the game window and doesn't "feel" the gameplay. So every decision in this project serves one goal: **make as much as possible verifiable automatically, as text and without a GUI**, and leave the human what they are irreplaceable at – judging whether the game is fun and looks good.

| Decision | Why it helps the agent |
|---|---|
| Logic in pure GDScript (`src/core`, `src/ai`), no nodes | Headless tests in seconds, without a window or the editor |
| All state changes as commands | One path for the player and the AI; a match = seed + command list → replay, bug reproduction |
| Determinism (a single `rng` in the state) | Tests are repeatable, a bug from a playtest can be reproduced |
| Data in `.tres` | Balance changes without touching code; text files, readable in diffs |
| Own test runner instead of an addon | Zero dependencies, a single `tools/test.sh` script with an exit code |
| `gdformat` hook after every edit | Syntax errors reach the agent immediately, not only at test time |
| Small tasks with acceptance criteria | The agent knows when it's done; criteria = tests |

## Roles

| Role | Who | Scope |
|---|---|---|
| Product owner / playtester | **You** | Vision, priorities, acceptance, judging "feel" and looks |
| `game-designer` | subagent | GDD, writing up tasks, balance in `data/`, player manual (`docs/MANUAL.md`) kept in sync with what is implemented |
| `gameplay-engineer` | subagent | `src/core`, `src/ai`, tests (TDD) |
| `presentation-engineer` | subagent | 3D scenes, camera, animations, UI, shaders |
| `unit-modeler` | subagent | Procedural model per real unit (`src/presentation/models/`), render-compare loop against the unit catalog; run via `/model-unit <id>`; the catalog is edited with the local web tool `tools/unit_catalog.sh` |
| `reviewer` | subagent | Checks compliance with the architecture and criteria, read-only |
| Orchestrator | main Claude Code session | Drives a task with the `/implement-task` skill, delegates, verifies |

Definitions: `.claude/agents/*.md`, process: `.claude/skills/implement-task/SKILL.md`.

Models: the engineers and the reviewer default to Sonnet, `game-designer` to Opus. Each task file has a `- **Model**:` line (`sonnet` or `opus`); `/implement-task` passes it to the engineers, reviews always run on Sonnet. Opus is reserved for hard tasks (tricky algorithms, determinism, timing between systems, large refactors). Start a fresh session per task – a long session makes every orchestrator turn more expensive.

## Work loop

```
idea ──► game-designer ──► docs/tasks/TASK-NNN.md (acceptance criteria)
                                   │
                         /implement-task TASK-NNN
                                   │
             gameplay-engineer: test fails → implementation → test passes
                                   │
             presentation-engineer: view reacts to new events
                                   │
                tools/check.sh ──► reviewer ──► fixes
                                   │
             game-designer: docs/MANUAL.md (player-facing changes)
                                   │
                  You: playtest (steps from the summary) ──► commit
```

Rules:
- **One task = one branch = one session.** Short sessions with a clean context work better than one huge one.
- **Logic first, then the view.** Logic is verifiable automatically; the view always needs you.
- **A bug from a playtest → first a test that reproduces it**, then the fix.
- You make the commit (or ask the agent to) after the playtest – git history is your checkpoint.

## Parallel work

When tasks touch different areas (e.g. combat in `src/core` and a new camera in `src/presentation`), run several sessions in separate **git worktrees** – each works on its own branch and copy of the files, so they don't overwrite each other:

```bash
git worktree add ../game-task-001 -b task-001
cd ../game-task-001 && claude "/implement-task TASK-001"
```

Avoid parallel work on the same `.tscn` file – scene conflicts merge badly.

## 3D graphics – realistically

The agent can't sculpt or texture-paint, but it builds convincing **procedural** miniatures from code (the v2 design shows the level: bevelled profile extrusions, lathes, a camouflage shader, PBR materials). The chosen path:
1. **Terrain and scatter**: procedural (height field, vertex colours, generated detail textures, instanced foliage) – TASK-016b, 018, 026 … 028.
2. **Units**: one procedural model per real unit (the faction only supplies camouflage), built with `MeshKit` (TASK-030) by the `unit-modeler` agent via `/model-unit <id>`. Input is the **unit catalog** (`docs/design/units/`, edited by the human in the local web tool `tools/unit_catalog.sh`, TASK-037): real dimensions, silhouette features, reference images, and the human's feedback on the last render. The agent iterates with `tools/render_unit.sh` (TASK-036): orthographic side/front/top views on a 1 m grid next to the reference image, dimensions vs. the real ones, triangle/mesh budgets, and a contract test (pivots, upright, footprint). Side-view line drawings and real dimensions give the best results; perspective photos only help with details.
3. **Fallback**: CC0 `.glb` packs (Kenney, Quaternius) in `assets/models/` if a procedural model can't reach the needed quality – a model file can then load a glTF instead, as long as it keeps the pivot contract.

## Next steps for the process (optional)

- **Screenshots for the agent** (done, TASK-006): `tools/screenshot.sh [out.png] [--frames=N] [--windows|--linux]` opens the battle scene in a 1280×720 window, waits N rendered frames (default 10), saves a PNG (default `.screenshots/battle.png`) and quits; the last stdout line is `Screenshot saved: <absolute path>`. The agent reads the PNG with its Read tool after a visual change instead of guessing. Same map, units and default camera every run (two runs give byte-identical PNGs). Exit codes: 0 saved, 1 blank/failed capture or script errors in the log, 2 no display or invalid arguments, 124 timeout (60 s for the whole run), 127 Godot not found. Under WSL it renders with the Windows Godot console build by default (`tools/windows_godot.sh`: found like `tools/run_windows.sh`, `GODOT_WIN` overrides; GPU, D3D12, Forward+ with SSAO, ~15 s), so agents see what the human sees; paths and the `SCREENSHOT_*` variables are passed through to Windows, and `Screenshot saved:` is a WSL path. `--linux` forces the Linux build, which needs a graphical environment (WSLg) and renders in software with the Compatibility look (no SSAO); `--windows` fails with 127 when the Windows build is missing. Debug variables: `SCREENSHOT_SELECT_UNIT=<id>` selects a unit and hovers a tile next to it, `SCREENSHOT_CAMERA=<unit id>,<yaw degrees>,<distance>` points the camera at a unit's tile. Follow-up: capturing a scripted game situation.
- **Unit render sheets** (TASK-036): `tools/render_unit.sh <unit_id> [--faction=<id>] [--views=side,front,top,three_quarter] [--reference=path] [--out=sheet.png] [--windows|--linux]` renders one model from `src/presentation/models/<unit_id>.gd` alone (without `VisualScale.unit_model_scale()`, faction camo, the battle scene's sun, flat `#5a5d55` background) on a grid in model space (faint every 0.1 unit = 1 m, stronger every 0.5 = 5 m). Orthographic `side` (+X right), `front` (looking along -X) and `top` share one scale, `three_quarter` is perspective (FOV 24, framed like the unit portraits). It writes one PNG per view and a sheet (2 x 2 views, the reference scaled to the height of a view cell on the right) to `.screenshots/units/<unit_id>_<faction>_sheet.png`. The default faction is the first of the catalog entry's `operators` that exists in `data/factions/` (else `poland`); the default reference is the first existing `side` (else `drawing`) image of `docs/design/units/units/<unit_id>/unit.json`, `--reference` overrides it. The last stdout lines are `Render saved: <sheet>`, `Stats: aabb_m=<L>x<W>x<H> triangles=<n> mesh_instances=<n> pivots=<names>` and, when the catalog has all three dimensions, `Real: <L>x<W>x<H> m, diff: <L%>/<W%>/<H%>` (model AABB in metres, 1 model unit = 10 m, vs. the real unit; length = overall length). The AABB covers visible nodes only; triangle and mesh counts include hidden poses (kneeling soldiers' `Stand`), the same rule as the contract budgets. Exit codes as `tools/screenshot.sh`; 2 also for a unit id without a model file, an unknown faction or view, or a missing id. Two runs give byte-identical PNGs. Under WSL it uses the Windows Godot console build (`Godot_v4.5.1-stable_win64_console.exe`, found like `tools/run_windows.sh` via `tools/windows_godot.sh`, `GODOT_WIN` overrides) by default: GPU rendering with D3D12 and Forward+ in ~15 s instead of the slow WSLg software renderer; paths are translated both ways, so `Render saved:` is a WSL path. `--linux` forces the Linux build (needs WSLg), `--windows` fails with 127 when the Windows build is missing. The model contract (upright, centred, footprint, pivots, budgets, shared meshes and camo) is checked for every model x faction by `tests/unit/test_unit_model_contract.gd`.
- **`/model-unit <unit_id> [--faction=<id>]`** (TASK-036): builds or reworks a unit's model from its catalog entry with the `unit-modeler` agent (render with `tools/render_unit.sh`, compare with the reference, at most 4 rounds), then checks `tools/check.sh`, the sheet and the battle screenshot, runs `reviewer` and sets the catalog status to `modeled`. The catalog's "Model review" screen shows the latest sheet next to the reference.
- **README screenshot**: `tools/readme_screenshot.sh` renders `docs/images/gameplay.png` (the shot at the top of README.md) with a fixed close-up framing. Every visible change to the battle scene re-renders it and commits it with the change (CLAUDE.md "When a task is done", `presentation-engineer`, `unit-modeler`, `/implement-task`), so the README always shows the current game. Under WSL it is rendered by the Windows Godot build (Forward+, SSAO), like all agent screenshots; renders from the Linux build (`--linux`) look different, so don't commit those as the README shot.
- **AI-vs-AI simulation** (TASK-012): `tools/simulate.sh N [--seed=S] [--max-turns=T] [--factions=<p0>,<p1>] [--verbose]` plays N headless matches (seeds S..S+N-1, default S=1, T=50, factions `poland,russia`; the output names them in a `Factions:` line) with `MatchRunner` (`src/ai/match_runner.gd`) and prints per-player win counts, draws (turn limit), errors and average match length – use it to judge balance changes in `data/**/*.tres` by numbers. Exit codes: 0 ok, 1 a match ended with `error` or script errors, 2 invalid arguments, 127 Godot not found.
- **Replay tests**: a recorded match (seed + commands) as a fixture; the test checks that replaying it produces the same final state. Protects against regressions in the rules.
- **CI** (GitHub Actions): `tools/install_godot.sh` + `tools/check.sh` on every PR.
- **MCP server for Godot**: there are community projects giving an agent access to the editor (scene tree, running, logs). Worth checking their current state once the simple flow becomes a limitation.

## How to start

1. `tools/install_godot.sh` (or your own Godot 4.5+ install, `godot` on PATH) and `pipx install "gdtoolkit==4.*"`.
2. `tools/check.sh` – should pass.
3. `tools/run.sh` – play the prototype.
4. Fill in docs/GDD.md together with the `game-designer` agent (the "Open questions" section).
5. `/implement-task TASK-001`.

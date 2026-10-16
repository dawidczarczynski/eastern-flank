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
| `game-designer` | subagent | GDD, writing up tasks, balance in `data/` |
| `gameplay-engineer` | subagent | `src/core`, `src/ai`, tests (TDD) |
| `presentation-engineer` | subagent | 3D scenes, camera, animations, UI, shaders |
| `reviewer` | subagent | Checks compliance with the architecture and criteria, read-only |
| Orchestrator | main Claude Code session | Drives a task with the `/implement-task` skill, delegates, verifies |

Definitions: `.claude/agents/*.md`, process: `.claude/skills/implement-task/SKILL.md`.

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

The agent won't model decent 3D models. Suggested path:
1. **Now**: procedural primitives (already in place – hexagonal tiles, capsules as units). Good enough to polish the gameplay.
2. **Later**: free CC0 packs in `.glb` format (e.g. Kenney – "Hexagon Kit", Quaternius) into `assets/models/`. The agent wires them into `MapView`/`UnitView`.
3. **What the agent does well**: shaders (water, fog of war, highlights), procedural map generation, materials, lighting, Blender Python scripts for batch processing of models.

## Next steps for the process (optional)

- **Screenshots for the agent**: a `tools/screenshot.sh` script that runs a scene, positions the camera, saves a PNG and exits. The agent can read images, so it gets a substitute for "sight" when making visual changes (works in WSL2 through WSLg).
- **Replay tests**: a recorded match (seed + commands) as a fixture; the test checks that replaying it produces the same final state. Protects against regressions in the rules.
- **AI vs AI simulations**: a headless script playing N matches and reporting statistics (who wins, match length) – a balancing tool for `game-designer`.
- **CI** (GitHub Actions): `tools/install_godot.sh` + `tools/check.sh` on every PR.
- **MCP server for Godot**: there are community projects giving an agent access to the editor (scene tree, running, logs). Worth checking their current state once the simple flow becomes a limitation.

## How to start

1. `tools/install_godot.sh` (or your own Godot 4.5+ install, `godot` on PATH) and `pipx install "gdtoolkit==4.*"`.
2. `tools/check.sh` – should pass.
3. `tools/run.sh` – play the prototype.
4. Fill in docs/GDD.md together with the `game-designer` agent (the "Open questions" section).
5. `/implement-task TASK-001`.

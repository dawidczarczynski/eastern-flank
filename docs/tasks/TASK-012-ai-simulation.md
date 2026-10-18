# TASK-012: Headless AI-vs-AI simulation script

- **Status**: done
- **Layers**: ai / tools
- **Depends on**: `Scenario.default_battle(seed)` from **TASK-011** (or TASK-005, whichever introduces it first). Useful after TASK-002/-010/-011 to tune their numbers.
- **Model**: sonnet

## Goal

A balancing tool for the designer: play many AI-vs-AI matches headless and get win rates and match length, so balance changes in `data/**/*.tres` are judged by numbers instead of gut feeling.

## Acceptance criteria (testable)

- [x] `MatchRunner` (`src/ai/match_runner.gd`, RefCounted, pure):
  - `static func play(seed_value: int, max_turns: int) -> Dictionary` – builds `Scenario.default_battle(seed_value)`, both players controlled by `AiPlayer`, loops `take_turn` while `winner == -1` and `state.turn <= max_turns`. Returns `{"seed": int, "winner": int, "turns": int, "result": "victory" | "turn_limit", "commands": int}` where `turns` is `state.turn` at the end for a victory and `max_turns` for a turn-limit draw (`winner == -1`), `commands` = `sim.history.size()`.
  - Safety: if the loop runs more than `max_turns * player_count + 1` iterations, `play` stops and returns `result == "error"` (guards against an AI that never ends its turn).
  - `static func summarize(results: Array[Dictionary]) -> Dictionary` → `{"matches", "wins": Array[int] (per player), "draws", "errors", "avg_turns_decided": float, "avg_turns_all": float}`; averages are `0.0` when there is nothing to average.
- [x] Tests `tests/unit/test_match_runner.gd`:
  - `play(12345, 1)` → `result == "turn_limit"`, `winner == -1`, `turns == 1` (no unit can kill on turn 1 – armies start 9+ hexes apart).
  - `play(7, 50)` called twice → identical dictionaries (determinism).
  - `play(7, 50)` → `result` is `victory` or `turn_limit`, never `error`; when `victory`, `winner` is 0 or 1 and `1 <= turns <= 50`.
  - `summarize([{winner: 0, turns: 10, result: "victory"}, {winner: -1, turns: 50, result: "turn_limit"}, {winner: 1, turns: 20, result: "victory"}])` → `matches 3`, `wins [1, 1]`, `draws 1`, `errors 0`, `avg_turns_decided 15.0`, `avg_turns_all ≈ 26.67` (tolerance 0.01).
  - `summarize([])` → `matches 0`, averages `0.0`.
- [x] Script `tools/simulate.sh N [--seed=S] [--max-turns=T]` runs headless (`--script res://tools/simulate.gd`), seeds `S … S+N−1` (default `S = 1`), default `T = 50`. Output (plain text, exact labels):
  ```
  Matches: 100 (seeds 1..100, max turns 50)
  Player 0 wins: 48 (48.0%)
  Player 1 wins: 45 (45.0%)
  Draws (turn limit): 7 (7.0%)
  Errors: 0
  Average length: 18.4 turns (decided), 20.6 turns (all)
  ```
  Exit code `0`; `1` if any match ended with `error`; `2` with a usage line for a missing/non-positive `N` or unknown option. `--verbose` additionally prints one line per match: `seed=<s> result=<r> winner=<w> turns=<t>`.
- [x] `tools/simulate.sh 100` finishes in under 60 s on the dev machine (report the measured time in the implementation notes; if slower, note where time goes rather than optimising in this task).
- [x] The turn limit is a harness parameter only – no draw rule is added to `GameState`/commands (see the GDD open question on victory conditions).
- [x] `docs/AGENTIC_WORKFLOW.md` mentions the command; the first 100-match results with the current data are recorded in the implementation notes.

## Playtest (for the human)

No visuals. Optionally run `tools/simulate.sh 20 --verbose` and check that the output looks sensible.

## Out of scope

- Swapping sides / mirrored seeds to cancel first-move advantage (note it if the results show a strong player-0 bias).
- Different AI types per side, per-unit-type statistics (damage dealt, survivals), parallel execution, CSV/JSON output.

## Implementation notes

- `MatchRunner` (`src/ai/match_runner.gd`): `play(seed, max_turns)` builds `Scenario.default_battle`, drives one `AiPlayer` per side through `GameSimulation`, with the `max_turns * player_count + 1` iteration guard (→ `"error"`). `summarize` aggregates; `wins` starts as `[0, 0]` and grows if a higher player id wins; `avg_turns_all` includes error matches (their `turns` = turn when the guard fired).
- `tools/simulate.sh` → `tools/simulate.gd` (SceneTree script) + `tools/simulate_options.gd` (pure argument parser, tested in `tests/unit/test_simulate_options.gd`). Usage line goes to stderr; a negative N is an invalid count, a second positional is rejected. Godot's version banner is filtered out so stdout matches the documented format. `--import` runs on every invocation (fixed ~1 s startup cost, same as `tools/test.sh`).
- The turn limit is a harness parameter only; no draw rule in `GameState`/commands.
- Tests: `tests/unit/test_match_runner.gd` (all criteria cases + errors counted separately). The `"error"` path of `play` is not tested – triggering it would need an injectable AI seam.
- **Timing**: `tools/simulate.sh 100` = 13.4 s wall-clock (WSL2 dev machine).
- **First results** (current data, seeds 1..100, max 50 turns):
  ```
  Matches: 100 (seeds 1..100, max turns 50)
  Player 0 wins: 34 (34.0%)
  Player 1 wins: 59 (59.0%)
  Draws (turn limit): 7 (7.0%)
  Errors: 0
  Average length: 8.6 turns (decided), 11.5 turns (all)
  ```
- **Bias**: a strong **player-1** advantage (59 % vs 34 %) – the opposite of a first-move advantage. Cause not investigated (spawn layout, map, or the AI walking into range first and eating the opening volley are candidates). Worth a follow-up task: mirrored seeds / side swap to separate side bias from first-move effects.

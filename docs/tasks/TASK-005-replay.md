# TASK-005: Save/replay a match as seed + command list

- **Status**: ready
- **Layers**: core / presentation (save key) / tools (fixture regeneration)
- **Depends on**: `Scenario.default_battle(seed)` from **TASK-011**. If TASK-011 is not done yet, extract `Scenario` here exactly as specified there, but without the archers (6 units, ids 1–6); TASK-011 then only adds the archers and regenerates the fixture.

## Goal

A whole match can be saved as `seed + list of commands` and replayed to the identical final state. This gives bug reproduction from playtests ("send me the match file") and a regression test that catches unintended rule changes.

## Acceptance criteria (testable)

- [ ] Every command serializes to a JSON-compatible `Dictionary` via `to_dict()`; `CommandCodec.from_dict(d: Dictionary) -> Command` (`src/core/commands/command_codec.gd`) rebuilds it (returns `null` for unknown/invalid input). Formats:
  - `MoveUnitCommand` → `{"type": "move", "unit_id": 3, "target": [q, r]}`
  - `AttackCommand` → `{"type": "attack", "attacker_id": 1, "target_id": 5}`
  - `EndTurnCommand` → `{"type": "end_turn"}`
- [ ] Round trip through text keeps types: `from_dict(JSON.parse_string(JSON.stringify(cmd.to_dict())))` yields a command of the same class with equal fields, ints are `int` (not `float`) and `target` is a `Vector2i`. Unknown `"type"`, missing fields or non-numeric values → `null`.
- [ ] `MatchRecord` (`src/core/match_record.gd`, RefCounted): `version: int = 1`, `scenario: String = "default_battle"`, `seed: int`, `commands: Array[Dictionary]`; `to_json() -> String`, `static from_json(text: String) -> MatchRecord` (`null` on invalid JSON or `version != 1`); `static from_simulation(sim: GameSimulation, seed: int) -> MatchRecord` built from `sim.history`.
- [ ] `GameState.snapshot() -> Dictionary` – a comparable description of the state: `turn`, `current_player`, `winner`, `rng_state` (`rng.state`), and `units` sorted by id (including dead ones), each `{id, owner, definition: String(definition.id), coord: [q, r], hp, moves_left, has_attacked}`.
- [ ] `Replay.run(record: MatchRecord) -> Dictionary` (`src/core/replay.gd`): builds the state with `Scenario.default_battle(record.seed)`, decodes and executes every command through `GameSimulation.execute`. Result: `{"ok": true, "simulation": GameSimulation}` or `{"ok": false, "error": <code>, "index": <command index>, "reason": <validate reason or "">}` with error codes `unknown_scenario`, `invalid_command`, `diverged` (a command was rejected).
- [ ] Tests `tests/unit/test_replay.gd`:
  - Record of: move unit 1 by one tile, `end_turn`, `end_turn` (any 3 valid commands on seed 12345) → replay `ok`, snapshot equals the snapshot of the original simulation.
  - Record whose first command is `{"type": "attack", "attacker_id": 99, "target_id": 1}` → `{"ok": false, "error": "diverged", "index": 0, "reason": "unit_not_found"}`.
  - `{"type": "teleport"}` at index 2 → `error == "invalid_command"`, `index == 2`.
  - `scenario: "unknown"` → `error == "unknown_scenario"`.
  - Two replays of the same record give equal snapshots.
- [ ] Regression fixture `tests/fixtures/replays/default_battle_12345.json`: a full AI-vs-AI match from seed `12345` (both sides `AiPlayer`, stopped at `game_over` or after turn 30) containing the record plus `"expected_final": <snapshot>`. The test replays it and compares the snapshot with `expected_final`; the failure message names the regeneration command.
- [ ] Regeneration script `tools/make_replay_fixture.sh` (runs a headless `--script`) rewrites that fixture. Regeneration is a deliberate step when rules change on purpose; the implementation notes say so.
- [ ] Presentation: `F5` saves the current match to `user://matches/last_match.json` (via `MatchRecord.from_simulation`), and the same happens automatically on `game_over`. The absolute path (`ProjectSettings.globalize_path`) is printed to the terminal.

## Playtest (for the human)

1. Play a few moves, press F5 – the terminal prints the path of `last_match.json`; the file contains the seed and your commands.
2. Finish a match – the file is overwritten automatically at "Victory!"/"Defeat!".
3. (Optional) Copy that file next to the fixture and ask the agent to turn it into a reproduction test.

## Out of scope

- Loading/watching a replay inside the 3D scene (replay viewer), multiple save slots, save-and-continue a match mid-game.
- Serializing maps or units directly (state is always rebuilt from seed + scenario).
- Backward compatibility across record versions.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

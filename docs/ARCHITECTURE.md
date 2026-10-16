# Architecture

## Layers

```
┌──────────────────────────────────────────────┐
│ Presentation  (Node, scenes, input, UI)      │  src/presentation/, scenes/
│  BattleController · MapView · UnitView · …   │
└───────────▲───────────────────────┬──────────┘
            │ events (Dictionary)    │ commands (Command)
┌───────────┴───────────────────────▼──────────┐
│ GameSimulation  – validate → apply → emit    │  src/core/game_simulation.gd
├──────────────────────────────────────────────┤
│ GameState · HexGrid · Unit · Terrain         │  src/core/
│ Commands                                     │  src/core/commands/
│ AiPlayer (issues commands like a player)     │  src/ai/
├──────────────────────────────────────────────┤
│ Data: UnitDefinition (.tres)                 │  src/core/data/, data/
└──────────────────────────────────────────────┘
```

Dependencies point downward only. `src/core` doesn't know graphics exist.

## Flow of a single action

1. The player clicks a tile → `BattleController` creates `MoveUnitCommand(unit_id, coord)` (or `AttackCommand(attacker_id, target_id)` when the tile holds an enemy).
2. `GameSimulation.execute()` calls `validate()`. A rejected command → `command_rejected` signal with a reason code (e.g. `unreachable`, `out_of_range`, `already_attacked`). Once `GameState.winner != -1` every command is rejected with `game_over`.
3. `apply()` changes `GameState` and returns events; the simulation emits them via `event_emitted`.
4. `BattleController` turns events into animations (`UnitView.move_to`) and refreshes the HUD.

The AI (`AiPlayer.take_turn`) does exactly the same, just without clicks.

## Coordinates

Hex grid, axial coordinates `(q, r)` as `Vector2i`, "pointy-top" layout. World ↔ tile conversions in `Hex.to_world` / `Hex.from_world`. Rectangular maps are generated in offset layout (`MapGenerator.offset_to_axial`).

## Events

| type | fields | emitted by |
|---|---|---|
| `unit_moved` | `unit_id`, `from`, `to` | MoveUnitCommand |
| `turn_ended` | `player` | EndTurnCommand |
| `turn_started` | `player`, `turn` | EndTurnCommand |
| `unit_attacked` | `attacker_id`, `target_id`, `damage` (before clamping HP at 0), `target_hp` | AttackCommand |
| `unit_died` | `unit_id` | AttackCommand |
| `game_over` | `winner` (only one player has living units left) | AttackCommand |

## Directory layout

| Directory | Contents |
|---|---|
| `src/core/` | Game state and rules (pure GDScript) |
| `src/core/commands/` | Commands – the only way to change state |
| `src/core/data/` | Resource classes (`Resource`) holding data |
| `src/ai/` | Computer opponents |
| `src/presentation/` | Node scripts: views, camera, scene controllers |
| `scenes/` | `.tscn` scenes (battle, UI) |
| `data/` | `.tres` data instances (units, later terrain, factions) |
| `assets/` | `.glb` models, textures, materials, shaders, audio, fonts |
| `addons/` | Godot plugins |
| `tests/` | Runner, `TestCase`, fixtures, `unit/` and `integration/` tests |
| `tools/` | Scripts: tests, lint, running, Godot installation |
| `docs/` | GDD, architecture, ADRs, tasks |

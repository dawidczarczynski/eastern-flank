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

## Unit visuals

`UnitView` = model (`UnitModels.build`, primitives, shared meshes/materials, faces +X) + faction marker draped on the terrain (`OverlayGeometry`) + HUD `UnitLabel` (a `Control` projected via `Camera3D.unproject_position`). The "done" dimming uses the pure helper `UnitStatus.is_done`; `BattleController` pushes selected/hovered/done state into the views.

## Coordinates

Hex grid, axial coordinates `(q, r)` as `Vector2i`, "pointy-top" layout. World ↔ tile conversions in `Hex.to_world` / `Hex.from_world`. Rectangular maps are generated in offset layout (`MapGenerator.offset_to_axial`).

## Events

| type | fields | emitted by |
|---|---|---|
| `unit_moved` | `unit_id`, `from`, `to`, `path` (`Array[Vector2i]`: tiles walked, excludes `from`, ends with `to`) | MoveUnitCommand |
| `turn_ended` | `player` | EndTurnCommand |
| `turn_started` | `player`, `turn` | EndTurnCommand |
| `unit_attacked` | `attacker_id`, `target_id`, `damage` (before clamping HP at 0), `target_hp`, `counter` (bool; true when the event is a counterattack by the target) | AttackCommand |
| `unit_died` | `unit_id` | AttackCommand |
| `game_over` | `winner` (only one player has living units left) | AttackCommand |

## Localization

All UI strings live in `assets/i18n/strings.csv` (columns `keys,en,pl`); Godot imports it into `strings.<locale>.translation`, registered in `project.godot` (fallback `en`). Keys are the English source strings (gettext style): `tr("Your turn")`, format strings are keys too and values are substituted after translation: `tr("Turn %d") % turn`. Static/pure helpers without `Object.tr()` call `TranslationServer.translate(key)`. Labels whose text is composed in code set `auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED` so the text is not translated twice. Every new UI string = a CSV row with `en` + `pl` (`tests/unit/test_localization.gd` checks coverage and placeholders). To try Polish, set the project setting `internationalization/locale/test="pl"` (do not commit it).

## Directory layout

| Directory | Contents |
|---|---|
| `src/core/` | Game state and rules (pure GDScript), incl. map generation and terrain elevation (`TerrainNoise`, `TerrainField`, `TerrainSurface` – the 3D surface height query) |
| `src/core/commands/` | Commands – the only way to change state |
| `src/core/data/` | Resource classes (`Resource`) holding data |
| `src/ai/` | Computer opponents |
| `src/presentation/` | Node scripts: views, camera, scene controllers |
| `scenes/` | `.tscn` scenes (battle, UI) |
| `data/` | `.tres` data instances (units, terrain, map generation settings; later factions) |
| `assets/` | `.glb` models, textures, materials, shaders, audio, fonts |
| `addons/` | Godot plugins |
| `tests/` | Runner, `TestCase`, fixtures, `unit/` and `integration/` tests |
| `tools/` | Scripts: tests, lint, running, Godot installation |
| `docs/` | GDD, architecture, ADRs, tasks |

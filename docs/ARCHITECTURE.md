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
│ Scenario (headless battle setup from a seed) │  src/core/scenario.gd
│ AiPlayer (issues commands like a player)     │  src/ai/
├──────────────────────────────────────────────┤
│ Data: UnitDefinition, FactionDefinition, …   │  src/core/data/, data/
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

`UnitView` = model (`UnitModels.build`: a registry that loads `src/presentation/models/<unit_id>.gd`, built with `ModelParts` primitives and shared meshes/materials, faces +X; each unit model is built once per unit and faction, units get copies with their own node trees and the camo materials restored per copy) + faction marker draped on the terrain (`OverlayGeometry`) + HUD `UnitLabel` (a `Control` projected via `Camera3D.unproject_position`). The "done" dimming uses the pure helper `UnitStatus.is_done`; `BattleController` pushes selected/hovered/done state into the views.

## Factions

`FactionDefinition` (`src/core/data/`, instances in `data/factions/*.tres`) holds a faction's `id`, `display_name` (translation key), `short_name`, `roster: Array[UnitDefinition]`, `default_force: Array[UnitDefinition]` (the default battle's units in spawn order, each in the roster) and a Presentation group (`color`, `ink_color`, `camo`, `vest_color`) that core/AI never read. `FactionRegistry.get_faction(id)` / `all()` / `ids()` / `has_faction(id)` look them up (explicit path table, see ADR 0007). Each player has a faction id in `GameState.player_factions` (default `FactionRegistry.DEFAULT_IDS` = `poland`, `russia`); the view gets everything faction-specific from `state.faction_of(player_id)` – never from owner-indexed constants. `Scenario.default_battle(seed, factions)` assigns them and spawns each player's `default_force`: range-1 units fill the front slots, the others the back slots. The map, spawn tiles and unit ids don't depend on the factions. Units outside the owner's roster are skipped.

## Replays and match records

A match is fully described by `scenario + seed + executed commands` (state is never serialized).

- `Command.to_dict()` gives a JSON-compatible form (`{"type": "move", "unit_id", "target": [q, r]}`, `{"type": "attack", "attacker_id", "target_id"}`, `{"type": "end_turn"}`); `CommandCodec.from_dict(d)` (`src/core/commands/command_codec.gd`) rebuilds it and returns `null` on anything unknown or malformed. JSON parses every number as a float: integral floats become `int`, non-integral / non-finite / beyond ±2^53 values, bools and strings are rejected. A new command type = `to_dict()` + a branch in `CommandCodec` + a codec test.
- `MatchRecord` (`src/core/match_record.gd`): `version` (1), `scenario`, `seed`, `factions: Array[StringName]` (optional in JSON; missing → `poland`, `russia`), `commands: Array[Dictionary]`; `from_simulation(sim, seed)` copies `sim.history` and `sim.state.player_factions`, `to_json()` / `from_json(text)` (`null` on invalid JSON, version ≠ 1 or malformed fields; extra keys ignored). `MatchRecord.normalize(value)` turns integral floats of parsed JSON back into ints for comparisons.
- `Replay.run(record)` (`src/core/replay.gd`) builds the scenario's state from the seed (only `"default_battle"` → `Scenario.default_battle(seed, record.factions)`) and executes each decoded command through `GameSimulation.execute`. Errors: `unknown_scenario` (index -1), `invalid_factions` (unknown id or not two ids; index -1), `invalid_command` (codec returned `null`), `diverged` (rejected; `reason` = the `validate()` code).
- `GameState.snapshot()` is the comparable state description (turn, current player, winner, `rng_state`, units sorted by id incl. dead). `rng_state` is stored as a **String** because the 64-bit RNG state does not survive a JSON double.
- Regression fixture `tests/fixtures/replays/default_battle_12345.json` (AI vs AI, seed 12345, until `game_over` or turn 30) = record + `"expected_final"` snapshot; `test_replay.gd` replays it. After an *intended* rule change, regenerate it with `tools/make_replay_fixture.sh` (headless `tools/make_replay_fixture.gd`) and commit the new file.

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

View-only annotations: `BattleController` adds `view_duration` (seconds) and `view_fx` (e.g. `rocket_volley`) to the copies of events it queues for playback (see `EventQueue`); the simulation's events are never modified.

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
| `data/` | `.tres` data instances (units, terrain, map generation settings, factions) |
| `assets/` | `.glb` models, textures, materials, shaders, audio, fonts |
| `addons/` | Godot plugins |
| `tests/` | Runner, `TestCase`, fixtures, `unit/` and `integration/` tests |
| `tools/` | Scripts: tests, lint, running, Godot installation |
| `docs/` | GDD, architecture, ADRs, tasks |

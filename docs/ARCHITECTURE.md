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

`UnitView` = model (`UnitModels.build`: a registry that loads `src/presentation/models/<unit_id>.gd`, built with `ModelParts` primitives and shared meshes/materials, faces +X; each unit model is built once per unit and faction, units get copies with their own node trees and the camo materials restored per copy) + faction marker draped on the terrain (`OverlayGeometry`) + HUD `UnitLabel` (a `Control` projected via `Camera3D.unproject_position`, anchored at the model file's `LABEL_HEIGHT` through `UnitModels.label_height`). The "done" dimming uses the pure helper `UnitStatus.is_done`; `BattleController` pushes selected/hovered/done state into the views.

Mesh kit (TASK-030, ADR 0012): `MeshKit` (`models/parts/mesh_kit.gd`, pure geometry, one material) builds chamfered and smooth primitives – `cbox`, `pillow`, `lathe`, `rod`, `bolt`, `stack`, `loft`, `plate`, `profile`, `sweep`, `tube` – in the caller's units (metres), optionally mapped by a `VehicleFrame` and a pivot `base`; `MeshKits` keeps one kit per material role (`k(&"body")`) and `add_to(pivot, materials)` adds one `MeshInstance3D` per material via `ModelParts.add` (pivots that move get their own `MeshKits`). Front faces are clockwise seen from outside (`(v2 − v0) × (v1 − v0)` along the normals). Every primitive writes the **vertex masks** in `ARRAY_COLOR` (8-bit), the contract with the paint shader:

| Channel | Meaning | Written as | Paint use |
|---|---|---|---|
| `r` | chamfer / edge | 1 on chamfer bands, box corners, plate rims, short diagonal lathe segments (< `chamfer_max`), tube end caps; 0 on faces | paint wear |
| `g` | openness | the kit's `openness` (1 = open, set lower by the model for recessed parts), × `INNER_OPENNESS` (0.35) on a lathe's inner wall | cavity darkening |
| `b` | per-part tint seed | `MeshKit.tint_seed(part centre)` – hash, constant per primitive call, deterministic | per-part tint |

## Graphics quality

`GraphicsQuality` (`src/presentation/graphics_quality.gd`, pure static) picks the LOW/HIGH preset (`detect` from renderer + adapter, `--quality=` override via `parse_override`) and holds the feature switches (`features`); `BattleController` applies them to the environment/sun/viewport (shadows, MSAA, 3D render scale) and passes `quality` to `MapView` (LOW: no foliage scatter) / `UnitView`.

`ColorGrade` (`src/presentation/color_grade.gd`, pure static, TASK-051) is the muted/olive colour grade: `grade(c, params)` and `lut(size, params)` bake a 3D LUT (`cached_texture()`, built once); `GraphicsQuality.apply_environment` assigns it as `adjustment_color_correction` on HIGH (feature `color_grade`) and disables adjustments on LOW.

## Terrain rendering

`MapView` builds one continuous terrain mesh (heights from `TerrainSurface`, 4 vertices per world unit) plus the backdrop ring (`BackdropMesh`, TASK-052), both drawn with one `ShaderMaterial` on `assets/shaders/terrain.gdshader` (`TerrainGround.material`, TASK-055):

- **Layers**: six CC0 ground materials (`assets/third_party/textures/ground/<layer>/`, credited in `credits.json`) in a fixed order: `0 grass`, `1 dry_grass`, `2 dirt` (also forest floor), `3 mud`, `4 gravel`, `5 rock`. `TerrainTextures` (static) decodes and packs them on the `WorkerThreadPool` while the mesh is built into three `Texture2DArray`s – `albedo_height` (RGB albedo, height in A), `normal_maps` (OpenGL), `roughness_ao` (R roughness, G AO) – size from `GraphicsQuality.features` `terrain_texture_size` (HIGH 1024², LOW 512²), cached per size.
- **Weights**: `TerrainSplat.weights(terrain, slope, height, water_level, moisture, macro)` (pure, static, `tests/unit/test_terrain_splat.gd`) gives six weights summing to 1 per vertex (plains: grass/dry grass by macro noise + dirt patches; forest: dirt floor; rock/gravel by slope and on high ground; mud/dirt shore band 0.12 above the water; water beds mud), then `TerrainSplat.smooth` averages neighbours within one mesh step. Layers 0–3 are stored in `ARRAY_COLOR` (8-bit, quantised so the sum stays within ±0.01), 4–5 in `ARRAY_CUSTOM0` (RGBA float, `TerrainGround.add_surface`; `.zw` free for TASK-035 roads/fields). `ARRAY_TEX_UV2` carries a value/saturation factor (darkened off-map margin, muted backdrop).
- **Shader**: world-space sampling at `layer_repeat` (real-world size / 7.7 m per unit × `TerrainGround.REPEAT_SCALE`), height blending (`w + h − max + 0.2`), roughness remapped to `[roughness_min, 1]`, AO, ±8 % low-frequency macro brightness, darker lake beds by depth. Uniforms `anti_tiling` (second sample ×3.7, rotated 37°, mixed by noise) and `triplanar` (rock on steep slopes) come from `GraphicsQuality.features` (`terrain_anti_tiling`, `terrain_triplanar`: HIGH only).

## Grass and wind

Grass (TASK-057) is cosmetic and fully in the view layer. `GrassPlanner` (pure, static; hash-seeded RNG, never `GameState.rng`) plans the clumps of one 4 x 4 world-unit chunk (`plan_chunk`): density per terrain (plains 90, hills 50, forest 25 per unit², none on water, the shore band or slopes above 0.5), scaled by the quality `grass_density`. `GrassField` (a `Node3D` owned by `MapView`) builds one `MultiMeshInstance3D` per chunk lazily – the first time the camera target (`MapView.set_camera_target`, fed by `BattleController`) comes within 20 units, one chunk per frame, rescanning only after the target moved – and keeps it. Chunks use `visibility_range_end` 14 with a 3 unit margin and `VISIBILITY_RANGE_FADE_SELF`, so grass fades out with distance (measured from the chunk centre) and costs nothing far away; they cast no shadows. The total is capped at `GrassPlanner.INSTANCE_BUDGET` (the density is cut back if the map would exceed it). `GrassMesh` is the 3-card clump, `GrassTexture` a procedural neutral grey blade card; the hue is the per-instance colour, the mean linear albedo of the `TerrainSplat` layers (`TerrainTextures` `average_colors`) weighted like the terrain shader, cached per 0.5 unit cell. Clump size is `0.07 x 0.05 x VisualScale.grass_scale()` (the `grass_scale` key follows the preset's `bush_scale`).

Ground overlays (unit marker rings and fills, reach / range / attack / hover washes) are lower than the grass, so they all use `GroundOverlay.material` (`assets/shaders/ground_overlay.gdshader`): the vertex shader pulls them towards the camera along the view ray by `GroundOverlay.depth_pull()` (tallest clump height / sin of the closest default camera pitch). The screen position is unchanged, only the depth, so overlays draw over the grass but stay hidden behind trees, units and ridges. Only rings and outlines get the pull; fills (`GroundOverlay.material(color, false)`) keep normal depth, because they lie under the unit models and a pull would tint the lower half of a model; they are `ground_only` instead – the shader compares the fill with the scene depth reconstructed to world Y and tints only the terrain, not wheels, tracks, boots or grass standing in the fill.

`Wind` registers the global shader parameters `wind_direction`, `wind_strength`, `wind_speed` at runtime (`RenderingServer.global_shader_parameter_add`, not in `project.godot`; strength 0 when the quality's `wind` is false). `assets/shaders/wind.gdshaderinc` reads them (`wind_offset`) and is shared by `grass.gdshader` and the later tree / undergrowth shaders. Under the headless dummy renderer the globals do not exist, so tests only check `Wind.strength()`.

## Units and factions

`UnitDefinition` (`src/core/data/`, one `data/units/<id>.tres` per real unit) holds `id`, `display_name` (real designation, or a translated descriptive name for squads), `short_name` (label, ≤ 6 characters), `unit_class` (`infantry` / `tank` / `mlrs`, ids from `docs/design/units/classes.json`), `mobility` (`foot` / `wheeled` / `tracked`, from the catalog) and the combat stats (`max_hp`, `move_points`, `attack`, `defense`, `attack_range`), derived by GDD "Stat derivation rules". Core rules read only the combat stats; `unit_class` and `mobility` group shared behaviour (presentation: volleys, locomotion, model contract – TASK-039b). `test_unit_catalog_consistency.gd` checks every unit against its catalog entry (`real_name`, `class`, `mobility`, roster factions ⊆ `operators`).

`FactionDefinition` (`src/core/data/`, instances in `data/factions/*.tres`) holds a faction's `id`, `display_name` (translation key), `short_name`, `roster: Array[UnitDefinition]`, `default_force: Array[UnitDefinition]` (the default battle's units in spawn order, each in the roster) and a Presentation group (`color`, `ink_color`, `camo`, `vest_color`) that core/AI never read. `FactionRegistry.get_faction(id)` / `all()` / `ids()` / `has_faction(id)` look them up (explicit path table, see ADR 0007). Each player has a faction id in `GameState.player_factions` (default `FactionRegistry.DEFAULT_IDS` = `poland`, `russia`); the view gets everything faction-specific from `state.faction_of(player_id)` – never from owner-indexed constants. `Scenario.default_battle(seed, factions)` assigns them and spawns each player's `default_force` in list order: range-1 units fill the front slots, the others the back slots (`Scenario.FRONT_SLOTS` / `BACK_SLOTS`; a force larger than the slots → `push_error`, extra units skipped). The map doesn't depend on the factions (spawn tiles are forced to plains); unit ids follow the spawn order, so they depend on the forces. Units outside the owner's roster are skipped. Balance between factions comes from `default_force` (unit counts), never from unit stats; `MatchRunner.play(seed, max_turns, factions)` / `tools/simulate.sh --factions=<p0>,<p1>` measure it.

## Replays and match records

A match is fully described by `scenario + seed + executed commands` (state is never serialized).

- `Command.to_dict()` gives a JSON-compatible form (`{"type": "move", "unit_id", "target": [q, r]}`, `{"type": "attack", "attacker_id", "target_id"}`, `{"type": "end_turn"}`); `CommandCodec.from_dict(d)` (`src/core/commands/command_codec.gd`) rebuilds it and returns `null` on anything unknown or malformed. JSON parses every number as a float: integral floats become `int`, non-integral / non-finite / beyond ±2^53 values, bools and strings are rejected. A new command type = `to_dict()` + a branch in `CommandCodec` + a codec test.
- `MatchRecord` (`src/core/match_record.gd`): `version` (2), `scenario`, `seed`, `factions: Array[StringName]` (required), `commands: Array[Dictionary]`; `from_simulation(sim, seed)` copies `sim.history` and `sim.state.player_factions`, `to_json()` / `from_json(text)` (`null` on invalid JSON, version ≠ 2 or malformed fields; extra keys ignored). `parse_json(text)` returns `{"record", "error"}` with a readable message instead – e.g. version 1 records (before TASK-039a's real units) are reported as unsupported (ADR 0009). `MatchRecord.normalize(value)` turns integral floats of parsed JSON back into ints for comparisons.
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
| `assets/` | `.glb` models, textures, materials, shaders, audio, fonts; `third_party/` holds downloaded CC0 assets (`hdri/`, `textures/`, `models/`), each file credited in `third_party/credits.json` (ADR 0011, checked by `test_third_party_assets.gd`) |
| `addons/` | Godot plugins |
| `tests/` | Runner, `TestCase`, fixtures, `unit/` and `integration/` tests |
| `tools/` | Scripts: tests, lint, running, Godot installation |
| `docs/` | GDD, architecture, ADRs, tasks |

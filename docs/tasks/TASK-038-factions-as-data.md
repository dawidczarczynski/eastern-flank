# TASK-038: Factions as data – `FactionDefinition`, player → faction, HUD and colours from the faction

- **Status**: ready
- **Layers**: core (resource, `GameState`, `Scenario`, match record) + presentation (palette lookups)
- **Depends on**: – (soft: TASK-005 match record, TASK-020/021 HUD). GDD: "Factions and units". ADR: 0002 (presentation group in a core resource), 0004 (scenario), 0005 (match record).
- **Model**: opus (touches state, scenario, replay format and many presentation call sites)

## Goal

Factions stop being "player 0 = blue, player 1 = red" constants and become data, so adding a country later is adding a `.tres` file. Rules and unit look stay the same in this task; the two current placeholder factions become **Poland** and **Russia** (names only – the real units come in TASK-039a).

## Design

- **`src/core/data/faction_definition.gd`** (`class_name FactionDefinition`, `Resource`): `id: StringName`, `display_name: String` (translated in the UI), `short_name: String` (2–3 letters, HUD badge), `roster: Array[UnitDefinition]`; `@export_group("Presentation")`: `color: Color` (UI), `camo: PackedColorArray` (3 colours), `vest_color: Color`. Core and AI never read the Presentation group (ADR-0002 rule).
- **Data**: `data/factions/poland.tres` ("Poland", `PL`, `#5b93d6`, camo `#4c5632`/`#3b3325`/`#22251d`, vest `#3d4529`) and `russia.tres` ("Russia", `RU`, `#d76a52`, camo `#8a7f5a`/`#6b6446`/`#a89c76`, vest `#5d5840`); both rosters = the three current unit definitions. The camo values are the design's for now; the real palettes (Pantera / EMR) are set from the catalog in TASK-039a. New CSV rows en + pl: `Poland`/`Polska`, `Russia`/`Rosja`. A registry `FactionRegistry` (core, static, like the unit definitions' loader) loads `data/factions/*.tres` by id.
- **State**: `GameState` stores `player_factions: Array[StringName]` (one per player) and exposes `faction_of(player_id) -> FactionDefinition`. `Scenario.default_battle(seed, factions := [&"poland", &"russia"])` assigns them; spawning validates that each unit's definition is in its player's roster (`push_error` + skip in release, assert in tests).
- **Match record / replay** (ADR-0005): the record stores the faction ids; old records without factions load with the default pair (backward compatible). Update the replay fixture if needed (`tools/make_replay_fixture.sh`).
- **Presentation**: replace `UiPalette.FACTION`, `UiPalette.FACTION_NAMES`, `UnitModels.BODY_COLORS`/`VEST_COLORS` and every owner-indexed colour/name lookup with the faction's data (`UiPalette.faction_color(state, player_id)` or similar). The TASK-029 camo materials (if done) take their colours from `faction.camo` and are cached per faction id, not per owner.
- **ADR** `docs/adr/0007-factions-as-data.md`.

## Acceptance criteria (testable)

- [ ] `tests/unit/test_factions.gd`: both `.tres` load via `FactionRegistry`; ids unique; every roster entry is a `UnitDefinition`; `camo.size() == 3`.
- [ ] `test_scenario.gd`: `default_battle(seed)` assigns `poland`/`russia`; `default_battle(seed, [&"russia", &"poland"])` swaps them; `faction_of(1).id == &"russia"` by default.
- [ ] `test_replay.gd` / `test_match_saver.gd`: a record round-trips its faction ids; a record without the field loads with the default pair and replays identically.
- [ ] `grep` finds no remaining owner-indexed faction colour/name arrays in `src/presentation/` (`UiPalette.FACTION`, `FACTION_NAMES`, `BODY_COLORS`, `VEST_COLORS` removed); `test_hud_model.gd`, `test_unit_popup_model.gd` pass using faction data.
- [ ] `tools/simulate.sh 20` gives the same results as before (factions don't change rules).
- [ ] Visual check: `tools/screenshot.sh` before/after identical except the HUD faction names/badges (Poland `PL`, Russia `RU`).

## Playtest (for the human)

1. Start a battle: HUD shows "Poland"/"Russia" (`PL`/`RU`) with the same colours as before; units look the same. Switch the game to Polish: "Polska"/"Rosja".
2. Optional: in `data/factions/russia.tres` change `color` to green in the editor, start again – the enemy's HUD strip, markers and labels turn green. Revert.
3. Load a match saved before this change (F5 save from an older build, if you have one) – it replays.

## Out of scope

- Real countries and per-vehicle definitions (TASK-039a), faction selection screen, flags.

## Implementation notes

_Filled in by the agent when done._

# ADR 0007: Factions are data (`FactionDefinition`), players are assigned faction ids

- **Status**: accepted
- **Date**: 2026-10-18

## Context

Factions were implicit: "player 0 = blue, player 1 = red", with colours and names as owner-indexed constants in the presentation (`UiPalette.FACTION`, `UnitModels.BODY_COLORS`, …). Real countries with their own units (TASK-039a) need a faction to be data: a name, a roster of unit types and a look, chosen per player.

## Decision

- `FactionDefinition` (`src/core/data/faction_definition.gd`, `Resource`): `id`, `display_name` (translation key), `short_name` (2–3 letters), `roster: Array[UnitDefinition]`; `@export_group("Presentation")`: `color`, `ink_color` (text drawn on `color`), `camo` (3 colours), `vest_color`. The ADR 0002 rule applies: core and AI never read the Presentation group.
- Instances live in `data/factions/*.tres` (`poland`, `russia`). `FactionRegistry` (`src/core/faction_registry.gd`, static) loads them by id from an **explicit path table** (`_PATHS`) – not by listing the folder, because exported builds list `.remap` files in `DirAccess` and a table keeps `all()` ordered deterministically. `test_factions.gd` fails if a `.tres` in the folder is missing from the table.
- `GameState.player_factions: Array[StringName]` (index = player id), filled with `FactionRegistry.DEFAULT_IDS` (`poland`, `russia`) by the constructor so hand-built test states have factions too; `GameState.faction_of(player_id)` resolves it through the registry (`null` for an unknown player/id). Factions are static per match and are **not** part of `snapshot()`.
- `Scenario.default_battle(seed, factions := DEFAULT_IDS)` assigns them. Spawns, map and unit ids do not depend on the factions; each spawn is checked with `Scenario.can_spawn` (definition id in the owner's roster) and skipped with `push_error` otherwise.
- `MatchRecord` stores `"factions"` (ids as strings) and stays **version 1**: the field is optional and a record without it loads with the default pair (amends ADR 0005's "no backward compatibility" for this additive field). `from_simulation` copies `sim.state.player_factions`. `Replay.run` builds the scenario with the record's factions and fails with `invalid_factions` for an unknown id or a count other than two.

## Consequences

- (+) Adding a country = a `.tres` + a `_PATHS` line + CSV rows for its name; no owner-indexed constants.
- (+) Old saved matches and the checked-in replay fixture (which has no `"factions"`) still replay unchanged.
- (−) Faction data is not in the snapshot, so a replay check does not compare factions; the record does.
- (−) The registry path table must be kept in sync with `data/factions/` (guarded by a test).

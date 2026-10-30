# TASK-086: Two-layer architecture – operational simulation, campaign state, battle hand-off (ADR)

- **Status**: done
- **Layers**: docs (ADR) + core skeleton
- **Depends on**: – (soft: TASK-088)
- **Model**: opus (architecture, determinism, save format)

## Goal

Decide how the operational layer ([VISION.md](../VISION.md), GDD "Vision decisions") sits next to today's tactical simulation before any operational rule is written, so TASK-092 … TASK-107 build on one agreed shape.

## Acceptance criteria (testable)

- [x] ADR in docs/adr/ (next free number) answering:
  - Where the operational logic lives (proposal: `src/core/operational/` + `src/ai/operational/`, same rules as `src/core/` – pure logic, commands, `rng` in state).
  - `OperationalState` / `OperationalSimulation` vs. the existing `GameState` / `GameSimulation`: separate classes with a shared `Command` base, or one generic simulation? Each layer has its own command list and RNG stream; how a battle's seed is derived from the operational RNG (deterministic replay of a whole campaign).
  - **Hand-off objects**: `BattleSetup` (map cut, companies per side with strength, `BattleObjectives`, `BattleConditions` – command points, ammunition, support, morale) from operation to battle, and `BattleResult` (losses per company, outcome, turns used) back. These are the *only* channels between the layers.
  - Campaign save / `MatchRecord`: an operational record with nested battle records (or battle commands inline); what replays.
  - Scene flow in presentation: operational scene ↔ battle scene, who owns the transition, how the state survives it.
- [x] Empty skeleton classes for `BattleSetup` and `BattleResult` (typed fields, `to_dict`/`from_dict`) with a round-trip test; `Scenario.default_battle` can be expressed as a `BattleSetup` (test: same initial snapshot).
- [x] docs/ARCHITECTURE.md gets a "Two layers" section pointing to the ADR.

## Playtest (for the human)

None – internal. Review the ADR.

## Player manual

None.

## Out of scope

Operational rules (TASK-092+), map import (TASK-087).

## Implementation notes

- ADR: [docs/adr/0015-two-layer-architecture.md](../adr/0015-two-layer-architecture.md). It decides five things:
  - Operational logic goes in `src/core/operational/` and `src/ai/operational/`.
  - `OperationalState`, `OperationalSimulation` and `OperationalCommand` are separate classes; they do not share a generic base with the tactical ones (GDScript has no generics).
  - Each layer has its own RNG stream. A battle's seed is drawn inside the `apply()` of the command that starts it.
  - `BattleSetup` and `BattleResult` are the only channels between the layers. The operation resolves a battle with `ResolveBattleCommand(result)` and keeps pending battles in a FIFO.
  - A `CampaignRecord` stores the operational commands plus each battle's setup and commands; it supports a fast operational replay and a full verification replay. A presentation autoload `Session` owns the transitions between the operational and battle scenes.
- `src/core/battle_setup.gd` holds `seed`, `map_id` and `map_region`, `operation_name`, `factions`, `companies` (`BattleSetup.Company`: player, unit_type, coord, strength, ref), per-side `conditions` (`BattleSetup.Conditions`: command_points, ammunition, morale, fire_support) and `objectives`. `objectives` is a `Dictionary` placeholder that TASK-088 replaces with `BattleObjectives`.
- `src/core/battle_result.gd` holds `winner`, `reason`, `turns` and `companies`. Each company has its start and end strength and `losses()`. `BattleResult.from_battle(setup, state)` builds it, and both classes have strict `to_dict` / `from_dict`.
- `Scenario.from_setup(setup)` builds every battle; company i becomes unit id i + 1. `Scenario.default_battle` is now `from_setup(default_battle_setup(...))`. The replay fixture is unchanged and still passes.
- One small behaviour change: a unit outside its owner's roster no longer gets its tile forced to plains. This only happens with misconfigured data. `Scenario.can_spawn` was removed (amendment note added to ADR 0007).
- Tests are in `tests/unit/test_battle_setup.gd`:
  - JSON round trips of `BattleSetup` and `BattleResult`, and rejection of malformed dicts.
  - `from_setup` gives the same snapshot and terrain as `default_battle`.
  - A company's strength sets the unit's starting HP; setups that cannot be placed are rejected.
  - `BattleResult` reports the losses of each company.
- For TASK-088: `BattleResult.reason` is currently `&"eliminated"` whenever there is a winner. Replace it with the reason the state records, and use it to tell a draw (`winner` -1) apart from a battle still running.

# ADR 0015: Two layers – operational simulation, battle hand-off, campaign record, scene flow

- **Status**: accepted
- **Date**: 2026-10-30
- **Task**: TASK-086

## Context

The vision ([VISION.md](../VISION.md), GDD "Vision decisions") adds an operational map above today's tactical battle: formations (battalion / brigade = a set of companies) move, strike and supply on the operational map; when they make contact a tactical battle starts, is fought in the conditions the operation created and its result flows back. Everything built so far is the tactical layer: `GameState` / `GameSimulation` / `Command`, deterministic through `GameState.rng`, recorded as scenario + seed + commands (ADR 0005). TASK-092 … TASK-107 need one agreed shape before the first operational rule is written.

## Decision

### 1. Where the operational logic lives

- `src/core/operational/` (state, commands, rules) and `src/ai/operational/` (operational AI), under the same hard rules as `src/core/` and `src/ai/`: pure logic (`RefCounted` / `Resource`), changed only by commands, randomness only from the operational state's `rng`, balance data in `data/**/*.tres` (e.g. `data/formations/`, `data/strike_means/`).
- Dependencies: the operational layer may use tactical **data** (`UnitDefinition`, `FactionDefinition`) and the hand-off classes (`BattleSetup`, `BattleResult`, section 3). It never reads or changes `GameState` / `GameSimulation`. The tactical layer knows nothing about the operational one.
- The hand-off classes live in `src/core/` next to `Scenario`: they are the tactical layer's input / output format, and scenario battles use them too.

### 2. Two simulations, not one generic one

- `OperationalState` / `OperationalSimulation` are separate classes mirroring `GameState` / `GameSimulation` (validate → apply → emit events, `history`), with their own command base `OperationalCommand` (`validate(state: OperationalState)`, `apply(...) -> Array[Dictionary]`, `to_dict()`) and their own `OperationalCommandCodec`.
- **Why not one generic simulation or a shared `Command` base**: GDScript has no generics; a base typed on `RefCounted` would cast in every command and lose the static typing the project relies on (`untyped_declaration`). The duplicated facade is ~20 lines; the conventions (reason codes, event dictionaries, `to_dict` / strict codec) are shared, the classes are not.
- **Two RNG streams**: `OperationalState.rng` (seeded from the campaign seed) and each battle's `GameState.rng`. The command that starts a battle draws the battle seed **inside `apply()`**: `setup.seed = state.rng.randi()` – so replaying the operational commands consumes the operational RNG identically and yields the same battle seeds. Nothing in a battle touches the operational RNG, so a battle can be replayed on its own and the operation can be replayed without running its battles.
- **Battle phase**: a contact puts a `BattleSetup` in `OperationalState.pending_battles` (FIFO; several contacts in one turn are fought one after another) and emits `battle_started` (`setup`). While a battle is pending the only valid operational command is `ResolveBattleCommand(result: BattleResult)` (others: `battle_pending`); it validates that the result belongs to the first pending setup (same company count, `ref`s and start strengths) and applies losses, retreat and initiative (TASK-095). Battles are always played (no auto-resolve, GDD).
- Players: operational player *i* is battle player *i* (`BattleSetup.factions[i]`); both layers are 2-player for now. Who moves first in a contact battle (the attacker) is decided in TASK-094 – a `first_player` field in `BattleSetup` if needed.

### 3. Hand-off objects – the only channels between the layers

`BattleSetup` (`src/core/battle_setup.gd`), operation → battle:

| Field | Meaning |
|---|---|
| `seed` | battle seed: map generation (generated maps) and `GameState.rng` |
| `map_id`, `map_region` | which map and which cut of it (`generated_river` today; imported real maps with a region from TASK-087 / TASK-094) |
| `operation_name` | display name (`GameState.operation_name`) |
| `factions` | faction id per player |
| `companies: Array[BattleSetup.Company]` | `player`, `unit_type` (UnitDefinition id in the faction roster), `coord`, `strength` (starting HP, 1 … max_hp), `ref` (operational id of the company, "" in scenario battles); company *i* becomes unit id *i* + 1 |
| `conditions: Array[BattleSetup.Conditions]` | per player: `command_points` (0 = unlimited, TASK-091), `ammunition`, `morale` (percent), `fire_support` (missions) – read by TASK-099 |
| `objectives` | placeholder `Dictionary` ({} = eliminate, no turn limit); TASK-088 replaces it with `BattleObjectives` (same `to_dict` / `from_dict` pattern) |

`BattleResult` (`src/core/battle_result.gd`), battle → operation: `winner` (−1 = draw), `reason` (`&"eliminated"`, TASK-088 adds the rest), `turns`, `companies: Array[BattleResult.Company]` (`player`, `unit_type`, `ref`, `strength_start`, `strength_end`, `losses()`), one per setup company in the same order. `BattleResult.from_battle(setup, state)` builds it from the finished battle.

- `Scenario.from_setup(setup) -> GameState` is the one way a battle starts (null with `push_error` when the setup cannot be placed). `Scenario.default_battle(seed, factions)` is `from_setup(default_battle_setup(seed, factions))`, so scenario battles, quick battles and contact battles share the path.
- Both classes are plain JSON-compatible data (`to_dict` / `from_dict`, strict like `CommandCodec`: `null` on anything malformed, integral JSON floats accepted). Fields grow as tasks need them; a field the tactical rules do not read yet is documented as such.
- Nothing else crosses: no shared state objects, no references from a battle into operational state, no operational events inside a battle.

### 4. Campaign record and saves

A campaign is fully described by `campaign scenario + seed + operational commands + battle commands`, as in ADR 0005 – state is never serialized:

```
CampaignRecord {"version": 1, "scenario": "<operation id>", "seed": S, "factions": [...],
                "commands": [<operational command dicts>],
                "battles": [{"setup": <BattleSetup dict>, "commands": [<tactical command dicts>]}, ...]}
```

- `ResolveBattleCommand.to_dict()` carries the full `BattleResult` dict, so the operational command list is self-contained.
- **Operational replay** (loading a save): replay `commands` through `OperationalSimulation.execute`; results come from the stored `ResolveBattleCommand`s, battles are not re-run. Fast.
- **Full verification** (regression fixtures, bug reports, `tools/simulate.sh` campaigns): additionally, for battle *k*, the setup the operation produced must equal `battles[k].setup` (else `diverged`), its tactical commands are replayed through `GameSimulation.execute` from `Scenario.from_setup`, and `BattleResult.from_battle` must equal the result in the matching `ResolveBattleCommand` (else `battle_diverged`).
- **Mid-battle save**: the last `battles` entry has commands but no `ResolveBattleCommand` yet; loading replays the operation up to the pending battle, rebuilds the battle from its setup and replays its commands.
- A single battle stays exportable as a `MatchRecord`; it gains a `"setup"` scenario that embeds the `BattleSetup` dict (format version bump, done in TASK-094 when the first contact battle exists). `"default_battle"` records keep working because the default battle is a setup.
- As in ADR 0005, records are valid only for the rules and data they were recorded with.

### 5. Scene flow in presentation

- An autoload `Session` (`src/presentation/session.gd`, a `Node`; autoloads are allowed in presentation only) owns everything that must survive a scene change: the current campaign (operational simulation + `CampaignRecord` being written) or, for a quick battle, just a `BattleSetup`. Scenes are freed on transitions and hold no game state of their own.
- `Session` is the only code that calls `change_scene_to_file` between operation and battle:
  - operational scene (TASK-093) gets `battle_started` → `Session.start_battle(setup)` → battle scene;
  - `BattleController` takes its setup from `Session` (fallback: `Scenario.default_battle_setup` – running `battle.tscn` directly or a quick battle from the menu) instead of calling `Scenario.default_battle(MAP_SEED)`;
  - on `game_over` the end screen's "Return to operation" calls `Session.finish_battle()`: `BattleResult.from_battle`, `ResolveBattleCommand` through the operational simulation, the battle's commands appended to the record, back to the operational scene, which rebuilds its view from the operational state.
- The main menu offers "Quick battle" (setup only) and, later, "Campaign".

## Alternatives considered

- **One generic simulation / shared `Command` base** – see 2: lost static typing for a few saved lines.
- **Battle state inside the operational state** (one big state, one RNG) – a battle could not be replayed or tested alone, and tactical randomness would shift every later operational roll.
- **Storing only the operational commands and re-running battles on load** – loading would replay every battle (slow) and any tactical rule change would break old saves outright; storing results keeps the operation loadable while verification stays available.
- **A root scene that swaps child scenes** instead of an autoload – equivalent; the autoload fits the existing `change_scene_to_file` menu flow and keeps `battle.tscn` runnable on its own.

## Consequences

- (+) Every operational task builds on known boundaries; the tactical layer stays testable and replayable on its own; `Scenario.default_battle` already runs through `BattleSetup`.
- (+) Deterministic campaigns: one seed, two RNG streams, battle seeds derived inside commands.
- (−) Two command families and codecs to keep in step with the same conventions.
- (−) `BattleSetup` / `BattleResult` change whenever a layer needs a new input or output (format changes ripple into `CampaignRecord`; no backward compatibility, as in ADR 0005 / 0009).

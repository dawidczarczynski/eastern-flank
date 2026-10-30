# TASK-086: Two-layer architecture – operational simulation, campaign state, battle hand-off (ADR)

- **Status**: ready
- **Layers**: docs (ADR) + core skeleton
- **Depends on**: – (soft: TASK-088)
- **Model**: opus (architecture, determinism, save format)

## Goal

Decide how the operational layer ([VISION.md](../VISION.md), GDD "Vision decisions") sits next to today's tactical simulation before any operational rule is written, so TASK-092 … TASK-107 build on one agreed shape.

## Acceptance criteria (testable)

- [ ] ADR in docs/adr/ (next free number) answering:
  - Where the operational logic lives (proposal: `src/core/operational/` + `src/ai/operational/`, same rules as `src/core/` – pure logic, commands, `rng` in state).
  - `OperationalState` / `OperationalSimulation` vs. the existing `GameState` / `GameSimulation`: separate classes with a shared `Command` base, or one generic simulation? Each layer has its own command list and RNG stream; how a battle's seed is derived from the operational RNG (deterministic replay of a whole campaign).
  - **Hand-off objects**: `BattleSetup` (map cut, companies per side with strength, `BattleObjectives`, `BattleConditions` – command points, ammunition, support, morale) from operation to battle, and `BattleResult` (losses per company, outcome, turns used) back. These are the *only* channels between the layers.
  - Campaign save / `MatchRecord`: an operational record with nested battle records (or battle commands inline); what replays.
  - Scene flow in presentation: operational scene ↔ battle scene, who owns the transition, how the state survives it.
- [ ] Empty skeleton classes for `BattleSetup` and `BattleResult` (typed fields, `to_dict`/`from_dict`) with a round-trip test; `Scenario.default_battle` can be expressed as a `BattleSetup` (test: same initial snapshot).
- [ ] docs/ARCHITECTURE.md gets a "Two layers" section pointing to the ADR.

## Playtest (for the human)

None – internal. Review the ADR.

## Player manual

None.

## Out of scope

Operational rules (TASK-092+), map import (TASK-087).

## Implementation notes

_Filled in by the agent when done._

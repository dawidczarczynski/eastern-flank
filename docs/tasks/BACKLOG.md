# Backlog

Statuses: `idea` → `ready` (specified, with criteria) → `in progress` → `to playtest` → `done`.

Rows after TASK-001 are in priority order (top = next to implement).

| ID | Title | Status | Depends on |
|---|---|---|---|
| TASK-000 | Skeleton: hex map, movement, turns, simple AI, camera | to playtest | – |
| [TASK-001](TASK-001-combat.md) | Basic melee combat | to playtest | – |
| [TASK-006](TASK-006-screenshot-script.md) | Screenshot script for agents (`tools/screenshot.sh`) | ready | – |
| [TASK-008](TASK-008-event-animation-queue.md) | Sequential event animation playback | ready | TASK-001 |
| [TASK-009](TASK-009-attackable-highlight.md) | Highlight attackable enemies (`AttackCommand.valid_targets`) | ready | TASK-001 |
| [TASK-004](TASK-004-path-preview.md) | Movement path preview on hover (`HexGrid.path_to`) | to playtest | – |
| [TASK-003](TASK-003-unit-info-panel.md) | Info panel for the selected unit | to playtest | TASK-001 |
| [TASK-002](TASK-002-terrain-resources.md) | Terrain types as `.tres` resources with a defense bonus | ready | TASK-001 |
| [TASK-010](TASK-010-counterattack.md) | Counterattack | ready | TASK-001 (soft: TASK-002) |
| [TASK-011](TASK-011-archer.md) | Ranged unit (archer) + starting setup in core (`Scenario`) | ready | **TASK-010** |
| [TASK-005](TASK-005-replay.md) | Save/replay a match as seed + command list | ready | `Scenario` from TASK-011 (or extract it here) |
| [TASK-012](TASK-012-ai-simulation.md) | Headless AI-vs-AI simulation (`tools/simulate.sh`) | ready | `Scenario` from TASK-011/TASK-005 |
| TASK-007 | Fog of war | idea | GDD open questions: scale, modes |

TASK-008 is not a hard dependency of anything, but it makes the visual parts of TASK-009/-004/-003/-010 easier to judge. TASK-006 lets agents check visual tasks themselves.

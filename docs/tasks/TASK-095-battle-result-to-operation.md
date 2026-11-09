# TASK-095: Battle result → operation – losses, retreat, readiness, after-action report (completes the vertical slice)

- **Status**: done
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data + presentation (after-action report)
- **Depends on**: TASK-094c, TASK-120
- **Sections**: GDD "Battle hand-off and auto-resolve" (contract: reads only `field_holder` / `retreat` / company strengths, **never `resolution`**), "Operational layer" → "Orders and postures"; reference [docs/design/operational_map/README.md](../design/operational_map/README.md) ("Panels" → after-action report)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

A battle, played or auto-resolved, changes the operation: companies lose strength, the loser may fall back, tired formations move less, and the human reads an after-action report on the staff map. Completes the first vertical slice (orders → contact → battle → result).

## Acceptance criteria (testable)

Core (in `ResolveBattleCommand.apply`, TASK-094a, after its checks):

- [ ] Losses: each `Formation.Company` (matched by `ref`) gets `strength_end`; a company at 0 is removed; a formation with no company left is removed (event `formation_destroyed`, its order dropped). Example: Polish mechanised battalion 40, companies end 7 / 5 / 6 / 10 → strength 28. Test with a played and an auto-resolved result with equal fields → **equal state** (`resolution` never read; test greps the command for `resolution`).
- [ ] `retreat` (player index or −1): that player's formation in the battle falls back **one hex** to the passable, free neighbour farthest from the enemy formation (not in an enemy zone of control when another exists; ties by `Hex.DIRECTIONS`), its order is dropped (`formation_order_interrupted`, reason `retreated`), event `formation_retreated` (`formation_id`, `from`, `to`). No free hex → it stays, event `formation_retreated` with `to` = `from` and `blocked` true. Closed countries are added by TASK-116. Tests: row grid, open grid, enemy on three sides, corner.
- [ ] `field_holder` is informational for the report; the winner does **not** move into the vacated hex **[ASSUMPTION]** (orders move it on the next turn).
- [ ] Readiness: `Formation.readiness` (0 … 100, start 100, in snapshot); a battle costs the participants `readiness_loss_attacker` 15 / `readiness_loss_defender` 10 **[ASSUMPTION]**; +`readiness_recovery` 10 at the start of the owner's turn for a formation that did not fight in its last turn (data `data/operational/aftermath.tres`, `problem()` checked). The order budget becomes `posture.budget(move_points) × max(40, readiness) / 100` rounded down, at least 1, in **one** helper used by `forecast` (event of TASK-092d) and by execution (TASK-092e). Examples: readiness 85 → march 8 × 85 % = 6; readiness 20 → 40 % = 3.
- [ ] Determinism: no `rng` draws; replay (fast and full, TASK-094d) of a record with one played and one auto battle gives identical snapshots; snapshot test updated.
- [ ] Event `battle_consequences` (`attacker_id`, `defender_id`, `losses` per player, `field_holder`, `retreat`) for the report. docs/ARCHITECTURE.md events table and "Two layers".
- [ ] **Not here:** *initiative* (the backlog's old wording) has no GDD rule (turn order is `first_player`) – left out until the human defines it (flagged for GDD Open questions); `delay` posture (needs the retreat rules above plus a design decision).

View – after-action report (replaces the short result notice of TASK-094c / TASK-120; must work under the 2.5D camera of [TASK-125](TASK-125-staff-map-restyle-2-5d.md), it is a screen-space panel):

- [ ] Panel per [README](../design/operational_map/README.md) "After-action report": who holds the field, who retreats (with the new hex), strength **before → after** per formation (strength segments of TASK-092b), losses own / enemy, **continue `↵`**. **Front and escalation effects as separate lines**: the front line effect comes from TASK-093c (e.g. "front moved: n hexes") and the escalation line is shown only when TASK-115 exists (a battle never raises the level – GDD – so it reads "no change"); both **[ASSUMPTION]**, omitted lines are acceptable until then.
- [ ] Shown identically after a played and an auto-resolved battle; also lists readiness change ("Readiness 100 → 85"). Counters update (strength segments, retreat slide using the TASK-092e animation); a destroyed formation's counter disappears. Strings `tr()`.
- [ ] Scene-level smoke test: a scripted contact resolved by the draw/auto path shows the report and the counters match the state.

## Playtest (for the human)

1. Cause a contact (TASK-094a), **Play battle**, win or lose, **Report to staff**: the after-action report shows holder, retreat, before → after, losses; **↵** closes it.
2. The formation's strength segments and the panel show the lower strength; a retreating formation slides one hex back and its order arrow is gone.
3. Repeat with **Auto-resolve** (TASK-120) and an equal outcome: the same report layout and the same consequences.
4. Give the tired formation a far order: the route forecast has more turns than before (readiness lowers the budget); after a quiet turn readiness recovers.

## Player manual

"Contact": after the battle – losses by company, the retreat rule, readiness and its effect on movement (numbers from `aftermath.tres`), reading the after-action report; played and auto-resolved results count the same.

## Out of scope

- Replacements (TASK-105); supply effects (TASK-096); retreat into closed countries (TASK-116); initiative; the `delay` posture; escalation effects of battles (none by design).

## Implementation notes

Core: `BattleConsequences` (losses by company, retreat, readiness) applied by `ResolveBattleCommand.apply`; `AftermathSettings` / `data/operational/aftermath.tres`; `Formation.readiness` / `fought`; single budget helper `OperationalOrders.budget` (forecast, execution, ring, route, panel). Events `battle_consequences` (extra `strength`, `readiness` before/after), `formation_retreated`, `formation_destroyed`, `formation_readiness_changed`. Replay snapshot test in test_auto_resolve_record.
View: "Aftermath" block in `StaffMapBattleResult` (line per formation, losses own/enemy), session records resolution events (played and auto), retreat slide reuses TASK-092e. Front/escalation lines omitted (no data yet); strength shown with `StrengthBar`, not the 5-segment gauge.

# TASK-148a: Operational journal (1/2, core): a per-side, per-turn record of everything that touched a side

- **Status**: done
- **Layers**: core
- **Depends on**: hard TASK-119a (done; same pattern as `PoliticalLog`)
- **Topic**: Two-layer game
- **Sections**: ARCHITECTURE "Events" (operational table), `src/core/operational/political_log.gd` (the pattern to copy)
- **Model**: sonnet

## Goal

The operation keeps a deterministic journal of its events; a side reads **its own view**: what it did and what the enemy did to it, per turn (the date comes from `OperationalClock`). The view is TASK-148b.

## Decisions (human, 2026-11-12)

- Visibility: own actions in full; the enemy's only where it touched us (a strike or battle against us, an enemy halted in contact with our formation). Enemy moves elsewhere are **not** written. No fog of war yet (TASK-100 will reuse the same `involved` rule).
- All entries are kept (no cap). Political entries are bare effects, never who decided (as `PoliticalLog`).
- Design: `docs/design/operational_map/operational_journal.html` (variant A).

## Acceptance criteria (testable)

- [ ] `OperationalJournal` (`src/core/operational/operational_journal.gd`, RefCounted, no Node / await / RNG / clock) with `entries: Array[Entry]`; `Entry` = `turn` (int, `state.turn` when appended), `category` (`strike`, `battle`, `move`, `politics`), `kind` (StringName, below), `actor` (int: the side that acted, -1 for none / political), `involved` (`Array[int]`, the sides that see it; empty = both), `coord` (Vector2i) + `has_coord` (bool), `args` (Dictionary of plain values: ids, counts, before / after).
- [ ] `entries_for(player: int) -> Array[Entry]` returns, in order, the entries whose `involved` is empty or contains `player`; `OperationalState.journal` exists (empty at start). The same history gives each side a different list; never changes `state.rng`.
- [ ] Kinds, one entry per event unless noted (events of TASK-093b..121 in the ARCHITECTURE table): move: `formation_moved` (involved owner), `formation_halted` (owner **and** the owners of adjacent enemy formations at the halt, so a contact is seen by both), `order_completed`, `order_interrupted` (with `reason`), `order_issued`, `order_cancelled`, `posture_changed`, `contact_forbidden` (attacker's owner); battle: `battle_pending` (both), `battle_resolved` (both; winner, reason), `battle_consequences` (both; losses, strength / readiness before / after), `formation_retreated` (both), `formation_destroyed` with cause `battle` (both); strike: **one** `strike` entry per strike, built from `strike_launched` + `strike_resolved` (+ the `installation_changed` / `formation_damaged` / `formation_destroyed` cause `strike` of the same command folded into its args: means, count, class, hits, intercepted, damage, target destroyed, `actor` = striking side, involved = striker and the other side); `formation_joined` (owner; `source`); politics (involved empty, `actor` -1, **no `by` / `player` stored**): `stance_changed`, `level_changed`, `decision` (decision id + country), `sanctuary_breach`, `casus_belli`, `operation_ended`.
- [ ] Other events (turn started / ended, stock, readiness recovery, installation repair, suppression lapse) append nothing; rejected commands append nothing.
- [ ] One place appends: `OperationalSimulation.execute` passes each event of an accepted command to `OperationalJournal.on_event(state, event)` in emission order (the state is the state after the whole command, as for `StaffMapTurnMarks`).
- [ ] `to_dict()` / `from_dict()` strict and JSON round-trip equal; a malformed entry gives null; `snapshot()` has `journal`; a dict without it loads empty (old saves).
- [ ] Replay determinism: a scripted operation (orders, a contact battle, a strike, a political decision) replayed gives an equal `journal.to_dict()`; two runs with the same seed are equal.
- [ ] Perspective test: after one strike by side 0 and one battle, `entries_for(0)` and `entries_for(1)` both hold the strike and the battle; a move of a side-1 formation far from side 0 is only in `entries_for(1)`; the same move ending in contact with a side-0 formation (halt) is in both.
- [ ] ARCHITECTURE: a short "Operational journal" note (no new event types); `docs/CODEMAP.md` refreshed by `tools/check.sh`; `tools/check.sh` passes.

## Playtest (for the human)

None (core only); see TASK-148b.

## Player manual

none (written by TASK-148b).

## Out of scope

- The view (TASK-148b); fog of war (TASK-100); installation repair lines; the tactical battle's own log.

## Implementation notes

`src/core/operational/operational_journal.gd` (`OperationalJournal` + `Entry`), `OperationalState.journal` (and `snapshot()["journal"]`), hooked in `OperationalSimulation.execute` after `PoliticalLog`. Tests: `tests/unit/test_operational_journal.gd`.

- Kinds: all of the list; `formation_order_interrupted` / `_completed` / `_issued` / `_cancelled` / `_posture_changed` map to `order_*` / `posture_changed`. `strike` is written on `strike_launched` (actor and involved = both sides) and completed by `strike_resolved` and the strike-cause `installation_changed` / `formation_damaged` / `formation_destroyed` of the same command (args: means, count, target, class_id, intercepted, hits, misses, damage, target_destroyed, before, after).
- Sides come from event fields: owner of a moved / ordered formation is looked up in the state (such formations survive their own command); `formation_halted` is seen by both when any adjacent hex holds an enemy formation. Battle and political entries have empty `involved` (both). `actor` is the attacker's owner for `battle_pending`, -1 for the other battle entries (the attacker may be gone).
- `args` hold plain values (ids as strings, hexes as `[q, r]`); `from_dict` turns whole floats back into ints so a JSON round trip is equal. `casus_belli` and `sanctuary_breach` store the country (and hex) only, no player.
- No deviations from the task.

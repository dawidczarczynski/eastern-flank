# TASK-094d: Contact (4/4) – `CampaignRecord`, campaign save and Continue, battle replay verification

- **Status**: blocked
- **Layers**: core (`src/core/operational/`, record) + presentation (Save, Continue)
- **Depends on**: TASK-094c
- **Sections**: ADR 0015 §4 (campaign save / `CampaignRecord`); GDD "Battle hand-off and auto-resolve"
- **Model**: opus (serialization and replay determinism)
- **Topic**: Two-layer game

## Goal

The human can save the campaign on the staff map (also with a battle pending) and continue it from the main menu; the record replays the whole operation and verifies played battles (GDD / ADR 0015 §4). TASK-120 adds auto entries to the same record.

## Acceptance criteria (testable)

- [ ] `CampaignRecord` (`src/core/operational/campaign_record.gd`): `operation_id`, `seed`, `human_side` (side id – lives here, never in the state), operational `commands` (dicts, in order), `battles: Array` entries `{setup, commands (tactical dicts), result, resolution: "played"}`; strict `to_dict` / `from_dict` (null on missing / malformed), JSON round trip test.
- [ ] `CampaignRecord.replay(fast := true)`: rebuilds `Operation.build(id, seed)` and executes the stored commands; `ResolveBattleCommand`s take their result from the record → identical `snapshot()` and events (test on a scripted 3-round run with one contact). `replay(full := true)` additionally re-runs each played battle's setup + tactical commands on `Scenario.from_setup` and compares to the stored result; a tampered result → `battle_diverged` (test).
- [ ] The `Session` records every executed operational command and, for a played battle, the tactical commands and result (TASK-094c); a battle in progress is not recorded until it ends.
- [ ] Save writes `user://campaigns/<name>.json` (atomic write: temp file then rename); load validates (`from_dict`, `replay`) and rejects a corrupt file with a message, never a crash. Test on a temp dir.
- [ ] A save with a **pending battle** restores the pending battle (same `BattleSetup`, same seed) – the notice shows again after Continue (test: `pending_battles` dicts equal).
- [ ] docs/ARCHITECTURE.md "Two layers": `CampaignRecord`, file location, `battle_diverged`; ADR 0015 §4 gets a dated note if the shape differs.

View:

- [ ] Staff map: **Save** (`F5`, menu entry) with a "Saved" toast; main menu: **Continue** (disabled with a reason when no save exists) loads the latest campaign into the staff map with the saved viewer side. Strings `tr()`.

## Playtest (for the human)

1. **Operation**, give an order, End turn twice, press **F5**: toast "Saved".
2. Quit to the main menu: **Continue** is enabled. Press it: the same turn, orders and positions as before.
3. Cause a contact, **do not** resolve it, save, quit, Continue: the contact notice is back with the same companies.
4. Play a battle, save after returning, Continue: the pending queue is empty and the state matches.

## Player manual

"Saving": F5, Continue, what is saved (the whole operation incl. a pending battle), that a battle in progress cannot be saved.

## Out of scope

- Auto-resolve entries and `auto_mismatch` (TASK-120); several save slots / a slot picker (later); cloud or network play; applying battle consequences (TASK-095 – the record replays whatever the commands do).

## Implementation notes

_Filled in by the agent when done._

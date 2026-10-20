# ADR 0009: Match records before the real units (TASK-039a) are rejected – format version 2

- **Status**: accepted
- **Date**: 2026-10-20

## Context

TASK-039a replaces the generic units (`infantry`, `cavalry`, `rocket_artillery`) with six real units (`pl_mech_infantry`, `m1a2_sepv3`, `homar_k`, `ru_motor_rifle`, `t72b3`, `bm27_uragan`) with their own stats, and Russia's default force grows to five units. A version 1 `MatchRecord` stores only the scenario, seed, factions and commands (ADR 0005); replayed today it would spawn different units with different stats (and a different unit count, so different unit ids), and its commands would diverge or – worse – replay "successfully" into a different match. Mapping old ids to new ones cannot fix that, because the stats and the army composition changed too. The human decided (2026-10-18) that pre-039 records are unsupported and that existing local saves are deleted.

## Decision

- `MatchRecord.VERSION` is **2**. Any other version is rejected; there is no id mapping and no migration.
- `MatchRecord.parse_json(text)` / `parse_dict(d)` return `{"record": MatchRecord, "error": ""}` or `{"record": null, "error": <readable message>}`. An older record gets "Match record version 1 is unsupported (this build reads version 2 only; records from before the real units of TASK-039a cannot be replayed)." `from_json` / `from_dict` keep returning `null` on any failure, so nothing crashes.
- `"factions"` is **required** in version 2 (every version 2 writer stores it). This ends ADR 0007's optional-field exception, which only existed for version 1 records written before TASK-038.
- The replay regression fixture (`tests/fixtures/replays/default_battle_12345.json`) is regenerated with `tools/make_replay_fixture.sh`, which now writes `"factions"`.
- The local `user://matches/last_match.json` saves (Windows `%APPDATA%\Godot\app_userdata\{Game,Eastern Flank}\matches\`) were deleted; none existed under `~/.local/share/godot/app_userdata/`.

## Consequences

- (+) An old save can never silently replay into a different match; the user gets a clear message.
- (+) The loader code is simpler (no optional field, no compatibility branch).
- (−) All replays recorded before TASK-039a are lost (accepted by the human).
- (−) Every future change that alters the starting state of a saved scenario needs the same decision again (bump the version or keep the old setup reproducible).

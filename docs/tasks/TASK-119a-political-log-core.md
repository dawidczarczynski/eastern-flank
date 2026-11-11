# TASK-119a: Political log (core)

- **Status**: done
- **Layers**: core
- **Depends on**: hard TASK-117 (done), TASK-115, TASK-114 (done); soft TASK-121, TASK-118 (log those kinds only once their events exist: `formation_joined` with a package `source`)
- **Topic**: Two-layer game
- **Tags**: mvp
- **Sections**: GDD "Countries and stances", "Escalation ladder", "Political decisions", ARCHITECTURE "Two layers" (operational bullets) and "Events" table
- **Model**: sonnet

## Goal

The operation keeps a short, deterministic history of political changes (stance, level, decisions, sanctuary breaches, allies and support arriving) that the politics overview (TASK-119b) can read.

## Decisions (human interview, 2026-11-11)

- The overview is built in the reserved right column of the Politics screen (H) as three read-only blocks (ladder table, countries list, event log); see TASK-119b.
- The log lives **in core**: `PoliticalLog` (pure, RefCounted-based) inside `OperationalState`, covered by the codec / replay round trip; the view only reads it.
- **Visibility is by effects only**: log lines and the countries list say what changed, never who decided it. An entry does not store the issuing player of a decision. A side appears in an entry only where the effect itself names one (e.g. a stance change "Lithuania -> NATO"). The ladder table in TASK-119b is the deliberate exception: it keeps the per-side "caused" counts (`escalation_caused`, `escalation_deescalated`). This asymmetry is intentional.

## Acceptance criteria (testable)

- [ ] `PoliticalLog` (`src/core/operational/political_log.gd`, RefCounted) holds `entries: Array[PoliticalLog.Entry]`; `Entry` = `turn` (int, `state.turn` when appended), `kind` (StringName), `country` (StringName, `&""` for none), `side` (int, -1 for none), `level_before` / `level_after` (int, -1 when not a level entry), `stance_before` / `stance_after` (StringName, `&""` when not a stance entry), `cause` (StringName, `&""` for none), `key` (StringName text key for the view, e.g. `&"political_log.stance_changed"`) and `args` (Dictionary of plain values for the text); no Node, no `await`, no RNG, no wall clock.
- [ ] Kinds and the event each one is appended for (exactly one entry per event): `stance_changed` <- `country_stance_changed` (`side` = the new stance's side, -1 neutral; `stance_before` / `stance_after`; `cause` = the event's `cause`); `level_changed` <- `escalation_changed` (`level_before` = `previous`, `level_after` = `level`; `cause` as in the event); `decision` <- `political_decision_taken` (`cause` = the decision id, `country`); `sanctuary_breach` <- `sanctuary_breached` (`country`; `side` stays -1); `contribution` <- `formation_joined` with `source` `contribution` (`country`, `side` = the formation's owner, `args.formation_id`).
- [ ] No entry stores `by`, `player` or the issuing side: after a decision by side 0 and the same decision by side 1 the two `decision` entries differ only in `turn` (test compares `to_dict()` with `turn` removed); `level_changed` and `sanctuary_breach` entries carry `side` -1.
- [ ] **[ASSUMPTION]** One place appends: `OperationalSimulation.execute` passes each event of an accepted command to `PoliticalLog.on_event(state, event)` in emission order, so `political_decision_taken` precedes its effects; rejected commands append nothing; events of other types append nothing.
- [ ] Cap 60: appending the 61st entry drops the oldest (entry 0 of 61 appended is gone, order preserved, `size()` stays 60).
- [ ] `OperationalState.political_log` exists (empty at start); `snapshot()` has `political_log` (array of entry dicts); `PoliticalLog.to_dict()` / `from_dict()` are strict and JSON round-trip equal (`JSON.stringify` then parse then `from_dict` gives equal `to_dict()`); a malformed entry (missing key, wrong type, unknown kind) gives null from `Entry.from_dict`.
- [ ] A snapshot / dict without `political_log` loads as an empty log (old saves); `PoliticalLog.from_dict` of a dict with more than 60 entries keeps the last 60.
- [ ] Replay determinism: replaying a `CampaignRecord` (a scripted operation with a stance change, an *Escalate*, a *Stand down*, a sanctuary breach and an ally joining) gives a state whose `political_log.to_dict()` equals the original's; two runs with the same seed give equal logs; the log never changes the RNG (`state.rng.state` equal with and without reading the log).
- [ ] Support kinds, only once TASK-121 events exist: `formation_joined` with a package `source` appends `support_arrived` (`cause` = package id, `side` = owner, `country`); the *Request support* decision appends the usual `decision` entry. Before TASK-121 this criterion is skipped and the kind is absent from `Entry.KINDS`.
- [ ] `tools/check.sh` passes; ARCHITECTURE "Events" table needs no new event type (the log adds none).

## Playtest (for the human)

None (core only). Playtest steps are in TASK-119b.

## Player manual

none (the visible part is written by TASK-119b).

## Out of scope

- Any view (TASK-119b); per-level caused counts (the state only tracks per-side totals); fog of war on the log (TASK-100); logging battles, strikes or movement.
- A new field in `CampaignRecord`: the log is rebuilt by replaying the commands. **[ASSUMPTION]** (a record without a log needs no migration).

## Implementation notes

`PoliticalLog` (+ `Entry`) in `src/core/operational/political_log.gd`; `OperationalState.political_log` (in `snapshot()` as an array of entry dicts); `OperationalSimulation.execute` feeds every event of an accepted command to `on_event`. Kinds: stance_changed, level_changed, decision, sanctuary_breach, contribution. Cap 60, strict `from_dict` (null on malformed; missing = empty). Tests: `tests/unit/test_political_log.gd`. Support kinds (`support_arrived`) deliberately absent until TASK-121 events exist. No snapshot loader exists in code, so "old save without `political_log`" is covered by `PoliticalLog.from_dict({})`. Replay determinism is covered by running the same commands twice (replay uses `execute`).

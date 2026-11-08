# ADR 0020: Political state in the operational layer

- **Status**: accepted
- **Date**: 2026-11-08
- **Task**: TASK-114 (GDD "Countries and stances", "Sides")

## Context

The operational layer needs to know which countries exist, where each stands, and whether a side may enter or strike a hex. Later tasks add the escalation ladder (TASK-115), borders in movement (TASK-116), political decisions (TASK-117) and allied formations (TASK-118). Both sides are playable, so no rule may ask "is this NATO?".

## Decision

- **Countries are data**: `CountryDefinition` (`data/countries/<id>.tres`: id, ISO code, name, `sanctuary`) and the start stances in `OperationDefinition.countries` (`CountrySetup`: stance, side, leaning). The sanctuary is a country flag, not a side rule.
- **State**: `OperationalState.countries: Array[CountryState]` holds stance, side, leaning and the per-player flags `casus_belli`, `breached_by`, `declared_by`; the hex -> country map is static (from the map's `country_rows`, or passed in for hand-made grids) and not in the snapshot. The snapshot gets `countries` sorted by id.
- **One change point**: every stance change goes through `CountryRules.set_stance`, which enforces the legal transitions of the GDD table and emits `country_stance_changed`. It is the single hook where later tasks attach the ladder's reactions and allied formations joining. Illegal transitions are rule errors (`push_error`, no change).
- **Relations are computed, never stored**: `CountryRules.relation(state, player, country)` returns own / enemy / hostile / neutral / none from the stance and side, so switching the viewing player or the side the human plays changes nothing in the state.
- **Open / closed** is derived: `may_enter` (own and no-country hexes open; hostile and neutral closed; enemy open, except an enemy sanctuary until the player has breached it), `may_strike` (same, but never own soil). A formation may not start on a hex closed to its player (`Operation.from_definition` rejects it).

## Consequences

The view tints and explains countries purely from `relation` / `may_enter` / `may_strike`. TASK-115 extends the sanctuary gate with the ladder level and `may_strike` with the ROE; TASK-116 uses `may_enter` in movement. Rejected: storing the relation per player (stale after every change, doubles the snapshot) and changing stances directly from commands (no single place for reactions).

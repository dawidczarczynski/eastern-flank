# ADR 0005: Matches are recorded as scenario + seed + commands

- **Status**: accepted
- **Date**: 2026-10-18

## Context

Playtest bug reports and a rules regression test both need a whole match reproduced exactly. The simulation is deterministic (ADR 0001, randomness only via `GameState.rng`) and every change goes through commands.

## Decision

- A match is stored as `MatchRecord` (`version`, `scenario`, `seed`, `commands` as `Command.to_dict()` dictionaries) in JSON. No state, map or unit is serialized; `Replay.run` rebuilds the state from the scenario + seed and re-executes the commands through `GameSimulation.execute`.
- `CommandCodec.from_dict` is the single decoder; it is strict and returns `null` for anything it does not fully understand. Integral JSON floats are converted back to `int`.
- `GameState.snapshot()` is the comparison format. The 64-bit `rng_state` is stored as a String because JSON numbers are doubles.
- A checked-in AI-vs-AI fixture (`tests/fixtures/replays/default_battle_12345.json`) with the expected final snapshot acts as a regression test; it is regenerated only deliberately with `tools/make_replay_fixture.sh`.
- No backward compatibility across record versions (`version != 1` is rejected).

## Consequences

- (+) Tiny files, exact reproduction, the same code path as live play.
- (+) Any rule change that alters the outcome of the recorded match fails a test with a pointer to the regeneration command.
- (−) Records are only valid for the rules, data and scenario they were recorded with; changing unit ids, spawn order, balance data or AI-relevant rules invalidates the fixture (regenerate it).
- (−) The seed must fit within ±2^53 to survive JSON exactly.

## Amended by TASK-038 (ADR 0007)

Records gained an optional `"factions"` field (faction id per player). It is additive, so the version stays 1 and records without it load with the default pair (`poland`, `russia`).

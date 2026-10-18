# ADR 0004: The starting battle setup lives in core (`Scenario`)

- **Status**: accepted
- **Date**: 2026-10-18

## Context

The map generation and starting armies were built in `BattleController` (presentation). Replays (TASK-005) and headless AI-vs-AI simulations (TASK-012) must build exactly the same battle without any scene.

## Decision

- `Scenario.default_battle(seed_value) -> GameState` in `src/core/scenario.gd` is the single place that builds the prototype battle: a 12×10 map from `MapGenerator.generate` with its own `RandomNumberGenerator` seeded with `seed_value`, `GameState(grid, 2, seed_value)`, spawn tiles forced to plains with `MapGenerator.force_terrain`, and units added in a fixed order (ids 1–8).
- `BattleController` only calls `Scenario.default_battle(MAP_SEED)`; it no longer preloads unit definitions.
- The scenario is still code (spawn list in `Scenario`), not a resource.

## Consequences

- (+) Any headless consumer gets the same battle from one seed; unit ids are stable, so recorded commands stay valid.
- (+) The setup is covered by tests (`test_scenario.gd`).
- (−) Changing the spawn order or positions changes unit ids and invalidates recorded replays – a deliberate change.
- (−) Spawn positions are code, not data; move them to a `.tres` scenario resource once there is more than one battle.

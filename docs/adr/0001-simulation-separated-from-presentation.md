# ADR 0001: Simulation separated from presentation

- **Status**: accepted
- **Date**: 2026-10-16

## Context

The game is developed mainly by AI agents that cannot see the screen. We need fast, automated verification of the game rules. A turn-based game naturally has a discrete state, which makes this separation easier.

## Decision

- All state and rules live in `src/core/` as `RefCounted`/`Resource`, with no scene nodes.
- State changes only through `Command` objects executed by `GameSimulation`.
- The presentation layer talks to the simulation only through commands (downward) and events (upward).
- Determinism: the only source of randomness is `GameState.rng`.

## Consequences

- (+) Headless tests with no GUI, fast and repeatable.
- (+) For free: replays, saving the game as a list of commands, easier multiplayer and AI-vs-AI simulations.
- (−) A bit more "glue" code in scene controllers.
- (−) We don't use Godot nodes (e.g. `AStar2D` as a node, scene signals) in the logic – we use our own implementations or `RefCounted` classes.

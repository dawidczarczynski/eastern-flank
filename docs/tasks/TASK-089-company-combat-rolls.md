# TASK-089: Company combat with per-element rolls and a damage forecast (design first)

- **Status**: idea
- **Layers**: GDD / balance (game-designer) → core (gameplay-engineer) → HUD forecast (presentation-engineer)
- **Depends on**: human approval of Step 1 (soft: TASK-088)
- **Model**: opus (balance, determinism, AI expected values)

## Goal

Combat feels like companies fighting – mostly predictable, never certain – and a battered company fights worse (GDD "Vision decisions": units are companies, HP = strength).

## Step 1 – game-designer (no code)

Propose and get approved: each strength point (HP) of the attacker rolls once through `GameState.rng` with a hit chance `p` derived from attack vs. defence + terrain, so that a **full-strength** company deals on average what today's formula deals (`max(1, attack − defence − bonus)`); a minimum damage rule or not; counters use the same roll; what the forecast shows (expected value + 10–90 % range); the effect on the AI (expected damage); simulation check over both side assignments (the 59/34 side bias question). Numbers into GDD "Combat", MANUAL update listed.

## Step 2 – implementation (after approval)

Acceptance criteria written in Step 1 (deterministic for a seed, replay test, `AttackCommand.forecast()` for the HUD and AI, simulation report before/after).

## Out of scope

Suppression / morale (TASK-090), indirect-fire accuracy from spotting (after TASK-007).

## Implementation notes

_Filled in by the agent when done._

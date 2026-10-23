# TASK-081: Unit orders as game rules – blind fire, smoke, ambush, relocate, resupply, dig in, camouflage (design first)

- **Status**: idea
- **Layers**: GDD / balance (game-designer) → core + ai (gameplay-engineer), commands, data. No presentation here.
- **Depends on**: GDD decisions below (human) (soft: TASK-039b balance)
- **Model**: opus (new commands, state, AI, determinism)

## Goal

The radial menu in the HUD handoff ([README section 04](../design/hud_v3/README.md)) offers six orders per own unit. Only *Move* exists today. This task turns the others into real rules so TASK-082 has something to call. The design file itself says what it assumes ("Order effects stored per unit: `camo, dug, smoke, ambush, scoot, suppressed`; movement clears camo/dug/ambush; smoke/scoot/suppressed clear at the owner's next turn; blind fire range tank/inf 1–2, MLRS 3–6") – these are *proposals* from the design, not decided rules.

## Step 1 – game-designer (no code)

Decide with the human and write into docs/GDD.md + task acceptance criteria: for each of 2 Blind fire (*Ostrzał na oślep*), 3 per-class order (tank *Zasłona dymna*, infantry *Zasadzka*, MLRS *Zmiana stanowiska*), 4 Resupply (*Uzupełnienie* – needs ammo/supply, which do not exist yet: GDD open question), 5 Dig in (*Okopanie*), 6 Camouflage (*Maskowanie*): action-point cost, preconditions (reasons for `validate()`), effect numbers (defence/visibility/accuracy modifiers), duration, interaction with fog of war (TASK-007 is only an idea → camouflage may be cosmetic/defence-only for now), AI use. Per order a list of the texts the UI needs (description, effect bullets, cost, disabled reason). Which orders ship first, which stay out (Resupply likely out until ammo exists).

## Step 2 – gameplay-engineer (after approval)

Split into one task per order group once Step 1 is approved (new commands in `src/core/commands/` through `GameSimulation.execute()`, per-unit effect state in `Unit` serialised in `MatchRecord`/save/`CommandCodec`, events added to the ARCHITECTURE table, effects in the data `.tres`, TDD tests, AI support or explicit "AI does not use it").

## Acceptance criteria

- [ ] Step 1 delivered: GDD section "Unit orders", per-order table, task specs written, human approved.

## Out of scope

HUD (TASK-082), visuals of smoke/camo/entrenchment (separate presentation tasks).

## Implementation notes

_Filled in by the agent when done._

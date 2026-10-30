# TASK-089b: Combat forecast in the HUD (expected damage, range, destroy chance, counter)

- **Status**: blocked
- **Layers**: presentation (HudModel, hover card); numbers only from `AttackCommand.forecast()`
- **Depends on**: **TASK-089a**. Design and decisions: `TASK-089a-company-combat-rolls.md` (sections 5 and 8).
- **Model**: sonnet

## Goal

Before an attack the player sees what to expect: average damage with its 10–90 % range, the chance to destroy the target and the expected counter – so rolled combat stays readable.

## Acceptance criteria

- [ ] `HudModel` (pure, tested in `tests/unit/test_hud_model.gd`) builds the forecast lines from `forecast()`: `DAMAGE 4.0 (2–6)`, `DESTROY 63 %` (hidden when 0, `<1 %` / `>99 %` at the edges), `COUNTER 0.6 (0–2)` / `NO COUNTER`; exact strings for the cases Abrams → squad, Abrams → Uragan, Homar-K → Uragan at 6 hexes.
- [ ] Shown only while a own unit is selected and the hovered enemy is a valid target; gone otherwise.
- [ ] A 0-damage strike plays without errors (no HP bar change, short "MISS" toast or none – presentation's choice).

## Playtest (for the human)

1. Select the Abrams, hover a red-marked T-72B3 on plains: the hover card shows `DAMAGE 3.0 (1–5)` and `COUNTER 1.3 (…)`.
2. Attack several times over a battle: results vary around the forecast; sometimes an infantry attack on a tank deals nothing.
3. Damage a unit heavily and attack with it: its forecast drops in proportion to its HP.
4. Watch an enemy turn: the AI prefers attacks with a high expected result, not just the weakest unit.

## Player manual

docs/MANUAL.md: the attack forecast in the hover card (expected damage, range, destroy chance, counter) – see the "Player manual" list in TASK-089a.

## Implementation notes

_Filled in by the agent when done._

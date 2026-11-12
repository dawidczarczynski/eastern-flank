# TASK-102b: Operational AI – political decisions and outside support

- **Status**: done
- **Layers**: core / ai
- **Depends on**: TASK-102a (hard), TASK-117 (hard), TASK-121 and TASK-122 (soft)
- **Sections**: GDD "Operational AI", "Political decisions", "Escalation ladder", "Countries and stances", "Outside support"; ARCHITECTURE: none
- **Model**: sonnet

## Goal

The AI leader also decides politically by a few simple data-driven rules – for either side – and never walks the operation into collapse or an early end.

## Acceptance criteria (testable)

- [ ] `AiProfile` (TASK-102a) gets political fields, all in `data/ai/default.tres`: `escalate_min_goal_gap`, `declare_min_strength_ratio` (default 1.5), `ultimatum_enabled` (default true), `support_min_affordable_level_margin` (default 1); no numbers in code.
- [ ] `plan` appends at most **one** political command per turn (one decision per side per turn), placed before the orders so its effects (open soil, joined allies) are visible to the order planner.
- [ ] Respect closed borders: the order planner (102a) never picks a destination or route in a country closed to the side; a test with a closed country shows no `closed_country` / `route_incidents` order.
- [ ] Avoid operation-ending actions: orders whose `route_incidents` report `ends_operation` true are not issued; orders whose incident only raises the level to 5 are not issued either unless the profile `aggression` ≥ 0.8.
- [ ] Always take a free response: when a support package with `response_to` the enemy's request is available and costs 0, the AI requests it in that turn (the free response has priority over every other decision).
- [ ] Request outside support when worth its cost: an available package is requested when level + cost ≤ 5 − margin (`support_min_affordable_level_margin`), the side is not standing down, and (cost > 0) the side has fewer formations than the enemy; a package with cost 0 is always requested when available. Skipped packages are logged in the plan's reason list.
- [ ] Until TASK-121 / TASK-122 exist the support rule is skipped: with no support packages in the operation the planner emits no `RequestSupport` command and tests for it are guarded behind the existence of the command class.
- [ ] Escalate: only when the profile says the AI's goal gap is large (≥ `escalate_min_goal_gap` goals still untaken), level + 1 ≤ 5 and not standing down; never at level 5.
- [ ] Declare hostilities / invoke alliance: *Declare hostilities* on a neutral or hostile country only with a casus belli (cost 0) or own strength ≥ `declare_min_strength_ratio` × the enemy's present strength; *Invoke alliance* on an own aligned country whose soil holds a goal; both only at level + cost ≤ 5.
- [ ] Demand neutrality: used when `ultimatum_enabled`, an enemy-aligned country accepts ultimatums, no enemy formation stands in it and level ≤ 2; otherwise never.
- [ ] Stand down: used when the side is in collapse (GDD "Collapse") or level ≥ 4 with nothing to gain, and the command's own conditions hold; never while a goal is within 2 hexes of being taken.
- [ ] Use nuclear weapon: only for the side whose data allows it (Russia), at level 5, in collapse, and when no other decision is valid (a test: any other valid decision available → not chosen); NATO's plan never contains it (`not_nuclear_power`).
- [ ] Every political command returned passes `validate()` when executed in sequence through `OperationalSimulation.execute()` (test with the AI as player 0 and as player 1, no side-specific code).
- [ ] Determinism: same state and profile → identical plan; no bluffing: no decision is planned that the planner's own rules list as "no effect".

## Playtest (for the human)

None (core / ai only; wiring is TASK-102c).

## Player manual

none (the manual line about the AI leader comes with TASK-102c).

## Out of scope

- Bluffing threats, long-term political plans, learning (TASK-103 may tune the profile).
- The wiring and the tactical AI (TASK-102c); fog (TASK-100).

## Implementation notes

- `src/ai/operational_politics.gd` (`OperationalPolitics.decide`) picks at most one decision; `OperationalAi.plan` puts it first (counts towards `max_commands`). Priority: Stand down, Demand neutrality, Invoke alliance, Declare hostilities, Escalate, and Use nuclear weapon only when none of these applies. Every candidate must pass its own `validate()`.
- `AiProfile` / `data/ai/default.tres` got `escalate_min_goal_gap` (2, untaken `take` goals), `declare_min_strength_ratio` (1.5), `ultimatum_enabled` (true), `support_min_affordable_level_margin` (1, unused until TASK-121 / 122) and three more thresholds: `stand_down_level` (4), `stand_down_goal_range` (2), `cap_incident_aggression` (0.8).
- Orders: `_incident_ok` rejects an order (also a kept standing order) whose route has an `ends_operation` incident or raises the level to the cap, unless aggression >= `cap_incident_aggression`; closed countries were already rejected by `IssueOrderCommand`.
- Stand down: in collapse, or level >= `stand_down_level` with no untaken `take` goal; never with an own formation within `stand_down_goal_range` of an untaken `take` goal. Declare hostilities additionally needs an untaken own `take` goal on that country's soil (otherwise it gains nothing); Invoke alliance needs any own goal on the ally's soil.
- Tests: `tests/unit/test_operational_ai_politics.gd`; `_orders_state` in test_operational_ai.gd refuses ultimatums so order tests stay free of decisions.
- Limitations: outside support (RequestSupport, free response) is skipped entirely, as TASK-121 / 122 do not exist (no reason list, no support tests); the orders of a plan are planned against the state before the decision (plan stays pure, there is no state clone), so soil opened by the decision is used by orders only on the next plan (TASK-102c may re-plan after executing the decision).

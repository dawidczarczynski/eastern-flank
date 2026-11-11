# TASK-102a: Operational AI – profile, goals, formation orders and strikes

- **Status**: ready
- **Layers**: core / ai
- **Depends on**: TASK-095 (hard), TASK-097a (hard)
- **Sections**: GDD "Operational AI", "Player roles", "Operational turns", "Orders and postures", "Deep strikes", "Escalation ladder"; ARCHITECTURE: none
- **Model**: sonnet

## Goal

An enemy leader that, on its turn, gives its formations orders (destination + posture) towards its goals and spends its 2 strikes sensibly – for either side, with the same rules as the human. First part of TASK-102 (split 2026-11-11).

## Decisions (human interview, 2026-11-11)

- Style: objective-driven rules (utility scoring), deterministic, tunable via data; not scripted, no lookahead search.
- Knowledge: full information (reads the whole `OperationalState`); fog / recon is TASK-100 (a visibility filter can be added later).
- Plumbing: a pure planner in `src/ai/` (`OperationalAi.plan(state, player) -> Array` of operational commands), executed one by one through `OperationalSimulation.execute()`; not a command source inside the simulation; no `Node`, `await` or autoload.
- Objectives: AI goals are data on the `OperationDefinition`, per side (hexes / installations with weight and role take / hold); `suwalki_gap.tres` gets a first set; TASK-107 reuses the same hexes as victory objectives.
- Strikes: priority list within a reserve – up to 2 per turn: enemy air-defence / airfield / C2 installations first (SEAD preference), then formations about to make contact; skip strikes that would be rejected or fall below a minimum expected value; keep a small stock reserve (data).
- Air-defence placement is dropped (sites are fixed installations, TASK-098a); the AI only prefers enemy air-defence sites as SEAD targets.
- Difficulty: one level, one `AiProfile` resource (weights, aggression, strike reserve, minimum expected value); no UI; TASK-103 balances it.
- Split: 102a orders + strikes, 102b politics, 102c wiring + tactical AI objectives.
- **[ASSUMPTION]** the AI acts only on its own turn; never has a different rule set than the human; a plan is bounded (`max_commands` in the profile, default 40) so it cannot loop; replays / campaign records contain the AI's commands like any other.

## Acceptance criteria (testable)

- [ ] `AiProfile` (Resource, `src/ai/`, instance `data/ai/default.tres`) holds: goal weight, distance weight, threat weight, `aggression` 0–1 (default 0.5), `strike_reserve` (default 1 salvo's worth of stock of the weapon), `min_strike_value` (default 10), `max_commands` (default 40); no numbers for these in code.
- [ ] `OperationDefinition` gets per-side AI goals (id of a hex or installation, `weight` int, `role` `take` / `hold`); `suwalki_gap.tres` has at least 3 goals per side; a test loads it and checks both sides have goals referring to existing hexes / installations.
- [ ] `OperationalAi.plan(state, player)` returns an `Array` of operational commands; it does not change `state` (state hash before == after planning).
- [ ] Every returned order command passes `validate()` against the state at the moment it is executed in sequence (a test executes the whole plan through `OperationalSimulation.execute()` and asserts every result is accepted).
- [ ] Formation with a `take` goal: it gets an order whose destination is that goal's hex or the reachable hex nearest to it, posture `advance` when the goal's hex is within `ceil(1 / aggression)` hexes of an enemy formation, else `march`; formation standing on a `hold` goal gets posture `defend` (no destination change).
- [ ] Two formations are never ordered to the same destination in one plan.
- [ ] A formation that already has a valid order towards its goal is left alone (no command emitted).
- [ ] Strikes: at most 2 `StrikeCommand`s per plan (the per-turn limit); targets ordered enemy air-defence site > airfield / C2 > formation with an enemy at distance ≤ 2 hexes; with all three target kinds in range the first strike hits the air-defence site.
- [ ] A target that `StrikeRules` would reject (`out_of_range`, ROE class not allowed at the current level, closed country) is never planned; the planner falls to the next candidate.
- [ ] A strike whose expected value (hit chance × damage × target weight) is below `min_strike_value` is skipped; with stock equal to the reserve no strike is planned for that weapon (stock above the reserve → allowed).
- [ ] The planner never plans a strike that would raise the escalation level above 5 (uses the strike forecast / `EscalationRules`, GDD "Escalation ladder").
- [ ] No side-specific code: the same test scenario passes with the AI as player 0 (NATO) and as player 1 (Russia); `grep` of `src/ai/operational*` finds no `nato` / `russia` / `poland` ids.
- [ ] Determinism: the same state and profile give the identical command list twice; a different profile changes the plan; after the operation has ended (`operation_over`) the plan is empty.
- [ ] Plan length ≤ `max_commands`; with `max_commands` 3 a state with 10 idle formations yields exactly 3 commands.
- [ ] Calling `plan` for the player who is not current returns an empty array.

## Playtest (for the human)

None (core / ai only; the AI is wired into the game in TASK-102c). Optional: `tools/simulate.sh` is not extended here.

## Player manual

none (the manual line about the AI leader comes with TASK-102c).

## Out of scope

- Political decisions and outside support (TASK-102b); the wiring into the staff map, the end of the AI's turn and the tactical AI (TASK-102c).
- Air-defence placement, fog (TASK-100), difficulty levels / UI, balancing (TASK-103), supply and reinforcements (TASK-096, TASK-105).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

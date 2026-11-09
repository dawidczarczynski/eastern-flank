# TASK-122: Outside support – strike means as package effects (Chinese missile components, Iranian drones, allied cruise missiles) added to the side's strike stock

- **Status**: blocked
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data + presentation (stock line in the Support tab)
- **Depends on**: TASK-121, TASK-097a
- **Model**: sonnet
- **Topic**: Two-layer game
- **Tags**: mvp

## Goal

Third countries that send weapons, not troops, matter: China's missile components and Iran's drones give Russia more deep strikes, allied cruise missiles do the same for NATO – each with the delay, conditions and responses of TASK-121, and consumed by the deep strike system like any other stock (GDD "Operational layer" → "Outside support", "Strategic options").

## Acceptance criteria (testable)

Contract with TASK-097 (must exist there; if TASK-097 did not build it, add it here): strike means are data (`StrikeMeansDefinition`, ids such as `cruise`, `ballistic`, `strike_drone`), each side has a stock in `OperationalState` (`strike_stock: Array[Dictionary]`, per player `{means_id: count}`, in the snapshot), and **one** entry point changes it upwards: `StrikeRules.add_stock(state, player, means_id, count, source: StringName) -> Array[Dictionary]` (event `strike_stock_changed` – `player`, `means`, `count`, `total`, `source`). A strike spends stock without knowing where it came from.

- [ ] `MeansGrant` (sub-resource: `means` StringName, `count` int) and `SupportPackage.strike_means: Array[MeansGrant]`. `Operation.from_definition` rejects (`push_error`, null – one test each): an unknown means id, `count` ≤ 0, the same means twice in one package. A package with only means (no formations) is valid (TASK-121's "no effect" rejection now means neither).
- [ ] Delivery (TASK-121's step, same timing, withdrawal and `support_delivered`): the grants are added through `add_stock(state, side, means, count, package_id)` in grant order, after the formations' events and before `support_delivered`; `support_delivered` gains `means: {means_id: count}`. Means never wait: a means-only package is delivered on its turn (no `support_delayed`).
- [ ] Examples (hand-made operation on TASK-116's quad grid, `first_player` 0, level 1; stocks from TASK-097's test data, e.g. player 1 `cruise` 4): package **D** side 1 – +3 `cruise`, levels 1–3, cost 0, delay 1 – requested by player 1 in turn 1 → at the start of player 1's turn 2 stock `cruise` 7, events `strike_stock_changed` (total 7, source D) then `support_delivered` (means {cruise: 3}). Package **E** side 1 – +2 `strike_drone`, levels 1–2, `max_caused` 0, `withdraw_if_unmet`, delay 2 – requested at level 1, then player 1 raises → withdrawn, stock unchanged. A package with one formation and +2 `cruise` → both effects, `formation_joined` before `strike_stock_changed`.
- [ ] Consumption without special cases: after D, player 1 strikes with `cruise` 7 times (TASK-097's strike command, ROE allowing) → the 8th is rejected with TASK-097's out-of-stock reason; the strike results do not depend on where the stock came from (same seed, same target: a strike from starting stock and one from granted stock give the same result).
- [ ] Shipped data (`suwalki_gap.tres`) **[ASSUMPTION – GDD "Outside support"; counts ≈ +50 % of the side's starting stock of that means, re-set to TASK-097's real stocks]**: `china_components` (china, side 1): +4 `cruise`, levels 1–2, `max_caused` 1, cost 0, delay 6, `withdraw_if_unmet`; `iran_drones` (iran, side 1): +8 `strike_drone`, levels 1–3, cost 0, delay 2; `allied_strike_means` (nato_allies, side 0): +4 `cruise`, levels 2–3, cost 0, delay 2, `response_to` [china_components, iran_drones]. Test reads them.
- [ ] No `rng` draws in the delivery (test: `rng_state` unchanged by a means delivery).
- [ ] docs/ARCHITECTURE.md: means grants in "Two layers"; `support_delivered.means`.

View (strike means in the Support tab, TASK-121):

- [ ] The Support tab shows a **Strike means** line per side stock (cruise / ballistic / drones counts from `StrikeRules`), updated on delivery; a package that delivers means shows what and when ("Iranian drones: 12 in 2 turns"); a **delivery toast** when means arrive; a withdrawn Chinese package is marked with the reason ("withdrawn – Russia above Open war") and a toast. The stock is the same number the strike view (TASK-101) offers.

## Playtest (for the human)

1. As Russia (`--side=russia`, `--debug` for the level): press D → Support: request Chinese and Iranian support; the Strike means line shows the pending deliveries and their delays.
2. End turns: delivery toasts, the stock rises. Raise the level above Open war: the Chinese package shows "withdrawn" with the reason and a toast.
3. As NATO: after Russia's requests the allied cruise missile response appears for free; take it, the NATO stock rises.
4. Check the stock numbers against the implementation-notes script.

## Player manual

Section in the "Politics" chapter (started by TASK-113) – the politics chapter (TASK-119) and the deep strike chapter (TASK-101) will say: which supporters send weapons, how many of which strike means arrive after how many turns, that China delivers only while Russia keeps the war at *Open war* or below and has caused at most one net escalation step, and that NATO can answer with allied cruise missiles for free.

## Out of scope

- New means types or new formation types from supporters; production or resupply of means over time (TASK-104 / later); the strike view (TASK-101); AI use (TASK-102).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

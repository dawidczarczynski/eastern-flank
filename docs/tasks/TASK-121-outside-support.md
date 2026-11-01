# TASK-121: Outside support – off-map supporters, support packages as data, the *Request support* decision, delayed arrival of formations, responses for the other bloc

- **Status**: blocked
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data
- **Depends on**: TASK-117, TASK-118
- **Model**: sonnet
- **Topic**: Two-layer game
- **Tags**: mvp

## Goal

The blocs can draw third parties into the war – North Korean troops for Russia, allied (US / German …) reinforcements for NATO – but only through the political game: a package becomes available at a certain escalation level, costs escalation and arrives late, and requesting it hands the other bloc a free answer (GDD "Operational layer" → "Outside support", "Sides", "Strategic options"; human decision 2026-11-01). Weapons-only packages (China, Iran) are TASK-122 on the same mechanism.

## Acceptance criteria (testable)

Data (`src/core/data/`, `data/`):

- [ ] `SupporterDefinition` (Resource, `data/supporters/<id>.tres`): `id`, `display_name` (English, translation key), `side` (0 / 1). Four files: `nato_allies` "NATO allies" 0, `north_korea` "North Korea" 1, `china` "China" 1, `iran` "Iran" 1 (test reads them).
- [ ] `SupportPackage` (sub-resource of the operation): `id`, `display_name`, `supporter`, `side`, `min_level`, `max_level`, `max_caused` (−1 = no limit), `response_to: Array[StringName]`, `escalation_cost`, `entry_casus_belli` (bool), `delay_turns`, `withdraw_if_unmet` (bool), `formations: Array[FormationPlacement]` (TASK-092b's placement; `coord` = entry hex, `player` = `side`). `OperationDefinition.support_packages: Array[SupportPackage]`.
- [ ] `Operation.from_definition` rejects (`push_error`, null – one test each): `side` ≠ the supporter's side; `min_level` > `max_level` or outside 0 … top − 1; negative `escalation_cost` / `delay_turns`; `max_caused` < −1; a duplicate package id; a `response_to` id that is unknown or of the same side; a placement whose `player` ≠ `side`, whose type's faction is not in the side's factions, whose entry hex is off the map / impassable; a formation id that repeats any formation id of the operation (placed, contributed or in another package); a package with no effect (no formations – TASK-122 adds means).

State (`src/core/operational/`):

- [ ] `SupportState` per package (setup order) in `OperationalState.support`: `id`, `definition`, `requested_turn` (−1), `delivered` (false), `withdrawn` (false), `waiting: Array[FormationPlacement]` (placements not yet on the map, filled on request). `get_support(id)`. Snapshot gains `support: [{id, requested_turn, delivered, withdrawn, waiting: [formation ids]}]` sorted by id; the TASK-092b determinism test still passes.

Pure rules (`SupportRules`, static, `src/core/operational/support_rules.gd`):

- [ ] `is_response(state, package_id) -> bool` – some package in `response_to` has been requested (by the other side).
- [ ] `request_problem(state, player, package_id) -> String` – `""` or, in this order: `unknown_package`, `not_your_package` (side ≠ player), `already_requested`; unless `is_response`: `level_too_low`, `level_too_high`, `escalation_record` (`caused[player] − deescalated[player]` > `max_caused` ≥ 0); then, with cost = 0 for a response else `escalation_cost`: `standing_down` (cost > 0 and TASK-117's cooldown), `threshold` (level + cost ≥ top).
- [ ] `status(state, supporter_id) -> Dictionary` `{status, side}`: `&"supporting"` (a package of it delivered or partly delivered – some formation joined), `&"considering"` (a package requested and on its way, or `request_problem` for its side returns `""` or only `standing_down` / `threshold`), else `&"uninvolved"`; withdrawn packages count as not requested.

Command (`RequestSupportCommand(package)`, `{"type": "request_support", "package": "<id>"}`; a political decision of TASK-117):

- [ ] Rejections: TASK-117's common ones first (`battle_pending`, `no_decisions_left`), then `request_problem`. Apply: `political_decision_taken` (`decision` `request_support`, `country` `&""`), `decisions_left` − 1, `requested_turn` = `turn`, `waiting` = all placements, event `support_requested` (`package`, `supporter`, `player`, `delivery_turn` = turn + delay, `responses` – the other side's package ids that list this one in `response_to` and are not requested yet), then `EscalationRules.raise(state, player, &"support_request", cost)` when cost > 0.

Delivery (in `EndOperationalTurnCommand.apply`, right after `operational_turn_started` of the new current player – a delivered formation can get orders in the same turn):

- [ ] For each package of the new current player in setup order with `requested_turn` ≥ 0, not delivered / withdrawn, and `turn ≥ requested_turn + delay_turns`: if `withdraw_if_unmet` and the package is not a response and its conditions (levels, `max_caused`) fail now → `withdrawn`, `waiting` cleared, event `support_withdrawn` (`package`, `reason` – the `request_problem` code), cost not refunded. Otherwise `Reinforcements.place(state, waiting, side, package_id, require_open = true)` (TASK-118): placed ones leave `waiting` (events `formation_joined` with `source` = package id); with `entry_casus_belli`, for each country receiving a formation that is **aligned** (not belligerent) with the side and whose `casus_belli[other]` is false → set it, event `casus_belli_gained` (`country`, `player` = other, `formation_id`, `at`); then `waiting` empty → `delivered`, event `support_delivered` (`package`, `player`, `formations` – ids placed in this package overall); not empty → event `support_delayed` (`package`, `reason` `&"no_open_entry"`, `waiting` – ids), retried at the start of each later own turn.

Examples (TASK-116's "quad" grid, `first_player` 0, level 1, player 0's F on (0, 0), player 1's R on (7, 3) in belarus; test packages: **A** side 0 – U1 (`pl_tank_battalion`) at (1, 0), levels 1–3, cost 1, delay 2, `response_to` [N]; **N** side 1 – N1 (`ru_motor_rifle_battalion`) at (7, 3), N2 (`ru_mlrs_battalion`) at (6, 3), levels 2–3, cost 1, delay 2, `entry_casus_belli`, `response_to` [A]; **C** side 1 – C1 (`ru_tank_battalion`) at (5, 2), levels 1–2, `max_caused` 0, cost 0, delay 2, `withdraw_if_unmet`):

- [ ] Turn 1, player 0: request N → `not_your_package`; request `x` → `unknown_package`; request A → accepted: level 2, caused [1, 0], events `political_decision_taken`, `support_requested` (delivery_turn 3, responses [N]), `escalation_changed` (1 → 2, `support_request`, by 0); a second request the same turn → `no_decisions_left`; `status(A's supporter)` considering 0.
- [ ] Turn 1, player 1: request N → accepted **as a response**: level stays 2, no `escalation_changed`, caused [1, 0]. Fresh state at level 1: request N → `level_too_low`; at level 2 (test raise) → accepted, level 3.
- [ ] Round 3: at the start of player 0's turn U1 joins on (1, 0), `support_delivered` (A); A's supporter `supporting`. At the start of player 1's turn N1's entry (7, 3) is held by R → N1 on the nearest free belarus hex by TASK-118's tie rule (the test names it), N2 on (6, 3); one `casus_belli_gained` (belarus, player 0) after the two `formation_joined`, then `support_delivered` (N). With belarus first made belligerent 1 (test `set_stance`) → no casus belli.
- [ ] Closed entry: belarus set neutral before round 3 → at player 1's turn 3 nothing placed, `support_delayed` (`no_open_entry`, [N1, N2]); again in turn 4; after `set_stance(belarus, aligned, 1)` during player 1's turn 4 → delivered at the start of player 1's turn 5, with the casus belli.
- [ ] Withdrawal: player 1 requests C in turn 1 at level 1 (no escalation); the test then calls `EscalationRules.raise(state, 1, &"test")` → at player 1's turn 3 `support_withdrawn` (`escalation_record`), nothing placed, C's supporter `uninvolved`. The raise by player 0 instead → C1 delivered on (5, 2). Raised to 3 by player 0 → withdrawn `level_too_high`.
- [ ] `threshold`: level 3 (test raise), player 0 requests A → `threshold`; in a state where player 1 requested N at level 2 (raising it to 3), A is a response → accepted at level 3, no change. At level 3 player 1 requests N (not a response) → `threshold`. `standing_down`: player 0 within its cooldown → A `standing_down`; as a response → accepted.
- [ ] Side symmetry: no side-specific code; the A / N examples with the sides swapped give the mirrored results.
- [ ] No `rng` draws (test: `rng_state` unchanged).

Shipped data (`suwalki_gap.tres`) **[ASSUMPTION – GDD "Outside support", balance by TASK-103]**:

- [ ] `allied_reinforcements` (nato_allies, side 0): `us_armor_1` "US Armored Battalion" (`pl_tank_battalion`, parent "US Armored Brigade Combat Team") + `nato_mech_1` "NATO Mechanised Battalion" (`pl_mech_battalion`, parent "Allied Reaction Force") – entry hexes on a major road within 2 hexes of the **west** map edge in Poland; levels 1–3, cost 1, delay 4, `response_to` [nk_troops]. `nk_troops` (north_korea, side 1): `kp_inf_1` "North Korean Infantry Battalion" (`ru_motor_rifle_battalion`, parent "KPA Expeditionary Corps") + `kp_art_1` "North Korean Artillery Battalion" (`ru_mlrs_battalion`) – entry hexes within 2 hexes of the **east** map edge in Belarus (Lida direction); levels 2–3, cost 1, delay 4, `entry_casus_belli`, `response_to` [allied_reinforcements]. Test: strengths 80 / 56, entry hexes in poland / belarus and passable, the response links mutual. Coordinates picked by the agent on the real map and listed in the implementation notes with the place names.

Codec, replay, docs:

- [ ] `OperationalCommandCodec`: round trip; missing or non-string `package` → null; unknown string decodes (rejected `unknown_package`).
- [ ] Operational replay (TASK-117's scripted `suwalki_gap` sequence) extended with one NATO request and one free North Korean response, run until both arrive → decode + replay identical snapshot and events.
- [ ] docs/ARCHITECTURE.md "Two layers": supporters, packages, `SupportRules`, `RequestSupportCommand` and its rejection codes, delivery in the end-of-turn step; "Operational events": `support_requested`, `support_delivered`, `support_delayed`, `support_withdrawn`; `formation_joined.source`; escalation cause `support_request`.

## Playtest (for the human)

None – no view yet (TASK-119 shows supporters and packages). The agent lists in the implementation notes two scripted lines on `suwalki_gap` – NATO requests reinforcements at *Limited war* (Russia answers with North Korea for free) and Russia requests North Korea at *Open war* (NATO answers for free, gets a casus belli on Belarus) – with the level, caused counts and arrival turns, so the human can judge the "whoever internationalises first pays" trade.

## Player manual

None yet – not visible before TASK-119. The politics chapter (TASK-119) will describe: the off-map supporters of each side (NATO allies; North Korea, China, Iran) and their status, each package (what arrives, where, after how many turns, from which escalation level, its escalation cost), the *Request support* decision, that a request lets the other side answer for free, that North Korean troops arrive through Belarus (and wait while Belarus is closed, handing NATO a casus belli while Belarus is only aligned).

## Out of scope

- Strike means as package effects (TASK-122); AI use of requests (TASK-102); the political panel (TASK-119); supporter factions, rosters and camouflage; events that change packages (TASK-106); supporters as on-map countries with stances.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

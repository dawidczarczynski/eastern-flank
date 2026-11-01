# TASK-116: Borders in movement and battle – closed countries in routes and orders, sanctuary breach and casus belli while orders execute, route incident forecast, the border rule for contact battles and retreats

- **Status**: blocked
- **Layers**: core (`src/core/operational/`)
- **Depends on**: TASK-115, TASK-094, TASK-095 (re-ordered 2026-11-01: the loop first – this task adds the border rule to the finished contact and retreat rules; TASK-092e via TASK-094)
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

Borders matter on the operational map: formations never wander into a neutral or hostile country, Russian soil stays off limits until the war is open, the first step onto it raises the escalation, and using an aligned country as a launch pad hands the enemy a reason to attack it (GDD "Operational layer" → "Countries and stances" → incidents). The player sees before giving an order which incidents it would cause.

## Acceptance criteria (testable)

Test grids (plains, formations of type `pl_mech_battalion` / `ru_motor_rifle_battalion`, 8 move points, stances as in `suwalki_gap` – poland belligerent 0, lithuania aligned 0, belarus aligned 1, russia belligerent 1 sanctuary – start level 1):

- "quad": 8 × 4 tiles; `poland` where q < 4 and r < 2, `russia` q ≥ 4 and r < 2, `lithuania` q < 4 and r ≥ 2, `belarus` q ≥ 4 and r ≥ 2.
- "line": 6 × 1 tiles; q 0–2 `poland`, q 3–5 `belarus`.

Routes and orders:

- [ ] `OperationalRoutes.plan` treats every hex with `CountryRules.may_enter(state, player, hex) == false` as impassable, except the hexes of the country the formation **currently stands in** (a formation is never trapped: it can always walk out of the country it is in). `walk` and `forecast` follow the plan unchanged. Quad: player 0 F on (0, 0) → `plan` to (3, 3) (lithuania, own) non-empty; to (7, 0) at level 1 empty, at level 2 non-empty and without belarus hexes. Player 1 R on (7, 3) → `plan` to (0, 0) non-empty and without lithuania hexes. Trapped case: R on (7, 3) after `set_stance(belarus, neutral)` → `plan` to (6, 1) non-empty (it may cross belarus to leave).
- [ ] `IssueOrderCommand` rejects a destination with `may_enter == false` with **`closed_country`** – checked after `invalid_destination`, before `occupied` (TASK-092d's order otherwise unchanged; test both neighbours of the new check). Quad: F to (7, 0) at level 1 → `closed_country`; R to (1, 3) → `closed_country`.
- [ ] Execution (TASK-092e) checks the destination first: a destination that has become closed → order removed, `formation_order_interrupted` with reason **`closed_country`** (before the `destination_occupied` check). Test: F en route from (0, 0) to (3, 3), then `set_stance(lithuania, neutral)` → the next end of turn interrupts it with `closed_country`; a route that only crossed lithuania to an open destination is re-planned around it or interrupted `no_route` (TASK-092e rules).
- [ ] Zones of control are unchanged by borders (a formation in a closed country still exerts its zone of control – GDD open question "Contacts at a closed border").

Incidents while orders execute (inside the execution step; events of a formation come right after its `formation_moved` and before its `formation_order_completed` / `formation_halted`):

- [ ] **Sanctuary breach**: for each entered hex in step order, if it lies in an enemy sanctuary not yet breached by the player → `EscalationRules.breach(state, player, country, hex, formation_id)` (TASK-115). Quad at level 2: F on (3, 0) with a `march` order to (5, 0) → F on (5, 0); events `formation_moved`, `sanctuary_breached` (russia, player 0, at (4, 0)), `escalation_changed` (2 → 3, `sanctuary_breach`, by 0), `country_stance_changed` lithuania → belligerent 0, `country_stance_changed` belarus → belligerent 1, `formation_order_completed`. A second formation entering russia later → no breach events.
- [ ] **Threshold during execution**: the same move at level 3 → the breach takes the level to 4; the last event is `operation_ended` (winner 1); no later event of that turn is emitted (no further formation executes, no `battle_started`, no `operational_turn_ended` / `operational_turn_started`); F stands on (5, 0) (test).
- [ ] **Casus belli**: for each step (previous hex → entered hex, the first previous hex being the start) from a country **aligned** (not belligerent) with the player into a hex whose country is `enemy` to the player → that country's `casus_belli[other player]` = true, event `casus_belli_gained` (`country`, `player` = the other player, `formation_id`, `at` = the entered hex) – once per country and player (flag already set → no event). Line: player 1 R on (4, 0) with a `march` order to (1, 0) → after its move `belarus.casus_belli[0]` true, one `casus_belli_gained`; R only moving inside belarus ((5, 0) → (3, 0)) → none. A stance change of the country resets the flags (TASK-114 `set_stance`).

Borders in battle (hooks into TASK-094's contact rule and TASK-095's retreat – the loop was built first, decided 2026-11-01):

- [ ] `ContactRules.battle_allowed(state, attacker, defender)` (TASK-094's predicate) also requires `CountryRules.may_enter(state, attacker.player, defender.coord)`: no battle against a formation in a country closed to the attacker (GDD "Countries and stances"; zones of control are unchanged, so the attacker still halts next to it). Line grid, player 0's F on (2, 0), player 1's R on (3, 0) (belarus): `battle_allowed(F attacks R)` false (belarus hostile to 0), `battle_allowed(R attacks F)` true (poland enemy to 1); after `set_stance(belarus, belligerent, 1, …)` both true. Integration: F in `advance` posture comes into contact with R by TASK-094's rule → no `battle_started`, F stays halted next to R; after the stance change the next contact check → `battle_started` with F as attacker.
- [ ] Retreat (TASK-095) never ends on a hex closed to the retreating player; when every retreat hex is closed, TASK-095's "no retreat possible" rule applies. Test on the quad grid at level 1: player 0's formation retreating from (3, 1) (poland) with poland hexes behind it → it never ends on a russia or belarus hex; the same formation on (3, 2) (lithuania) may retreat inside lithuania or poland only.
- [ ] A battle never raises the escalation level and never sets a casus belli (test: level, `caused` and flags unchanged by `ResolveBattleCommand`).

Forecast for the view and the AI:

- [ ] `EscalationRules.route_incidents(state, formation, route: Array[Vector2i]) -> Array[Dictionary]` (pure, no state change): the incidents the route would cause in order, assuming nothing else changes: `{type: &"sanctuary_breach", country, at, steps, ends_operation: bool}` (cumulative level + steps ≥ top) and `{type: &"casus_belli", country, for_player, at}`. Quad, level 2, F route (3, 0) → (6, 0): one breach, `steps` 1, `ends_operation` false; at level 3: `ends_operation` true. Line, R route to (1, 0): one `casus_belli` for player 0 at (2, 0). Empty for a route inside own countries.

Real operation and performance:

- [ ] On `Operation.build("suwalki_gap", 7)` (test): a Belarus-group formation ordered to a hex near Suwałki is accepted and its route has no `lithuania` hex; a Polish formation ordered to Grodno → `closed_country`; a Polish formation ordered to a hex in the Kaliningrad oblast → `closed_country` at level 1, accepted after `EscalationRules.raise(state, 1, &"test")` (level 2), and its `route_incidents` list one breach.
- [ ] Speed: TASK-092c's cross-map `plan` on the theatre with the country check ≤ 36 ms median (≤ 1.2× its budget; country lookup per hex O(1)).
- [ ] Operational replay test of TASK-092e extended with one breach and one casus belli: identical snapshot and events after decode + replay; no `rng` draws.
- [ ] docs/ARCHITECTURE.md: closed hexes in `OperationalRoutes`, `closed_country` (order rejection and interruption), incidents in the execution step, `route_incidents`, the border check in `ContactRules.battle_allowed` and in retreat; "Operational events": `casus_belli_gained`.

## Playtest (for the human)

None – no view yet (TASK-093 / TASK-119 draw closed countries and route warnings). The agent lists in the implementation notes the scripted `suwalki_gap` run of TASK-092e again, now with borders: which orders were rejected as `closed_country`, which formations crossed from Belarus into Poland (casus belli) – so the human can judge whether the start layout still makes sense.

## Player manual

None yet – not visible before TASK-093 / TASK-119. The politics chapter will describe: formations never enter a neutral or hostile country (orders there are refused), Russian soil opens at Open war and the first entry raises the escalation by one, attacking out of an aligned country gives the enemy a casus belli against it, and the route preview warns about both. The operational chapter's battle section (TASK-094 / TASK-095) gains: no battle is fought against a formation standing in a country closed to the attacker (it still stops your advance next to it), and a beaten formation never retreats into a closed country.

## Out of scope

- The decisions that open a country (TASK-117), allied formations joining (TASK-118), strikes (TASK-097 calls `on_strike`), supply through countries (TASK-096), AI use of `route_incidents` (TASK-102). The contact rule and retreat themselves are TASK-094 / TASK-095; this task only adds the border checks to them.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

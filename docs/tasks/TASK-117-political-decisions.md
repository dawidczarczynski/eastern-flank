# TASK-117: Political decisions – Escalate, Stand down, Declare hostilities, Invoke alliance, Demand neutrality (commands, one per turn, cooldown, codec)

- **Status**: blocked
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data
- **Depends on**: TASK-116
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The player makes the strategic choices the human asked for: widen the war (authorise wider strikes, attack Belarus, bring Lithuania in) or keep it small (stand down, force Belarus out with an ultimatum) – each a deliberate decision with a visible price on the escalation ladder (GDD "Operational layer" → "Political decisions", "Strategic options").

## Acceptance criteria (testable)

Data and state:

- [ ] `EscalationLadder` gains **[ASSUMPTION]** (test reads the file): `decisions_per_turn` 1, `decision_escalation` 1, `declaration_escalation` 1, `alliance_escalation` 1, `stand_down_cooldown_turns` 2, `demand_neutrality_max_level` 2; `problem()` rejects negatives and `decisions_per_turn` < 1.
- [ ] `CountrySetup.accepts_ultimatum` (bool, default true); `suwalki_gap.tres`: lithuania **false** (a NATO member with allied troops on its soil), the others true **[ASSUMPTION – GDD "Sides"]** (test reads the file).
- [ ] `SideDefinition.alliance_decision_name` (English, translation key – the view's name for *Invoke alliance*): `nato` "Invoke collective defence", `russia` "Invoke the Union State" (test reads the files). The command itself is the same for both sides.
- [ ] `OperationalState`: `decisions_left` (int – the current player's; set to `decisions_per_turn` at the start and in `EndOperationalTurnCommand` when the next player's turn starts), `stand_down_until: Array[int]` [0, 0]. Snapshot gains `decisions_left` and `stand_down_until`.

Commands (the issuer is always `state.current_player`; every accepted decision first emits `political_decision_taken` (`player`, `decision` – the command's type, `country` – `&""` for none), then its effects; `decisions_left` − 1). Common rejections first, in this order: `battle_pending`, `no_decisions_left`. "Escalating" decisions (Escalate, Declare hostilities, Invoke alliance) are also rejected with `standing_down` while `turn ≤ stand_down_until[player]`.

Test setup: TASK-116's "quad" grid, `first_player` 0, level 1, player 0's F on (0, 0), player 1's R on (7, 3) (belarus).

- [ ] **`EscalateCommand`** `{"type": "escalate"}` – rejections after the common ones: `standing_down`, `threshold` (level + `decision_escalation` ≥ top). Apply: `EscalationRules.raise(state, player, &"decision", decision_escalation)`. Example: player 0 escalates → level 2, caused [1, 0]; a second decision in the same turn → `no_decisions_left`; in its next turn again → level 3 (the allies join – TASK-115 events); at 3 → `threshold`.
- [ ] **`StandDownCommand`** `{"type": "stand_down"}` – rejections: `at_floor` (level 0), `recent_escalation` (`last_raise_turn[player]` ≥ `turn − 1` – the player raised the level in this or the previous round, by any cause), `occupying` (a formation of the player stands in a country it breached or declared hostilities on). Apply: `EscalationRules.lower(state, player, &"stand_down")`, `stand_down_until[player]` = `turn + stand_down_cooldown_turns`. Examples: player 0 escalates in turn 1 → stand down in turn 2 `recent_escalation`, in turn 3 accepted (level 1, deescalated [1, 0]); then Escalate in turns 4 and 5 → `standing_down`, in turn 6 accepted. F standing in russia after a breach → `occupying`. Standing down below the start level is allowed (to 0); calm decay never raises it again.
- [ ] **`DeclareHostilitiesCommand(country)`** `{"type": "declare_hostilities", "country": "<id>"}` – rejections: `unknown_country`, `own_country` (relation own), `already_at_war` (relation enemy), `standing_down`, `threshold` (level + cost ≥ top; cost = 0 when `casus_belli[player]`, else `declaration_escalation`). Apply: `set_stance(country, belligerent, 1 − player, &"declared", player)` (a neutral joins the **other** side), `declared_by[player]` = true, then `raise(state, player, &"declaration", cost)` when cost > 0. Examples: player 0 declares on belarus → belarus belligerent 1, level 2, `may_enter(0, (5, 3))` true; with `belarus.casus_belli[0]` set first → level stays 1 and no `escalation_changed`; on russia → `already_at_war`; on lithuania → `own_country`.
- [ ] **`InvokeAllianceCommand(country)`** `{"type": "invoke_alliance", "country": "<id>"}` – rejections: `unknown_country`, `not_your_ally` (relation not own), `already_at_war` (own but belligerent), `standing_down`, `threshold` (level + `alliance_escalation` ≥ top). Apply: `set_stance(country, belligerent, player, &"invoked", player)`, then `raise(state, player, &"alliance", alliance_escalation)`. Examples: player 0 on lithuania → belligerent 0, level 2; on belarus → `not_your_ally`; on poland → `already_at_war`; player 1 on belarus → belligerent 1, caused [0, 1].
- [ ] **`DemandNeutralityCommand(country)`** `{"type": "demand_neutrality", "country": "<id>"}` – rejections: `unknown_country`, `not_hostile` (relation not hostile – the country must be aligned with the other side), `refuses_ultimatum` (`accepts_ultimatum` false), `level_too_high` (level > `demand_neutrality_max_level`), `troops_present` (a formation of the other player stands in that country). Not blocked by standing down. Apply: `set_stance(country, neutral, -1, &"neutrality_demanded", player)`; no escalation. Examples: player 0 on belarus with R there → `troops_present`; R moved to (5, 0) by the test → accepted, belarus neutral, `may_enter(1, (5, 3))` false; at level 3 → `level_too_high`. Player 1 on lithuania with no player-0 formation there and lithuania's `accepts_ultimatum` false → `refuses_ultimatum`; with it set true in the test → accepted (the rule is data, not side).
- [ ] **Side symmetry** (both sides playable – GDD "Sides"): no decision contains side-specific code; the examples mirrored on the quad grid give mirrored results (player 1 escalates in turn 1 → caused [0, 1]; player 1 invokes belarus → belligerent 1; player 1 declares on lithuania → lithuania belligerent 0, level 2, `declared_by[1]`).
- [ ] Decisions never change formations, orders or postures (snapshot diff limited to countries, escalation, decision fields).

Codec and determinism:

- [ ] `OperationalCommandCodec`: round trip of all five; null for a missing or non-string `country` where required; an unknown country string decodes (rejected by `validate` as `unknown_country`).
- [ ] Operational replay: on `Operation.build("suwalki_gap", 7)`, a scripted 4-round sequence with orders and decisions (one Escalate, one rejected Stand down, one Invoke alliance, one Demand neutrality rejected for `troops_present`) → decode + replay → identical snapshot and events; `rng_state` unchanged.
- [ ] docs/ARCHITECTURE.md: the five commands and their rejection codes; "Operational events": `political_decision_taken`.

## Playtest (for the human)

None – no view yet (TASK-119 adds the political panel). The agent describes in the implementation notes four short scripted lines on `suwalki_gap` (NATO keeps Belarus out with an ultimatum after the Belarus group crosses; NATO attacks Kaliningrad after escalating; Russia invokes Belarus; Russia declares hostilities on Lithuania after NATO launched out of it) with the level, stances and caused counts after each step, so the human can judge whether the trade-offs in GDD "Strategic options" come out as designed.

## Player manual

None yet – not visible before TASK-119. The politics chapter will describe the five decisions for both sides (with each side's name for *Invoke alliance*), when each is available (the reasons shown when not, incl. that Lithuania refuses ultimatums), their effects and escalation cost, one decision per turn, and the 2-turn cooldown after standing down.

## Out of scope

- The political panel and confirmations (TASK-119); allied formations entering play (TASK-118 – triggered by `set_stance` automatically); decisions by the AI (TASK-102); *Request support* (TASK-121 – uses this task's decision budget, `standing_down` and `threshold` checks); further decisions such as "guarantee neutrality", "request access" or peace offers (GDD open question "Political layer v1"; TASK-106 events); victory points for escalation (TASK-107).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

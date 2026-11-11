# TASK-107a: Operation victory – hex control, the Gap chain, scoring and the endings (core + data)

- **Status**: blocked
- **Layers**: core / data (+ ai: swap of the provisional score in the simulation runner)
- **Depends on**: TASK-103b (hard); TASK-104, TASK-105, TASK-106, TASK-118, TASK-121 (soft – none required)
- **Topic**: Two-layer game
- **Tags**: mvp
- **Sections**: GDD "Sides" (Victory bullet), "Operational turns", "Escalation ladder" (end of the operation, victory hooks), "Operational AI" (AI goals); ARCHITECTURE "Operational events"; grep docs/CODEMAP.md for `OperationDefinition`, `OperationalState`, `CollapseRules`, `EscalationRules`, `CampaignRecord`, `InstallationPlacement`, `ProvisionalScore`
- **Model**: sonnet

## Goal

The Suwałki operation has real objectives and a real end: NATO keeps the Gap road link open, Russia closes it, side cities are worth points, and the operation ends by one scoring rule for both sides. First part of TASK-107 (split 2026-11-11).

## Decisions (human interview, 2026-11-11)

- **Hex control** = the last side with a formation on the hex. Initial owner: the side of the hex's country (hexes of a country with no side start unheld, `-1`); a hex holding a start formation belongs to that formation's side. An installation counts as held while its hex is held. **No zones of control** for holding. Holder state lives in `OperationalState` (saved, replay-safe).
- **[ASSUMPTION]** Update rule: a hex's holder changes when a formation **ends its move on the hex** or **wins the battle there** (the attacker that takes the hex after a battle); passing through does not change it. Chosen as the cheapest deterministic rule.
- **Gap road link** = an ordered chain of road hexes Suwałki – Marijampolė, data `gap_chain` on the `OperationDefinition`; the implementer picks the real road hexes from `data/maps` and documents the hex list in Implementation notes. Russia's Kaliningrad–Belarus land link is the same chain condition. NATO's link is **open** while no chain hex is held by Russia; Russia **closes** it when it holds **every** chain hex.
- **Ending**: `round_limit` 30 (data). Russia wins instantly when it holds the whole chain at the end of `closed_rounds_to_win` 2 (data) consecutive rounds (reason `gap_closed`). Otherwise at the limit the higher score wins (reason `round_limit`); difference under `draw_margin` 5 (data) = draw. Existing endings stay: nuclear use (winner −1, reason `nuclear_use`) and the collapse rules exactly as TASK-140 has them (this task adds no ending of its own).
- **Scoring (all data on the operation)**: NATO – Chernyakhovsk 5; Russia – Białystok 5, Vilnius 5; Grodno 5 for whoever holds it at the end; Gap open at the end 10 for NATO; Gap closed (whole chain held) 10 for Russia; minus 3 per net escalation step caused (`max(0, caused − deescalated)`).
- **Single source of truth**: victory objectives are the same hexes / installations as the AI goals (TASK-102a). **[ASSUMPTION]** the AI goals keep the hexes and weights; `OperationDefinition` gets `objectives` (id of hex or installation, side, `points`, `holder_rule`: `own_side` / `any`) and the AI goals reference objective ids for their hex and weight where they overlap (goals without an objective stay as they are).
- **[ASSUMPTION]** `nuclear_use` keeps the rules' winner −1 (GDD "Escalation ladder"); the human-facing label is "Defeat for Russia, nobody wins". The GDD keeps both statements consistent.
- Side choice stays outside the operational state (107b). Balance of both sides was done by TASK-103b; this task re-runs it with the real victory.

## Acceptance criteria (testable)

- [ ] `HexControl` (pure, `src/core/operational/`): `holder(state, hex)` returns 0 / 1 / −1; initial holders per the Decisions (Polish-country hex 0, Russian-country hex 1, unowned country −1, start formation hex = its side).
- [ ] A formation of side 1 ending a move on a hex held by side 0 makes side 1 the holder; moving through it (hex not the last step) leaves the holder unchanged (test).
- [ ] The attacker that takes a hex after a won battle becomes its holder; a drawn or lost battle leaves it unchanged (test).
- [ ] An installation counts as held by the holder of its hex; hex holders are saved with `OperationalState` (to_dict / from_dict round trip equal) and a replay of the same commands gives identical holders.
- [ ] `OperationDefinition` data: `gap_chain` (≥ 3 ordered hexes, each a land hex with a road link, consecutive hexes neighbours), `round_limit` 30, `closed_rounds_to_win` 2, `draw_margin` 5, `objectives` with the points above; `suwalki_gap.tres` carries them; a test loads it and checks every objective / chain hex exists on the map and the chain starts at Suwałki and ends at Marijampolė.
- [ ] `OperationVictory.gap_status(state, def)` returns `open` while no chain hex is held by side 1, `closed` when side 1 holds every chain hex; chain of 4 hexes with side 1 on 3 → `open`, on all 4 → `closed`; a chain hex held by side 0 or `-1` never closes it (hand-made state).
- [ ] `OperationVictory.score(state, def)` returns per side a breakdown (list of `{id, points}` lines, `escalation_penalty`, `total`); hand-made: NATO holds Chernyakhovsk + Gap open + Grodno = 5 + 10 + 5 = 20, escalation caused 2 and deescalated 0 → −6 → total 14.
- [ ] Penalty: caused 3, deescalated 1 → −6 (net 2); caused 1, deescalated 3 → 0 (never positive).
- [ ] Grodno held by neither side at the end gives 0 to both; held by side 1 gives 5 to side 1 only.
- [ ] `closed_rounds_to_win`: whole chain held at the end of round 7 and round 8 → `operation_ended` winner 1, reason `gap_closed` after round 8; held in round 7 only and lost in round 8 → no ending and the counter resets to 0 (test; the counter is in `OperationalState`, saved).
- [ ] Round limit: at the end of round 30 with totals 20 vs 14 → winner 0, reason `round_limit`; difference 4 → winner −1 (draw); difference exactly 5 → the higher side wins; equal totals → draw.
- [ ] Order of checks at the end of a round: an existing ending (nuclear use) has already ended the operation and wins; `gap_closed` is checked before `round_limit`; a `gap_closed` on round 30 gives `gap_closed` (test).
- [ ] `operation_ended` carries `winner`, `reason` (`gap_closed`, `round_limit`, plus the existing ones) and a `score` payload `{0: breakdown, 1: breakdown}` (also for `nuclear_use`, where `winner` stays −1); after it every command is rejected `operation_over`.
- [ ] A new event `objective_changed` (`hex`, `holder`, `previous`) is emitted when a hex that carries an objective or a chain hex changes holder; no event for other hexes (test); ARCHITECTURE "Operational events" lists `objective_changed` and the extended `operation_ended`.
- [ ] `CampaignRecord` round trip: a record of an operation that ended by `gap_closed` replays to the same holders, score and result.
- [ ] Determinism: two runs of the same seed and commands give identical holders, counters, scores and endings.
- [ ] The 103a runner calls `OperationVictory` instead of `ProvisionalScore`; its report API shape (winner, reason, endings by type) is unchanged, with new ending types `gap_closed` and `round_limit` replacing `turn_cap`; 103a tests that referred to the provisional score are adapted; `ProvisionalScore` is removed (no dead code).
- [ ] Re-run `tools/simulate.sh 30 --mode=operation --seed=1`: record both sides' win shares of decided operations in Implementation notes; if either is outside 40–60 %, adjust only data (objective points, `round_limit`) and state what was changed.
- [ ] GDD updated: "Sides" Victory bullet becomes the decided rule (hex control, chain, points, endings, ties), "Operational turns" loses "No end of the operation yet", and the Open questions entries "hex control" and "Objectives per side" are marked decided.

## Playtest (for the human)

None for the core; check the report of `tools/simulate.sh 20 --mode=operation --seed=1` (win shares, endings `gap_closed` / `round_limit`). The player-visible part is TASK-107b.

## Player manual

none (the end notice and objectives are written in TASK-107b)

## Out of scope

- Any view, side chooser and end notice (TASK-107b); zones of control; supply (TASK-096); new endings; fog.
- Balancing beyond the data re-tune above.

## Implementation notes

_Filled in by the agent when done: the chosen `gap_chain` hex list, the win shares, decisions, known limitations._

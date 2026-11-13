# TASK-107a: Operation victory – hex control, the Gap chain, scoring and the endings (core + data)

- **Status**: done
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

- **gap_chain** (13 hexes, axial, Suwałki to Marijampolė along the road, found by BFS over road links): (17,34) Suwałki, (18,33), (19,32), (20,31), (21,30), (22,29), (23,28), (24,27), (25,26), (26,25), (27,24), (28,23), (29,22) Marijampolė. Six Polish and seven Lithuanian hexes; Suwałki starts held by NATO.
- **Objectives** (data `objectives` on `suwalki_gap.tres`): Chernyakhovsk airfield (installation, NATO 5), Białystok command post (installation, Russia 5), Vilnius (hex 56,17, Russia 5), Grodno depot (installation, `any`, **40** after tuning). Gap open 10 (NATO) / closed 10 (Russia), penalty 3 per net step.
- **Win shares** (`tools/simulate.sh 30 --mode=operation --seed=1`): first run with Grodno 5: NATO 28 / Russia 0 / 2 draws (Russia causes ~10 escalation steps per match = about -30, and never takes a scoring hex). Grodno 30: NATO 17 / Russia 8 / 5 draws (68 / 32 %). Final, Grodno 40 (only data change, objective points): NATO 15, Russia 12, draws 3 (nuclear 1) = **NATO 55.6 % / Russia 44.4 %** of decided operations; endings: round_limit 96.7 %, nuclear 3.3 %, gap_closed 0 %.
- **Decisions**: `OperationalState.definition` (static) carries the victory data so commands can end the operation; hand-made states without it have no victory rule (existing tests unchanged, only `test_calm_works_from_the_cap` raises its `round_limit`). `turn_cap` / `provisional_draw_threshold` removed (replaced by `round_limit` / `draw_margin`). The runner's `max_rounds` runs on a duplicate of the definition with a lower `round_limit`. Runner summary: `undecided` removed, `wins_provisional` -> `wins_by_score`, `decided` = matches without an error. AI goals `nato_hold_bialystok`, `nato_take_grodno`, `ru_hold_grodno` use `objective_id` (hex single source; weights stay on the goals). Attacker taking a hex after a won battle does not physically move there. `nuclear_use` event now carries `score`.
- **Limitations**: the AI has no goal for Vilnius, Chernyakhovsk or the chain, so `gap_closed` never happens in AI-vs-AI matches (0 %) and the result is mostly decided by Grodno and the escalation penalty; a follow-up AI task should add goals for the victory objectives. Reinforcements that appear (joined allies, support) do not take their hex. CampaignRecord `gap_closed` replay is tested on a hand-made strip operation via `replay_on`, since the shipped operation cannot reach it by commands in a test.

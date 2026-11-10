# TASK-140: Escalation ladder stretched to 7 levels, the threshold = a Russian nuclear attack

- **Status**: ready
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data + presentation (chip, ladder card, decisions, warnings)
- **Depends on**: TASK-117 (soft: TASK-097b – if its strike view is already committed, adapt its warning too)
- **Sections**: GDD "Escalation ladder", "Political decisions", "Deep strikes" (Escalation line), TASK-115 / 116 / 117 task files
- **Model**: opus (changes core rules, the snapshot / codec and the end-of-operation rule in several systems)

## Goal

The strategic threshold becomes a last resort and gets a concrete meaning: **Russia uses a nuclear weapon**. The ladder has 7 levels (0–6); incidents and ordinary decisions stop at level 5; level 6 is reached only by Russia's dedicated nuclear-strike decision, only from level 5 and only while Russia is in collapse. NATO can never trigger it. Playtest feedback 2026-11-10: with 5 levels the threshold came after three incidents.

## Acceptance criteria (testable)

Data (`data/operational/escalation.tres`, `EscalationLadder`) **[ASSUMPTION numbers]**:

- [ ] 7 levels: 0 `contained`, 1 `limited_war`, 2 `open_war`, 3 `regional_war`, 4 `general_war` (new, ROE as Open war), 5 `strategic_alert` (new, ROE as Open war), 6 `strategic_threshold` (the nuclear attack; no classes); `top()` = 6; `sanctuary_open_level` 2, `allies_join_level` 3 unchanged. New fields: `collapse_strength_pct = 50`, `collapse_readiness_pct = 35`, `collapse_readiness_strength_pct = 70`; `problem()` rejects pct outside 1–100. Levels 4 and 5 have no effects beyond headroom.
- [ ] Side data gets a flag `may_use_nuclear` (true for Russia only, false for NATO) so no rule names a side. The test ladders of existing tests keep working (they build their own levels or are updated).
- [ ] The cap `top() - 1` is derived from `top()`, never a literal 5; a 5-level test ladder still behaves as before except for the new rules below.

Fielded strength and collapse (new pure `CollapseRules`, no `rng`):

- [ ] `OperationalState.fielded_strength[player]` (int, in snapshot and codec) is the sum of `max_strength()` of every formation that has entered play for that player: at build, `formation_joined` (TASK-118) and support arrival (TASK-121); destroyed formations stay in the sum. Replay: identical snapshot after decode + replay.
- [ ] `CollapseRules.strength_pct(state, p)` = 100 × present strength / fielded strength (integer division; 100 when fielded is 0); `avg_readiness(state, p)` over surviving formations (100 when none).
- [ ] `CollapseRules.in_collapse(state, p)` – test table with fielded 400: present 200 (50 %) → true; 204 (51 %) with readiness 100 → false; present 280 (70 %) with average readiness 35 → true; 284 (71 %) with readiness 0 → false; 280 with readiness 36 → false; no formations → true. The rule is the same for player 0 and 1 (mirror test).

Caps and the nuclear attack (`EscalationRules`, `EscalateCommand`, new `NuclearStrikeCommand`):

- [ ] `raise(state, by, cause, steps)` never goes above `top() - 1` (level 5) and returns the capped result: from 4 with `steps` 3 → level 5; `caused[by]` grows by the real steps only; from 5 a further raise is a no-op (no event, `raised_this_round` unchanged). No `operation_ended` can come from `raise`.
- [ ] Incident behaviour at the cap: a sanctuary breach at level 5 still marks the country breached and emits `sanctuary_breached` but no `escalation_changed`; an urban strike at level 5 still does its damage.
- [ ] Urban strikes: the **first** urban strike by a side in the operation adds +1; every later urban strike by that side adds 0 (flag `urban_escalated[side]`, in snapshot and codec, never cleared – once per side per operation, like the sanctuary breach); the other side's first urban strike still adds +1. The old per-round limit is not implemented.
- [ ] `EscalateCommand` is capped at level 5 for **both** sides: at level 5 it is rejected with `level_cap` whether or not the side collapses; below 5 it behaves as before.
- [ ] `NuclearStrikeCommand` (decision "Use nuclear weapon") accepted only when: the side's `may_use_nuclear` is true, level == `top() - 1` (5), and `CollapseRules.in_collapse(state, player)`. Then: level 6, `caused[player]` +1, `escalation_changed`, `operation_ended` with reason **`nuclear_use`**, `by` = player, winner = the other side, pending battles dropped. Rejections (checked in this order): `operation_over`, `not_nuclear_power` (NATO, always), `level_too_low` (level < 5), `no_collapse`. It is not blocked by standing down. It counts as the side's decision for the turn (one decision per own turn). Codec and replay round-trip the command.
- [ ] `DeclareHostilitiesCommand`, `InvokeAllianceCommand`, `RequestSupportCommand` are rejected with `level_cap` (reuse the existing code if the former "would reach the threshold" reason exists; list any rename in the notes) when level + cost > 5.
- [ ] `EscalationRules.route_incidents` and `strike_escalation` never report `ends_operation` true; breach steps are clipped to the cap (a breach at level 5 reports `steps` 0).
- [ ] Calm and `StandDownCommand` work from level 5 (calm 5 → 4 after 3 quiet rounds, not below the start level); level 6 is final (operation over).
- [ ] Mirror test: the same collapse scenario with sides swapped gives the mirrored collapse result (the nuclear command itself stays Russia-only); no `rng` draws in any of the above.
- [ ] The existing tests that pin "level 4 ends the operation" (`test_escalation.gd`, `test_borders_movement.gd`, `test_political_decisions.gd`, `test_strike_*`, `test_staff_map_*`) are rewritten to the new numbers; no test is deleted without an equivalent.

View (presentation reads state only):

- [ ] `StaffMapEscalationChip`: 7 ticks coloured green → red (the generator already follows `top()`); text and ticks still fit the 290 px chip (test: tick count 7, `lit_ticks` right at level 0 / 5).
- [ ] Ladder card (TASK-115): 7 rows with the new names, level 6 labelled "Nuclear attack"; below them a **collapse strip** per side: "Russia · strength 72 % · readiness 80 · collapse at ≤ 50 %" from `CollapseRules`; the red "COLLAPSE" tag appears when `in_collapse` is true (test on a model function: strip text for a fixture state, tag flag).
- [ ] Decisions panel (TASK-117): a **"Use nuclear weapon"** button exists only for Russia's player (not shown for NATO); disabled with the reason (`level_too_low` "Only at the highest level of escalation", `no_collapse` "Only while the army is collapsing"); when enabled it is red and opens a heavily worded red confirmation, e.g. "Use a nuclear weapon? This ends the operation. Russia is judged to have crossed the line." (test on the model: visibility per side, enabled flag and reason per state). The plain Escalate button is disabled at level 5 with the `level_cap` reason for both sides; Declare / Invoke / Request show the `level_cap` reason at level 5.
- [ ] Route / order warnings (TASK-116) and the strike confirm card (TASK-097b, if committed): an incident at level 5 reads "Already at the highest level – no further escalation"; the red "This ends the operation" tag disappears from incidents.
- [ ] Operation-over notice for reason `nuclear_use`: "Russia used a nuclear weapon. The operation ends." and names the winner (the other side); no "threshold" wording.
- [ ] i18n keys added to `assets/i18n/strings.csv`; ARCHITECTURE: `CollapseRules`, `NuclearStrikeCommand`, `fielded_strength`, `urban_escalated`, `may_use_nuclear`, new reason codes, end reason `nuclear_use`; event table unchanged (`escalation_changed`, `operation_ended`).

## Playtest (for the human)

1. Operation, NATO: raise through Open war / Regional war by decisions and breach Kaliningrad, strike a town – the chip climbs to 4 or 5 and stays there; the operation does **not** end. A further incident only shows "no further escalation". A second urban strike by the same side adds no level.
2. Open the ladder card (click the chip): seven rows, the collapse strip for both sides with percentages.
3. `--debug` panel: destroy / damage most Russian formations until Russia's strength is ≤ 50 %: the "COLLAPSE" tag lights on the strip. As Russia (`--side=russia`) at level 5, "Use nuclear weapon" turns red with the heavy confirmation; confirm – the operation ends with the nuclear notice, NATO is named the winner.
4. As NATO the button never appears; the plain Escalate is disabled at level 5.
5. As Russia at level 5 without collapse, or in collapse below level 5: the button is disabled with the reason.
6. Judge whether level 5 is hard enough to reach and whether the collapse figures feel right (tune in the .tres).

## Player manual

Rewrite the "Escalation ladder" table in docs/MANUAL.md to seven levels (numbered as in the chip, 0–6), add *General war* and *Strategic alert* (no automatic effect), the cap at level 5 for incidents and decisions, the once-per-operation urban-strike rule, the **collapse** rule (when an army counts as collapsing, in plain numbers) and the last level: **only Russia, only at level 5, only while its army is collapsing, may use a nuclear weapon; this ends the operation and Russia is judged the loser**; NATO cannot. Change the "end" paragraph, the decision table (new "Use nuclear weapon" row, `level_cap` rejections), the Deep strike "Escalation" paragraph and the confirm-card bullet; document the collapse strip and the red nuclear confirmation.

## Out of scope

- Real morale, effects at levels 4 and 5 beyond headroom, AI use of the nuclear option (TASK-102 reads the GDD: last resort only, when Russia is collapsing, at level 5), balance by simulation (TASK-103), score weights for the `nuclear_use` result (TASK-107).

## Implementation notes

_Filled in by the agent when done._

# TASK-101: Deep strike forecast – expected hits and damage of a planned salvo in the confirm card

- **Status**: to playtest
- **Layers**: core (pure `StrikeRules.forecast`), presentation (staff map: odds row extension, pure text model)
- **Depends on**: TASK-097b, TASK-098a, TASK-098b (all done; soft: TASK-100 – reconnaissance modifier)
- **Sections**: GDD "Deep strikes"; ARCHITECTURE "Operational events" (no new event); TASK-098b notes (`StaffMapOddsRow`, `StaffMapAirDefence`), TASK-089a (how `CombatForecast` is done)
- **Model**: sonnet (exact binomial over a small salvo; the one tricky part, formation damage, reuses the resolution's helper)
- **Topic**: Two-layer game
- **Tags**: mvp

## Decisions (human, 2026-11-11)

Q1 re-scoped to the **forecast only**: strike mode, confirm card, report card, trails (TASK-097b) and the interception odds row (TASK-098b) already exist. Q2 the forecast is **exact and computed in core**, with the same probabilities as the resolution (no Monte Carlo, no RNG, no state change). Q3 shown on the existing **confirm card** (optionally the panel's "AT TARGET" chip) by extending the odds row; **no distribution bar** (it would need `/design-ui`; follow-up). Q4 **no new design**: the rows reuse the look of `StaffMapOddsRow`. Q5 the reconnaissance modifier stays 0 until TASK-100; the forecast takes the same modifier the resolution uses.

## Goal

Before confirming a strike the player sees what it is likely to achieve – expected hits, the chance of at least one hit, and the expected result on the target – so that choosing a weapon and salvo size is an informed decision (like `CombatForecast` in battles).

## Acceptance criteria (testable)

Core (`StrikeRules.forecast(state, player, weapon_id, salvo, target)` or a small `StrikeForecast` class; pure, no `state.rng`, no state change – state compared before / after in a test):

- [ ] Returns {} for an unknown weapon, a weapon of the other side, an empty target, `StrikeRules.target_problem(...) != ""` (out of range, closed country, ROE, destroyed), or stock 0.
- [ ] Effective salvo = `clampi(salvo, 1, mini(max_salvo, stock))`; the result carries `count` (the effective one) so that "stock lower than salvo" shows the capped number; test: salvo 4, stock 2 -> `count` 2.
- [ ] Per-missile hit probability `p_hit_missile` = (1 - p_intercept/100) x p_hit/100, with p_intercept = `interception_chance` (capped at 100, interceptability above 100 % can exceed it: Geran-2 under 90 % cover -> 100, never negative) and p_hit = `clampi(accuracy_pct + recon_modifier, 0, 100)`; both come from the same functions `resolve` uses (extract a shared helper if needed). Test: for every shipped weapon on a covered and an uncovered target the forecast's `p_intercept`, `p_hit` and `p_hit_missile` equal the values in the `strike_resolved` event of a real `StrikeCommand` on a copy of the state.
- [ ] Salvo distribution is the exact binomial of `count` trials with `p_hit_missile`: `expected_hits` = count x p; `p_at_least_one` = 1 - (1-p)^count. Test: JASSM-ER (accuracy 90, interceptability 70) salvo 4 with no cover -> p 0.90, expected hits 3.6, at least one 99.99 %; with one site giving 30 % combined cover -> intercept 21, p 0.711, expected hits 2.844 (tolerance 1e-6).
- [ ] Installation target: for k = 0..count hits the integrity after is `maxi(0, before - k x damage)`; `expected_integrity_after` and `p_destroyed` (integrity 0) are the binomial-weighted sums. Test: integrity 100, damage 40, salvo 4, p 0.5 -> `p_destroyed` = P(k >= 3) = 0.3125 (5/16), expected integrity after = sum over k of C(4,k)/16 x max(0, 100 - 40k) = 28.75; integrity 30, one hit of 40 -> after 0 (floor).
- [ ] Formation target: for k hits the strength lost is computed by the **same helper** the resolution uses (each hit takes `formation_damage` from the strongest company, ties lowest index, floor 0; a formation with no strength left is destroyed) – refactor `_damage_formation`'s arithmetic into a pure function on a strengths array that both call; `expected_strength_lost` and `p_destroyed` are the binomial-weighted sums. Test: companies [4, 4, 4], damage 3, 2 hits -> lost 6 (strongest first: 4->1, then 4->1); a one-company formation with 2 strength and one hit of 3 -> lost 2, destroyed; a test that the forecast's lost strength for each k equals the `before - after` of a real resolution with k forced hits (call the helper on a copy).
- [ ] A suppressed air-defence site does not count (forecast `p_intercept` equals the value after the suppression, as in resolution); a destroyed one does not count; works for player 0 and player 1 (Polish and Russian weapons).
- [ ] Deterministic: the same inputs give the same dictionary twice; the forecast never changes `state.rng` (state before / after equal, including the RNG state).

View (pure text model, e.g. in `StaffMapAirDefence` / `StaffMapStrikeText`, tested without a scene):

- [ ] Hits row: "Expected hits 1.8 of 4 – at least one hit 97%" (one decimal for hits; whole-% rounding, but "100%" only when exactly 1.0 and "0%" only when exactly 0 – otherwise clamp to 1..99). Test: p 0.5, count 4 -> "Expected hits 2.0 of 4 – at least one hit 94%".
- [ ] Installation row: "Expected integrity 100 -> 41, destroyed ~12%" (integer expected integrity, destroyed as whole % with "~"; when `p_destroyed` is 0 the tail ", destroyed ~12%" is dropped).
- [ ] Formation row: "Expected loss ~3 strength" (rounded to whole points; ", destroyed ~N%" appended only when `p_destroyed` > 0).
- [ ] The rows appear in the confirm card below the interception row for a legal target, and **update live** when the weapon or salvo changes (salvo +/-: the numbers change at once; stock lower than the salvo shows the capped count). Out-of-range / illegal targets (reason line shown) show **no** forecast rows.
- [ ] Optional: the panel's "AT TARGET" chip shows the hits row for the hovered target while a weapon is picked (skip it if it does not fit the chip; state so in the notes).
- [ ] Scene smoke test with a hand-made state: S -> pick a weapon -> click a target -> the card shows the hits row and the installation (or formation) row with the core's numbers; salvo change updates them; `--side=russia` works the same.

## Look (Claude Design)

No new design: the two rows reuse the look of `StaffMapOddsRow` (font, size, colour, spacing of the confirm card); no new element, no bar. Compare a `tools/screenshot.sh` render of the confirm card with docs/design/operational_map before reporting.

## Playtest (for the human)

1. Operation (`--debug`, F9 to Open war): S -> `jassm_er` -> click a Russian airfield in Kaliningrad: the card shows the interception row, "Expected hits ... of N - at least one hit ...%" and "Expected integrity 100 -> X, destroyed ~Y%".
2. Change the salvo with the salvo control: the numbers update at once; a larger salvo raises expected hits and destroyed %.
3. Pick a formation target: the card shows "Expected loss ~N strength".
4. Strike an air-defence site first (SEAD), then the airfield: the interception row drops to "Air defence suppressed" and the expected hits rise.
5. Pick a weapon whose stock is lower than the salvo: the card shows the capped count; a target out of range shows no forecast rows.
6. Confirm a few strikes: the real results scatter around the forecast (it is an average, not a promise).
7. `--side=russia`: the same against Polish targets.

## Player manual

Chapter **Deep strikes**, a part "Strike forecast": what the confirm card rows mean – expected hits is the average number of missiles that get through and hit (after interception and the weapon's accuracy), "at least one hit" the chance that the strike achieves anything, expected integrity / loss the average result on the target and "destroyed ~N%" the chance to destroy it; they are **averages, not guarantees** – a single strike can do much better or worse; the forecast follows air-defence suppression and the salvo size live and is not shown for targets you cannot strike.

## Out of scope

A distribution bar or histogram (needs `/design-ui`; follow-up); reconnaissance (TASK-100 – the modifier is 0 and the forecast will pick it up through the shared hook); the AI's use of the forecast (TASK-102); changes to the resolution rules or numbers (TASK-103); forecasting several strikes in a row; battle-layer display.

## Implementation notes

- Core: `StrikeRules.forecast` (exact binomial, no RNG, no state change) plus shared helpers `hit_chance` and `strengths_after_hits` (the resolution's formation damage now uses it). Tests: `test_strike_forecast.gd` (incl. forecast = resolution for every shipped weapon).
- View: `StaffMapStrikeText.forecast_rows` (pure text, `test_staff_map_strike_forecast.gd`), `confirm_model["forecast_rows"]`, a `Forecast` label box under the odds row of `StaffMapStrikeConfirm` (scene test in `test_staff_map_air_defence_view.gd`). Strings added to `strings.csv` (en, pl); MANUAL "Strike forecast".
- Deviation: the rows are plain mono 11 labels in the card's text colour, not bordered `StaffMapOddsRow` boxes (that row has a shield glyph that does not fit). Not compared with a screenshot (no render done).
- Salvo is fixed while the card is open; the salvo changes in the panel and the card is rebuilt on the next click, so "live" means on re-opening.
- The optional "AT TARGET" chip hits row was skipped (chip is 24 px, single-line).

# TASK-097b: Deep strike v1 (2/2, view) – strike mode on the staff map: pick means, legal targets, confirm with the escalation warning, result marker

- **Status**: done
- **Layers**: presentation (staff map); reads state and events only, executes `StrikeCommand` through `OperationalSimulation.execute`
- **Depends on**: TASK-097a, TASK-117 (the Escalate decision used by "raise and strike")
- **Sections**: GDD "Deep strikes", "Operational map view"; ARCHITECTURE "Operational events"
- **Model**: sonnet
- **Topic**: Two-layer game
- **Tags**: mvp

## Goal

The player strikes from the staff map: key S, pick a means and salvo, see which targets are legal (and why the others are not), confirm with the escalation consequences spelled out, and see the result on the map at once (decisions Q12, Q10; rules and data in [TASK-097a](TASK-097a-deep-strike-core.md)). Forecast of hit chances and the strike report are TASK-101.

## Acceptance criteria (testable)

Pure view model (`StaffMapStrike`, tested without a scene) and the scene:

- [ ] View model from state: means list `{id, name, stock, range_hexes, max_salvo}` for the viewer side, `strikes_left`, salvo limits (1 … min(`max_salvo`, stock)); per target `{legal, reason_code, reason_text}` from `StrikeRules.target_problem(state, player, id, means)`. Texts (English, translation keys): `closed_country` "Closed soil – opens at Open war / Regional war", `roe_class` "Not allowed at this level – needs Open war", `own_soil` "Own territory", `out_of_range` "Out of range of {means}", `target_destroyed` "Already destroyed". Test: each code gives its text; a legal target has none.
- [ ] Escalation warning text from `StrikeRules.escalation_preview` and the ladder: 0 → none; ≥ 1 → "Breaches Russian sanctuary: +1 escalation" and/or "Urban hex: +1", the new level named; when `level + preview ≥ top` → danger line "Reaches the strategic threshold – you would lose the operation". Test on TASK-115's strip grid.
- [ ] **Strike mode** (key **S**, and a HUD button next to the escalation chip; Esc leaves): a panel (HUD v3 frame, like the contact notice) lists means with stock and range, the salvo stepper and "Strikes: n/N". With a means picked, the **legal targets glow**, illegal ones are dimmed and show their reason on hover; the hover card of an out-of-range target says "Out of range of Cruise missile". Not the viewer's turn / operation over / battle pending: the mode cannot be opened (reason shown).
- [ ] Clicking a legal target opens the **confirm card**: target, means × salvo, escalation lines, red threshold line when applicable; **Confirm** executes `StrikeCommand`, **Cancel** returns to the mode. A rejected command shows its code as a toast and changes nothing.
- [ ] **Raise and strike** (decision by the human, 2026-11-09): a target rejected only with `roe_class` (or `closed_country` for an enemy sanctuary that the next level opens) is not a dead end when the political decision *Escalate* (TASK-117) is available – `decisions_left` > 0, no cooldown, and `level + 1` allows the class (and opens the sanctuary) without reaching the top. Such a target is shown as **conditional** (amber, not dimmed) with the reason "Needs Open war – raise the level first". Clicking it opens the confirm card with a first line "**Escalate** to <next level> (uses this turn's decision)", then the usual escalation lines computed for the **new** level; **Confirm** executes the Escalate decision command and then `StrikeCommand` (two ordinary commands in a row, nothing new in the core). If Escalate is rejected nothing is struck and the code is shown; if the strike is rejected after a successful Escalate, the toast says the level was raised but the strike failed. Not offered when the level is already enough (plain confirm card), when the decision is spent, or when one level is not enough (reason stays). Test on the strip grid: an airfield at level 2 offers raise-and-strike, at level 1 it does not (two levels short), after the decision is spent it does not.
- [ ] **Result**: toast from `strike_resolved` ("Cruise ×2 on Chernyakhovsk airfield: 1 intercepted, 1 hit – integrity 100 → 65", threshold/breach lines from the escalation events), a **burst marker** on the hex (colour by hit / intercepted / missed) that fades at the start of the viewer's next turn; the installation marker bar, a struck formation's counter strength, the stock line and the strikes counter update from events.
- [ ] **Strike trail on the map** (decision by the human, 2026-11-09), from `strike_launched` / `strike_resolved` only (no state reads beyond the events and `CountryRules`): (a) a **trajectory** – a thin arc in the striker's side colour from the nearest hex of a country own to the striker (the hex the range was measured from; pure helper, tested) to the target hex, drawn with a short animation (~0.6 s) when the strike resolves, then kept as a faint trace; (b) **interception marks** – a small mark on each intact enemy air-defence site within `air_defence_radius` of the target that contributed to `p_intercept`, shown only when `intercepted` > 0, with the count; (c) **traces of both sides** stay until the start of the viewer's next turn, so the enemy's strikes during its turn are visible too; at most 8 traces at once (the oldest fade first), and nothing is drawn for a strike the viewer cannot see once fog exists (TASK-100 hook: one `is_visible` predicate, always true now). Test: the pure helper picks the nearest own hex (own country change → another origin); a strike with 0 intercepted draws no interception marks; the traces are cleared at the viewer's turn start; a scene smoke test that a strike creates one trace and one burst marker.
- [ ] **Result report card** (decision by the human, 2026-11-10, variant A of `docs/design/operational_map/strike-result-report.html`; replaces the one-line toast): after `strike_resolved` a `StaffMapStrikeReport` card (header with side tab, name, outcome pictograms and counts, integrity / strength before → after, interceptor sites, escalation ticks and lines, footer with stock and strikes left for own strikes) with the timing and keys from the mockup (9 s then chip, enemy cards 3.5 s queued, J ↵ ◂ ▸ Esc). Model `StaffMapStrikeText.report_model(state, event, trail)` is pure and unit-tested (own, enemy with no stock, destroyed, all intercepted, all missed, escalation, threshold); `resolved()` stays as the fallback string. Enemy reports list only interceptor sites the viewer can see (TASK-100 `is_visible`). The designation is shown only once TASK-141a adds the field (name only until then).
- [ ] **X close button** on every such window: the report card, the collapsed chip, the strike panel and the confirm card (top-right of the frame, 24 px hit area; Esc / ↵ keep working; on the report it dismisses it, nothing collapses). Tests for the model, the X on each window and the queue.
- [ ] Scene-level smoke test: with a hand-made state, S → pick `cruise` → click an airfield → Confirm changes its bar and the stock line and shows a toast; an out-of-range and a closed target cannot be confirmed and show their reason; the mode works for player 1 (`--side=russia`).

## Look (Claude Design)

Result report: follow `docs/design/operational_map/strike-result-report.html` (variant A, accepted 2026-11-10) – frame, tokens, sizes, states, timing and the X button are specified there; the X also goes on the strike panel and the confirm card.

No strike mockup in `docs/design/operational_map`. Reuse the contact notice panel frame, `StaffMapCard`, the toast and counter components (grep CODEMAP); colours `ui.text`, danger `ui.alert #e07c5e`, legal-target glow in the viewer's side colour. State the deviation in the notes.

## Playtest (for the human)

1. **Operation** as NATO (`--debug`): press **S**: means with stock and range, "Strikes: 2/2"; pick `cruise`: Russian formations on Polish soil glow; Kaliningrad and Belarus targets are dimmed ("Closed soil …"); hover shows the reason.
2. F9 → raise to *Open war*: Kaliningrad's airfield and command post glow; click the airfield: card with "+1 sanctuary breach, +1 urban hex" and the new level; Confirm: the strike mode closes by itself (glows vanish; S opens it again), burst marker, the bar drops, the escalation chip rises.
3. Pick `strike_drone`, hover a far target: "Out of range of Strike drone".
4. Spend the stock / strikes: the means is greyed at 0, a third strike in a turn is refused (press S to reopen after each strike); end turn: counter back at 2.
5. At level 3 pick a town target: the red threshold line appears; Confirm ends the operation (end notice).
6. `--side=russia`: the same flow against Polish targets.
7. Raise and strike: at level 1 (default) an airfield is amber; click: the card starts with "Escalate to Open war"; Confirm raises the level and strikes.
8. Trail: after a strike an arc runs from the nearest own hex to the target (animated, then faint); with a defended target, interception marks with counts appear on the air-defence sites; the enemy's strikes after End turn leave their arcs too; the traces vanish at the start of your next turn.
9. Result report: confirm a strike; after the burst a card appears at the left under the turn bar (name, outcome counts, integrity before → after, interceptor sites, escalation, stock). It collapses to a chip after 9 s; J toggles it; X on the card and on the chip dismisses it; Esc and Enter still work.
10. End the turn with enemy strikes: each report shows for 3.5 s, the chip shows '1/n', ◂ ▸ browse; the enemy report shows no stock and no interceptor sites you cannot see.
11. Strike panel and confirm card each have an X top-right that closes them like Esc.

## Player manual

Extend the **Deep strikes** chapter: how to open strike mode (S, Esc), pick means and salvo, what glowing / dimmed targets and the reasons mean, the confirm card and its warnings, the result toast, burst marker and strike trail (arc and interception marks), strikes per turn.

## Out of scope

Hit-chance forecast and effectiveness preview, the strike report panel (TASK-101); reconnaissance-dependent visibility (TASK-100); AI use (TASK-102).

## Implementation notes

Done: pure `StaffMapStrike` view model and `StaffMapStrikeTrail` (origin, interceptors, traces, 8-trace cap, cleared at the viewer's turn start, `is_visible` fog hook); scene parts `staff_map_strike_{panel,confirm,layer,hud}.gd` in `src/presentation/operational/`; S / Esc / Enter, STRIKE [S] button in the turn bar; raise-and-strike (`EscalateCommand` then `StrikeCommand`); toast, burst markers, arcs, interception marks. Tests: `test_staff_map_strike_model.gd` (21), `test_staff_map_strike_mode.gd` (14). `tools/screenshot.sh` got a `strike:<means>[:<target>[:fire]]` token.

Deviations (no strike mockup): panel and confirm card reuse the contact-notice frame with an alert tab; only rings drawn on targets (no hex fill): double ring = legal, amber = conditional, dark disc = illegal; burst marker on the hex centre; STRIKE button in the turn bar under-row, not the bottom command bar; sanctuary line names the country; only the strongest air-defence site shows "x n"; rejection codes stay raw in the toast.

Ladder note: the shipped ladder needs Open war (level 2) for airfields, so raise-and-strike is offered at level 1 (not 0), not "level 2 / level 1" as the criterion text says.

Limitations: interception marks read post-strike air-defence integrity (a destroyed covering site has no mark); no real fog yet; 60 FPS not measured (target/hover recompute ~3 ms). One timing test (`test_auto_resolve:test_speed`) failed once under parallel load, passes alone.


### Addendum after the first playtest (2026-11-10)

- Interception marks are rebuilt from the event (struck installation's `damage_dealt` added back), so they are correct also when the struck site is air defence. One arc per missile (outcomes intercepted → hit → missed, staggered, own arc height and bend); intercepted ones burst mid-air at an interceptor site, misses land beside the target. New `staff_map_strike_fx.gd`: impacts vary by target class and outcome; max 6 strikes kept.
- Result toast replaced by the **report card** (accepted mockup `docs/design/operational_map/strike-result-report.html`, variant A): `StaffMapStrikeText.report_model` (pure), `StaffMapStrikeReport`, `StaffMapStrikeChip`, `StaffMapStrikeReports` (queue, 9 s / 3.5 s), `StaffMapCloseButton` (X on report, chip, strike panel, confirm card); keys J / Enter / Esc / arrows. Tokens `outcome_hit/intercepted/miss` in `StaffMapPalette`.
- Deviations: card tab is text-width; header shows name and ×N only (designation after TASK-141a); card sits lower below 1500 px width; the chip body is not clickable; burst-marker colours on the map (hit red, intercepted amber) differ from the report's outcome tokens; `test_unit_model_contract` / `test_auto_resolve` timing tests flake under load.
- Second playtest: strike mode closes after a made strike (rejections keep it open); chip made compact (tab, weapon ×N, short result, X; J and arrows work but are not printed; placed under the turn bar row, clamped at narrow widths); header texts "TURN n · side" (card) and "STRIKES: n/N" (panel header) removed (the panel body and the report footer keep strikes left).
- Follow-ups from playtest: TASK-140 (escalation ladder / nuclear threshold), TASK-141a/b (named weapons).
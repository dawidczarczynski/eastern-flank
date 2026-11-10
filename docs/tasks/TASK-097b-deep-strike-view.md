# TASK-097b: Deep strike v1 (2/2, view) – strike mode on the staff map: pick means, legal targets, confirm with the escalation warning, result marker

- **Status**: ready
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
- [ ] Scene-level smoke test: with a hand-made state, S → pick `cruise` → click an airfield → Confirm changes its bar and the stock line and shows a toast; an out-of-range and a closed target cannot be confirmed and show their reason; the mode works for player 1 (`--side=russia`).

## Look (Claude Design)

No strike mockup in `docs/design/operational_map`. Reuse the contact notice panel frame, `StaffMapCard`, the toast and counter components (grep CODEMAP); colours `ui.text`, danger `ui.alert #e07c5e`, legal-target glow in the viewer's side colour. State the deviation in the notes.

## Playtest (for the human)

1. **Operation** as NATO (`--debug`): press **S**: means with stock and range, "Strikes: 2/2"; pick `cruise`: Russian formations on Polish soil glow; Kaliningrad and Belarus targets are dimmed ("Closed soil …"); hover shows the reason.
2. F9 → raise to *Open war*: Kaliningrad's airfield and command post glow; click the airfield: card with "+1 sanctuary breach, +1 urban hex" and the new level; Confirm: toast, burst marker, the bar drops, the escalation chip rises.
3. Pick `strike_drone`, hover a far target: "Out of range of Strike drone".
4. Spend the stock / strikes: the means is greyed at 0, a third strike in a turn is refused; end turn: counter back at 2.
5. At level 3 pick a town target: the red threshold line appears; Confirm ends the operation (end notice).
6. `--side=russia`: the same flow against Polish targets.
7. Raise and strike: at level 2 an airfield is amber; click: the card starts with "Escalate to Open war"; Confirm raises the level and strikes.
8. Trail: after a strike an arc runs from the nearest own hex to the target (animated, then faint); with a defended target, interception marks with counts appear on the air-defence sites; the enemy's strikes after End turn leave their arcs too; the traces vanish at the start of your next turn.

## Player manual

Extend the **Deep strikes** chapter: how to open strike mode (S, Esc), pick means and salvo, what glowing / dimmed targets and the reasons mean, the confirm card and its warnings, the result toast, burst marker and strike trail (arc and interception marks), strikes per turn.

## Out of scope

Hit-chance forecast and effectiveness preview, the strike report panel (TASK-101); reconnaissance-dependent visibility (TASK-100); AI use (TASK-102).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

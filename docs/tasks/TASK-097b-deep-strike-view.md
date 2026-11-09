# TASK-097b: Deep strike v1 (2/2, view) – strike mode on the staff map: pick means, legal targets, confirm with the escalation warning, result marker

- **Status**: idea
- **Layers**: presentation (staff map); reads state and events only, executes `StrikeCommand` through `OperationalSimulation.execute`
- **Depends on**: TASK-097a
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
- [ ] **Result**: toast from `strike_resolved` ("Cruise ×2 on Chernyakhovsk airfield: 1 intercepted, 1 hit – integrity 100 → 65", threshold/breach lines from the escalation events), a **burst marker** on the hex (colour by hit / intercepted / missed) that fades at the start of the viewer's next turn; the installation marker bar, a struck formation's counter strength, the stock line and the strikes counter update from events.
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

## Player manual

Extend the **Deep strikes** chapter: how to open strike mode (S, Esc), pick means and salvo, what glowing / dimmed targets and the reasons mean, the confirm card and its warnings, the result toast and burst marker, strikes per turn.

## Out of scope

Hit-chance forecast and effectiveness preview, the strike report panel (TASK-101); reconnaissance-dependent visibility (TASK-100); AI use (TASK-102).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

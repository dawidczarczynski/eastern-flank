# TASK-094c: Contact (3/4) – Play battle: scene transition, commander's briefing, report to staff, return to the staff map

- **Status**: ready
- **Layers**: presentation (`Session` autoload, scene flow, briefing, end screen) + core (small: result → command)
- **Depends on**: TASK-094a, TASK-094b
- **Sections**: GDD "Player roles", "Battle hand-off and auto-resolve"; ADR 0015 §5 (scene flow); docs/tasks/TASK-086-two-layer-architecture.md
- **Model**: opus (scene transitions that must keep two simulations alive)
- **Topic**: Two-layer game

## Goal

On the contact notice the human presses **Play battle**, fights the battle as the commander on the cut map with the formations' companies, presses **Report to staff** and lands back on the staff map exactly as it was, the battle resolved (GDD "Player roles"). Consequences of the result are TASK-095.

## Acceptance criteria (testable)

- [ ] `Session` (autoload, presentation) owns the `OperationalSimulation` and the human's side across scenes: **Play battle** (`B`) → takes the first pending `BattleSetup` (built by TASK-094b), `Scenario.from_setup`, loads the battle scene; the staff map scene is freed but the operational state and view settings (camera, viewer, toggles) are kept and restored. Test (controller level): state `snapshot()` is identical before the transition and after returning.
- [ ] The played battle uses the setup exactly: company strengths, `Conditions` (command points …), objectives, seed (`GameState.rng`), factions. Test: `Scenario.from_setup(pending)` has the same unit ids / HP as the companies; the same setup + same commands twice → identical result.
- [ ] Commander wording: the briefing at the battle start shows **Mission** (task + the objectives in words) and **Intent** (the leader's order text) from `BattleSetup.Mission`; the battle HUD keeps a one-line mission reminder; the end screen is titled as a report with a **Report to staff** button (replaces "back to menu" in a campaign battle; scenario battles are unchanged). Strings `tr()` (en + pl).
- [ ] On the end screen, `BattleResult.from_battle(setup, state)` goes into `ResolveBattleCommand` (TASK-094a); the pending battle is removed and the staff map shows a **short result notice** (per formation: companies' strength before → after, the winner). TASK-120's auto-resolve reuses this notice, TASK-095 replaces it with the after-action report.
- [ ] Esc → quit to menu from a campaign battle abandons the session without a result (the pending battle stays in the saved operation once TASK-094d exists) **[ASSUMPTION]**; a played battle cannot be switched to auto-resolve.
- [ ] The notice's **Play battle** button is enabled; **Resolve as draw (debug)** stays under `--debug`.
- [ ] Headless smoke test of the controller: scripted contact → `Session.play_battle()` with a scripted tactical AI-vs-AI run (existing harness) → result → `ResolveBattleCommand` → `pending_battles` empty, End turn possible.
- [ ] docs/ARCHITECTURE.md "Two layers" (scene flow, `Session`).

## Playtest (for the human)

1. Cause a contact as in TASK-094a; on the notice press **Play battle** (or `B`): the 3D battle starts on the cut map; the briefing shows Mission and Intent; the HUD shows a mission line.
2. Fight (or let it run to the turn limit); the end screen reads as a report and offers **Report to staff**.
3. Press it: the staff map returns with the same camera and selection, the notice shows the result (before → after strengths, winner), the queue is empty and End turn works.
4. Check that the companies in the battle are the ones of the two formations (panel on the staff map vs the battle).

## Player manual

"Contact" chapter: Play battle, the briefing, what ends a battle, Report to staff, the short result; the commander and leader roles in one paragraph.

## Out of scope

- Applying losses, retreat, readiness (TASK-095); auto-resolve (TASK-120); saving (TASK-094d); the map cut (TASK-094b).

## Implementation notes

_Filled in by the agent when done._

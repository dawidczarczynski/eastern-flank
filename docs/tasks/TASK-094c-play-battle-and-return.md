# TASK-094c: Contact (3/4) – Play battle: scene transition, commander's briefing, report to staff, return to the staff map

- **Status**: done
- **Layers**: presentation (`Session` static class, scene flow, briefing, end screen) + core (small: result → command)
- **Depends on**: TASK-094a, TASK-094b
- **Sections**: GDD "Player roles", "Battle hand-off and auto-resolve"; ADR 0015 §5 (scene flow); docs/tasks/TASK-086-two-layer-architecture.md
- **Model**: opus (scene transitions that must keep two simulations alive)
- **Topic**: Two-layer game

## Goal

On the contact notice the human presses **Play battle**, fights the battle as the commander on the cut map with the formations' companies, presses **Report to staff** and lands back on the staff map exactly as it was, the battle resolved (GDD "Player roles"). Consequences of the result are TASK-095.

## Acceptance criteria (testable)

- [x] `Session` (static class, presentation; see Implementation notes) owns the `OperationalSimulation` and the human's side across scenes: **Play battle** (`B`) → takes the first pending `BattleSetup` (built by TASK-094b), `Scenario.from_setup`, loads the battle scene; the staff map scene is freed but the operational state and view settings (camera, viewer, toggles) are kept and restored. Test (controller level): state `snapshot()` is identical before the transition and after returning.
- [x] The played battle uses the setup exactly: company strengths, `Conditions` (command points …), objectives, seed (`GameState.rng`), factions. Test: `Scenario.from_setup(pending)` has the same unit ids / HP as the companies; the same setup + same commands twice → identical result.
- [x] Commander wording: the briefing at the battle start shows **Mission** (task + the objectives in words) and **Intent** (the leader's order text) from `BattleSetup.Mission`; the battle HUD keeps a one-line mission reminder; the end screen is titled as a report with a **Report to staff** button (replaces "back to menu" in a campaign battle; scenario battles are unchanged). Strings `tr()` (en + pl).
- [x] On the end screen, `BattleResult.from_battle(setup, state)` goes into `ResolveBattleCommand` (TASK-094a); the pending battle is removed and the staff map shows a **short result notice** (per formation: companies' strength before → after, the winner). TASK-120's auto-resolve reuses this notice, TASK-095 replaces it with the after-action report.
- [x] Esc → quit to menu from a campaign battle abandons the session without a result (the pending battle stays in the saved operation once TASK-094d exists) **[ASSUMPTION]**; a played battle cannot be switched to auto-resolve.
- [x] The notice's **Play battle** button is enabled; **Resolve as draw (debug)** stays under `--debug`.
- [x] Headless smoke test of the controller: scripted contact → `Session.play_battle()` with a scripted tactical AI-vs-AI run (existing harness) → result → `ResolveBattleCommand` → `pending_battles` empty, End turn possible.
- [x] docs/ARCHITECTURE.md "Two layers" (scene flow, `Session`).

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

- Core: `ContactBattle` (`src/core/operational/contact_battle.gd`) – `problem`, `prepare` (a copy of the first pending battle with its map cut on the formations' current hexes), `formation_ids` (shared with `ResolveBattleCommand`), `hexes`. `MatchRunner.run(sim, max_turns)` split out of `play` for battles started from a setup. The result → command step lives in `Session.finish_battle` (`ResolveBattleCommand(BattleResult.from_battle(...))`) because `src/core/operational` must not reference `GameState`.
- **Deviation:** `Session` (`src/presentation/session.gd`) is a class with static state, like `BattleOptions`, not an autoload node: it survives the scene change the same way, needs no project.godot autoload and works in headless tests / `--script` tools (an autoload named like a `class_name` cannot coexist). It is still the only code that changes scene between the two layers (`Session.change_scene`).
- Staff map: notice Play battle enabled (`StaffMapContactNotice.set_play_problem` for a disabled state), `StaffMap.play_battle` / `view_settings`, rebuild around `Session.take_simulation`, `StaffMapContacts.sync` (queue from the state), `StaffMapBattleResult` (short result notice). If the battle cannot be played (`not_fieldable`, `map_failed` …) a toast says why.
- Battle: `BattleController.human_player` (was the constant 0) and `campaign`; the AI moves first when it is its turn; `BattleBriefing` (Mission / Intent, Take command / Enter); `BattleHud.set_campaign` (mission line, "Commander's report" caption, Report to staff button / Enter); Esc in a campaign battle → `Session.abandon()` + menu. The main menu also abandons the session.
- Tests: `test_contact_battle.gd` (setup used exactly, determinism, resolve), `test_session.gd` (headless smoke: contact → play → AI-vs-AI → report → End turn), `test_staff_map_session.gd` (controller level: snapshot + view settings identical after return, result notice), `test_battle_briefing.gd`.
- Screenshot states: `SCREENSHOT_SHOTS=briefing,report:victory` (battle), `SCREENSHOT_STAFF_MAP=contact:ru_mr_1:pl_mech_1,result` (staff map).
- [ASSUMPTION] Esc from a campaign battle ends the operation (back to the menu) until TASK-094d saves it.

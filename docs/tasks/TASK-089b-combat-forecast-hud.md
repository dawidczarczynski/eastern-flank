# TASK-089b: Combat forecast – target tag, crosshair cursor and the unit ring (RMB on a unit)

- **Status**: done
- **Layers**: presentation (new radial ring control + detail card, forecast tag, cursor, `BattleController` input routing); pure models in `src/presentation/` with tests; numbers only from `AttackCommand.forecast()` / `HudModel.attack_forecast()`
- **Depends on**: **TASK-089a**. Design and decisions: `TASK-089a-company-combat-rolls.md` (sections 5 and 8); ring look: `docs/design/hud_v3/README.md` §04 (+ `hud-elementy.html`, `icons.svg`).
- **Model**: opus

## Goal

Before an attack the player sees what to expect – average damage with its 10–90 % range, the chance to destroy the target and the expected counter – where they are looking, not buried in the hover card.

## Design (human's decisions, 2026-10-30)

The first iteration (forecast box inside the hover card) was rejected in playtest: "you have to look for it in the card, it is not readable". Replaced by:

1. **Target tag + crosshair cursor.** While an own unit is selected and the cursor is over an enemy that is a valid target of it (`AttackCommand.valid_targets`), the mouse cursor becomes a crosshair (`CURSOR_CROSS` or a custom amber crosshair) and a **compact tag** next to the cursor replaces the full hover card: e.g. `ATTACK ~3 (1–5)` · `DESTROY <1 %` (omitted at 0) · `COUNTER ~1.3` / `NO COUNTER`. Anything else (own unit, enemy out of range, nothing selected) shows the normal hover card and the default cursor.
2. **LMB on a valid target attacks at once** – unchanged.
3. **RMB click (no drag) on an enemy unit opens the target ring** – the radial menu of the HUD v3 design (§04 geometry: six trapezoid segments, dashed inner hex, tick ring, key numbers, follows the unit's projected position every frame, clamped on screen), here with two active slots and four empty, dimmed ones (reserved for later actions such as fire support):
   - **1 ATTACK** – the detail card beside the ring (272 px, flips near the edge) shows the full forecast prominently: big expected damage, a 10–90 % range bar, destroy chance, expected counter with its range or NO COUNTER. Clicking it (or key 1) executes `AttackCommand` through `GameSimulation.execute()`. Disabled (design's disabled / hover-disabled colours) with the reason from `AttackCommand.validate()` mapped to text: no unit selected, out of range, already attacked, no command points, …
   - **2 INFO** – hovering shows the action's description; clicking it (or key 2) shows the unit's card (UnitPopup) next to the ring. There is no hover card on the map any more: the card is only reachable through INFO.
   - RMB on an **own** unit opens the same ring with INFO only (slot 1 empty until TASK-082's orders).
   - Esc, LMB elsewhere or RMB elsewhere closes it; opening it hides the tag. RMB on empty ground keeps today's behaviour (deselect).
   - Only on the human's turn and when input is allowed (no event playback).
4. The ring geometry (segment polygons, label centres, point → slot hit test) is a pure class reusable by TASK-082's orders ring.
5. A 0-damage strike plays as a hit with no HP loss; no MISS toast.

## Acceptance criteria

- [x] Pure, tested: ring geometry (hit test at each label centre returns its slot; gaps, r < 84, r > 160 → none); target ring model (slots, ATTACK enabled/disabled + reason text for each `validate()` reason, forecast lines for the detail card); tag text from `HudModel.attack_forecast()` (exact strings for Abrams → squad, Abrams → Uragan, Homar-K → Uragan at 6 hexes stay pinned in `tests/unit/test_hud_model.gd`).
- [x] Tag + crosshair only while a own unit is selected and the hovered enemy is a valid target; normal card and cursor otherwise.
- [x] RMB click on an enemy opens the ring, RMB drag still rotates the camera; ATTACK executes only through `GameSimulation.execute()`; Esc / click elsewhere closes; the ring follows the camera.
- [x] The forecast box is removed from the hover card.
- [x] Strings in en + pl; screenshot hooks for the tag and the open ring; `tools/check.sh` passes.

## Playtest (for the human)

1. Select the Abrams, hover a T-72B3 in range on plains: crosshair cursor, tag `ATTACK ~3.0 (1–5)` … `COUNTER ~1.3`; hover an enemy out of range: normal card, normal cursor.
2. RMB-click the T-72B3: the ring opens on it and follows when you pan/rotate; hover ATTACK: full forecast in the detail card; click it: the attack plays and the ring closes.
3. RMB-click an enemy out of range: ATTACK is red/disabled with "out of range"; hovering INFO shows only its description, clicking INFO (or 2) shows the unit's card; Esc closes.
3a. Hover units on the map: no unit card appears. RMB-click an own unit: the ring with INFO only; INFO shows its card.
4. RMB-drag still rotates the camera without opening the ring; RMB on empty ground still deselects.
5. Attack several times over a battle: results vary around the forecast; sometimes an infantry attack on a tank deals nothing.

## Player manual

docs/MANUAL.md: the attack tag + crosshair, the unit ring (RMB on a unit: ATTACK with the forecast for enemies, INFO card for every unit; no hover card), controls list – see the "Player manual" list in TASK-089a.

## Implementation notes

### Iteration 3 (playtest feedback, 2026-10-30, main session)

The human: the unit card should appear only after pressing INFO, not on hover, and the same action should exist for own units.

- **No hover card on the map**: `BattleController` no longer creates the hover `UnitPopup`; `_update_target_tag` only drives the tag + crosshair. The unit card shows only through the ring's INFO (`UnitPopup.suppressed` and `UnitPopupModel.placement` stay, unused by the battle).
- **INFO on click**: hovering INFO shows its action card (`ACTION [2] INFO`, "Show the unit's card…"); clicking it or key 2 toggles the unit's card beside the ring.
- **Ring for own units**: RMB on any living unit opens it; `TargetRingModel.build(state, viewer_player, attacker_id, target_id)` gives an own unit an empty slot 1 (no ATTACK, `attack` card `{}`) and INFO, summary tab `UNIT`. RMB on a unit no longer deselects (RMB on the ground and Esc still do). Key hint `RMB ON UNIT – UNIT MENU`.
- Screenshot state `ring_own:<selected>-<own unit>` (ring on an own unit, INFO triggered); `ring_info` now means INFO triggered. README shot re-rendered (key hint text).

### Iteration 2 (target tag, crosshair, target ring – 2026-10-30, presentation-engineer opus; review fixes in the main session)

- **Pure, tested**: `RadialRingGeometry` (`src/presentation/radial_ring_geometry.gd`: README §04 polygons, label centres, `slot_at` → -1 in gaps / r < 84 / r > 160, inner hex, ticks, key positions, `clamp_center`, `card_position` x+206 with flip), `TargetRingModel` (six slots: 1 ATTACK, 2 INFO, four empty; ATTACK reason texts for every `validate()` reason + NO UNIT SELECTED; ATTACK card = `attack_forecast` with DAMAGE as the big number, range bar on the target's HP scale; summary card), `HudModel.attack_tag` (`ATTACK ~4.0 (2–6)` · `DESTROY <1 %` · `COUNTER ~0.6` / `NO COUNTER`), `TargetTag.placement`. Tests: `test_radial_ring_geometry.gd`, `test_target_ring_model.gd`, `test_hud_model.gd` (iteration-1 exact strings kept).
- **Views**: `ui/radial_ring.gd` (drawn in `_draw`, redrawn only on change; normal / hover / disabled / hover-disabled / dimmed empty; forbidden cursor on disabled; only the disc takes input, so wheel and RMB-drag over it don't reach the camera), `ui/ring_detail_card.gd`, `ui/target_tag.gd`, `ui/crosshair_cursor.gd` (amber crosshair built in code). The design's centre caption "JEDNOSTKA" is left out (unreadable over the unit).
- **Input** (`TargetRingController`): RMB click (not drag) on a living enemy opens the ring (even with nothing selected → ATTACK disabled); any click outside closes it and does nothing else; RMB on another enemy reopens there; Esc, end turn, target death, event playback / AI turn close it. ATTACK: LMB or key 1 → `GameSimulation.execute(AttackCommand)`. INFO: hover shows the enemy's card, click / key 2 pins it. RMB on ground / own unit still deselects. The tag is hidden while a HUD control (end turn button) is under the cursor.
- The forecast box of iteration 1 is removed from `UnitPopup` (file back to its committed state). Key hints gain `RMB ON ENEMY – TARGET MENU` (README shot re-rendered for it).
- `battle_controller.gd` stays under the 1000-line limit: the `_on_mouse_motion` / `_text_input_has_focus` wrappers were inlined (the G-key focus check now covers only `LineEdit` – the battle scene has no `TextEdit`), `debug_focus_camera` reuses `debug_focus_point`.
- **Screenshots**: `SCREENSHOT_CAMERA=2,-40,13 SCREENSHOT_SHOTS=tag:2-6,ring:2-6,ring_attack:2-6,ring_info:2-6,ring_blocked:2-9 tools/screenshot.sh .screenshots/target.png`; the debug-only `BattleController.debug_place_next_to` moves the target next to the attacker in the state (screenshot tool only).
- **Deferred**: no automated test of the controller's input routing (only the pure parts); the ring's hover doesn't update while it follows a panning camera under a still mouse (cosmetic).

### Iteration 1 (forecast box in the hover card – rejected in playtest)

2026-10-30 (main session; review by `reviewer`, manual by `game-designer`).

- **HudModel** (`src/presentation/hud_model.gd`): `attack_forecast(state, attacker_id, defender_id)` returns the card lines as `{label, value}` (`DAMAGE`/`DESTROY`/`COUNTER`/`NO COUNTER`), and returns `[]` unless the defender is in `AttackCommand.valid_targets` of the attacker. That covers nothing selected, own unit, out of range, already attacked and the AI's turn. `destroy_chance_text` formats the destroy chance: `""` at 0, `<1 %`, `>99 %`, `100 %` when certain. Tested strings: Abrams → squad `DAMAGE 4.0 (2–6)`, `DESTROY <1 %`, `COUNTER 0.6 (0–2)`; Abrams → Uragan `5.4 (4–6)`, `63 %`, `0.2 (0–1)`; Homar-K → Uragan at 6 `5.0 (4–6)`, `33 %`, `NO COUNTER`. The spec's guess for that last case had no numbers; (5/6)^6 ≈ 33 %.
- **Hover card** (`UnitPopup`): an amber-ruled box right under STRENGTH, with the caption on the left and the mono value on the right. It is hidden when there are no lines. `BattleController._update_unit_popup` rebuilds the card when the (hovered unit, selected unit) pair changes. Event playback hides the card, so it is rebuilt with fresh numbers after every attack or move. The visibility condition was compressed to keep the file at the 1000-line lint limit.
- **0-damage strike**: no MISS toast. Playback reads only `target_hp`, and the core path is covered by `test_combat_rolls.gd` `test_damage_can_be_zero`.
- **i18n**: DAMAGE / DESTROY / COUNTER / NO COUNTER (pl: OBRAŻENIA, ZNISZCZENIE, KONTRATAK, BEZ KONTRATAKU).
- Verified with a screenshot (temporary debug hook, not committed): Abrams selected, hovering a T-72B3 next to it shows `DAMAGE 3.0 (1–5)`, `DESTROY <1 %`, `COUNTER 1.3 (0–3)`. The README shot doesn't hover, so it is unchanged.
- MANUAL: §7 (attacking, 0 damage, worked examples), §10 (unit card: attack forecast), §13 (forecast removed from "not in the game yet").

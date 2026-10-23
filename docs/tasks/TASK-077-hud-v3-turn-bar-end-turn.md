# TASK-077: HUD v3 – turn bar, end-turn module, key hints

- **Status**: ready
- **Layers**: presentation (`BattleHud` rewritten on TASK-076 primitives; `HudModel` extended), tests, docs (MANUAL controls, ARCHITECTURE if events/model change). Role: **presentation-engineer**.
- **Depends on**: **TASK-076**
- **Model**: sonnet

## Goal

Restyle the top turn bar, the bottom-right end-turn block and the key hints to the handoff design (README sections 01 and 05; see [hud-elementy.html](../design/hud_v3/hud-elementy.html)). Behaviour stays: `end_turn_pressed`, `refresh`, `on_turn_started`, `set_end_enabled`.

## Design

- **Turn bar** (top centre, hangs from the top edge): trapezoid frame (`26 px` slants), inner padding 12/44, two faction blocks 236 px (hex badge 40×36 with faction short name in the faction ink, name 15 px Chakra, meta `AKTYWNA|OCZEKUJE · N JEDN.` – via `tr()`, new keys in the CSV en + pl), 4 px wide-hatch bar under the active block in its colour, inactive block opacity .6 with the existing .3 s tween; centre column `TURA` / number 32 px mono / `▸ FACTION` in the active colour, 1 px dividers. 300×10 tick ruler under the bar (61 ticks, heights 8/5/3).
- **Ready counter**: `GOTOWE` + `ready / total`, one 14×8 block per unit (filled = active faction colour, empty = 1 px inset outline). Needs per-unit ready flags from `HudModel.top_bar` (`units` / `ready` counts already exist; the block row only needs the two numbers, for the *active* side).
- **End-turn button**: min height 52, fill = active faction colour, chamfer 14 bottom-right, Chakra 15 px 700, ls .14em, left 10×26 dark hatch, `↵` hint; hover ×1.12, pressed ×.9, disabled keeps .5 alpha. Focus mode stays `FOCUS_NONE`.
- **Key hints** above the button (bottom 92): panel + 1 px line, chamfer 8 top-left, keycaps (1 px line border, amber mono 10). Replace the single long hint string with keycap/label pairs for the keys the game really has (LMB, RMB, wheel, WASD/QE, Ctrl+wheel/RF, Home, G, Enter, F5) – do not show design-only keys (1–6 orders) until TASK-082.
- The old centred bottom hint box and the old top bar are removed; turn banner is TASK-080.

## Acceptance criteria (testable)

- [ ] `HudModel` tests still pass; new model fields (if any) tested, status keys untranslated.
- [ ] A scene test builds `BattleHud` headless, calls `refresh` with a two-faction state and checks: both blocks show the right names/counts, active hatch visible only on the active side, ready blocks count = ready units, button colour = active faction colour, `set_end_enabled(false)` dims it.
- [ ] Locale en and pl both show no raw keys (localisation test passes).
- [ ] The HUD still ignores the mouse except the end-turn button.
- [ ] `tools/screenshot.sh` renders; README gameplay screenshot re-rendered (`tools/readme_screenshot.sh`) and checked.
- [ ] `tools/check.sh` passes.

## Playtest (for the human)

1. Turn bar: active side lit with the hatch bar, other side dimmed; switches with a .3 s fade when the turn passes.
2. Ready counter drops as units finish; End turn button takes the active colour; Enter and click both end the turn.
3. Compare side by side with the HTML at 1920×1080 (sizes, hatch, chamfers).

## Player manual

Controls table: the key hints (unchanged keys, new look).

## Out of scope

Turn banner / toast / targeting bar (TASK-080), unit and terrain cards (078, 079).

## Implementation notes

_Filled in by the agent when done._

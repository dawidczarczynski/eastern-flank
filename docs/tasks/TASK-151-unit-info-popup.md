# TASK-151: Unit info popup – tag, brief card, on-demand full panel

- **Status**: done
- **Layers**: presentation
- **Depends on**: –
- **Sections**: docs/design/operational_map/README.md "Unit info" (spec), unit_info_popup.html (variant A frames A1–A8)
- **Model**: sonnet

## Goal

Selecting a formation no longer opens a docked panel that hides the map (e.g. Kaliningrad as a march target). **Reworked 2026-11-13** (human decision, overrides the popup design): the hover tag, brief card and chip are dropped; a short unit info is shown in the bottom-bar left slot (the hex strip's place, same look), the full panel opens only on request.

## Acceptance criteria (testable)

- [x] The bottom-bar left slot shows a formation strip (`StaffMapUnitStrip`): tab "FORMATION · OWN/HOSTILE" in the side colour, name (at most 2 lines), columns STRENGTH (gauge + "40 / 40"), POSTURE, ORDER; hostile shows only "EST." / "?" (no gauge).
- [x] Priority of the slot: counter under the cursor > hex under the cursor (as before) > selected own formation.
- [x] Long names are abbreviated only until they fit the title (`NAME_MAX_CHARS`), with a language-aware table (English and Polish, by the game locale); diacritics are upper-cased correctly.
- [x] Keys 1/2/3 arm a posture for the next click (Esc or the same key cancels); the armed posture shows in the POSTURE column and in the route preview.
- [x] RMB on an own counter opens the ring with slot [5] INFO (also on the hex order ring); RMB on a hostile counter opens the order ring on its hex when an own formation is selected (ATTACK ..., [5] INFO = the hostile's panel), else the full panel directly; key I opens the panel; RMB on a bare hex stays the order ring.
- [x] Full panel gets ✕; follows the selection while open; closed by ✕, Esc, I or a click on the bare map (a click on another counter keeps it open).
- [x] The panel no longer opens on selection; the clear zone reserves its dock only while it is open.

## Playtest (for the human)

1. Move the cursor over a counter (own and hostile): the bottom-left slot shows its strip (tab "FORMACJA · WŁASNA" / "· WRÓG", name, STRENGTH, POSTURE, ORDER); hostile shows SZAC. and ?. Move off the counter onto bare hex: the slot returns to the hex strip.
2. Select an own formation and put the cursor on the top bar or off the map: the slot keeps showing the selection. Press 2: POSTURE reads ATTACK in amber; Esc restores it.
3. Switch the language to Polish and English; select a battalion with a long name (e.g. "1. Batalion Piechoty Zmotoryzowanej"): the name stays within two lines, abbreviated only as needed.
4. RMB on own counter → ring → INFO → panel; click bare map → panel closes; select another counter with it open → it switches.

## Player manual

Controls: unit strip, 1/2/3, RMB on a counter, INFO slot, I.

## Out of scope

- Fog rules (TASK-100); only the display of what is already known.

## Implementation notes

Implemented by `StaffMapUnitStrip` (widget in the slot next to `StaffMapCard`, same columns look), `StaffMapUnitCardModel` (pure; hostile shows only "EST." / "?"; `abbreviate(name, max_chars, locale)` with `ABBREVIATIONS_EN` / `ABBREVIATIONS_PL`, `upper()` for diacritics) and `StaffMap._sync_unit_strip` / `unit_strip_target` (priority counter > hex > selection; per frame, the hex strip hides while the unit strip shows). Ring: `SLOT_INFO` and an `on_counter` mode in `StaffMapOrderRingModel`. `StaffMapFormationPanel` is shown only via `open_info` (RMB on a counter → ring INFO, hostile RMB, key I) and follows the selection; it closes by ✕, Esc, I or a click on the bare map. Keys 1/2/3 on the staff map arm a posture; `_route.set_posture` shows it in the preview and the strip shows it amber.

Dropped on 2026-11-13: hover tag, brief card, chip, `StaffMapUnitCard`, `StaffMapUnitCards` (delay, fades, dimming, Alt peek), `StaffMapCardAnchor`, the U hide key with its GameSettings entry and i18n keys. Screenshot token `unit[:<formation id>]` shows the strip (replaces `cards`). RMB at the centre of an enemy counter opens the panel / order ring, so attack by left click or RMB on the hex outside the counter. Mockup `unit_info_popup.html` is superseded for tag / card / chip.

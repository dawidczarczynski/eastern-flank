# TASK-078: HUD v3 – unit card (hover popup)

- **Status**: done
- **Layers**: presentation (`UnitPopup` rebuilt, `UnitPopupModel` extended), tests, docs. Role: **presentation-engineer**.
- **Depends on**: **TASK-076** (soft: TASK-082 for the active-effect tags; the rank chip needs ranks – see Open questions)
- **Model**: sonnet

## Goal

The hover card gets the handoff look (README section 02): chamfered frame, faction-coloured type tab, crosshair portrait, segmented HP, bar stats, bracket tags, optional note and status footer. Data comes from the existing `UnitPopupModel` (portrait via `PortraitRenderer`).

## Design

- 320 px wide, chamfer 16 (top-right + bottom-left), `pointer-events` none. Placement: cursor x + 24, flipped to x − 344 on overflow, y clamped to [110, H − 620] – reuse/adjust `UnitPopupModel.placement()`.
- Rows exactly as README: tab row (type tab in faction colour + faction name right), name 21 px Chakra uppercase + designation (mono 11, muted – the unit's real designation, e.g. `M1A2 SEPv3`; use catalog/unit data, no new data if absent → hide), portrait 296×160 with scanlines, centred crosshair (46 px circle + 68 px cross) and four 9 px corner brackets, **rank chip hidden** until ranks exist, HP `SIŁA` + `8/10` with one skewed segment per HP (8 px, gap 2, colours from `UiPalette.hp_color`), 2-column stats with 4 px bar and 10 px tick overlay, bracket tags, note (3 px amber left bar, tinted bg), status footer (8 px hex dot + status).
- Active effects (Okopana, Zamaskowana, …) appended to tags **only if** the unit has such state – until TASK-081 exists there are none; the model takes a generic `effects: Array[String]`.
- Hide while the radial menu (TASK-082) is open: expose `UnitPopup.suppressed`.

## Acceptance criteria (testable)

- [x] `UnitPopupModel` tests: designation, tags, effects array (empty by default), segments count = max HP, placement flip/clamp numbers.
- [x] Scene test: card builds for each unit class headless, size stays ≤ 620 px tall with 8 tags and a note.
- [x] No raw translation keys in en/pl; `tools/check.sh` passes; `tools/screenshot.sh` + README screenshot re-rendered and checked.

## Playtest (for the human)

1. Hover own and enemy units: tab/frame colour follows the unit's faction; HP segments match HP; card flips at the right screen edge and never leaves the screen.
2. Compare with the HTML card (portrait overlay, segment skew, bars).

## Player manual

Describe the card fields (HP, stats, status).

## Open questions

- Rank pips need an experience system (GDD "Experience ranks", undecided) → chip omitted now.

## Out of scope

Rank system, order effects (TASK-081).

## Implementation notes

- `UnitPopup` rebuilt on `FramedPanel` (tab row, name + designation, crosshair portrait, HP segments, bar stats, bracket tags, note, status footer). `UnitPopupModel.build` gained `designation` (`short_name`, hidden for infantry / when equal to the name), `tags` (mobility + `effects`), `effects` (empty until TASK-081) and `note` (always empty for now).
- Placement clamps y to [110, H − card height − 16] instead of the fixed H − 620 (better on small viewports).
- Rank chip omitted (no ranks). `UnitPopup.suppressed` exists but has no caller until TASK-082.
- New i18n keys `Foot`, `Wheeled`, `Tracked`; pl `STRENGTH` is now "SIŁA".
- Only the infantry card was rendered by the agent/me (`SCREENSHOT_HOVER_UNIT=1 tools/screenshot.sh`); other classes, enemy colours and the pixel comparison with the HTML card are for the human.

# TASK-175b: Objectives map layer (key M)

- **Status**: blocked
- **Layers**: presentation
- **Depends on**: TASK-175a
- **Topic**: Two-layer game
- **Sections**: GDD "Sides" (Victory / Endings, Objective tiers), docs/design/operational_map/objectives_window.html, docs/design/operational_map/README.md (last paragraph "Objectives window and layer")
- **Model**: sonnet

## Goal

The objectives are marked on the staff map (toggle M): rings with holder and points, names from zoom Z1, the Gap chain as a ribbon; a marker click opens the window on that row.

Design (human, 2026-11-17): variant A of `objectives_window.html`; split from TASK-175 on 2026-11-17.

## Acceptance criteria (testable)

Part 4 - layer (`StaffMapObjectivesLayer`, model on `StaffMapAirDefenceLayer` / `StaffMapControlLayer`)
- [ ] Per objective: dashed amber ring r 19, holder glyph, points plate 48x16; names shown from zoom Z1 up, the selected objective's name always.
- [ ] Gap ribbon along the chain: Russia-held part solid `side.enemy` (for a Russian viewer `side.own`), the rest dotted amber; tag "THE GAP | n/13 +10".
- [ ] Redraw only on `objective_changed` or a zoom-level change (test counts redraws: 0 on unrelated events, 1 per matching event).
- [ ] Key M toggles the layer; row "Objectives · M" in `StaffMapOptionsWindow`, default on; while the objectives window is open the layer is forced visible and the previous state restored on close.
- [ ] Click on a marker plate opens the objectives window with that row selected (and centres as in part 3).

## Design check

Compare a screenshot / render with `docs/design/operational_map/objectives_window.html` (variant A) and state every deviation and why in Implementation notes.

## Playtest (for the human)

1. Press M: markers, names (zoomed in), Gap ribbon and tag appear / disappear; the Map options row follows; open the window with the layer off: layer shows, closing restores off.
2. Click a marker plate: window opens on that row.

## Player manual

docs/MANUAL.md 12b: layer M and its Map options row.

## Out of scope

- Score forecast / variant B score strip.
- Edge arrows for off-screen objectives.
- New victory rules beyond the 5-round count; scoring changes (Gap 10 points at the end stays).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

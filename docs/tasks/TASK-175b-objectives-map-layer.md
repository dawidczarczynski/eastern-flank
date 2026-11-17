# TASK-175b: Objectives map layer (key M)

- **Status**: done
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

- New `StaffMapObjectivesLayer` (screen-space Control in the counter layer, over the air-defence zones, ignores the mouse). Rows come from `StaffMapObjectivesModel.rows`; it is recomputed only by `refresh` (on `objective_changed` and at build), a zoom-level change or a selection change (`redraw_count`, tested: 0 on unrelated events, 1 per match). Camera moves only re-project the cached rows (`layout`, not counted).
- Wiring in `StaffMap`: key M / "Objectives · M" row in Map options (default on), forced visible while the objectives window is open (via its `visibility_changed`, so every close path restores the toggle), selected row passed from `selection_changed`, click on a plate / ring / Gap tag (`_click_objective_marker`, after the counter pick) opens the window and `activate_row` centres it. Tests: `test_staff_map_objectives_layer.gd`; option-count tests bumped 7 → 8. MANUAL 12b and the Polish "THE GAP" string added.
- Colours follow the window: holder glyph and ribbon by status for the viewer (`side.own` / `side.enemy`), as the task text says; the counters themselves colour by side index, so with Russia as viewer the layer's "own" blue differs from Russia's red counters - to decide with the human.
- Deviations from variant A: the Gap ribbon end caps and the tag are drawn in the layer's code with the mono font; the name sits 13 px under the plate; no 10 % hex fill under the marker (the selected-hex outline is the existing journal ring). Only one zoomed-in screenshot was seen (ring, glyph, plate, name at an airfield); the Gap ribbon was not seen by the agent.

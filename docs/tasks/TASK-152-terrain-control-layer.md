# TASK-152: Staff map – terrain control layer

- **Status**: done
- **Layers**: presentation (+ docs)
- **Depends on**: –
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

The player sees at a glance which ground has been taken: hexes held by a side other than their country's original side are marked on the staff map, both enemy ground we took and our ground the enemy took.

## Acceptance criteria (testable)

- [ ] Pure helper (view-model, no nodes) `occupied(state) -> Dictionary` (hex → holder): every hex where `HexControl.holder` is ≥ 0 and differs from `state.hex_initial` of that hex's country start side (a hex with a start formation counts as its formation's side, as `HexControl.setup` does). Tests on a hand-made state: untouched start = empty; a hex taken by the enemy appears with the enemy side; retaken by the original side disappears; deterministic.
- [ ] Contour edges between occupied hexes of one holder and everything else, chained into polylines (reuse the `FrontLine.edges` chaining / `smooth` where possible). Test: one hex → one closed loop of 6 edges; two adjacent hexes → one loop of 10.
- [ ] Rebuilt only when the occupation set or viewer changes (signature compare), never per frame.
- [ ] The simulation is untouched (rule 3; `OperationalState.snapshot()` identical with and without the layer).
- [ ] The old front-line zone tint (mesh, `T` toggle, `TINT_ALPHA`) is removed; the front line ribbon and teeth stay. Tests of the tint are replaced.
- [ ] Toggle key **K** and a seventh row "Terrain control · K" in Map options (default on); hex card CONTROL row filled in words.

## Look (Claude Design)

Accepted: [terrain_control.html](../design/operational_map/terrain_control.html) variant A, spec in the operational_map README ("Terrain control"). Per hex holder colour 13 % + 45° hatch 6 px / 2 px / 55 %; contour 2 px solid with 4 px `map.void` casing 70 %, smoothed, round caps; Z0 without hatch; layer below counters; look as `StaffMapAirDefenceLayer` hatch. Compare your screenshot with the mockup and state deviations.

## Playtest (for the human)

1. Start an operation: no hatched area (nothing occupied yet).
2. Move a formation into an enemy-country hex and end the turn: the hex shows a hatch in your colour with a solid contour; the hex card says "captured".
3. Let the enemy take one of your hexes: red hatch. Press **K**: the layer toggles; the Map options row follows.
4. Zoom Z0 → Z2: contour stays 2 px, hatch appears from Z1.

## Player manual

Section in the "Operational map" chapter: what the hatch means, key K.

## Out of scope

- Hex control as a rule (supply, TASK-096); a count chip or region labels (variant B, rejected).

## Implementation notes

- `TerrainControl` (src/presentation/operational/terrain_control.gd): pure view model – `occupied`, `signature` (hash of `hex_holders`), `contours` (closed loops per holder, own chaining as `FrontLine` keeps its helpers private), `card_text` / `words`.
- `StaffMapControlLayer` (+ `assets/shaders/staff_map_control.gdshader`): 13 % fill + 45° hatch (6 px / 2 px / 55 %, screen-space), 2 px contour with 4 px `map.void` 70 % casing, smoothed (exact at Z2 grid), hatch off at Z0. Rebuilt only when the holder signature, viewer or visibility changes; refreshed from `_refresh_orders` (hidden while counters slide).
- Front-line zone tint, `T` toggle and `TINT_ALPHA` removed. Key **K** was already the country card: the country card moved to **T** (freed by the tint). Map options got the seventh row; `view_settings` key `terrain_control`.
- Hex card: the Stance column becomes "Control" with one word (Occupied / Captured) on an occupied hex; the full phrase ("NATO – captured from Russia") is `TerrainControl.card_text` (the strip has no room for it).
- Screenshot token `occupy:<player>:<col>:<row>[:<radius>]` in tools/screenshot.gd. Tests: tests/unit/test_terrain_control.gd; options / K tests updated; tint test removed.
- Deviations: the holder colour is drawn over the country tint instead of replacing it; the hatch steps in at Z1 instead of fading; no round caps (loops are closed).
- Playtest fixes (2026-11-14): (1) rule change by the human – `HexControl` now takes every hex of a move's route, not only the end hex (`EndOperationalTurnCommand._execute_order`, test `test_a_move_takes_every_hex_it_walks_through`, GDD "Sides" updated); (2) Z0 was invisible: fill 34 %, contour 3.5 px + 6 px casing at Z0 (README updated).

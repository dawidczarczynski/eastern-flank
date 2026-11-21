# TASK-203: Hex grid off by default under real scale – what is still missing next to key G

- **Status**: idea
- **Layers**: presentation (`MapView` grid layer, HUD toggle, settings)
- **Depends on**: –
- **Sections**: ARCHITECTURE "Chunked lazy world" (grid layer); docs/design/ mockups for any HUD element
- **Model**: sonnet
- **Tags**: battle-look

## Goal

The hex grid can already be hidden (key **G**, modes `auto` / `off`, TASK-049; the bottom bar has the button; MANUAL.md describes it). What is missing for the reference look: under the `true` preset the landscape is shown **without** the grid by default, and with it hidden the selection, reach and target hints still read clearly.

## Acceptance criteria (testable)

- [ ] Under `true` the grid mode starts `off` (the setting is per preset: `balanced` keeps `auto`); G and the bottom-bar button still switch it, and the choice is kept for the session.
- [ ] With the grid off the hints that need it stay: the hovered tile outline, reachable tiles when a unit is selected, attack targets and objective tiles are drawn as soft ground decals (no full-grid lines); verified by a screenshot of a selected unit with the grid off.
- [ ] No game rule or event changes; toggling does not change `GameState` (test); the grid layer is freed when off and rebuilt on toggling within one second.
- [ ] If a HUD element changes, it follows the existing HUD parts (`/design-ui` first when there is no mockup).
- [ ] Screenshots Read: the same view with the grid off and on, with a unit selected.

## Playtest (for the human)

1. Start a battle under the `true` preset: no grid on the landscape; select a unit – its reach and targets are still clearly marked; press G to bring the grid back.

## Player manual

MANUAL.md §10 / controls table: the default under real scale and what stays visible without the grid (by `game-designer`).

## Out of scope

- Removing the hexes from the simulation (they stay the mechanics, GDD "Visual direction").

## Implementation notes

_Filled in by the agent when done._

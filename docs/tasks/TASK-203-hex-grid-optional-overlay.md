# TASK-203: Hex grid as an optional overlay (appearance without the grid)

- **Status**: idea
- **Layers**: presentation (`MapView` grid layer, HUD toggle, settings)
- **Depends on**: –
- **Sections**: ARCHITECTURE "Chunked lazy world" (grid layer); docs/design/ mockups for any HUD element
- **Model**: sonnet
- **Tags**: battle-look

## Goal

The landscape can be seen as the reference shows it – with no hex grid on it – while the hexes stay the mechanics: the grid becomes an overlay the player toggles (and which shows automatically while targeting or moving).

## Acceptance criteria (testable)

- [ ] A setting / key (default decided with the human: on in the tactical battle, off in screenshots and `true` showcase) toggles the grid lines and tile tints (`MapView` grid layer); the state is kept for the session; `DevTunables.grid_on` / the arena keep working.
- [ ] While off, the interaction hints that need the grid stay: the hovered tile outline, selectable / reachable tiles when a unit is selected, attack targets, objective tiles – drawn as soft decals instead of the full grid.
- [ ] No game rule or event changes; the grid layer is freed when off (no cost) and rebuilt on toggling within one second.
- [ ] If a HUD element is added, it follows the existing HUD parts (`/design-ui` first if there is no mockup – the human picks a variant).
- [ ] Tests: toggling does not change `GameState`; the layer count with the grid off; hover hints still produced.
- [ ] Screenshots Read: the same view with the grid off and on.

## Playtest (for the human)

1. Toggle the grid in a battle: with it off the landscape shows no lines, units can still be selected, moved and targeted with clear hints.

## Player manual

MANUAL.md: how to toggle the grid and what stays visible without it (by `game-designer`).

## Out of scope

- Removing the hexes from the simulation (they stay the mechanics, GDD "Visual direction").

## Implementation notes

_Filled in by the agent when done._

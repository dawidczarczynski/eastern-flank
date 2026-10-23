# TASK-070: Varied vegetation on open ground – grass patches, tall grass, meadow flowers, scrub clumps

- **Status**: idea – needs a design pass (what an open Central-European field looks like) before `ready`.
- **Layers**: presentation (`grass_planner.gd`, `grass_field.gd`, grass shader, `scatter_planner.gd`)
- **Depends on**: **TASK-057** (grass cards, wind), **TASK-061** (scrub species `shrub` / `undergrowth` in `TreeField`), soft **TASK-071** (species and palette)
- **Model**: sonnet

## Goal

Plains stop being a uniform lawn: patches of tall and short grass, dry stalks, meadow flowers, nettle/bramble clumps and occasional scrub give the open ground a natural, uneven look (requested 2026-10-23 while playtesting TASK-061).

## Design (draft)

- Low-frequency noise (world space, deterministic) decides per area: short grass / tall grass / dry grass / bare patch; `GrassPlanner` varies card height and colour by it.
- Tall-grass clumps (grass card ×2.2 height) next to forests and field edges, as originally planned in TASK-061 ("open side of the edge").
- A few flower and weed clumps as sparse coloured cards (white/yellow/purple, Central-European meadow species), same wind shader.
- Occasional scrub clumps (reuse `shrub`/`undergrowth` through `TreeField`), more on tile borders than in the centre; a unit tile centre stays clear.
- Budgets: counted in the large-map budget of TASK-072.

## Acceptance criteria (testable)

- [ ] (to be written when `ready`.)

## Playtest (for the human)

1. Plains show visible patches of different grass height and colour; no obvious repetition at default zoom.
2. Units standing in tall grass stay readable.

## Player manual

None (presentation only).

## Out of scope

- Fields, hedgerows and roads (TASK-035); rules for concealment in tall grass.

## Implementation notes

_Filled in by the agent when done._

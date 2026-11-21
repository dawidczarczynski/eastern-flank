# TASK-199: Solitary trees, hedgerows, tree lines and orchards in the open country

- **Status**: idea
- **Layers**: presentation (`ScatterPlanner` meadow features, `TreeField`)
- **Depends on**: TASK-135
- **Sections**: ARCHITECTURE "Real-scale vegetation"; look reference (TASK-190)
- **Model**: sonnet

## Goal

The open country reads like the reference: single trees in fields, tree lines along field edges, roads and streams, hedgerows between parcels and small copses – at real size, from OSM where it knows them (`natural=tree`, `natural=tree_row`, `barrier=hedge`, `landuse=orchard`) and by rule where it does not.

## Acceptance criteria (testable)

- [ ] The importer (or the existing layers) provides the point / line features above where OSM has them; missing data is filled by rule: tree lines along roads and parcel balks on fields with a hashed probability, copses on hills and wet ground, orchards on `landuse=orchard` and at farm plots.
- [ ] Planners are pure and deterministic (`ScatterPlanner` streams, no `GameState.rng`); trees at real size (`VisualScale.tree_size`) with the species shares of the region; hedges as a dense line of shrub instances (`shrub` / `undergrowth` species) of real height (1.5–4 m) with gaps.
- [ ] Features keep off roads, buildings (TASK-195 mask when present), water and the forest fill; they stand on the near surface like the forest trees.
- [ ] Budget: <= 20 % more instances in open hexes than today, chunked on the existing tree layer, no new draws; frame time unchanged within 0.5 ms.
- [ ] Tests: counts per hex in range, lines follow their polylines, determinism, nothing inside a forest tile or footprint.
- [ ] Screenshots Read at 1.2 / 5 / 24: field edges and roads are lined with trees, parcels are separated by hedges.

## Playtest (for the human)

1. `true` preset: open country shows solitary trees, tree lines and hedgerows like the reference; forests are unchanged.

## Player manual

None.

## Out of scope

- Settlement plots (TASK-198); forest interior (TASK-135).

## Implementation notes

_Filled in by the agent when done._

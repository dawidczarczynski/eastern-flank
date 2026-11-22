# TASK-200: Field parcels as distinct crops – colours, rows, edges

- **Status**: idea
- **Layers**: presentation (`FieldParcels`, `ParcelMap`, terrain ground shader)
- **Depends on**: TASK-190, TASK-108g (parcels from the land-cover raster; `FieldParcels` is the follow-up TASK-108f's)
- **Sections**: ARCHITECTURE "Terrain"; TASK-192b (satellite colour); look reference (TASK-190)
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Farmland reads as a patchwork of crops like the reference: each parcel with its own colour (wheat gold, rape yellow, green cereal, stubble, ploughed brown, fallow), visible rows from close up and clear edges – not a uniform muted tone.

## Acceptance criteria (testable)

- [ ] Crop kinds and their colours are data (`FIELDS_DEFAULT` / a resource); each parcel gets a crop by rule (region mix, neighbours differ, hash of the parcel id) and a harvest-state tone; `balanced` keeps its look (test).
- [ ] Under `true` the parcel colour is stronger and mottled (large-scale noise), with row structure (direction per parcel, spacing in real metres 0.3–0.75 m by crop) fading in below ~150 m, and a darker headland strip along the edge; meadows keep the grass look.
- [ ] Edges: balks / tracks between parcels (the existing BALK kind) are lighter strips; field roads cross the patchwork on `highway=track` data.
- [ ] If TASK-192b (satellite colour) landed, the far colour follows it and only the near rows and crop tint come from this task; otherwise the colours come from the rule.
- [ ] Frame time unchanged within 0.3 ms (one more texture sample at most).
- [ ] Tests: crop assignment deterministic and neighbours differ; row direction constant per parcel; no row pattern beyond its fade distance.
- [ ] Screenshots Read at 1.2 / 5 / 24 against the reference.

## Playtest (for the human)

1. Fly over farmland: parcels in different crops, rows visible when low, no moiré from afar.

## Player manual

None.

## Out of scope

- Buildings and settlements; animated crops (wind in grain) – a possible follow-up.

## Implementation notes

_Filled in by the agent when done._

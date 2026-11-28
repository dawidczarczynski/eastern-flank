# TASK-223g: Water network (7/7): riparian belt – willows, alders, scrub and reeds along the water, GPU-placed

- **Status**: blocked
- **Layers**: presentation (GPU vegetation layer, masks)
- **Depends on**: TASK-223e
- **Sections**: ADR 0034 decision 4; ADR 0033; docs/GPU_SCATTER_PATTERNS.md
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Rivers are lined by a dark belt of trees and scrub like real lowland rivers, so from the gameplay camera the river course reads even where the water itself is narrow.

## Acceptance criteria (testable)

- [ ] A riparian habitat in `VegetationMasks` from `WaterNetwork`: width by river class (stream 5–10 m, river 15–40 m, lake shore 10–25 m) and land cover (none through built-up land, narrower along fields); fields, meadows and buildings stop at its outer edge.
- [ ] Species mix in the belt (willow, alder, hazel scrub, reeds on flat wet banks) as GPU-placed layers on ADR 0033's framework; no CPU per-chunk plan.
- [ ] GDScript reference of the rules with tests (habitat width, species shares, nothing on the water or the bridges).
- [ ] 60 FPS on HIGH kept; screenshots at default and close camera Read and described in the notes.

## Playtest (for the human)

1. Battle on Suwałki: rivers lined with willows and alders, reeds on flat shores; fields end before the belt.

## Player manual

None.

## Out of scope

- Forest stands crossing rivers (unchanged).

## Implementation notes

_Filled in by the agent when done._

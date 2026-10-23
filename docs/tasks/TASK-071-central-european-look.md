# TASK-071: Central-Eastern European look – species, palette, terrain character

- **Status**: idea – needs a study first (screenshots of options for the human to pick, like TASK-059).
- **Layers**: presentation (`tree_species.gd`, `tree_meshes.gd`, `tree_field.gd` colours, terrain textures/tints, `color_grade.gd`, grass colours), docs
- **Depends on**: soft **TASK-061**, **TASK-070**
- **Model**: sonnet (opus for the species/mesh study if needed)

## Goal

The battlefield reads as Poland / Belarus / western Russia in late summer or early autumn instead of a generic or tropical landscape (reported 2026-10-23: "the overall vibe is tropical").

## Design (draft, to be confirmed by the study)

- **Likely causes of the tropical feel** (check each with screenshots): too saturated, uniformly bright greens; round broad-leaf crowns that look like tropical canopy; sparse trunks on lawn-like grass; the HDRI/grade too warm and clear.
- **Species**: Scots pine (dominant, straight trunk, small flat crown), Norway spruce, silver birch, oak, alder, hornbeam/aspen; fewer broad, dense crowns. Pine-heavy mixed forest, spruce stands in wetter spots.
- **Palette**: muted, slightly yellowed greens, more dry-grass ochre and brown, some autumn tint in deciduous crowns, darker conifers; field/stubble colours instead of lawn green.
- **Ground**: sandy light soil, ferns and blueberry/heather undergrowth in pine forest, bracken, reeds at water, mist/haze option; grey-brown overcast grade as a variant (HDRI choice from TASK-054).
- **Study**: 3 rendered variants of the same view (A current, B muted summer, C early autumn) to decide the palette before the full change.

## Acceptance criteria (testable)

- [ ] (to be written when `ready`, after the study.)

## Playtest (for the human)

1. Compare the study variants and pick one.
2. After the change: does the map read as a Central-Eastern European landscape?

## Player manual

None (presentation only).

## Out of scope

- Per-scenario seasons or weather (could follow).

## Implementation notes

_Filled in by the agent when done._

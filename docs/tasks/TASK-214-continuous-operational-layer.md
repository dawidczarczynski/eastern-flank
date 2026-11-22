# TASK-214: Operational layer without hexes – design decision (one world for both scales)

- **Status**: idea
- **Layers**: core, ai, presentation (design first)
- **Depends on**: TASK-213
- **Sections**: ADR 0029 (decision 8), ADR 0018; GDD "Operational map", "Operational map view"
- **Model**: opus
- **Tags**: continuous-space

## Goal

Decide, and then split into tasks, how the operational layer works without the 5 km hex grid so that a formation and a battle share one world in metres. **This task is `/refine-task` material – do not implement before the questions are answered.**

## Open questions (for the human, then ADR 0030)

- Control of ground: an influence raster (cell size?), regions / provinces, or circles around formations? Who "holds" a place; how does the front line follow from it?
- Movement and routes: free paths over a navigation grid (as TASK-206, coarser) with a per-turn distance, or routes along roads and passes only?
- Contact: distance threshold between opposing formations -> a battle on the terrain where they meet (replaces the hex -> battle map mapping of ADR 0018, `contact_map.gd`).
- Objectives, strikes and air defence: zones (circles / polygons) instead of hexes; country membership from the border polygons instead of a country per hex.
- Migration: the operational tests (`test_hex_control`, `test_staff_map_*`, `test_operation_victory`, `test_contact_map`, `test_operational_map_data` and others) and the operation data (`data/operational/`, `data/maps/`) change with it – staged or one cutover?
- Is the gain worth it, or does the operational layer keep a hidden grid for the rules (as ADR 0028 for the old tactical maps)?

## Acceptance criteria (testable)

- [ ] The questions are answered in an ADR; the follow-up tasks are written (core model, AI, staff map view, data migration, manual).

## Playtest (for the human)

none (design task)

## Player manual

none

## Out of scope

- Any code.

## Implementation notes

_Filled in by the agent when done._

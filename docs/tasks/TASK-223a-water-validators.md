# TASK-223a: Water network (1/7): validators and devtools overlay – measure the river and lake errors

- **Status**: ready
- **Layers**: core (`WaterValidator`, pure) + presentation (devtools overlay) + tools
- **Depends on**: –
- **Sections**: ADR 0034 decision 5; ARCHITECTURE "River water and bridges"
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Every water error on a map is listed with its position instead of being found by eye, so the rewrite (223b–g) starts from a measured list and later tasks are accepted by "zero violations".

## Acceptance criteria (testable)

- [ ] `WaterValidator.check(...) -> Array[Dictionary]` (`{rule: StringName, position: Vector2 (world), value: float, limit: float}`), pure, deterministic; reads today's data (river lines from `FeatureRibbonPlanner.lines`, levels from `RiverChannel`, `TerrainSurface`, water tiles, bridges) behind one small adapter so 223c can feed `WaterNetwork` instead.
- [ ] Rules, each with a unit test on a hand-made grid that breaks it exactly once: `surface_rises` (water surface rises > 0.05 m downstream), `junction_step` (tributary vs main river level at a confluence > 0.1 m), `lake_step` (river end vs lake level > 0.1 m), `dry_bed` (ground above the surface inside the water), `flooded_bank` (ground below the surface outside the water within the bank band), `shallow` (water depth < 0.5 m on a river ≥ 6 m), `width_jump` (width changes > ×1.5 within 50 m away from a junction), `bridge_short` (deck does not span the water), `steep_water` (surface gradient > 2 %). Distances and heights in metres via `MapScale`.
- [ ] `tools/water_report.sh [--map=…] [--region=col:row]` prints counts per rule and the first 20 positions; run on Suwałki (theatre hex 47,45 cut and the `suwalki` battle map), numbers written in the implementation notes.
- [ ] Devtools: a switch "Water errors" in the terrain viewer and the battle draws a marker per violation (colour per rule, label on hover); off by default, no cost when off.

## Playtest (for the human)

1. Devtools → terrain viewer at 47,45 → switch "Water errors" on.
2. Markers sit where rivers run uphill, step into lakes or float above the ground.

## Player manual

None (devtools only).

## Out of scope

- Fixing any violation (223c–223e).

## Implementation notes

_Filled in by the agent when done._

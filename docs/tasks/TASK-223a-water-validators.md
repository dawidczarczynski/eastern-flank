# TASK-223a: Water network (1/7): validators and devtools overlay – measure the river and lake errors

- **Status**: done
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

- Core: `WaterSample` (reaches downstream-ordered with width / level in metres, `ground` and `lake_at` callables, bridges) and `WaterValidator.check(sample)` – the nine rules, results grouped in `RULES` order. Tests: `tests/unit/test_water_validator.gd` (one hand-made river per rule, clean river, junction exemption of `width_jump`, determinism).
- Adapter: `WaterSampleAdapter.build(grid, surface)` (presentation, it reads `FeatureRibbonPlanner`): river lines + widths, levels recomputed with `RiverChannel.levels` (downstream = lower end), ground = `TerrainSurface.height_at` (channel dug in), lakes = WATER tiles at the water plane, bridges from `BridgeSites`. Heights in metres = units × `MapScale.metres_per_unit` / `RiverChannel.VERTICAL` (the drawn relief is exaggerated ×2). Rivers narrower than 6 m have no channel and are left out. TASK-223c swaps the adapter for a `WaterNetwork` reader.
- Definitions chosen: junction = a reach end within 15 m of another reach; lake = at the end or 60 m ahead of it; `dry_bed` / `shallow` checked at the centre of each vertex, `flooded_bank` 1.5 m beyond the water edge on both sides; `width_jump` compares each vertex with those up to 50 m upstream, one report per jump, skipped within 50 m of a junction; `bridge_short` against the width of the nearest reach.
- Tool: `tools/water_report.sh` (+ `tools/water_report.gd`), widths from the land-cover raster like the battle (`RiverWidths.apply`). docs/TOOLS.md updated.
- Devtools: DEVTOOLS page switch **Water errors** (`DevTunables.water_errors`); `BattleController` adds `WaterErrorOverlay` after `MapView.build` only when it is on (the validator does not run otherwise), so it works in the battle and the terrain viewer. One unshaded, no-depth-test pillar (40 m) per violation, coloured per rule, in one MultiMesh; the label under the mouse shows `rule value / limit`.
- Review: confluence checked before the lake probe; bank probes in other water skipped; a bridge counts as over the water within half the width of the centre line. `dry_bed` is reported per vertex (one cause, many hits) – 223c may group runs like `width_jump`.
- `tests/unit/test_salvo_fx.gd` now resets VisualScale / MapScale in `before_each`: the new test file reshuffled the shards and put it behind a test that leaves another scale active (pod length 0.03).
- Measured 2026-11-28:
  - `suwalki` battle map: 0 reaches (all its rivers are ≤ 3.8 m, no channel), 8 bridges, 0 violations.
  - theatre hex 47,45 cut (`--map=suwalki_theatre --region=47:45`): 14 reaches, 5 bridges – `surface_rises` 0, `junction_step` 0, `lake_step` 1 (1.19 m step at 19.45, 23.23), `dry_bed` 1461 (mostly a constant 2.17 m: where the level is clamped to the water plane the channel stops at `TerrainSurface._CHANNEL_FLOOR` 0.03 above it), `flooded_bank` 376 (bank probes that land in another reach or a lake are skipped), `shallow` 11, `width_jump` 1, `bridge_short` 0, `steep_water` 106.
  - `surface_rises` 0 is expected: the 2026-11-28 stop-gap makes `RiverChannel.levels` monotone. `junction_step` 0 may mean the ribbon chains do not end within 15 m of each other (tributaries fade out short of the main line), so check the confluences in the overlay.

# TASK-202: Real-scale roads, tracks and paths – width, surface, edges

- **Status**: idea
- **Layers**: presentation (road ribbons, ground decals / splat)
- **Depends on**: TASK-134
- **Sections**: ARCHITECTURE "Terrain" (road ribbons); look reference (TASK-190)
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Roads read like the reference at real scale: narrow village roads, gravel and dirt tracks across fields and forests, tarmac with centre lines on main roads, shoulders and ruts – with the right width in metres, following the terrain.

## Acceptance criteria (testable)

- [ ] Widths and surfaces by OSM class in metres through `MapScale` (data): motorway / primary 7–10 m asphalt with markings, secondary / residential 4–6 m asphalt, `track` and `service` 2.5–4 m gravel or dirt, `path` 1–2 m worn earth; surface tag overrides.
- [ ] Ribbons lie on the near surface (no floating or sinking edge on slopes, TASK-134) and blend into the verge (soft edge, tinted grass border, gravel shoulder); dirt tracks get a darker rut pair and a grassy centre when little used (hash).
- [ ] Junctions and ends are clean (no overlaps showing z-fighting; the ribbon planner's tests extended); bridges / culverts keep their current treatment.
- [ ] Close-up detail under ~100 m: pebbles / cracks texture in metres, puddle patches on dirt roads (hashed), skid marks stay with TASK-058 decals.
- [ ] Frame time unchanged within 0.3 ms; `balanced` unchanged (test).
- [ ] Screenshots Read at 0.4 / 1.2 / 5 against the reference (village road, field track, forest track).

## Playtest (for the human)

1. Follow roads, field tracks and forest tracks: widths and surfaces look right, edges are soft, no flicker.

## Player manual

None.

## Out of scope

- Traffic; bridge models; railway detail.

## Implementation notes

_Filled in by the agent when done._

# TASK-072: Scalability for very large maps (umbrella)

- **Status**: done (superseded by TASK-072a and TASK-072b)
- **Layers**: presentation, tools
- **Depends on**: –
- **Model**: –

## Goal

Maps far larger than today's (the human wants squads on maps with ~100 m hexes, 6x more hexes per area) hold a stable frame rate and a short load time. Split on 2026-11-20 into:

- TASK-072a – benchmark tool and 1x / 4x / 16x baseline measurements.
- TASK-072b – chunked lazy world with metre-based distance rings (depends on 072a).

## Decisions (2026-11-20)

1. Scope: streaming core + benchmark. TASK-134 (terrain LOD) and TASK-135 (impostors, canopy shells, real density) keep their scope and plug into 072b.
2. Target: 16x today's area (~11 500 hexes; Suwałki 720 x 16) builds and runs.
3. Frame bar is map-size independent: 16x costs about the same per frame as Suwałki at every camera distance, no hitch above 33 ms while panning; load time and memory not linear in area. Hard 60 FPS stays with TASK-134/135/138.
4. Presentation layer + tools only; scatter determinism unchanged, no `GameState.rng`.

## Implementation notes

No code in this file; see TASK-072a and TASK-072b.

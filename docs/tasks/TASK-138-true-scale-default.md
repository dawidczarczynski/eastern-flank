# TASK-138: Wire MapScale into the battle and make `true` the default scale preset

- **Status**: blocked
- **Layers**: presentation (`MapScale.apply_map_id`, `VisualScale` default, settings, README screenshot)
- **Depends on**: TASK-111, TASK-134, TASK-135, TASK-136, TASK-137
- **Sections**: GDD "Open questions" (Realistic scale); ADR 0021
- **Model**: sonnet

## Goal

The battle scene uses real scale by default on every map: `MapScale.apply_map_id` runs when a battle is built, and `true` replaces `balanced` as the default preset.

## Acceptance criteria (testable)

- [ ] `MapScale.apply_map_id` is called on battle start; metres per unit = 144.34 (± 0.01) for `suwalki_battle` and for generated maps.
- [ ] The default `VisualScale` preset is `true`; `balanced` and `current` remain selectable (setting or env var).
- [ ] Tests that assumed the old default are updated; core tests, replays and `tools/simulate.sh` results are unchanged (presentation only).
- [ ] Frame time at 46 / 24 / 7 / 1.0 on Suwałki and the default battle ≤ 16.7 ms avg on the RX 580, or the human accepts the recorded shortfall.
- [ ] `tools/readme_screenshot.sh` re-run and `docs/images/gameplay.png` Read and committed.

## Playtest (for the human)

1. Start the default battle and Suwałki: units are markers when zoomed out, real models up close, forests dense.
2. Compare with the earlier look; the settings still allow `balanced`.

## Player manual

Update §10 "Screen" and the unit descriptions: units are drawn at their real size; use the markers to find them; the zoom range, group drawing and the larger scale of the terrain as written by TASK-111 / TASK-136.

## Out of scope

- Rule changes; platoon-level units.

## Implementation notes

_Filled in by the agent when done._

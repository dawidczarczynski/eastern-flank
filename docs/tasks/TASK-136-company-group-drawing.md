# TASK-136: Company drawn as a group of 3–4 real-size models

- **Status**: blocked
- **Layers**: presentation (`UnitView`, `UnitModels`, wreck handling; core untouched)
- **Depends on**: TASK-111, TASK-134 (soft: TASK-135)
- **Sections**: GDD "Open questions" (Realistic scale – How a company is drawn), "Vision decisions"; ADR 0021
- **Model**: opus (placement on the exact surface, event timing between systems)

## Goal

Below ~3 units camera distance a company is drawn as 3–4 real-size vehicles or squads spread around its hex centre; the number of models follows its strength, destroyed ones leave wrecks. Mechanics (HP = strength, one unit per hex) do not change.

## Acceptance criteria (testable)

- [ ] Model count from HP fraction: HP 10 of 10 → 4 models (3 for 3-vehicle classes), HP 5 → 2, HP 1 → 1; never 0 while the unit lives (pure function, tested for every HP 1–10).
- [ ] Offsets: deterministic slots 50–80 m (0.35–0.55 units) from the hex centre, fully inside the hex, ≥ 40 m apart; the same unit always gets the same slots (no RNG draw).
- [ ] The group is drawn only when camera distance < `CameraMath.GROUP_DRAW_DISTANCE` (3.0, TASK-111); above it one model (or none) plus the marker.
- [ ] Each model's base touches the drawn terrain surface (± 0.1 m) on the Suwałki map, sampled at 20 hexes; none sunk or floating.
- [ ] A damage event removing strength turns the last model(s) into wrecks (smoke, no pop); a kill leaves wrecks for all; no state read except via events / `GameState`.
- [ ] Movement, attacks, muzzle flash and selection use the group's lead model as origin/target; hex-based picking unchanged.
- [ ] Frame time at distance 1.2 and 3 on Suwałki with 4 groups visible ≤ the ADR 0021 numbers + 1 ms.

## Playtest (for the human)

1. Zoom into a company: 3–4 vehicles standing in the hex; damage it and watch models turn into wrecks.
2. Zoom out past ~3 units: the group collapses to the marker without flicker.

## Player manual

§ Units / Screen: a company shows as a group of vehicles or squads when zoomed in; the number of vehicles follows its strength; one tag per company.

## Out of scope

- Platoon as tactical unit (Option B, GDD open question); effects rescale (TASK-137).

## Implementation notes

_Filled in by the agent when done._

# TASK-190: Real-scale look (A): forest as one dark canopy, aerial perspective

- **Status**: to playtest
- **Layers**: presentation (`LookPreset`)
- **Depends on**: TASK-135
- **Sections**: ARCHITECTURE "Real-scale vegetation"; look reference: Arma 3 Chernarus / Arma Reforger Everon aerial views (human, 2026-11-21)
- **Model**: sonnet
- **Tags**: battle-look

## Goal

At real size the landscape reads like the reference: forests are one dark, even canopy (not a confetti of light and dark species) and the distance fades into a bluish haze, which gives the scale.

## Acceptance criteria (testable)

- [x] Under `true` the leaf colours are close, dark summer greens (`LookPreset.REAL_SIZE_LEAF_COLORS`, birch only a little lighter); `balanced` unchanged (test).
- [x] Under `true` the depth fog starts at ~700 m and is dense by ~11 km, bluish, taking the sky's colour (`REAL_SIZE_AIR`, metres through `MapScale`); `balanced` keeps the look's fog (test).
- [x] The canopy shell brightness follows the darker greens (`shell_brightness` 2.7).
- [x] Screenshots at distances 5 / 12 / 24 read by the agent.

## Playtest (for the human)

1. `--debug`, DEVTOOLS SCALE = TRUE SIZE, Suwałki: zoom out from the forest to the widest view.
2. Forests read as one dark canopy; the far landscape fades into haze; compare with the reference.

## Player manual

None (look only).

## Out of scope

- Terrain colour (TASK-192), impostor lighting (TASK-191), loading (TASK-189).

## Implementation notes

`LookPreset.REAL_SIZE_LEAF_COLORS` darkened and brought together (pine #34502f … birch #56743a); `LookPreset.REAL_SIZE_AIR` (depth fog 700 m → 11 km, curve 1.0, #a8bccf, aerial perspective 0.85) applied by `apply_to_environment` under `true`; `shell_brightness` 1.9 → 2.7. Depth fog only: no frame-time cost. Screenshots `.screenshots/veg/g2_5`, `g3_12`, `g3_24`. Known: the far canopy shell is still a little darker and flatter than the reference's forest tops; the haze is grey-blue (the HDRI sky's colour through aerial perspective).

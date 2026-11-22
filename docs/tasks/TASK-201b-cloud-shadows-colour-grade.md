# TASK-201b: Moving cloud shadows and colour grade for `true`

- **Status**: ready
- **Layers**: presentation (`assets/shaders/cloud_shadow.gdshaderinc`, global shader uniforms, `LookPreset` grade)
- **Depends on**: TASK-201a
- **Sections**: ARCHITECTURE "Graphics quality", "Real-scale vegetation"; ADR 0023, 0026, 0027; look reference TASK-190
- **Model**: sonnet
- **Tags**: battle-look

## Goal

Soft clouds drift across the landscape and the `true` colour grade ties the scene to the reference – within the frame budget.

## Decisions (2026-11-22)

- TASK-201 is split into 201a and 201b; cloud shadows (from TASK-066, merged via 201) live here.
- Clouds do not fall on units (human decision): units stay evenly lit for readability; the camo shader does not include the cloud shader.
- Reference look = Arma 3 Chernarus / Arma Reforger Everon aerial views, as in TASK-190.
- Model sonnet: tuning plus one shader include, no tricky algorithm.

## Acceptance criteria (testable)

- [ ] Shared include `cloud_shadow.gdshaderinc` (design from docs/tasks/TASK-066-cloud-shadows.md): world-space tileable noise, drifting with time, offset by the sun direction; included by the terrain, grass and foliage shaders (test greps each).
- [ ] Global uniforms `cloud_shadow_strength`, `cloud_scale`, `cloud_speed` exist; strength is a look value and is 0 on LOW (test).
- [ ] The noise texture is tileable (seam test: edge pixels differ by <= 1/255 across the wrap, like TASK-027).
- [ ] The camo (unit) shader does not include the cloud shader (test).
- [ ] Cloud pattern roughly matches the sky's clouds (scale and drift direction; checked in screenshots).
- [ ] Colour grade for `true`: saturation / contrast / shadow-tint / highlight-tint values tuned from the reference, set via the existing `LookPreset` "grade" dict through the ColorGrade path; values recorded in implementation notes.
- [ ] `balanced` grade and cloud strength unchanged (test vs today's values).
- [ ] Frame time at camera 1.2 / 5 / 24 <= 16.7 ms avg on the RX 580 (`true`, HIGH, 720p), or the shortfall and the quality level holding it recorded.
- [ ] Screenshots Read at 5 / 12 / 24: tone compared to the reference, units clearly readable under cloud patches.

## Playtest (for the human)

1. `true` preset, zoom out: soft darker patches drift slowly over ground and trees, never over units, no visible repeating pattern.
2. Tone matches the reference feel; frame rate while panning.

## Player manual

None.

## Out of scope

- Time of day / weather, real volumetric clouds, volumetric light rays.

## Implementation notes

_Filled in by the agent when done._

# TASK-071: Central-Eastern European look – species, palette, terrain character

- **Status**: done – study done, the human picked variant B (muted summer, 2026-10-23).
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

- [x] `LookPreset` holds the look (ground tints, leaf colours, species shares, autumn share, grade, water, fog/exposure); the default is `muted_summer`, `current` reproduces the old look.
- [x] Pine-heavy mixed forest (pine 78 % / spruce 22 %, birch 50 % / oak 20 % / alder 30 %); yellowed, darker greens; sandy dirt.
- [x] Water is opaque, dark and green (not Mediterranean blue).
- [x] Tests: `test_look_preset.gd`, shares in `test_tree_species.gd`; `tools/check.sh` passes.
- [x] Human playtest: the map reads as Central-Eastern Europe.

## Playtest (for the human)

1. Compare the study variants and pick one.
2. After the change: does the map read as a Central-Eastern European landscape?

## Player manual

None (presentation only).

## Out of scope

- Per-scenario seasons or weather (could follow).

## Implementation notes

Study: `SCREENSHOT_LOOK=<current|muted_summer|early_autumn|overcast>` in `tools/screenshot.sh` (renders in `.screenshots/look/`). The human chose B `muted_summer` and approved its water; the other presets stay in `LookPreset.PRESETS` for comparison (C autumn, D overcast with grey fog).
New: `src/presentation/look_preset.gd`; read by `ColorGrade` (grade merged, `reset_cache()`), `GraphicsQuality.apply_environment` (fog/exposure), `TerrainGround`/`TerrainTextures` (layer tints), `TreeField` (leaf colours), `TreeSpecies` (shares, autumn share) and `MapView._build_water`.
Not done (follow-ups): reeds/ferns/heather undergrowth (TASK-070), hornbeam/aspen species, bark colours, an overcast HDRI. The big open lawn changes only slightly with the ground tint.

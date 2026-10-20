# TASK-066: Moving cloud shadows on terrain, foliage and units

- **Status**: idea – after the custom ground/foliage shaders exist; decide whether units receive the shadows too (camo shader) and how strong it may be without hurting readability.
- **Layers**: presentation (`assets/shaders/cloud_shadow.gdshaderinc`, global shader uniforms, terrain/grass/foliage/camo/water shaders)
- **Depends on**: **TASK-055** (terrain shader), **TASK-057** (global uniforms, grass shader), soft **TASK-060** (foliage shader), **TASK-054** (sky clouds to match), TASK-050 (off on LOW)
- **Model**: sonnet

## Goal

Large, soft cloud shadows drift slowly across the battlefield, like on a real partly cloudy day – the single strongest "this is a real landscape" cue at strategic zoom.

## Design (draft)

- Godot's `DirectionalLight3D` has no light projector, and a moving `Decal` cannot tile. Instead a shared include samples a tileable low-frequency noise texture in world space: `mask = smoothstep(0.45, 0.65, noise((world.xz + wind_dir · TIME · cloud_speed) / cloud_scale))`, `cloud_scale` ≈ 18 world units, `cloud_speed` 0.25 u/s; the global uniforms `cloud_shadow_strength` (0.3 HIGH, 0 LOW), `cloud_scale`, `cloud_speed`.
- Applied in every opaque world shader that should receive it: `ALBEDO *= 1 − mask · strength · 0.6` and `SPECULAR`/direct light reduced via a `light()` tweak only if cheap; units via the camo shader (decision).
- Shadow direction offset by the sun direction so clouds project consistently.

## Acceptance criteria (testable)

- [ ] (to be written when `ready`) the include exists and every listed shader includes it; the global uniforms exist and `cloud_shadow_strength == 0` on LOW; the noise texture is tileable (seam test like TASK-027).

## Playtest (for the human)

1. Zoom out: soft darker patches drift slowly across the map in the wind direction, over ground, trees and (if chosen) units.
2. They never make a unit hard to read; no visible repeating pattern.

## Player manual

None (presentation only).

## Out of scope

- Real volumetric clouds, weather changes.

## Implementation notes

_Filled in by the agent when done._

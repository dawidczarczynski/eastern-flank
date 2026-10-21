# TASK-050: Graphics quality presets (LOW / HIGH), auto-detected, overridable

- **Status**: done
- **Layers**: presentation (`src/presentation/graphics_quality.gd`, battle scene setup), tools (`run*.sh`/`screenshot.sh` pass-through), tests
- **Depends on**: – (do it before the heavier realism tasks; TASK-051 … TASK-066 read their switches from here)
- **Model**: sonnet

## Goal

The realistic features (SSIL, SSR, grass, particles, decals, wind) run at full quality on the target GPU (Windows, D3D12, Forward+) and degrade automatically on slow renderers (the WSLg software rasteriser used for previews), so the game stays usable everywhere.

## Design

- Pure class `GraphicsQuality` (`class_name`, `RefCounted`, static):
  - `enum Level { LOW, HIGH }`.
  - `detect(rendering_method: String, adapter_name: String) -> Level`: `LOW` when `rendering_method == "gl_compatibility"` or `adapter_name` contains (case-insensitive) `llvmpipe`, `softpipe`, `swiftshader` or `microsoft basic render`; otherwise `HIGH`.
  - `parse_override(args: PackedStringArray) -> int`: `--quality=low` → `LOW`, `--quality=high` → `HIGH`, anything else / missing → `-1` (no override).
  - `features(level: Level) -> Dictionary` – the single place later tasks read their switches from. Initial keys (later tasks add theirs, each with a test):

    | key | LOW | HIGH |
    |---|---|---|
    | `ssao` | false | true |
    | `ssil` | false | true |
    | `ssr` | false | true |
    | `glow` | false | true |
    | `shadow_atlas_size` | 2048 | 4096 |
    | `shadow_max_distance` | 40.0 | 80.0 |
    | `msaa_3d` | 0 (`Viewport.MSAA_DISABLED`) | 1 (`MSAA_2X`) |
    | `grass_density` | 0.0 | 1.0 |
    | `decals_max` | 16 | 64 |
    | `particles` | false | true |
    | `wind` | false | true |
    | `backdrop_scatter` | false | true |

- At battle start the battle scene computes `level = override if override >= 0 else detect(ProjectSettings rendering method, RenderingServer.get_video_adapter_name())`, applies the environment/viewport/sun switches it owns (ssao, ssil, ssr, glow, shadow size/distance, MSAA) and exposes `features` to views (`MapView`, `UnitView`, effects) – e.g. a `quality: Dictionary` set before `build()`. Print one line `Graphics quality: HIGH (auto: <adapter>)` to stdout.
- The `project.godot` values stay the HIGH values; LOW only switches things off at runtime.
- `tools/run.sh`, `tools/run_windows.sh`, `tools/screenshot.sh` pass a `--quality=…` option through as a user argument (after `--`); `screenshot.sh --windows` defaults to HIGH by detection, `--linux` to LOW.

## Acceptance criteria (testable)

- [x] `tests/unit/test_graphics_quality.gd`: `detect("forward_plus", "NVIDIA GeForce RTX 3060") == HIGH`; `detect("forward_plus", "llvmpipe (LLVM 15.0.7, 256 bits)") == LOW`; `detect("gl_compatibility", "NVIDIA…") == LOW`; `detect("forward_plus", "Microsoft Basic Render Driver") == LOW`.
- [x] `parse_override(["--quality=low"]) == LOW`, `["--quality=HIGH"] == HIGH` (case-insensitive), `["--foo"] == -1`, `[] == -1`.
- [x] `features(LOW)` and `features(HIGH)` have the same key set; values as in the table.
- [x] Applying LOW to a test `Environment` turns off `ssao_enabled`, `ssil_enabled`, `ssr_enabled`, `glow_enabled`; HIGH turns on the ones TASK-051/TASK-056 configure (`test_battle_look.gd` adjusted: it asserts the HIGH environment).
- [x] `tools/screenshot.sh --linux` prints `Graphics quality: LOW`; `--windows` prints `HIGH` (agent checks stdout; note in the implementation notes if only one build is available).
- [x] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh` (Windows build → HIGH), Read it: it must look exactly as before this task (no regressions); commit only if it changed.

## Playtest (for the human)

1. `tools/run_windows.sh`: the console shows `Graphics quality: HIGH`; the game looks as before.
2. `tools/run.sh` (WSLg): the console shows `Graphics quality: LOW`; the game runs noticeably smoother than before, with softer shadows and no ambient occlusion.
3. `tools/run_windows.sh -- --quality=low` (or the documented syntax): forced LOW on the GPU build.

## Player manual

Add a short note (e.g. a "Graphics" line in section 10 or a new short section): "The game picks a graphics quality automatically: on a slow or software graphics driver it switches off the expensive effects. Start it with `--quality=low` or `--quality=high` to choose yourself." There is no in-game settings screen yet.

## Out of scope

- A settings menu, per-feature toggles in the UI, resolution scaling (FSR), saving the choice.
- MEDIUM preset (add it when a real mid-range GPU is tested).

## Implementation notes

- `src/presentation/graphics_quality.gd` (`GraphicsQuality`): `detect`, `parse_override`, `features`, `level_name`, `apply_environment`, `apply_sun`, `apply_viewport` (shadow atlas size via `RenderingServer`, `msaa_3d`). Tests: `tests/unit/test_graphics_quality.gd`; `test_battle_look.gd` asserts the HIGH environment.
- `BattleController._setup_graphics_quality()` runs first in `_ready`: override from `OS.get_cmdline_user_args()`, else `detect(RenderingServer.get_current_rendering_method(), get_video_adapter_name())`; prints the line, applies the switches to a **duplicate** of the environment resource (the cached `.tres` stays untouched; shallow copy – the sky is still shared, keep that in mind if a later task mutates sky settings at runtime), the sun and the viewport, and sets `quality` on `MapView` and each `UnitView` (no reader yet – later tasks).
- **Deviations from the table**: HIGH `msaa_3d` is `MSAA_4X` (2), not 2X, to match `project.godot` so HIGH looks exactly as before (a test guards the match). `apply_environment` at HIGH turns SSAO on but only *keeps* ssil/ssr/glow as the resource has them (never switches on an effect TASK-051/056 haven't configured); LOW forces all four off.
- Tools: `run.sh` / `run_windows.sh` accept `--quality=low|high` and pass it after `--` (no `--` needed from the caller: `tools/run_windows.sh --quality=low`); `screenshot.sh` passes it through, `screenshot_options.gd` accepts it.
- Stdout checked with both builds: `--linux` → `Graphics quality: LOW (auto: llvmpipe (LLVM 9.0.1, 256 bits))`; `--windows` → `Graphics quality: HIGH (auto: Radeon RX 580 Series)`; `--windows --quality=low` → `Graphics quality: LOW (override)`. `run.sh` / `run_windows.sh` pass-through not run by the agent (needs the human).
- `tools/readme_screenshot.sh` re-render is byte-identical to the committed `docs/images/gameplay.png` – nothing to commit.
- Review fixes: `run_windows.sh` appended the option after `Start-Process` (ignored) – moved before it; `run.sh` empty-array expansion safe under `set -u`; dropped the hard-coded key count test (later tasks add keys).
- Not tested (scene-bound): that the scene's environment is a copy. Godot's exit-time "leaked resources" lines in screenshot runs predate this task.
- MANUAL.md: "Graphics" bullet in section 10.
- **Playtest round 1** (human: `tools/run.sh` unplayable): the table's LOW only switched off SSAO (unsupported by Compatibility anyway) and MSAA – no speed-up. Measured on llvmpipe (WSLg, 4 cores, 1600×900, frame time): base 2125 ms / 6.6 M primitives; no MSAA 2124; half resolution 1877; no shadows 1024; no foliage 395; no foliage + no shadows 249; + half resolution 138. The foliage (≈1600 triangles per deciduous tree, thousands of trees, drawn again for the shadow pass) is the cost. Human chose option B: LOW adds `shadows: false` (sun `shadow_enabled`), `foliage: false` (`MapView.build` skips the scatter; forests show by terrain colour) and `render_scale: 0.5` (`Viewport.scaling_3d_scale`). Result: LOW 151 ms/frame (≈14× faster). Remaining cost: ~370 draw calls from the unit models.
- The `Graphics quality:` line is printed (checked in `tools/run.sh` output), but under WSLg it comes after a block of Vulkan/OpenGL fallback warnings.

# TASK-050: Graphics quality presets (LOW / HIGH), auto-detected, overridable

- **Status**: ready
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

- [ ] `tests/unit/test_graphics_quality.gd`: `detect("forward_plus", "NVIDIA GeForce RTX 3060") == HIGH`; `detect("forward_plus", "llvmpipe (LLVM 15.0.7, 256 bits)") == LOW`; `detect("gl_compatibility", "NVIDIA…") == LOW`; `detect("forward_plus", "Microsoft Basic Render Driver") == LOW`.
- [ ] `parse_override(["--quality=low"]) == LOW`, `["--quality=HIGH"] == HIGH` (case-insensitive), `["--foo"] == -1`, `[] == -1`.
- [ ] `features(LOW)` and `features(HIGH)` have the same key set; values as in the table.
- [ ] Applying LOW to a test `Environment` turns off `ssao_enabled`, `ssil_enabled`, `ssr_enabled`, `glow_enabled`; HIGH turns on the ones TASK-051/TASK-056 configure (`test_battle_look.gd` adjusted: it asserts the HIGH environment).
- [ ] `tools/screenshot.sh --linux` prints `Graphics quality: LOW`; `--windows` prints `HIGH` (agent checks stdout; note in the implementation notes if only one build is available).
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh` (Windows build → HIGH), Read it: it must look exactly as before this task (no regressions); commit only if it changed.

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

_Filled in by the agent when done._

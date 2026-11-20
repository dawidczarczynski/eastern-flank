# TASK-072a: Large-map benchmark – synthetic 1x / 4x / 16x maps and baseline measurements

- **Status**: done
- **Layers**: presentation (read-only), tools (benchmark); no core rule change
- **Depends on**: –
- **Sections**: GDD "Visual direction" (Performance); ADR 0021, ADR 0022
- **Model**: sonnet

## Goal

A repeatable benchmark that builds the Suwałki battle map at 1x, 4x and 16x area and prints build time, memory, instance/triangle counts and frame time at fixed cameras, so TASK-072b has a baseline and a pass/fail bar.

## Decisions (2026-11-20)

1. Scope of 072 is a streaming core plus a benchmark; 072a is the benchmark, 072b the chunked lazy world. TASK-134 (terrain LOD) and TASK-135 (impostors, canopy shells, real density) keep their own scope and plug into 072b.
2. Target: a map 16x today's Suwałki area (720 x 16 = 11 520 hexes) must build and run.
3. Frame bar is map-size independent: the 16x map costs about the same per frame as today's Suwałki at every camera distance. Hard 60 FPS stays with TASK-134/135/138.
4. 072a measures only; no streaming, no scene change. Presentation-layer plus tools, no core rule change, no `GameState.rng` use.

## Acceptance criteria (testable)

- [ ] `tools/bench_large_map.sh [--scale=1|4|16 | --all] [--quality=low|high]` exists (documented in docs/TOOLS.md) and prints one table row per scale and camera.
- [ ] Synthetic maps: the Suwałki tile grid is tiled (mirrored at the seams so heights/terrain stay continuous) to 1x (30x24), 4x (60x48) and 16x (120x96 = 11 520 hexes); a unit test checks the tile counts and that the seam heights match within 1 mm.
- [ ] The tiling lives in a pure helper (`RefCounted`, no `Node`) and is deterministic: same input → identical grid (test).
- [ ] Per scale it prints: build time (s, wall clock of `MapView.build`), static memory delta (MB), MultiMesh instance count, triangles, draw calls.
- [ ] Per scale and camera (distances 46 / 24 / 7 / 1.2 as in ADR 0021, plus a pan sweep of 10 s) it prints avg and max frame time via SCREENSHOT_MEASURE_FRAMES; the pan sweep also prints the count of frames > 33 ms.
- [ ] 16x completes without crash or out-of-memory on the RX 580 build; if it does not, the failure point (stage, MB) is recorded instead.
- [ ] Implementation notes hold the 1x/4x/16x table, the linear-growth factors (build time, memory per area), and the top 3 cost centres per scale (tools/perf_profile.gd breakdown) – these become 072b's baseline.
- [ ] `tools/check.sh` passes; the benchmark itself is not part of the test run.

## Playtest (for the human)

1. Run `tools/bench_large_map.sh --all`; read the table: build time and memory grow about 4x and 16x.
2. Optional: `SCREENSHOT_SCENARIO` with the 4x map shows one continuous landscape without seam lines.

## Player manual

None.

## Out of scope

- Any streaming, chunk manager, LOD or budget change (TASK-072b, TASK-134, TASK-135).
- Units and game logic at scale (pathfinding, AI).

## Implementation notes

Added `MapTiler` (src/core/map_tiler.gd, pure, tested in tests/unit/test_map_tiler.gd), `tools/bench_large_map.gd` + `.sh` (docs/TOOLS.md). Each scale runs in its own Godot process on a bare scene (map, sun, environment, camera). Mirroring happens in offset space: seam tiles have equal elevation, but a mirrored row shifts the hex parity by half a hex (the surface interpolates, so no height jump). Roads and rivers are not copied.

Baseline: Windows Godot, GPU, HIGH, 1280x720 window, vsync off (2026-11-20):

| scale | hexes | build s | grass prebuild s | static MB | video MB | instances | tris k | draws |
|---|---|---|---|---|---|---|---|---|
| 1x | 720 | 5.17 | 2.89 | 79 | 593 | 111 640 | 4 631 | 970 |
| 4x | 2 880 | 14.35 | 1.18 | 188 | 913 | 156 466 | 7 710 | 2 203 |
| 16x | 11 520 | 51.73 | 0.64 | 609 | 1 934 | 531 056 | 20 288 | 3 550 |

Frame time avg ms (max): distances 46 / 24 / 7 / 1.2 are within 0.3 ms of each other per scale: 1x 10.8 (11.4), 4x 11.4 (11.8), 16x 21.6 (22.2). Pan sweep: 1x 11.3 avg, max 103.7, 27 frames > 33 ms; 4x 18.1, max 41.1, 65 frames; 16x 25.0, max 36.6, 2 frames.

Growth: build time x2.8 (4x), x10 (16x) per area, i.e. roughly linear in hexes beyond the fixed cost; static memory x2.4 / x7.7; video memory x1.5 / x3.3; frame time is flat at 4x but doubles at 16x (instances and draws are not culled by distance) – the bar for TASK-072b is 16x ~ 1x. 16x built and ran without failure.

Not done: the "top 3 cost centres per scale" from tools/perf_profile.gd. The profile is wired to the battle scene's node names and the bench uses a bare scene; use `tools/perf.sh` on the battle as the starting point in TASK-072b. The Linux software renderer (llvmpipe) crashes in the bench; use the Windows build.

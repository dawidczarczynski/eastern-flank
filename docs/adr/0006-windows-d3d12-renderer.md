# ADR 0006: Windows builds render with Direct3D 12

- **Status**: accepted
- **Date**: 2026-10-18

## Context

TASK-026 enabled SSAO in the battle environment. On the human's machine (AMD Radeon RX 580, Godot 4.5.1, Forward+) SSAO on the default Vulkan driver breaks the image: terrain loses its colour and turns flat grey, and foliage breaks up into square blocks. Changing the SSAO quality or half-size project settings makes no difference. The same scene rendered with `--rendering-driver d3d12` is correct and shows the expected contact shadows. The WSLg screenshot path (`tools/screenshot.sh`) does not run Forward+ and never shows SSAO, so it can't catch this.

## Decision

- `project.godot` sets `rendering/rendering_device/driver.windows="d3d12"`. Linux and other platforms keep Vulkan.
- `test_battle_look.gd` asserts the setting, so it isn't dropped by accident.
- To check SSAO visually, run `tools/screenshot.gd` with the Windows Godot console build (`--script res://tools/screenshot.gd -- C:/.../out.png`) instead of `tools/screenshot.sh`.

## Consequences

- (+) SSAO and the sky-based lighting work on the target machine without lowering visual quality.
- (−) Godot 4.5's D3D12 driver has no pipeline cache yet, so shader compilation may cause short stutters the first time new materials appear.
- (−) The Vulkan bug isn't fixed, only avoided. If D3D12 causes problems, the fallback is `ssao_enabled = false` in `battle_environment.tres`, or checking again on newer AMD drivers or Godot versions.

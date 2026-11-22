# TASK-191: Real-scale look (B): impostors and canopy lit by the scene's sun

- **Status**: done
- **Layers**: presentation (`TreeImpostors`, `tree_impostor.gdshader`, `canopy.gdshader`)
- **Depends on**: TASK-189
- **Sections**: ARCHITECTURE "Real-scale vegetation"; ADR 0026, ADR 0027; look reference (TASK-190)
- **Model**: opus (baked normals, matching the full trees' shading)
- **Tags**: battle-look

## Goal

Distant forest is lit like the near trees: sunlit crowns bright on the sun side, slopes and the far sides of crowns in shade – instead of the impostors' baked, fixed light and the shell's own dome shading.

## Acceptance criteria (testable)

- [x] The impostor atlas bakes albedo (unlit) and a normal map per view (two atlas textures, same layout); `tree_impostor.gdshader` is lit (not `unshaded`) with the baked normal turned to the view, so the scene's sun and ambient light it.
- [x] A full tree and its impostor at the hand-over distance differ by ≤ 10 % in mean luminance in a screenshot crop (sun side and shade side).
- [x] The canopy shell takes its colour from the unlit atlas mean and its dome normals from the same sun; it meets the impostors without a tone step at the hand-over (screenshot).
- [~] Forest on a slope facing away from the sun is visibly darker than on a slope facing it (screenshot). (partial: far slope measured darker; sun-facing brighter not isolated)
- [x] Frame time on Suwałki at 1.2 / 5 / 24 ≤ 16.7 ms on the RX 580 (`true`, HIGH, 720p).

## Playtest (for the human)

1. `true` preset, Suwałki: orbit the camera around a forest – the sun side is bright, the far side dark, at every distance.
2. Zoom in and out across the full-tree / impostor / canopy distances: no change in brightness.

## Player manual

None (look only).

## Out of scope

- Impostors casting shadows on the terrain (a later task if needed).

## Implementation notes

- **Bake** (`TreeImpostors`): every view is rendered twice with the new unlit `assets/shaders/foliage_bake.gdshader` (the LOD0 card shader, `foliage_body.gdshaderinc` under `#define IMPOSTOR_BAKE`, linear tone mapping, no lights): pass 1 the unlit albedo (leaf colour x card texture x baked AO, bark), pass 2 the view-space normal of the bent card normals encoded 0..1 (pre-linearised so the 8-bit sRGB target stores the encoding itself). Two atlases of one layout (`atlas()`, `normal_atlas()`, both mipmapped; colour / normal divided by coverage like before). The bake's sun and ambient are gone. The bake takes two passes now (not timed separately; ~1 s before).
- **Lit impostors** (`tree_impostor_view.gdshaderinc`, shared by `tree_impostor.gdshader` and `forest_impostor.gdshader`): no longer `unshaded` (`specular_disabled`, roughness 0.85, backlight 0.35 x albedo as the LOD0 leaves). The vertex shader passes the bake camera's axes for this quad (`impostor_basis`: right, up / towards the camera at the bake elevation of 15°); the fragment decodes the blended normal of the two views, turns it into the world and the view, so the scene's sun, shadows (impostors receive, still do not cast) and ambient light them. The GPU-placed forest tilts that basis with the lattice slope under the tree (two extra lattice lookups per vertex) by `impostor_slope_share` (0.6); TreeField's per-instance impostors stay upright (no ground normal in their instance data).
- **Canopy shell** (`ForestShell`, `canopy.gdshader` `lit_domes`): species colours are the unlit atlas mean (`TreeImpostors.base_color`); the mesh normals are now the drawn ground's (area-weighted face normals of the ground heights, the lift left out so forest edges do not tilt), the dome normals stand on them turned by the same `slope_share`, and lean towards the camera by `shell_view_share` (0.55): the visible half of a crown faces the viewer, which the impostors' baked normals reproduce (bright with the sun behind the camera, dark against it). Without the lean the shell was +82 % brighter than the impostors against the sun. The backdrop canopy (`lit_domes` 0) is unchanged.
- **New / changed look values** (`LookPreset.vegetation()`): `impostor_albedo` 1.08 (a full crown shades its own inner leaves, the picture does not), `impostor_slope_share` 0.6, `shell_view_share` 0.55, `shell_brightness` 2.7 -> 1.55.
- **Measured** (Windows Godot, RX 580, D3D12, HIGH, 720p, Suwałki `true`, `SCREENSHOT_FOCUS=25.1,16.5,<yaw>,<d>`; mean linear luminance of forest-only crops; yaw -40 = sun behind the camera, 140 = against the sun):
  - Full trees vs impostors at the hand-over (d 1.2, normal vs `full_tree_cap` 0 = every tree an impostor, same camera): sun side 0.0330 vs 0.0330 and 0.0330 vs 0.0334 (0 / +1 %); shade side 0.0193 vs 0.0193 and 0.0213 vs 0.0194 (0 / -9 %).
  - Shell vs impostors at the shell hand-over (d 5, normal vs shell off + impostors to 5 km): sun side 0.0702 vs 0.0707 (-1 %); against the sun 0.0457 vs 0.0420 and 0.0873 vs 0.0795 (+9 / +10 %). The shell's 9 m crown pattern still reads coarser than the thinned impostors at ~1 km (pattern, not tone; unchanged by this task).
  - Slope: the same camera (yaw 50, d 3) with `impostor_slope_share` 0.6 vs 0: impostor forest where the ground falls away from the sun is 2-31 % darker (blocks of the far band), nothing brighter in that view; a sun-facing slope brightening was not isolated in a screenshot.
  - Frame time (120 frames, uncapped; baseline = HEAD before the task, same session, git worktree): d 1.2: 13.86 ms (GPU 13.46) vs 12.96 (12.53); d 5: 10.16 ms (9.79) vs 9.14 (8.77); d 24: 8.77 ms (8.40) vs 8.66 (8.31). Lit impostors cost ~0.9-1 ms at d 1.2 / 5; all under 16.7 ms.
- **Look change**: the forest is brighter than before overall (impostor band at d 5 ~+25-35 % luminance against the old baked light) and now shows a sun side and a shade side.
- **Tests**: `tests/unit/test_impostor_lighting.gd` (atlas and normal atlas same size / layout / coverage, unit normals; both impostor shaders lit and turning the baked normal; the bake material is the LOD0 material on the unlit bake shader; the shell paints the unlit atlas mean; shell normals follow the ground slope, not the lift). Headless the atlas is the flat silhouette (normal `FLAT_NORMAL`).
- **Not verified**: motion (orbiting, zooming through the bands) and the live window; the hand-over band in motion is the playtest's.

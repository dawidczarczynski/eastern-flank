# TASK-191: Real-scale look (B): impostors and canopy lit by the scene's sun

- **Status**: ready
- **Layers**: presentation (`TreeImpostors`, `tree_impostor.gdshader`, `canopy.gdshader`)
- **Depends on**: TASK-189
- **Sections**: ARCHITECTURE "Real-scale vegetation"; ADR 0026, ADR 0027; look reference (TASK-190)
- **Model**: opus (baked normals, matching the full trees' shading)
- **Tags**: battle-look

## Goal

Distant forest is lit like the near trees: sunlit crowns bright on the sun side, slopes and the far sides of crowns in shade – instead of the impostors' baked, fixed light and the shell's own dome shading.

## Acceptance criteria (testable)

- [ ] The impostor atlas bakes albedo (unlit) and a normal map per view (two atlas textures, same layout); `tree_impostor.gdshader` is lit (not `unshaded`) with the baked normal turned to the view, so the scene's sun and ambient light it.
- [ ] A full tree and its impostor at the hand-over distance differ by ≤ 10 % in mean luminance in a screenshot crop (sun side and shade side).
- [ ] The canopy shell takes its colour from the unlit atlas mean and its dome normals from the same sun; it meets the impostors without a tone step at the hand-over (screenshot).
- [ ] Forest on a slope facing away from the sun is visibly darker than on a slope facing it (screenshot).
- [ ] Frame time on Suwałki at 1.2 / 5 / 24 ≤ 16.7 ms on the RX 580 (`true`, HIGH, 720p).

## Playtest (for the human)

1. `true` preset, Suwałki: orbit the camera around a forest – the sun side is bright, the far side dark, at every distance.
2. Zoom in and out across the full-tree / impostor / canopy distances: no change in brightness.

## Player manual

None (look only).

## Out of scope

- Impostors casting shadows on the terrain (a later task if needed).

## Implementation notes

_Filled in by the agent when done._

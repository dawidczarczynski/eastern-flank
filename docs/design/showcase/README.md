# Model detail study (2026-10-21)

How far the procedural approach (GDScript primitives, no textures) goes when detail is the only goal. Reference material for TASK-062 (surface wear), TASK-067 (infantry v3) and future `/model-unit` runs; nothing here is loaded by the game.

| File | What it is |
|---|---|
| `m1a2_showcase.gd.txt` | M1A2 SEPv3 study after the cuts: ~32 600 triangles, ~320 ms cold build. Own mesh kit (`Kit`: chamfered box, lathe with edge flags, superellipsoid `pillow`, `plate` with chamfered rims, `tube`, `bolt`). |
| `infantry_showcase.gd.txt` | Infantry squad study: smooth swept bodies (`sweep` with elliptic sections), soft gear, chamfered weapons; ~25 400 triangles (no hidden stand poses), ~150 ms cold build. |
| `showcase_paint.gdshader.txt` | Weathering paint: hard-edged three-tone camo, wear on chamfers (vertex colour R), cavity darkening (G), per-part tint (B), dust on up-facing faces, streaks, mud, fade. |
| `m1a2_max_hero.jpg`, `m1a2_max_rear.jpg` | Maximum version (~104 000 triangles). |
| `m1a2_cut_hero.jpg` | After removing what the camera never sees (tracks behind the skirts, inner wheel halves, hidden suspension) – visually the same. |
| `infantry_current_close.jpg`, `infantry_close.jpg` | Current squad (before TASK-068) vs. the study. |

To run a study again: rename to `.gd` / `.gdshader`, put the model in `src/presentation/models/` and the shader in `assets/shaders/showcase_paint.gdshader`, then `tools/render_unit.sh <id>` (remove them again – the contract test checks every model file).

Findings:

- What removes the "toy" look: chamfers on every part, many small parts (bolts, hinges, handles, cables, rails), soft shapes for cloth, and paint that looks used (camo with hard edges, wear, dust, mud).
- Hidden geometry is where triangles go: 75 % of the maximum M1A2 was tracks and running gear behind the skirts. Spend triangles where the camera looks.
- From the battle camera the difference is small (tank ~150 px, soldier ~40 px): silhouette, camo scale and contrast, large chamfers and poses matter; bolts, track shoes and faces only show in close-ups.
- The real cost is the GDScript build time, not the GPU (ADR 0010).
- Infantry hits a lower ceiling: organic shapes from primitives give a neat figurine, but no cloth folds or faces.

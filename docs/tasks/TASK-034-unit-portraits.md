# TASK-034: Unit portraits in the hover popup (rendered from the 3D model)

- **Status**: to playtest (revised 2026-10-22: real units per faction, faction camouflage, lighting v3; the detailed models exist, so this can go any time)
- **Layers**: presentation (`src/presentation/ui/unit_popup.gd`, a portrait renderer; camera framing maths tested in `tests/unit/`)
- **Depends on**: **TASK-021** (popup). The detailed models exist (six real units). Soft: TASK-062 / TASK-067 (portraits get better with them, nothing to change here), TASK-054 (if the HDRI sky is done, use it for the portrait's ambient). Reference: `docs/design/v2/game_screen.scene.js` lines 414–431 (`makePortraits`), `docs/design/v2/game_screen.template.html` lines 86–91, screenshots `docs/design/v2/shots/01-v2-units.jpg`, `02-v2-units.jpg`, `hover.jpg`.
- **Model**: sonnet

## Goal

The hover card shows a lit 3D portrait of the unit (its actual model in faction camouflage), like the design, so units are recognisable at a glance.

## Design → Godot

- **Renderer** `src/presentation/portrait_renderer.gd` (Node): one `SubViewport` 640 × 340 (own `World3D`, `transparent_bg = false`), rendered once per (unit type, owner) and cached as `ImageTexture` (`get_texture().get_image()` after the frame is drawn – use `RenderingServer.frame_post_draw` or `await` here, this is the presentation layer). Scene in the viewport, port of `makePortraits`:
  - background and fog `#3a3f35`, fog depth 2.2–6; environment from the battle environment (TASK-051 look: AgX, sky ambient/reflections; TASK-054 HDRI if done), ambient ~0.7 of the battle value; the portrait renders with the active graphics quality (TASK-050) – no SSIL/glow needed in the portrait.
  - `DirectionalLight3D` `#fff0d8` at `(1.2, 2.4, 1.6)` looking at the origin, shadows on.
  - ground disc radius 5, colour `#6b7150`, roughness 1, receives shadows.
  - model from `UnitModels.build(...)` for the unit's definition and its owner's faction (camouflage from the faction, TASK-038), `rotation.y = −0.6` (relative to the model's +X forward); turret / launcher at rest.
  - camera FOV 24°: from the model's AABB `size = aabb.size.length()`, `c = aabb center`: position `c + (size·0.82, size·0.4, size·1.02)`, look at `c − (0, 0.02, 0)`.
- **Popup**: a 170 px high portrait area under the header, background `#2a2e27`, `TextureRect` with `STRETCH_KEEP_ASPECT_COVERED`. Portraits are pre-rendered at battle start for every (unit definition, owner) pair present in the scenario (today 3 per faction, 6 in total) so the first hover has no hitch; while not ready, show the plain background.
- Update the TASK-021 placement test values if the card height changes (`h` is measured, the rule stays).

## Acceptance criteria (testable)

- [ ] Pure framing function `PortraitRenderer.camera_transform(aabb: AABB) -> Transform3D` (static) tested in `tests/unit/test_portrait_renderer.gd`: for `AABB((-0.5, 0, -0.25), (1, 0.5, 0.5))` the camera position equals `c + size·(0.82, 0.4, 1.02)` and its forward vector points at `c − (0, 0.02, 0)` (±1e-4).
- [ ] The cache returns the same `Texture2D` for repeated requests of the same (type, owner) and different ones per owner.
- [ ] The popup shows the portrait area for every unit type; `test_unit_popup_model.gd` still passes (the model may gain a `portrait_key`).
- [ ] Agent visual check: a screenshot with a scripted hover (TASK-021's `debug_select_and_hover`) shows the portrait; compare with `docs/design/v2/shots/hover.jpg`. If the screenshot tool can't capture the `SubViewport`, save one portrait to `.screenshots/portrait_*.png` and read it.

## Playtest (for the human)

1. Hover each of your units: the card shows a lit 3D view of the unit, angled from the front-right, with a soft shadow on a dark green ground and fog behind it.
2. Hover enemy units: their own (Russian) vehicles and squad in their faction's camouflage.
3. The first hover after the battle starts appears without a stutter.

## Out of scope

- Rank pips, unit names, designations, tags shown on the design's portrait card (GDD ideas: "Unit identity", "Experience ranks").
- Animated / rotating portraits.

## Implementation notes

- `PortraitRenderer` (src/presentation/portrait_renderer.gd): one SubViewport with its own World3D, one pair rendered per frame, cached as `ImageTexture` (same object per (definition, owner); blank background until `is_ready`). Pure helpers `camera_transform`, `key_of`, `visible_aabb` are tested in tests/unit/test_portrait_renderer.gd. All pairs of the scenario are queued at battle start.
- Ambient/tonemap values are literals copied from the battle environment (flat ambient colour at 0.7 x 0.65, as tools/render_unit.gd does), not read from the active look; the HDRI sky is not used in the portrait.
- Popup: 170 px portrait area (`set_portrait`), updated every frame so it appears when the render finishes.
- Debug: `SCREENSHOT_HOVER_UNIT=<id>` (tools/screenshot.gd, `debug_hover_unit`) hovers a unit and shows its card; checked with tools/screenshot.sh (M1A2 portrait visible, Polish camouflage).
- Unrelated: docs/tasks/TASK-069 was already untracked in the tree.

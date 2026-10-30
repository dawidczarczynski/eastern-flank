# TASK-084: In-game unit catalog (main menu + model viewer)

- **Status**: done
- **Layers**: presentation (new menu scene and viewer scene, `project.godot` main scene), tests
- **Depends on**: – (soft: TASK-023 localization is done and used for the strings; TASK-045 deploy step is done; TASK-047 `turret_traverse` adds its animation to the list when it lands)
- **Model**: sonnet
- **Topic**: Visual design v2 and real units

## Goal

The game starts in a main menu with **Start operation**, **Language** and **Unit catalog**. The catalog lets the player browse every unit in the game, look at its model from any side, zoom in and play the animations the unit has – the same ones the battle uses.

## Design

- **Main menu** (`scenes/ui/main_menu.tscn`, becomes `run/main_scene`; built mostly in code per CLAUDE.md): three buttons.
  - *Start operation* → loads `scenes/battle/battle.tscn` (today's start, unchanged).
  - *Language* → switches between the available locales (en, pl from TASK-023) with `TranslationServer.set_locale`, stored in the user settings (file under `user://`), applied at start; the menu re-translates immediately.
  - *Unit catalog* → loads the viewer scene. A *Back* / `Esc` returns to the previous screen.
  - Later menu entries (load game, options) are out of scope; the layout leaves room for them.
- **Viewer** (`scenes/ui/unit_catalog.tscn`):
  - Left list of all units from the unit definitions (`data/units/*.tres`, grouped by class), the selected one shown on a plain ground disc (1 m model-space grid optional) with the battle's lighting (same environment as `tools/render_unit.sh`).
  - If a unit has models for several factions (operators), a faction switcher; the model is built through `UnitModels.build(id, 0, faction)` – the same path as the battle, no separate model code.
  - **Orbit camera**: drag with LMB rotates around the unit (yaw, limited pitch), mouse wheel zooms (limits from the model's AABB so a squad and a Homar-K both fill the view), double click / `Home` resets. Optional auto-rotate toggle.
  - **Animation buttons**, built from the model's declared mechanisms (`UnitModels.mechanisms(model)`), so each unit shows only what it has: *Drive* (wheels / tracks spin, `pose_tank` with a running distance; squads: march bob), *Deploy* (jacks and shields, `pose_deployables` 0 ↔ 1), *Raise launcher* and *Traverse* (`pose_launcher`, eased like the battle sequence), *Fire* (the full volley sequence: deploy → raise → traverse → `RocketVolley` flashes into a dummy target → back), *Hit* and *Death* (`UnitView.play_hit` / `play_death`, with a *Reset* that rebuilds the model), squads: *Kneel / stand*. Buttons for planned mechanisms (`turret_traverse`, `gun_recoil`) appear when their TASKs implement them – the list is data-driven by a table `mechanism id → animation entries`, not hard-coded per unit.
  - Unit facts next to the model (name, class, stats from the definition, real dimensions and notes from the catalog text if available through the unit definition) – only what is already in `data/`; the game never reads `docs/`.
- **Reuse, not copy**: the animation steps use the same tween helpers as `battle_controller.gd` (`_tween_launcher`, `_tween_deploy`, `DEPLOY_DURATION` …). Move the helper(s) that both need into a small presentation class (e.g. `VolleyPlayback`) rather than duplicating them; the battle keeps its behaviour. The viewer holds no game rules and no `GameState` (a `UnitView` can be built stand-alone, as in the screenshot tools).
- Performance: a single model, so the viewer must hold 60 FPS easily; the focused-window frame pacing (`FramePacing`) applies here too.

## Acceptance criteria (testable)

- [x] `project.godot` main scene is the main menu; *Start operation* opens the battle exactly as today (the existing battle/`tools/screenshot.sh` flow still works, it may load the battle scene directly).
- [x] Language switch changes `TranslationServer.get_locale()` and the menu labels (en ↔ pl), persists in `user://` and is restored on the next start (a test with a temp settings path).
- [x] The catalog lists every unit definition in `data/units/` (test: count equals the number of `.tres` files) and builds each model without errors (test iterates all units and factions that have a model; placeholder model counts as a warning in the list, not a crash).
- [x] Animation table: for a model declaring `launcher` + `stabilisers`, the entries are *Deploy*, *Raise*, *Traverse*, *Fire*; a squad only *Drive/march* and *Kneel*; a tank without implemented turret traverse only *Drive* (pure function `CatalogAnimations.for_model(model) -> Array[...]`, unit-tested with the real Homar-K, Uragan, tank and infantry models).
- [x] Orbit camera maths (yaw wrap, pitch clamp, zoom clamp from AABB, reset) is a pure class with unit tests, like `camera_math.gd`.
- [x] Playing *Fire* leaves the model exactly in its built pose afterwards (jacks, shields, pod, traverse back at 0); *Reset* after *Death* restores a clean model.
- [x] `tools/check.sh` passes; a screenshot of the menu and of the catalog (Homar-K deployed) is rendered with `tools/screenshot.sh` options extended as needed and Read.

## Playtest (for the human)

1. Start the game: the menu shows Start operation, Language, Unit catalog; Start operation opens the battle as before.
2. Language: switch to Polish and back; the labels change at once; restart – the choice is kept.
3. Catalog: click through all units; each is shown on the ground disc and fills the view sensibly.
4. Drag to rotate around a unit (all sides, also from above and the rear), wheel to zoom close to the Uragan cab and the Homar-K rear jacks.
5. Play the animations: Homar-K *Fire* (jacks, pod, salvo, stow), Uragan *Fire* (shields close over the glass), *Drive* on wheels and tracks, squad march, hit and death with reset.
6. Esc / Back returns to the menu; the battle still starts and plays normally afterwards.

## Player manual

Add a short "Main menu and unit catalog" section to docs/MANUAL.md (by `game-designer`): menu entries, language, catalog controls (rotate, zoom, animation buttons).

## Out of scope

- Load game / options / quit screens beyond leaving room in the layout; a full settings menu (graphics quality, audio).
- Editing units, showing real-unit research data from `docs/design/units/` (that stays in the `tools/unit_catalog.sh` web tool), other languages than the existing ones.
- Terrain, vegetation or lighting presets in the viewer.

## Implementation notes

- Main menu (`scenes/ui/main_menu.tscn`, now `run/main_scene`) and catalog (`scenes/ui/unit_catalog.tscn`); code in `src/presentation/ui/` and `src/presentation/catalog/` (`OrbitMath`, `CatalogAnimations`, `CatalogUnits`, `CatalogStage`). Language persisted by `GameSettings` in `user://settings.cfg`.
- `VolleyPlayback` (src/presentation/volley_playback.gd) holds the deploy/launcher/salvo tween helpers shared by the battle and the catalog; `UnitView.model()` was added as an accessor.
- Deviation: Homar-K and Uragan also get *Drive* (they declare `wheels`); a model with only `launcher` + `stabilisers` gets exactly Deploy, Raise, Traverse, Fire (tested).
- Screenshot tool: `SCREENSHOT_SCENE=menu|catalog`, `SCREENSHOT_LOCALE`, `SCREENSHOT_CATALOG=<unit>[:<anim>+..[:yaw,pitch,dist]]`; menu and catalog (Homar-K deployed) screenshots were rendered and read.
- Follow-up (playtested): Fire uses the battle's `SalvoFxPool` (backblast fire/smoke, plumes, trails, lights; impacts off via `effects_for_volley(with_lights, with_impacts=false)`) and shoots at a point `TARGET_DISTANCE` = 30 away, so the rockets leave the screen (no target post, framing = the model only); Drive raises the battle's dust and exhaust (`UnitView.drive_effects`).
- Not verified: input feel, FPS, Uragan shields closing, and that the battle volley (Homar-K/Uragan) plays as before after the refactor. Hit animation has no recovery test.

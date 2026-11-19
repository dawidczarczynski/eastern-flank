# TASK-186b: Devtools: look / performance switches and arena unit editor

- **Status**: done
- **Layers**: presentation
- **Depends on**: TASK-186a
- **Sections**: docs/TOOLS.md
- **Model**: sonnet

## Goal

The developer flips quality, unit scale, colour look, grid, FPS overlay and camera limits live (arena panel and DEVTOOLS page), and edits the selected arena unit's HP, moves and flags. No GDD change (developer tool). Uses the `DevTunables` store from TASK-186a (session only, no disk saving).

## Acceptance criteria (testable)

- [ ] Switches stored in `DevTunables` (defaults = today's behaviour, tested): graphics quality override (Auto / LOW / HIGH; Auto = current `--quality=` or default), `VisualScale` preset (current / true size), `LookPreset` (all 4 looks), grid (on), FPS overlay (off), unlock camera distance (off). Overrides honoured only while `DevTunables.active`.
- [ ] Quality, scale and look changes apply live to the arena map view (rebuilt or re-tinted without leaving the scene); no override leaves the real battle unchanged (test with `active = false`).
- [ ] Grid toggle hides / shows the hex grid overlay in the arena.
- [ ] FPS overlay: a corner label "NN FPS  X.X ms" updated at most 4 times per second from `Engine.get_frames_per_second()` and the frame time; no draw call stats. Toggle in the arena panel and on the DEVTOOLS page; the state is shared via the store.
- [ ] Unlock camera distance: with it on, the camera's min distance is halved and the max doubled (values recorded in the notes); off restores the originals. Test: the limits are read from the store.
- [ ] DEVTOOLS page gets the same switches where they make sense (quality, scale, look, FPS overlay); the page stays English only and uses existing menu plates; without `--debug` the menu is unchanged.
- [ ] Unit editor in the arena panel for the selected unit: HP spin (1..max HP), moves spin (0..max moves), dug-in and ambush check boxes. Edits go directly to the state like Place / Remove (bench only, not recorded). Test: set HP 3 -> unit HP 3; values clamped to range; no selection -> editor disabled.
- [ ] After an edit the HP bar / flags in the view refresh (event or explicit refresh, as Place / Remove do).

## Playtest (for the human)

1. Arena: switch quality LOW / HIGH and look presets; units and ground change at once.
2. Turn the grid off and on; turn the FPS overlay on in the arena and on the DEVTOOLS page: FPS and ms in a corner.
3. Unlock camera distance: zoom further in and out than before; turn it off: limits are back.
4. Select a tank, set HP 2 and moves 0, tick dug-in: the bar and move allowance match; Fire at it to see it die.
5. Start a normal battle from the menu: nothing changed from the overrides.

## Player manual

none (developer tool).

## Out of scope

- Terrain brush and map size (dropped from the first version; possible future task).
- Draw call / memory statistics in the FPS overlay.
- Future tasks (candidates from the 2026-11-19 analysis):
  - **C. Battle bench**: scenario + seed picker (`Scenario.NAMES`, `contact_battle`), faction pair; watch AI vs AI (x1 / x4 / skip), pause / step one event, god mode, reveal all, force end turn / win, command point and fire support refill, damage forecast dump; replay a saved `MatchRecord`.
  - **D. Operational bench**: open the staff map as NATO or Russia; buttons for the `--debug` keys (F9 politics / contact panels, F10 quick contact), jump to a formation, skip turns, give supply / fuel, reveal recon, trigger a strike.
  - **E. Launched tools**: unit catalog, screenshot of the current scene to `.screenshots/`, copy seed / scenario / camera as a `SCREENSHOT_*` command line.
- Saving tunables to disk; changing game rules or balance data.

## Implementation notes

- `DevTunables` (src/presentation/dev_tunables.gd) got the switches: `quality_choice` (Auto / LOW / HIGH), `true_size`, `look_name`, `grid_on`, `fps_overlay`, `unlock_camera`, with readers `quality_override()`, `scale_preset()`, `look_preset()`, `grid_enabled()`, `camera_min_distance()`, `camera_max_distance()` that return today's values while not `active`. `activate()` / `deactivate()` apply / restore the global `VisualScale` and `LookPreset` (only when a non-default is stored).
- Camera: unlocking halves `CameraMath.MIN_DISTANCE` (7 -> 3.5) and doubles `MAX_DISTANCE` (46 -> 92); `CameraMath.zoom` and `CameraRig.set_view` read the limits from the store. Switching the unlock off does not pull an already far camera back until the next zoom.
- `BattleController._setup_graphics_quality` takes the store's override before `--quality=`.
- Live apply: `ArenaController.rebuild_view()` re-applies look / scale, re-runs the quality setup, rebuilds the `MapView` and recreates the unit views (units, HP and camera stay; selection is dropped). Not re-created: the salvo FX pool and muzzle flash keep the quality they were built with (their particle switch changes on the next arena entry).
- Panel: *View* section (quality, scale, look pickers; grid, FPS overlay, unlock camera boxes) and *Selected unit* editor (HP / moves spin boxes, dug-in / ambush boxes; disabled without a selection; edits go to the state directly like Place, then `UnitView.refresh_label` + HUD refresh). `MapView.set_grid_auto` added.
- `FpsOverlay` (src/presentation/fps_overlay.gd): "NN FPS  X.X ms" top right, real-time refresh every 250 ms, visible while `DevTunables.fps_overlay`; added to the arena and, in a `--debug` run, to the main menu. DEVTOOLS page: four plates (quality, scale, look, FPS overlay) that cycle the store; they count once the arena opens.
- Tests: `tests/unit/test_dev_switches.gd`. Not verified in a running window (headless cannot draw): rebuild in place, panel layout, the menu overlay.

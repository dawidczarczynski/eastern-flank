# TASK-065: Wrecks and smoke – destroyed vehicles stay as burning hulks instead of vanishing

- **Status**: done (persistence rules are a proposed **[ASSUMPTION]**, see below)
- **Layers**: presentation (`WreckView`, death playback in `UnitView`/battle view, camo shader `burnt` parameter, particles), tests
- **Depends on**: **TASK-050** (`particles`), TASK-008 (event queue, done); soft **TASK-064** (shared particle/smoke textures), soft **TASK-058** (scorch decal under the wreck), soft **TASK-062** (burnt look on the worn shader)
- **Model**: sonnet

## Goal

When a vehicle is destroyed, the player sees it: a flash, the hulk turns black and burnt, the turret is knocked askew, and a column of smoke rises for a while. The battlefield fills with the traces of the fight.

## Current state

On `unit_died` the unit darkens (`DIE_DARKEN_DURATION` 0.25 s) and fades out (`DEATH_DURATION` 0.85 s total), then the view is removed.

## Open questions / decision needed (human)

- **Persistence [ASSUMPTION]**: wrecks stay for the whole battle; a wreck is **hidden** (fades out over 0.5 s) when a living unit ends a move on its tile, so it never overlaps a unit; the smoke column stops after **3** `turn_started` events after the death. Alternatives: wrecks disappear after N turns; wrecks never hide (units drive through them).
- **Infantry**: no wreck (proposed) – the squad fades as today and leaves only the scorch mark (TASK-058). Alternative: fallen soldiers (tone/rating question).
- Wrecks are **pure scenery**: they don't block movement, give no cover and can't be selected. If wrecks should ever give cover, that is a rule change in core (a new task for game-designer).

## Design

- **Death playback** (same total duration `EventQueue.DEATH_DURATION`, no change to the event queue timing):
  0.00 s flash (OmniLight `#ffb060`, energy 6 → 0 over 0.25 s, range 2.5) + a burst of 20 fire/smoke particles;
  0.00–0.40 s camo shader `burnt` 0 → 1 (albedo → `#1d1b19` with noisy rusty-brown patches `#4a2e1e`, roughness 0.95, metallic 0.05, camo pattern faintly visible at 10 %);
  0.10–0.40 s if the model has a `Turret` pivot: turret yaw +20…35°, tilt 6…10° and lifted 0.01 (deterministic from the unit id hash); launcher pods (`Pod`) drop to their stowed pose.
  Then the unit's label, base marker, hover popup and picking are removed (the `UnitView` leaves the units dictionary at the same moment as today) and a `WreckView` owns the hulk mesh.
- **Smoke**: `GPUParticles3D` column at the hull centre (HIGH; LOW: none), dark grey `#2b2a28` → light `#6b6965`, lifetime 4 s, rising 0.6 u/s to ≈ 3 units, drifting with the wind uniform; after the first turn rate halves (thin smoke); small flickering fire light (energy 0.8 ± 0.4, 6 s) only during the first turn.
- **WreckView**: not pickable (no collision, not in the hover/raycast set), excluded from `UnitView` queries; hidden when a living unit's `unit_moved` ends on its tile (fade 0.5 s); smoke stops after 3 `turn_started` events.

## Acceptance criteria (testable)

- [ ] `test_wreck_view.gd` (headless, with a fixture battle view):
  - after playing `unit_died` for a tank: no `UnitView` with that id remains; one `WreckView` at the unit's tile with the burnt shader parameter == 1 and the turret pivot rotated by 20–35° yaw relative to before; deterministic for the same unit id;
  - the total death playback duration equals `EventQueue.DEATH_DURATION` (unchanged);
  - hover/picking at the wreck's tile returns no unit (popup stays hidden);
  - after a `unit_moved` ending on that tile the wreck becomes hidden; a move passing through but ending elsewhere leaves it visible;
  - after 3 `turn_started` events the smoke emitter has `emitting == false`;
  - infantry death leaves no `WreckView`;
  - with `particles = false` no particle nodes are created, the wreck still appears.
- [ ] `camo.gdshader` has `burnt` (float, default 0).
- [ ] Agent visual check (Windows build): a scripted kill in the screenshot hook shows a black hulk with a tilted turret and a smoke column; the HUD unit count drops as before.
- [ ] Re-render `docs/images/gameplay.png` with `tools/readme_screenshot.sh`, Read it (default shot has no deaths – unchanged), commit only if changed.

## Playtest (for the human)

1. Destroy an enemy tank: flash, the tank turns black, its turret twists, smoke rises; its tag and hover card disappear.
2. Hover the wreck: no unit card; clicking it does nothing (or moves your selected unit there if reachable).
3. Move one of your units onto the wreck's tile: the wreck fades away as your unit arrives.
4. End turns: the smoke thins after one turn and stops after three.
5. Destroy infantry: no wreck, a scorched patch only (if TASK-058 is done).
6. Does a smoking wreck ever get confused with a live unit at default zoom? Report it.

## Player manual

Section on combat / units dying: "A destroyed vehicle leaves a burning wreck. Wrecks are only scenery: they don't block movement, give no cover and disappear when a unit moves onto their tile." (Adjust to the human's persistence decision.)

## Out of scope

- Wrecks giving cover or blocking (rule change), secondary explosions, ammo cook-off, crew bailing out, damage states before death.

## Implementation notes

- Persistence implemented as the proposed assumption (wrecks stay, hide on a move ending on their tile, smoke stops after 3 `turn_started` events – each player's turn start counts; infantry leaves no wreck). Not yet confirmed by the human.
- New: `WreckPlan` (pure timeline/turret offsets from unit-id hash), `WreckLife` (pure smoke/hide counters), `WreckView`, `WreckField` (owner, wired in `BattleController`); `UnitView.play_death(on_wreck)`; `burnt` is an instance uniform in `camo.gdshader`. `DEATH_DURATION` unchanged.
- Tests: `tests/unit/test_wreck_view.gd` (11). Known gaps: hover/picking and controller wiring are covered only indirectly.
- Screenshot hook `SCREENSHOT_WRECK=<unit id>` in `tools/screenshot.*` (HIGH, Windows build): dark rusty hulk with smoke column seen; close-up of hull/turret, smoke density and the live tween/fade not seen. Default README shot has no deaths.
- Playtest additions (human request): vehicles stand on a wide black burnt-ground decal (`GroundMarks.wreck_burnt`, `DecalTextures.burnt_ground`, radius 0.95); `GrassField.add_clearing` removes grass/flowers there; `BurntGround` hides bushes/trees/undergrowth and soots rocks inside the circle. Playtested by the human, done.

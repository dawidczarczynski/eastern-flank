# TASK-123: Sound – UI clicks, gunshots per unit, explosions, engines, tracks, forest ambience

- **Status**: done
- **Layers**: presentation (`AudioDirector` + pure `SoundPlanner`, buses, assets), data (sound ids on `UnitDefinition`), tests. Roles: **presentation-engineer**; core only gets data fields.
- **Depends on**: – (soft: TASK-064 move effects, TASK-048 recoil, TASK-075 salvo effects – sounds hook into the same playback moments)
- **Sections**: ARCHITECTURE "Events" (view-only annotations `view_fx`), ADR 0011 (third-party assets and `credits.json`)
- **Model**: sonnet

## Goal

The battle sounds like a battle: buttons click, every unit type fires with its own sound, shells explode, vehicles rumble and clank while moving, and a zoomed-in forest is full of birdsong.

## Design

- `assets/audio/sfx/` and `assets/audio/music/` exist and are empty; third-party files go to `assets/third_party/audio/`, each credited in `assets/third_party/credits.json` (`"kind": "audio"`, licence, source URL; `test_third_party_assets.gd` must pass). **Only CC0 files** (no attribution needed). CC-BY files only if the credit is also shown in the game's credits screen – prefer CC0 and say in the notes if an item had to be synthesised or left as a placeholder.
- Audio is presentation only: a single `AudioDirector` (Node under the battle scene) listens to the same playback moments as the animation queue (`EventQueue` events + `view_fx`), never to `GameSimulation` directly and never changing state. Which sound plays for which event / unit / camera state is decided in a pure, testable `SoundPlanner` (RefCounted, no `AudioStreamPlayer`).
- Buses `Master` → `SFX`, `UI`, `Ambient` (created in code or `default_bus_layout.tres`); volume sliders in the existing settings (`GameSettings`) – at least Master and Ambient mute/volume, persisted like the other settings.
- Variation: each sound id maps to 2–4 variants (`AudioStreamRandomizer` with pitch ±5 %, volume ±1 dB) so repeated shots don't sound mechanical. Randomness for the view only – never `GameState.rng`.
- Sound ids as data on `UnitDefinition` (rule 5): `fire_sound` (e.g. `tank_cannon`, `rifle`, `mlrs_rocket`), `engine_sound` (`diesel_heavy`, `diesel_light`, `none` for infantry), `move_sound` (`tracks`, `wheels`, `footsteps`). A sound id → stream list table is a resource (`data/audio/sound_bank.tres`, class in `src/core/data/` or `src/presentation/`), not constants in code.
- Playback limits (performance and ears): max ~16 simultaneous one-shots (steal the oldest/quietest), 3D positional (`AudioStreamPlayer3D`, distance attenuation tuned to the battle camera) for in-world sounds, plain `AudioStreamPlayer` for UI. Loops start/stop with `unit_moved` playback; no per-frame allocation.

## Sounds and where to look for them (all to be verified per file before download – licences on OpenGameArt/Freesound are per file)

| need | candidate source | licence |
|---|---|---|
| UI clicks, hovers, switches | Kenney "Interface Sounds" (kenney.nl/assets/interface-sounds) or "UI Audio" – 100 / 50 OGG files | CC0 |
| rifle / machine gun shots | OpenGameArt "The Free Firearm Sound Library" (opengameart.org/content/the-free-firearm-sound-library), "gunshots" (opengameart.org/content/gunshots) | CC0 |
| tank cannon, artillery, rocket launch, explosions | Kenney "Sci-Fi Sounds" (has explosions / launches, kenney.nl/assets/sci-fi-sounds) and "Impact Sounds"; search Freesound with the filter *Licence: CC0* for "tank cannon", "artillery", "explosion", "rocket launch"; itch.io "Tank shooter sound effects" (Sixdots Soft) only if its licence is stated as CC0 | CC0 (verify) |
| engine loops | OpenGameArt "racing car engine sound loops" (CC0, pitch-shifted variants → pitch down for diesel, heavy tank); "Engine-loop heavy vehicle/tank" by Nayckron is **CC-BY 3.0 / GPL 3.0 – not allowed** unless the human accepts attribution | CC0 only |
| tracks (clank / rattle loop) | none found as CC0 – search Freesound CC0 "tank tracks", "chain rattle", "metal clank loop"; fallback: layer a low-passed metal rattle with the engine loop | CC0 (verify) |
| forest ambience with birds | OpenGameArt "Forest Ambience" (TinyWorlds, seamless loop, opengameart.org/content/forest-ambience), "forest bird sounds" (10 clips, CC0, opengameart.org/content/forest-bird-sounds) for random one-shot chirps on top, "birds and wind ambient" (opengameart.org/node/93987) | CC0 |

## Acceptance criteria (testable)

- [ ] UI: every HUD button (end turn, menu, dialogs) plays a click on press, a soft hover tick on hover; selecting a unit and giving a move/attack order each have their own short cue. `SoundPlanner` unit test: UI event → sound id.
- [ ] Shots: a `unit_attacked` plays the attacker's `fire_sound` at the attacker's position when its `view_fx` fire moment arrives (not when the event is queued); different `UnitDefinition`s give different sound ids (tank ≠ infantry ≠ MLRS ≠ artillery); a salvo plays one launch sound per rocket (or a short stagger), not a single cue. Test: planner maps `T-72B3`, `pl_mech_infantry`, `homar_k` to three different ids.
- [ ] Explosions: the impact of a shell / rocket plays an explosion at the target hex (small for a hit, bigger for `unit_died`); a miss (`damage` 0) plays a weaker or no impact. Test: planner returns `explosion_large` for a death, `explosion_small` for a hit, none for a complete miss with direct fire.
- [ ] Engines: a moving vehicle with an `engine_sound` plays its loop from the start to the end of the `unit_moved` playback, pitch rising slightly at start and falling at stop (≤ 0.5 s ramp), positional; infantry has none. Two vehicles moving at once don't exceed the polyphony limit.
- [ ] Tracks: `move_sound = tracks` adds a clank/rattle loop for tracked units only (wheeled vehicles get a tyre/road hum, infantry footsteps or nothing), same start/stop as the engine.
- [ ] Forest ambience: when the camera is zoomed in (distance below a data threshold) over forest, a forest/bird loop fades in (≈ 1.5 s) and fades out when the camera zooms out or moves over non-forest terrain; random bird one-shots at random intervals on top. Pure test: `SoundPlanner.ambient_for(camera_distance, forest_fraction_under_camera)` returns the loop id and target volume (0 when zoomed out or < threshold forest). The forest fraction is read from the visible tiles around the camera focus (map data, cheap – computed on camera stop, not per frame).
- [ ] Sound bank: every sound id in `UnitDefinition` and the planner exists in `sound_bank.tres` with ≥ 1 stream (test fails on a missing id or a missing file); every audio file is in `credits.json` with a CC0 (or explicitly approved) licence.
- [ ] Settings: Master volume and a mute toggle work and persist; with volume 0 / mute no player is started. Headless tests and `tools/simulate.sh` run without an audio device (the director is only built in the presentation scene; dummy audio driver is fine).
- [ ] Performance: no frame-time regression in `tools/screenshot.sh`-style benchmarks of the battle scene (60 FPS budget); one-shots are pooled players, not instanced per shot.
- [ ] `tools/check.sh` passes.

## Playtest (for the human)

1. Start a battle with sound on: click buttons and select/move units – hear clicks and cues.
2. Attack with a tank, infantry and (if present) MLRS/artillery – each sounds different; shells explode at the target, a destroyed unit gets a bigger explosion.
3. Move a tank: engine and track clank for the whole move, ending when it stops; move infantry: no engine.
4. Zoom the camera close over a forest: birds fade in; zoom out or pan to a plain: they fade out.
5. Lower Master volume / mute in settings; restart the game – the setting stays.
6. Check the mix: nothing clips with several units firing at once; the idle game stays quiet (also in a background window – see `FramePacing`).

## Player manual

Add a short "Sound" section to docs/MANUAL.md: volume and mute settings, what the ambient forest sound means (camera zoom over forest).

## Out of scope

- Music / soundtrack (`assets/audio/music/` stays empty).
- Voice lines, unit acknowledgements.
- Operational-layer (staff map) sounds – can reuse the UI bus in a later task.
- Dynamic mixing by combat intensity, reverb zones, occlusion by terrain.
- Distinct sounds per individual weapon calibre beyond the sound ids already on the unit definitions.

## Implementation notes

Done (not yet playtested by the human).

- **Core data**: `UnitDefinition.fire_sound / engine_sound / move_sound` (units: tanks `tank_cannon` + `diesel_heavy` + `tracks`, MLRS `mlrs_rocket` + `diesel_light` + `wheels`, Polish squad `rifle`, Russian squad `rifle_ak`, infantry engine/move `none`); `SoundBank` resource class (`src/core/data/sound_bank.gd`) and `data/audio/sound_bank.tres` (id -> variants, base pitch, gain, loop, ambient thresholds `ambient_max_distance` 14 / `ambient_min_forest` 0.3 / `ambient_fade` 1.5, polyphony 16 one-shots + 8 loops).
- **Presentation** (`src/presentation/audio/`): pure `SoundPlanner` (UI action -> id, fire id, impact rule, move loops, loop ramp envelope, `ambient_for`, `forest_fraction`), `SoundMix` (buses Master -> SFX / UI / Ambient, mute and volume), `AudioDirector` (pooled `AudioStreamPlayer3D`, steal-oldest, movement loops that follow the unit, forest loop + random bird chirps, ambient re-evaluated only after the camera stopped for 0.25 s), `AudioSalvoEffects` (one launch sound per rocket, impact on every third rocket and the last). `BattleController` hooks: HUD end-turn button click/hover, select / move / attack order cues (also the ring's ATTACK), error cue for a rejected human order, shot + delayed impact at the hit step, salvo hooks, loops for the `unit_moved` tween, `explosion_large` when `unit_died` plays. Settings: `GameSettings.load_sound / save_sound`; main menu has a Sound on/off button and Master / Ambient sliders. Added a `end_button()` accessor to `BattleHud` and an `attack_ordered` signal to `TargetRingController`.
- **Assets** (all CC0, ~4 MB, listed in `assets/third_party/credits.json`, kind `audio`; ADR 0011 amended): Kenney "Interface Sounds" (UI), rubberduck "25 CC0 bang / firework SFX" (tank cannon), rubberduck "100 CC0 SFX" (explosion), Thimras "Battle at sea" (cannon fire layer, explosions), "The Free Firearm Sound Library" (rifle shots, trimmed and downmixed), qubodup "Rocket launch" (trimmed), domasx "racing car engine sound loops" (engines, pitched down in the bank), TinyWorlds "Forest Ambience" (mp3), pauliuw "forest bird sounds" (8 kHz clips).
- **Synthesised / placeholders**: the track clank loop and the wheel hum loop (`tools/gen_move_loops.py` -> `assets/audio/sfx/*.wav`; no CC0 recording found). Footsteps for infantry: not done (the planner ignores `footsteps`; infantry has `move_sound = none`). The engine loops are racing-car loops pitched down, not real diesels; bird clips are only 8 kHz. All of it is untuned by ear (the agent cannot listen): levels (`gain_db` in the bank) and attenuation (`AudioDirector.UNIT_SIZE`) need a playtest.
- **Not covered**: sounds on the operational map, hover sounds on the main menu buttons (the menu has no director), hover ticks for the radial ring.
- **Tests**: `test_sound_planner`, `test_sound_bank` (ids, files, credits), `test_sound_settings` (persistence, silent director, pools), `test_main_menu` (sound controls), `test_third_party_assets` accepts kind `audio`.
- **Screenshot**: the battle scene is unchanged (the only UI change is in the main menu).

**Playtest round 1 fixes**: map cues (select / move / attack / error) are now Kenney ticks and clicks (<= 0.1 s) at -19..-26 dB with different pitches; every button / toggle / slider of the main menu and unit catalog clicks and ticks (`AudioDirector.hook_tree`). Tank / MLRS movement: the racing-car loops and the first synthetic clank were replaced by synthesised 8 s seamless loops (diesel firing pulses over a low-passed rumble, low track thuds with irregular spacing, tyre hum), gains -14..-18 dB, ramp pitch 0.94 -> 1. Rocket launch: the qubodup recording was replaced by a synthesised 1.4 s ignition thump + decaying hiss at -9 dB, rockets staggered by 0..0.1 s. Everything above (engines, tracks, wheels, rocket) is synthesised (`tools/gen_move_loops.py`), the removed CC0 files (domasx engine loops, qubodup rocket launch, unused Kenney files) are gone from credits.json. Untested by ear.

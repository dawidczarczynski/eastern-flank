# Backlog

Statuses: 💡 `idea` → 🟢 `ready` (specified, with criteria) → 🟡 `in progress` → 🟣 `to playtest` → 🔵 `done`; also 🔴 `blocked` (below) and ⚪ `merged`. Write the status as plain text – `tools/backlog.py --fix` adds the icon.

`blocked` = specified like `ready`, but a hard dependency is not `done` yet. It switches to `ready` as soon as every hard dependency is `done` (and back to `blocked` if a new unfinished hard dependency is added). Hard dependencies are the task IDs in the "Depends on" column before the first `soft`, `(` or `;` – keep soft ones under `soft:`. `tools/backlog.py --fix` applies the rule to this table and the task files' Status lines; `tools/check.sh` fails while they are out of date.

Rows after TASK-001 are in priority order (top = next to implement).

| ID | Title | Status | Depends on |
|---|---|---|---|
| TASK-000 | Skeleton: hex map, movement, turns, simple AI, camera | 🔵 done | – |
| [TASK-001](TASK-001-combat.md) | Basic melee combat | 🔵 done | – |
| [TASK-006](TASK-006-screenshot-script.md) | Screenshot script for agents (`tools/screenshot.sh`) | 🔵 done | – |
| [TASK-008](TASK-008-event-animation-queue.md) | Sequential event animation playback | 🔵 done | TASK-001 |
| [TASK-009](TASK-009-attackable-highlight.md) | Highlight attackable enemies (`AttackCommand.valid_targets`) | 🔵 done | TASK-001 |
| [TASK-004](TASK-004-path-preview.md) | Movement path preview on hover (`HexGrid.path_to`) | 🔵 done | – |
| [TASK-003](TASK-003-unit-info-panel.md) | Info panel for the selected unit | 🔵 done | TASK-001 |
| [TASK-013](TASK-013-lighting-atmosphere.md) | Lighting & atmosphere like the design (fog, ACES, sun, ambient) | 🔵 done | – |
| [TASK-014](TASK-014-ui-theme.md) | UI theme: IBM Plex fonts, palette, panel styles (`HudTheme`) | 🔵 done | – |
| [TASK-023](TASK-023-localization.md) | Localization setup: CSV en + pl, `tr()` for HUD strings | 🔵 done | – (before the HUD tasks) |
| [TASK-015](TASK-015-camera.md) | Camera like the design: drag-pan, RMB rotate, pitch by distance, map clamp | 🔵 done | – (soft: TASK-023) |
| [TASK-002](TASK-002-terrain-resources.md) | Terrain types as `.tres` resources with a defense bonus | 🔵 done | TASK-001 |
| [TASK-016a](TASK-016a-terrain-elevation.md) | Deterministic terrain elevation in core (`TerrainField`, `TerrainSurface`) | 🔵 done | – (after TASK-002 recommended) |
| [TASK-016b](TASK-016b-terrain-mesh.md) | Continuous terrain mesh, water plane, grid lines, surface picking | 🔵 done | **TASK-016a** (soft: TASK-013, TASK-015) |
| [TASK-017](TASK-017-map-overlays.md) | Map overlays: reach wash + rings, pulsing hover ring, path dots | 🔵 done | **TASK-016b**, TASK-014 (soft: TASK-009) |
| [TASK-019](TASK-019-unit-models.md) | Unit models from primitives, faction markers, unit labels (+ upright check) | 🔵 done | **TASK-016b**, **TASK-017**, TASK-014 (soft: TASK-008, TASK-009) |
| [TASK-022](TASK-022-movement-animation.md) | Unit movement along the path with turning (0.26 s/tile) | 🔵 done | **TASK-008**, TASK-016b, TASK-019 |
| [TASK-025](TASK-025-unit-locomotion.md) | Unit locomotion: marching soldiers (step bob, kneelers stand), tank wheels + slope tilt | 🔵 done | **TASK-022**, TASK-019 (soft: TASK-008, TASK-016b) |
| [TASK-018](TASK-018-scatter.md) | Scatter: trees and rocks (MultiMesh, view-local RNG) | 🔵 done | **TASK-016b** |
| [TASK-020](TASK-020-hud-layout.md) | HUD layout: turn bar, end-turn button, controls hint, turn banner | 🔵 done | **TASK-014**, TASK-023, TASK-015 (soft: TASK-008, TASK-019) |
| [TASK-024](TASK-024-terrain-panel.md) | Terrain panel (bottom-left) with path cost, replaces the path `Label3D` | 🔵 done | **TASK-014**, **TASK-016a**, TASK-017, TASK-023 (soft: TASK-002) |
| [TASK-021](TASK-021-unit-hover-popup.md) | Unit hover popup (replaces the TASK-003 panel) | 🔵 done | **TASK-014**, TASK-019, TASK-023 (soft: TASK-024, TASK-002) |
| [TASK-010](TASK-010-counterattack.md) | Counterattack | 🔵 done | TASK-001 (soft: TASK-002) |
| [TASK-011](TASK-011-rocket-artillery.md) | Ranged unit (rocket artillery) + starting setup in core (`Scenario`) | 🔵 done | **TASK-010** |
| [TASK-005](TASK-005-replay.md) | Save/replay a match as seed + command list | 🔵 done | `Scenario` from TASK-011 (or extract it here) |
| [TASK-012](TASK-012-ai-simulation.md) | Headless AI-vs-AI simulation (`tools/simulate.sh`) | 🔵 done | `Scenario` from TASK-011/TASK-005 |
| [TASK-026](TASK-026-lighting-ibl.md) | Lighting v2: sky as ambient/reflection source, SSAO | 🔵 done | TASK-013 |
| [TASK-027](TASK-027-terrain-detail.md) | Terrain detail: tileable detail texture + normal map, denser mesh, macro colour, water normals | 🔵 done | TASK-016b (soft: TASK-026) |
| [TASK-028](TASK-028-foliage.md) | Foliage v2: lobed crowns with baked AO, bush layer, better rocks | 🔵 done | TASK-018 (soft: TASK-026, TASK-027) |
| [TASK-029](TASK-029-camo-pbr-materials.md) | Unit materials: procedural camouflage shader, PBR palette | 🔵 done | TASK-019 (soft: TASK-026) |
| [TASK-030](TASK-030-mesh-kit.md) | Mesh kit v2 from the model study: chamfers with edge flags, pillow, sweep, tube, plate; RGB vertex masks (rewritten 2026-10-22) | 🔵 done | – (reference `docs/design/showcase/`) |
| [TASK-037](TASK-037-unit-catalog-tool.md) | Unit catalog: local web tool for unit references (`tools/unit_catalog.sh`) | 🔵 done | – |
| [TASK-038](TASK-038-factions-as-data.md) | Factions as data: `FactionDefinition`, player → faction, HUD/colours from the faction | 🔵 done | – (soft: TASK-005, TASK-020) |
| [TASK-040](TASK-040-catalog-ai-research.md) | Unit catalog: AI research (`/research-unit`) verified in the form; agent jobs from the UI | 🔵 done | TASK-037 (soft: TASK-036) |
| [TASK-036](TASK-036-unit-model-pipeline.md) | Unit model pipeline: model per unit, faction camo, `tools/render_unit.sh`, contract test, `/model-unit` | 🔵 done | **TASK-029**, **TASK-038** (soft: TASK-037); done without the original TASK-030 |
| [TASK-039a](TASK-039a-real-units-core.md) | Real units and countries: core, data, scenario, balance (Poland vs Russia) | 🔵 done | **TASK-038**, TASK-037 |
| [TASK-039b](TASK-039b-real-units-presentation.md) | Real units and countries: labels, popup, locomotion by class, translations, faction camo | 🔵 done | **TASK-039a** |
| [TASK-041](TASK-041-catalog-mechanisms.md) | Unit catalog: mechanisms registry (`mechanisms.json`), per-unit `mechanisms` with params, validation, research, readiness | 🔵 done | TASK-037, TASK-040 |
| [TASK-042](TASK-042-catalog-mechanisms-ui.md) | Unit catalog: edit mechanisms in the form; research + verify Uragan / Homar-K mechanisms | 🔵 done | **TASK-041** |
| [TASK-043](TASK-043-model-mechanisms-contract.md) | Models carry their mechanisms (`MECHANISMS` metadata), registry contract test, `/model-unit` passes them on; fills the empty catalog mechanisms of tanks and squads | 🟢 ready | **TASK-041**, TASK-042 |
| [TASK-044](TASK-044-launcher-parameters.md) | Launcher with parameters: traverse range (vehicle turns first), stowed direction (replaces the Uragan's `stowed_yaw` meta), elevation per unit | 🔴 blocked | **TASK-043** |
| [TASK-045](TASK-045-stabilisers.md) | Deploy step: `stabilisers` (jacks) + `blast_shields` (cab shields) before a volley; Homar-K jacks, Uragan rework (TASK-046 merged in) | 🔴 blocked | **TASK-044**, TASK-042 |
| [TASK-031](TASK-031-tank-model-v2.md) | First detailed tank (v2 design → real tank) + reusable tracked running gear – `unit-modeler` | 🔵 done (superseded by `/model-unit m1a2_sepv3`, `t72b3`) | – |
| [TASK-047](TASK-047-turret-traverse.md) | `turret_traverse`: turret turns and gun elevates before direct fire (also counters) | 🔴 blocked | **TASK-044**, **TASK-043** (tank models exist) |
| [TASK-032](TASK-032-infantry-model-v2.md) | First detailed infantry squad + parameterised soldier kit – `unit-modeler` | 🔵 done (superseded by `/model-unit pl_mech_infantry`, `ru_motor_rifle`; next: TASK-067) | – |
| [TASK-033](TASK-033-mlrs-model-v2.md) | First detailed rocket artillery + reusable truck/launcher parts – `unit-modeler` | 🔵 done (superseded by `/model-unit homar_k`, `bm27_uragan`) | – |
| [TASK-034](TASK-034-unit-portraits.md) | Unit portraits in the hover popup (`SubViewport`) | 🔵 done | **TASK-021** (soft: TASK-062, TASK-067, TASK-054) |
| [TASK-046](TASK-046-blast-shields.md) | `blast_shields`: cab window shields lowered before a volley (Uragan) | ⚪ merged into TASK-045 | – |
| [TASK-048](TASK-048-gun-recoil.md) | `gun_recoil`: barrel recoil + muzzle flash on direct fire | 💡 idea | **TASK-047**; look at 047 in game first |
| [TASK-049](TASK-049-overlay-readability.md) | Overlay readability: reach outline, dim outside, hover-only fill, faint fading grid (G toggle) | 🔵 done | – |
| [TASK-050](TASK-050-graphics-quality.md) | Graphics quality presets LOW/HIGH, auto-detected, `--quality=` override | 🔵 done | – |
| [TASK-051](TASK-051-lighting-atmosphere-v3.md) | Lighting & atmosphere v3: AgX, lower sun, aerial perspective, SSIL, subtle glow, colour-grading LUT | 🔵 done | soft: TASK-050 |
| [TASK-052](TASK-052-camera-horizon.md) | Camera v2: lower pitch with horizon, top-down when far, backdrop terrain beyond the map (generator-independent) | 🔵 done | soft: TASK-051, TASK-050 |
| [TASK-059](TASK-059-visual-scale-study.md) | Visual scale study: units vs. trees vs. hexes (screenshots for the human's decision) | 🔵 done | soft: TASK-052, TASK-051 |
| [TASK-053](TASK-053-third-party-assets.md) | Third-party CC0 assets: ADR, `assets/third_party/`, credits manifest + test | 🔵 done | – (decision (a) 2026-10-22: CC0 allowed – textures, HDRI, vegetation models; unit models stay procedural) |
| [TASK-054](TASK-054-hdri-sky.md) | HDRI sky (CC0 Poly Haven) as sky, ambient and reflections | 🔵 done | **TASK-053**, **TASK-051** |
| [TASK-055](TASK-055-terrain-splat-shader.md) | Terrain shader v3: blended CC0 PBR layers by terrain type + slope, triplanar, anti-tiling | 🔵 done | **TASK-053** (soft: TASK-050, TASK-051, TASK-052; related TASK-035) |
| [TASK-056](TASK-056-water-v2.md) | Water v2: depth colour, shore foam, scrolling ripples, SSR | 🔵 done | soft: TASK-050, TASK-054, TASK-055 |
| [TASK-057](TASK-057-grass-wind.md) | Grass: MultiMesh alpha cards, distance LOD, shared wind shader | 🔵 done | **TASK-050**, **TASK-059** (sizes from `VisualScale`) (soft: TASK-055, TASK-052) |
| [TASK-061](TASK-061-forest-edges.md) | Forest edges and undergrowth: shrub belts along borders, forest-floor cover | 🔵 done | **TASK-059** (soft: TASK-057, TASK-060) |
| [TASK-058](TASK-058-ground-decals.md) | Ground decals from events: track marks, craters, scorch | 🔵 done | soft: TASK-050, TASK-055, TASK-065 |
| [TASK-060](TASK-060-trees-v3.md) | Trees v3: leaf-card crowns, trunks/branches, wind, per-instance variation | 🔵 done | **TASK-059**, **TASK-057** (soft: TASK-030, TASK-050; TASK-053 done – optional CC0 bark/leaf textures) |
| [TASK-062](TASK-062-unit-surface-wear.md) | Unit surface v2: chamfers in the existing helpers, weathering paint on RGB masks (study shader) – presentation + `unit-modeler` | 🔵 done | **TASK-030** |
| [TASK-063](TASK-063-unit-markings.md) | Unit markings: national markings per faction, tactical numbers – presentation + `unit-modeler` | 🟢 ready | TASK-038, TASK-036 (soft: TASK-062; anchor pass shared with TASK-064); Russian marking default to confirm |
| [TASK-064](TASK-064-movement-dust-exhaust.md) | Movement effects: dust from tracks/wheels, exhaust smoke | 🔵 done | **TASK-050** (soft: TASK-058, TASK-055, TASK-059; anchor pass shared with TASK-063) |
| [TASK-065](TASK-065-wrecks-smoke.md) | Wrecks and smoke on destruction instead of vanishing | 🔵 done | **TASK-050** (soft: TASK-064 `ParticleFx`, TASK-058, TASK-062 – same shader, do 062 first); persistence to confirm |
| [TASK-074](TASK-074-mlrs-salvo-sequence.md) | Rocket salvo sequence: full ripple salvo (12 Homar-K / 16 Uragan, visible pauses), `SalvoTiming`, rockets along the tube on steep paths, seeded landings, pod twitch, HP steps per rocket, simple flashes, `SalvoEffects` hooks; salvos exempt from the AI-turn speed-up (max 1.5×) | 🟢 ready | **TASK-011**, **TASK-058** (soft: TASK-073 – works with today's `Mouth*` markers, fallback without; TASK-044 / TASK-045 – same `_play_volley`, rebase; TASK-048); salvo pacing to confirm |
| [TASK-075](TASK-075-mlrs-salvo-effects.md) | Rocket salvo effects: backblast cloud + ground dust, motor plume + distance-emitted smoke trail, impact fireball / dust ring / lingering smoke column, `fx_lights`, pooled particles (`SalvoFxPool`, ≤ 1 250 alive), LOW mesh-only, 60 FPS check | 🔴 blocked | **TASK-074**, **TASK-064**, **TASK-058**, **TASK-050** (soft: TASK-065, TASK-073); camera shake to confirm |
| [TASK-076](TASK-076-hud-v3-foundation.md) | HUD v3 foundation (handoff `docs/design/hud_v3/`): Chakra Petch + JetBrains Mono fonts, tokens in `UiPalette`, chamfer / frame / hatch primitives (`HudShapes`, `FramedPanel`), vignette + scanlines + corner brackets | 🔵 done | – |
| [TASK-077](TASK-077-hud-v3-turn-bar-end-turn.md) | HUD v3: trapezoid turn bar with tick ruler, ready counter + end-turn button, keycap hints | 🔵 done | **TASK-076** |
| [TASK-078](TASK-078-hud-v3-unit-card.md) | HUD v3: unit hover card (crosshair portrait, segmented HP, bar stats, bracket tags; rank chip waits for ranks) | 🔵 done | **TASK-076** (soft: TASK-082) |
| [TASK-079](TASK-079-hud-v3-terrain-card.md) | HUD v3: terrain card with dotted leaders + operation label (`operation_name` in the scenario) | 🔵 done | **TASK-076** |
| [TASK-080](TASK-080-hud-v3-notices.md) | HUD v3: turn banner, toast, targeting bar, loading screen | 🔵 done | **TASK-076** (soft: TASK-077, TASK-079) |
| [TASK-081](TASK-081-unit-orders-rules.md) | Unit orders as rules (blind fire, smoke, ambush, relocate, resupply, dig in, camouflage): game-designer pass first, then core/AI tasks | 💡 idea | GDD decisions by the human (soft: TASK-039b) |
| [TASK-082](TASK-082-hud-v3-radial-orders-menu.md) | HUD v3: radial orders menu on RMB (geometry, detail card, keys 1–6, targeting mode) | 🔴 blocked | **TASK-076**, **TASK-081** (soft: TASK-080, TASK-078) |
| [TASK-066](TASK-066-cloud-shadows.md) | Moving cloud shadows on terrain, foliage (and units?) | 💡 idea | **TASK-055**, **TASK-057**, TASK-054 (soft: TASK-060) |
| [TASK-068](TASK-068-squad-carry-poses.md) | Squad readability at battle zoom: mixed weapon carries (aim / ready / low) and a flank watcher | 🔵 done | – ; open: Polish vest colour contrast |
| [TASK-067](TASK-067-infantry-v3.md) | Infantry v3: smooth procedural soldiers (swept bodies, soft gear, chamfered weapons), squad budget 40k | 🟣 to playtest | **TASK-030**, **TASK-062** (soft: TASK-063); reference `docs/design/showcase/` |
| [TASK-069](TASK-069-tank-model-v3.md) | Tank v3: rework `m1a2_sepv3` / `t72b3` after the M1A2 study (chamfers, small parts, hidden geometry cut, ≤ 40k) – `unit-modeler` | 🔵 done | **TASK-030**, **TASK-062** (soft: TASK-063, TASK-034, TASK-047, TASK-048); reference `docs/design/showcase/m1a2_showcase.gd.txt` |
| [TASK-073](TASK-073-mlrs-model-v3.md) | Rocket launcher v3: rework `homar_k` / `bm27_uragan` on MeshKits (chamfers, small parts, hidden geometry cut, shared wheeled running gear, ≤ 40k) – `unit-modeler` | 🔴 blocked | **TASK-045**, **TASK-069** (soft: TASK-062, TASK-064, TASK-063, TASK-034, TASK-067); jacks / shields from 045 rebuilt, not redesigned |
| [TASK-070](TASK-070-open-field-vegetation.md) | Varied vegetation on open ground: grass kinds (short / tall / dry stalks / nettle) by world noise, meadow flower clusters, thorn-scrub clumps on tile borders; tunables in `LookPreset.meadow` | 🔵 done | **TASK-057**, **TASK-061** (soft: TASK-071) |
| TASK-071 | Central-Eastern European look: species, palette, terrain character (study first) | 🔵 done | soft: TASK-061, TASK-070 |
| TASK-072 | Scalability for very large maps: benchmark tool, chunked lazy world, distance budgets (study first) | 💡 idea | soft: TASK-061, TASK-070 |
| TASK-007 | Fog of war | 💡 idea | GDD open questions: scale, modes |
| TASK-035 | Rivers, roads, named cities with buildings (v2 design, lines 41–130, 504–594) | 💡 idea | GDD decision ("Ideas from the visual design"), hand-made maps |

TASK-008 is not a hard dependency of anything, but it makes the visual parts of TASK-009/-004/-003/-010 easier to judge. TASK-006 lets agents check visual tasks themselves.

Visual design port (TASK-013 … TASK-024, target look in `docs/design/`): "look first, rules later" – the look is ported onto the current mechanics; gameplay ideas from the mock-up are in the GDD ("Ideas from the visual design"). Every visual task ends with an agent check via `tools/screenshot.sh` against `docs/design/reference.png`. Recommended overall order:

006 → 008 → 009 → 013 → 014 → 023 → 015 → 002 → 016a → 016b → 017 → 019 → 022 → 025 → 018 → 020 → 024 → 021 → 010 → 011 → 005 → 012 → (007).

- 008 and 009 first: TASK-019's hit animation and "done" state and TASK-022's timing build on them; TASK-017 restyles 009's markers.
- 023 right after the theme, so every later HUD task adds its strings through `tr()` instead of retrofitting.
- 002 before 016a/016b, so 016b can remove the then-obsolete `height`/`color` presentation fields in one go.
- 016 is split (016a core elevation + tests, 016b mesh) – each half is one session. The terrain panel was split out of the HUD task as TASK-024 for the same reason.
- 011 after 016a: its `Scenario` must force spawn tiles with `MapGenerator.force_terrain` (not `set_terrain`).

Visual design v2 and real units (TASK-026 … TASK-039b, references in `docs/design/v2/` and `docs/design/units/`): more detailed terrain, foliage and unit models, everything procedural. Factions are **real countries**, units are **real equipment with their own stats** (GDD: "Factions and units"). Recommended order:

026 → 027 → 028 → 029 → 037 → 038 → 036 → 039a → 039b → 034, then `/model-unit <id>` per catalog entry. 031–033 were reached by `/model-unit` runs and closed as superseded (2026-10-22); 030 was rewritten as the mesh kit v2 from the model study (2026-10-21) and now belongs to the realism unit track below. Remaining mechanisms: 043 → 044 → 045 (incl. the former 046) → 047 → (048).

- 026 first: the later material tasks are judged under the sky-based ambient and reflections.
- 027/028 (terrain) and 029/030 (units) are independent tracks.
- 037 (catalog tool) has no dependencies – it can be done any time, even first, so the human can start collecting units early.
- 038 moves the current two placeholder factions into data; 036 builds on it (camo from the faction).
- 031–033 build the first model of each class from the v2 design and create the reusable parts; if TASK-039a has picked the real vehicles by then, they model those, otherwise the current generic units.
- 039a/039b: stats, rosters and balance approved by the human (GDD "Stat derivation rules"); 039a can go right after 038 – it doesn't need the new models. 031–033 then model the real vehicles directly.
- Every further unit: catalog entry (`tools/unit_catalog.sh`) → `/model-unit <id>` → stats `.tres` + roster (game-designer). The catalog statuses (`draft` → `ready_for_model` → `modeled` → `in_game`) are the backlog for models; they don't get task files.
- 035 (rivers, roads, cities) changes rules – game-designer pass first; fits the hand-made map direction.
- **Mechanisms (041 → 042 → 043 → 044 → 045, then 047; 046 merged into 045; 048 is an idea)**: animations are declared per real unit in the catalog (`mechanisms` with parameters, registry `docs/design/units/mechanisms.json`), not per class – the Homar-K and the Uragan are both `mlrs` but animate differently. Do 041/043 before 031–033 and further `/model-unit` runs, so new models declare their mechanisms from the start. They don't depend on 039a (039a's model renames update the test's `LEGACY_MODELS` like `KINDS`). The Uragan model was built before 044/045 (front-stowed via an ad-hoc `stowed_yaw` meta, no jacks or shields); 044 moves it to the `stowed` param and 045 reworks it with jacks and window shields; TASK-073 then rebuilds both launchers on the kit (v3), after 045 so the jacks and shields are built only once.

Visual realism (TASK-049 … TASK-066, requested 2026-10-20): the battle scene moves from "tabletop" toward a Steel Division / Combat Mission-like look – realistic terrain, light and units, clean minimal UI (GDD "Visual direction: realism"). All of it is presentation-only (views react to events, no rules in the view, assets under `assets/`); tasks are for `presentation-engineer`, the unit parts of 062–064 also for `unit-modeler`. Every task ends with re-rendering `docs/images/gameplay.png`. Recommended order:

049 → 050 → 051 → 052 → 059 (scale decision) → 053 → 054 → 055 → 056 → 057 → 061 → 058 → (tree decision) 060; unit track 030 → 062 → 067 / 069, with 063 + 064 (one anchor pass per vehicle) → 065 in parallel; 066 last.

- Quick wins first: 049 (overlays stop covering the ground) and 051 (light, haze, grading) change the look most for the least work.
- 050 early: every later task reads its LOW/HIGH switches (target D3D12 GPU; the WSLg software renderer only previews and must stay usable).
- 059 is a screenshot study: the human picks the unit/tree scale (realism vs. readability) before trees, grass and decals are sized.
- 053: decision (a) recorded 2026-10-22 – CC0 textures, HDRI and vegetation models allowed, unit models stay procedural. 054, 055 and option B of 060 wait for 053 to be implemented (ADR + manifest + test).
- 059's preset choice sets the sizes in 057, 058, 061 and 064 (they read `VisualScale`, no hard-coded sizes).
- The unit track is independent of the terrain track: 062 needs TASK-030's kit and masks; 063/064 need model anchors from `unit-modeler` – add both anchor sets in one rework per vehicle.
- ADR numbers: 0001–0010 are taken; tasks that write an ADR use the next free number at the time (030, 043 and 053 each write one).
- Roads, rivers and fields stay in TASK-035; 055 reserves two splat channels for them.
- 074 (rocket salvo sequence) → 075 (salvo effects): 074 is the timing, paths, HP steps and pacing with simple flashes and is shippable alone; 075 fills its `SalvoEffects` hooks with 064's `ParticleFx` pool. Neither waits for the launcher reworks: they work with today's `Mouth*` markers. 044 / 045 edit the same `_play_volley` – whichever of them lands after 074 rebases onto `SalvoTiming.salvo_duration` instead of `RocketVolley.total_duration()`.

HUD v3 (TASK-076 … TASK-082, handoff from Claude Design in `docs/design/hud_v3/`: `README.md` spec, `hud-elementy.html` pixel reference, `icons.svg`): restyles the whole HUD to the military C2 look. 076 (fonts, tokens, primitives) first; 077 / 078 / 079 / 080 are independent of each other afterwards. The radial orders menu (082) needs orders that are not rules yet – 081 (game-designer decisions) comes first, so 076–080 ship without it. The design's samples that the game cannot back yet are left out: rank pips, city names, order effect tags, `1–6` key hints.

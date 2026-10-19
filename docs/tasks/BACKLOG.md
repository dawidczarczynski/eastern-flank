# Backlog

Statuses: `idea` → `ready` (specified, with criteria) → `in progress` → `to playtest` → `done`.

Rows after TASK-001 are in priority order (top = next to implement).

| ID | Title | Status | Depends on |
|---|---|---|---|
| TASK-000 | Skeleton: hex map, movement, turns, simple AI, camera | done | – |
| [TASK-001](TASK-001-combat.md) | Basic melee combat | done | – |
| [TASK-006](TASK-006-screenshot-script.md) | Screenshot script for agents (`tools/screenshot.sh`) | done | – |
| [TASK-008](TASK-008-event-animation-queue.md) | Sequential event animation playback | done | TASK-001 |
| [TASK-009](TASK-009-attackable-highlight.md) | Highlight attackable enemies (`AttackCommand.valid_targets`) | done | TASK-001 |
| [TASK-004](TASK-004-path-preview.md) | Movement path preview on hover (`HexGrid.path_to`) | done | – |
| [TASK-003](TASK-003-unit-info-panel.md) | Info panel for the selected unit | done | TASK-001 |
| [TASK-013](TASK-013-lighting-atmosphere.md) | Lighting & atmosphere like the design (fog, ACES, sun, ambient) | done | – |
| [TASK-014](TASK-014-ui-theme.md) | UI theme: IBM Plex fonts, palette, panel styles (`HudTheme`) | done | – |
| [TASK-023](TASK-023-localization.md) | Localization setup: CSV en + pl, `tr()` for HUD strings | done | – (before the HUD tasks) |
| [TASK-015](TASK-015-camera.md) | Camera like the design: drag-pan, RMB rotate, pitch by distance, map clamp | done | – (soft: TASK-023) |
| [TASK-002](TASK-002-terrain-resources.md) | Terrain types as `.tres` resources with a defense bonus | done | TASK-001 |
| [TASK-016a](TASK-016a-terrain-elevation.md) | Deterministic terrain elevation in core (`TerrainField`, `TerrainSurface`) | done | – (after TASK-002 recommended) |
| [TASK-016b](TASK-016b-terrain-mesh.md) | Continuous terrain mesh, water plane, grid lines, surface picking | done | **TASK-016a** (soft: TASK-013, TASK-015) |
| [TASK-017](TASK-017-map-overlays.md) | Map overlays: reach wash + rings, pulsing hover ring, path dots | done | **TASK-016b**, TASK-014 (soft: TASK-009) |
| [TASK-019](TASK-019-unit-models.md) | Unit models from primitives, faction markers, unit labels (+ upright check) | done | **TASK-016b**, **TASK-017**, TASK-014 (soft: TASK-008, TASK-009) |
| [TASK-022](TASK-022-movement-animation.md) | Unit movement along the path with turning (0.26 s/tile) | done | **TASK-008**, TASK-016b, TASK-019 |
| [TASK-025](TASK-025-unit-locomotion.md) | Unit locomotion: marching soldiers (step bob, kneelers stand), tank wheels + slope tilt | done | **TASK-022**, TASK-019 (soft: TASK-008, TASK-016b) |
| [TASK-018](TASK-018-scatter.md) | Scatter: trees and rocks (MultiMesh, view-local RNG) | done | **TASK-016b** |
| [TASK-020](TASK-020-hud-layout.md) | HUD layout: turn bar, end-turn button, controls hint, turn banner | done | **TASK-014**, TASK-023, TASK-015 (soft: TASK-008, TASK-019) |
| [TASK-024](TASK-024-terrain-panel.md) | Terrain panel (bottom-left) with path cost, replaces the path `Label3D` | done | **TASK-014**, **TASK-016a**, TASK-017, TASK-023 (soft: TASK-002) |
| [TASK-021](TASK-021-unit-hover-popup.md) | Unit hover popup (replaces the TASK-003 panel) | done | **TASK-014**, TASK-019, TASK-023 (soft: TASK-024, TASK-002) |
| [TASK-010](TASK-010-counterattack.md) | Counterattack | done | TASK-001 (soft: TASK-002) |
| [TASK-011](TASK-011-rocket-artillery.md) | Ranged unit (rocket artillery) + starting setup in core (`Scenario`) | done | **TASK-010** |
| [TASK-005](TASK-005-replay.md) | Save/replay a match as seed + command list | done | `Scenario` from TASK-011 (or extract it here) |
| [TASK-012](TASK-012-ai-simulation.md) | Headless AI-vs-AI simulation (`tools/simulate.sh`) | done | `Scenario` from TASK-011/TASK-005 |
| [TASK-026](TASK-026-lighting-ibl.md) | Lighting v2: sky as ambient/reflection source, SSAO | done | TASK-013 |
| [TASK-027](TASK-027-terrain-detail.md) | Terrain detail: tileable detail texture + normal map, denser mesh, macro colour, water normals | done | TASK-016b (soft: TASK-026) |
| [TASK-028](TASK-028-foliage.md) | Foliage v2: lobed crowns with baked AO, bush layer, better rocks | done | TASK-018 (soft: TASK-026, TASK-027) |
| [TASK-029](TASK-029-camo-pbr-materials.md) | Unit materials: procedural camouflage shader, PBR palette | done | TASK-019 (soft: TASK-026) |
| [TASK-030](TASK-030-mesh-kit.md) | `MeshKit`: bevelled profile extrusion, lathe, taper, rods, bake per material | ready | – (soft: TASK-029) |
| [TASK-037](TASK-037-unit-catalog-tool.md) | Unit catalog: local web tool for unit references (`tools/unit_catalog.sh`) | done | – |
| [TASK-038](TASK-038-factions-as-data.md) | Factions as data: `FactionDefinition`, player → faction, HUD/colours from the faction | done | – (soft: TASK-005, TASK-020) |
| [TASK-040](TASK-040-catalog-ai-research.md) | Unit catalog: AI research (`/research-unit`) verified in the form; agent jobs from the UI | done | TASK-037 (soft: TASK-036) |
| [TASK-036](TASK-036-unit-model-pipeline.md) | Unit model pipeline: model per unit, faction camo, `tools/render_unit.sh`, contract test, `/model-unit` | done | **TASK-030**, **TASK-029**, **TASK-038** (soft: TASK-037) |
| [TASK-039a](TASK-039a-real-units-core.md) | Real units and countries: core, data, scenario, balance (Poland vs Russia) | ready | **TASK-038**, TASK-037 |
| [TASK-039b](TASK-039b-real-units-presentation.md) | Real units and countries: labels, popup, locomotion by class, translations, faction camo | ready | **TASK-039a** |
| [TASK-041](TASK-041-catalog-mechanisms.md) | Unit catalog: mechanisms registry (`mechanisms.json`), per-unit `mechanisms` with params, validation, research, readiness | ready | TASK-037, TASK-040 |
| [TASK-042](TASK-042-catalog-mechanisms-ui.md) | Unit catalog: edit mechanisms in the form; research + verify Uragan / Homar-K mechanisms | ready | **TASK-041** |
| [TASK-043](TASK-043-model-mechanisms-contract.md) | Models carry their mechanisms (`MECHANISMS` metadata), registry contract test, `/model-unit` passes them on | ready | **TASK-041** (soft: TASK-042) |
| [TASK-044](TASK-044-launcher-parameters.md) | Launcher with parameters: traverse range (vehicle turns first), stowed direction, elevation per unit | ready | **TASK-043** |
| [TASK-045](TASK-045-stabilisers.md) | `stabilisers`: jacks lowered before a volley (generic deploy step), Homar-K jacks | ready | **TASK-044**, TASK-042 |
| [TASK-031](TASK-031-tank-model-v2.md) | First detailed tank (v2 design → real tank) + reusable tracked running gear – `unit-modeler` | ready | **TASK-036** (soft: TASK-039a, TASK-043) |
| [TASK-047](TASK-047-turret-traverse.md) | `turret_traverse`: turret turns and gun elevates before direct fire (also counters) | ready | **TASK-044**, **TASK-031** |
| [TASK-032](TASK-032-infantry-model-v2.md) | First detailed infantry squad + parameterised soldier kit – `unit-modeler` | ready | **TASK-036** (soft: TASK-039a, TASK-043) |
| [TASK-033](TASK-033-mlrs-model-v2.md) | First detailed rocket artillery + reusable truck/launcher parts – `unit-modeler` | ready | **TASK-036** (soft: TASK-039a, TASK-043 … TASK-045) |
| [TASK-034](TASK-034-unit-portraits.md) | Unit portraits in the hover popup (`SubViewport`) | ready | **TASK-021** (soft: TASK-031 … TASK-033) |
| [TASK-046](TASK-046-blast-shields.md) | `blast_shields`: cab window shields lowered before a volley (Uragan) | idea | **TASK-045**; Uragan research must confirm the shields |
| [TASK-048](TASK-048-gun-recoil.md) | `gun_recoil`: barrel recoil + muzzle flash on direct fire | idea | **TASK-047**; look at 047 in game first |
| TASK-007 | Fog of war | idea | GDD open questions: scale, modes |
| TASK-035 | Rivers, roads, named cities with buildings (v2 design, lines 41–130, 504–594) | idea | GDD decision ("Ideas from the visual design"), hand-made maps |

TASK-008 is not a hard dependency of anything, but it makes the visual parts of TASK-009/-004/-003/-010 easier to judge. TASK-006 lets agents check visual tasks themselves.

Visual design port (TASK-013 … TASK-024, target look in `docs/design/`): "look first, rules later" – the look is ported onto the current mechanics; gameplay ideas from the mock-up are in the GDD ("Ideas from the visual design"). Every visual task ends with an agent check via `tools/screenshot.sh` against `docs/design/reference.png`. Recommended overall order:

006 → 008 → 009 → 013 → 014 → 023 → 015 → 002 → 016a → 016b → 017 → 019 → 022 → 025 → 018 → 020 → 024 → 021 → 010 → 011 → 005 → 012 → (007).

- 008 and 009 first: TASK-019's hit animation and "done" state and TASK-022's timing build on them; TASK-017 restyles 009's markers.
- 023 right after the theme, so every later HUD task adds its strings through `tr()` instead of retrofitting.
- 002 before 016a/016b, so 016b can remove the then-obsolete `height`/`color` presentation fields in one go.
- 016 is split (016a core elevation + tests, 016b mesh) – each half is one session. The terrain panel was split out of the HUD task as TASK-024 for the same reason.
- 011 after 016a: its `Scenario` must force spawn tiles with `MapGenerator.force_terrain` (not `set_terrain`).

Visual design v2 and real units (TASK-026 … TASK-039b, references in `docs/design/v2/` and `docs/design/units/`): more detailed terrain, foliage and unit models, everything procedural. Factions are **real countries**, units are **real equipment with their own stats** (GDD: "Factions and units"). Recommended order:

026 → 027 → 028 → 029 → 030 → 037 → 038 → 036 → 031 → 032 → 033 → 039a → 039b → 034, then `/model-unit <id>` per catalog entry. Mechanisms (TASK-041 … TASK-048, see the last point) slot in before 031: 041 → 042 → 043 → 044 → 045 → 031 → 047.

- 026 first: the later material tasks are judged under the sky-based ambient and reflections.
- 027/028 (terrain) and 029/030 (units) are independent tracks.
- 037 (catalog tool) has no dependencies – it can be done any time, even first, so the human can start collecting units early.
- 038 moves the current two placeholder factions into data; 036 builds on it (camo from the faction).
- 031–033 build the first model of each class from the v2 design and create the reusable parts; if TASK-039a has picked the real vehicles by then, they model those, otherwise the current generic units.
- 039a/039b: stats, rosters and balance approved by the human (GDD "Stat derivation rules"); 039a can go right after 038 – it doesn't need the new models. 031–033 then model the real vehicles directly.
- Every further unit: catalog entry (`tools/unit_catalog.sh`) → `/model-unit <id>` → stats `.tres` + roster (game-designer). The catalog statuses (`draft` → `ready_for_model` → `modeled` → `in_game`) are the backlog for models; they don't get task files.
- 035 (rivers, roads, cities) changes rules – game-designer pass first; fits the hand-made map direction.
- **Mechanisms (041 → 042 → 043 → 044 → 045, then 047 after 031; 046 / 048 are ideas)**: animations are declared per real unit in the catalog (`mechanisms` with parameters, registry `docs/design/units/mechanisms.json`), not per class – the Homar-K and the Uragan are both `mlrs` but animate differently. Do 041/043 before 031–033 and further `/model-unit` runs, so new models declare their mechanisms from the start. They don't depend on 039a (039a's model renames update the test's `LEGACY_MODELS` like `KINDS`). The Uragan model (`/model-unit bm27_uragan`) comes after 042 (verified entry), 044 (front-stowed, limited traverse) and 045 (jacks); 046 when its research confirms the window shields.

# Backlog

Statuses: `idea` → `ready` (specified, with criteria) → `in progress` → `to playtest` → `done`.

Rows after TASK-001 are in priority order (top = next to implement).

| ID | Title | Status | Depends on |
|---|---|---|---|
| TASK-000 | Skeleton: hex map, movement, turns, simple AI, camera | to playtest | – |
| [TASK-001](TASK-001-combat.md) | Basic melee combat | to playtest | – |
| [TASK-006](TASK-006-screenshot-script.md) | Screenshot script for agents (`tools/screenshot.sh`) | done | – |
| [TASK-008](TASK-008-event-animation-queue.md) | Sequential event animation playback | to playtest | TASK-001 |
| [TASK-009](TASK-009-attackable-highlight.md) | Highlight attackable enemies (`AttackCommand.valid_targets`) | ready | TASK-001 |
| [TASK-004](TASK-004-path-preview.md) | Movement path preview on hover (`HexGrid.path_to`) | to playtest | – |
| [TASK-003](TASK-003-unit-info-panel.md) | Info panel for the selected unit | to playtest | TASK-001 |
| [TASK-013](TASK-013-lighting-atmosphere.md) | Lighting & atmosphere like the design (fog, ACES, sun, ambient) | ready | – |
| [TASK-014](TASK-014-ui-theme.md) | UI theme: IBM Plex fonts, palette, panel styles (`HudTheme`) | ready | – |
| [TASK-023](TASK-023-localization.md) | Localization setup: CSV en + pl, `tr()` for HUD strings | ready | – (before the HUD tasks) |
| [TASK-015](TASK-015-camera.md) | Camera like the design: drag-pan, RMB rotate, pitch by distance, map clamp | ready | – (soft: TASK-023) |
| [TASK-002](TASK-002-terrain-resources.md) | Terrain types as `.tres` resources with a defense bonus | ready | TASK-001 |
| [TASK-016a](TASK-016a-terrain-elevation.md) | Deterministic terrain elevation in core (`TerrainField`, `TerrainSurface`) | ready | – (after TASK-002 recommended) |
| [TASK-016b](TASK-016b-terrain-mesh.md) | Continuous terrain mesh, water plane, grid lines, surface picking | ready | **TASK-016a** (soft: TASK-013, TASK-015) |
| [TASK-017](TASK-017-map-overlays.md) | Map overlays: reach wash + rings, pulsing hover ring, path dots | ready | **TASK-016b**, TASK-014 (soft: TASK-009) |
| [TASK-019](TASK-019-unit-models.md) | Unit models from primitives, faction markers, unit labels (+ upright check) | ready | **TASK-016b**, **TASK-017**, TASK-014 (soft: TASK-008, TASK-009) |
| [TASK-022](TASK-022-movement-animation.md) | Unit movement along the path with turning (0.26 s/tile) | ready | **TASK-008**, TASK-016b, TASK-019 |
| [TASK-018](TASK-018-scatter.md) | Scatter: trees and rocks (MultiMesh, view-local RNG) | ready | **TASK-016b** |
| [TASK-020](TASK-020-hud-layout.md) | HUD layout: turn bar, end-turn button, controls hint, turn banner | ready | **TASK-014**, TASK-023, TASK-015 (soft: TASK-008, TASK-019) |
| [TASK-024](TASK-024-terrain-panel.md) | Terrain panel (bottom-left) with path cost, replaces the path `Label3D` | ready | **TASK-014**, **TASK-016a**, TASK-017, TASK-023 (soft: TASK-002) |
| [TASK-021](TASK-021-unit-hover-popup.md) | Unit hover popup (replaces the TASK-003 panel) | ready | **TASK-014**, TASK-019, TASK-023 (soft: TASK-024, TASK-002) |
| [TASK-010](TASK-010-counterattack.md) | Counterattack | ready | TASK-001 (soft: TASK-002) |
| [TASK-011](TASK-011-archer.md) | Ranged unit (archer) + starting setup in core (`Scenario`) | ready | **TASK-010** |
| [TASK-005](TASK-005-replay.md) | Save/replay a match as seed + command list | ready | `Scenario` from TASK-011 (or extract it here) |
| [TASK-012](TASK-012-ai-simulation.md) | Headless AI-vs-AI simulation (`tools/simulate.sh`) | ready | `Scenario` from TASK-011/TASK-005 |
| TASK-007 | Fog of war | idea | GDD open questions: scale, modes |

TASK-008 is not a hard dependency of anything, but it makes the visual parts of TASK-009/-004/-003/-010 easier to judge. TASK-006 lets agents check visual tasks themselves.

Visual design port (TASK-013 … TASK-024, target look in `docs/design/`): "look first, rules later" – the look is ported onto the current mechanics; gameplay ideas from the mock-up are in the GDD ("Ideas from the visual design"). Every visual task ends with an agent check via `tools/screenshot.sh` against `docs/design/reference.png`. Recommended overall order:

006 → 008 → 009 → 013 → 014 → 023 → 015 → 002 → 016a → 016b → 017 → 019 → 022 → 018 → 020 → 024 → 021 → 010 → 011 → 005 → 012 → (007).

- 008 and 009 first: TASK-019's hit animation and "done" state and TASK-022's timing build on them; TASK-017 restyles 009's markers.
- 023 right after the theme, so every later HUD task adds its strings through `tr()` instead of retrofitting.
- 002 before 016a/016b, so 016b can remove the then-obsolete `height`/`color` presentation fields in one go.
- 016 is split (016a core elevation + tests, 016b mesh) – each half is one session. The terrain panel was split out of the HUD task as TASK-024 for the same reason.
- 011 after 016a: its `Scenario` must force spawn tiles with `MapGenerator.force_terrain` (not `set_terrain`).

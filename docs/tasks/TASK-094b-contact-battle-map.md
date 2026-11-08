# TASK-094b: Contact (2/4) – tactical map for a contact anywhere on the theatre, deployment and objectives

- **Status**: done
- **Layers**: core (`src/core/`, importer in `tools/`) + data (`data/maps/`, `data/operational/contact.tres`) + presentation (debug preview)
- **Depends on**: TASK-094a
- **Sections**: GDD "Battle hand-off and auto-resolve", Open questions "Tactical maps for contacts anywhere"; ADR 0015, ADR 0018; docs/TOOLS.md (importer)
- **Model**: opus
- **Topic**: Two-layer game

## Goal

A contact at any hex of the theatre gets a real tactical map (about 10 × 7.5 km of the real terrain around the fight), the companies deployed on it facing each other, and objectives derived from the situation. The theatre is ~1.7 M tactical hexes, so one big import no longer fits; this task measures first and implements the cheapest option that meets the budget. Clickable through a debug preview; the real "Play battle" is TASK-094c.

## Acceptance criteria (testable)

- [ ] **Measure first** (numbers in the implementation notes and an ADR amendment): size on disk, memory and load time of (A) a pre-imported chunked theatre-wide tactical layer (`data/maps/suwalki_tactical/`, chunks loaded around the contact) vs (B) importing the cut on demand from the cached OSM / DEM data. Budget **[ASSUMPTION]**: contact map ready ≤ 1.5 s, repository growth ≤ 50 MB. Recommended A; the agent picks within the budget. If neither fits, stop and record the finding in GDD Open questions instead of shipping.
- [ ] `ContactMap.build(setup, operational_grid) -> BattleSetup` (pure; fills `map_id` / `map_region` and company `coord`s of TASK-094a's draft): the region is `contact.tres` `width` × `height` tactical hexes (40 × 30 **[ASSUMPTION]**) centred on the midpoint between the two formations' operational hexes, clamped to the theatre. Tests on a small hand-made tactical grid: region inside the map, centred, clamped at the border.
- [ ] Deployment: the attacker's companies in the third of the region nearest its operational hex, the defender's in the opposite third, in setup order on the nearest free passable tiles (no water / impassable, no two on one tile), spaced ≥ 1 hex; deterministic. Test: every company placed, none overlaps, attacker closer to its side's edge.
- [ ] Objectives derived (`BattleObjectives`): the defender must **hold** the hex(es) at the region centre, the attacker must **take** them; `turn_limit` from `contact.tres` (12 **[ASSUMPTION]**); draw = defender holds the field (matches `settle` in TASK-120). Test: an attacker occupying the centre at the end wins, otherwise the defender.
- [ ] `Scenario.from_setup(setup)` on the built setup succeeds for every adjacent pair of formation positions of the shipped `suwalki_gap` start (test loops over a sample of ≥ 20 contact points, including a border one) and measures the build time (≤ budget).
- [ ] The result keeps the real terrain: a contact on the Gap road shows a road in the map cut, a lake hex is water (test against the theatre import).
- [ ] docs/ARCHITECTURE.md "Two layers": `ContactMap`, `contact.tres`, the chosen tactical layer. ADR 0018 amended.

View (debug preview, `--debug` only):

- [ ] Staff map F9 panel "Contact map": click two adjacent operational hexes (attacker, defender) → the cut is **outlined on the staff map** (on the relief, px-width line; works under the 2.5D camera of [TASK-125](TASK-125-staff-map-restyle-2-5d.md)) and the panel lists size, deployment counts and build time; button **Open battle map** loads the tactical battle scene on that cut through the existing battle entry (the agent finds it; TASK-094c replaces it with the Session flow). **[ASSUMPTION]** returning goes to the main menu.

## Playtest (for the human)

1. Start with `--debug`, **Operation**, open F9 → Contact map, click a Polish and an adjacent hex near Suwałki: a rectangle outlines the cut; the panel shows build time.
2. **Open battle map**: the 3D battle opens on the real terrain of that area (roads, lakes, forest where the staff map shows them), the two formations' companies deployed facing each other. Check the objective hexes in the centre.
3. Repeat at a corner of the theatre and next to a lake: the cut stays inside the map.

## Player manual

Short note in "Contact": the battlefield is the real terrain around the contact point; the defender holds the centre, the attacker must take it. Numbers (turn limit) from `contact.tres`.

## Out of scope

- Playing the battle in the campaign flow and returning (TASK-094c); campaign save (TASK-094d); auto-resolve (TASK-120); fine DEM relief or new tactical terrain types.

## Implementation notes

Logic + data done (2026-11-08). View done: `StaffMapContactPreview` (model), `StaffMapContactPanel`, `StaffMapContactDebug` (outline via `StaffMapRouteRibbon`), F9 opens it with the politics panel; `BattleOptions.pending_setup` → `BattleController` builds the state with `Scenario.from_setup`; Esc with nothing selected returns to the main menu; F5 does not save a match for setup battles. Hexes without a fieldable formation get a stand-in. Tests: `test_staff_map_contact_preview.gd`, one scene test in `test_staff_map_contacts.gd`. `battle_controller.gd` carries `gdlint: disable=max-file-lines` (file at the limit; split later). Note for TASK-094c: `ContactMap.build` takes `(setup, attacker_hex, defender_hex)`, not an operational grid. Not verified in the running game; screenshots checked by the agent only.

**Measured** (dev machine, WSL2; details in ADR 0018 amendment "Tactical layer"):
- (A) chunked layer from the operational cache: offline import 9 min 32 s, peak 1.02 GB; repository +3.32 MB (122 files); cold cut of 4 chunks 25 ms (+0.8 MB), `ContactMap.build` + `Scenario.from_setup` slowest 248 ms / mean 162 ms over 37 contacts.
- (B) on demand from the cache: 8.5 s per cut (Python, one tile; a corner needs up to 4), Godot `JSON.parse` of one 56 MB tile alone 2.06 s; needs the 1.9 GB cache shipped. Fails both budgets. **A chosen.**

**Core / data**: `TacticalLayer` + `TacticalChunk` (`src/core/data/`, `data/maps/suwalki_tactical/`), `ContactSettings` (`data/operational/contact.tres`: 40 × 30, turn limit 12, spacing 2, `suwalki_theatre` → `suwalki_tactical`), `ContactMap` (`src/core/operational/contact_map.gd`: `build(setup, attacker_hex, defender_hex)`, `build_with(..., theatre, layer, settings)`, `centre_tile`, `region_around`, `attack_direction`, `objective_hex`, `objectives`, `deploy`). `Scenario.from_setup` cuts a layer named by `map_id` with `map_region`; on imported maps / cuts a spawn tile keeps its real terrain unless water / impassable. Importer `--profile=layer` (`tools/import_map.py`, Python tests `TacticalLayerTest`). CREDITS, TOOLS.md, ARCHITECTURE "Two layers" updated. No new commands or events.

**Deviations**: the API takes the two operational hexes (`build(setup, attacker_hex, defender_hex)`), not an operational grid – the pending setup does not carry the hexes, so TASK-094c must pass them (from the `battle_pending` event / formations) or store them. The layer comes from the operational inputs: no FIELDS, only major roads and rivers, GLO-90 relief (hills calibrated to 10 m). The objective is the passable tile nearest the cut's centre (one hex). Companies the player's battle faction cannot field (e.g. a contributed Lithuanian formation under the Polish faction) still fail `from_setup` – a TASK-094a/c issue, not the map.

Tests: `test_contact_map.gd` (hand-made layer: region centred / clamped / even row, cut, elevation, deployment, objectives and their outcome), `test_contact_map_theatre.gd` (shipped layer, 37 contacts of the `suwalki_gap` start incl. a west-edge one within 1.5 s, Suwalki roads, Lake Sniardwy water).

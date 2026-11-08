# TASK-094b: Contact (2/4) – tactical map for a contact anywhere on the theatre, deployment and objectives

- **Status**: ready
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

_Filled in by the agent when done._

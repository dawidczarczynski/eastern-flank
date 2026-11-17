# TASK-163: Contact battle deployment: defender placed around the objective

- **Status**: done
- **Layers**: core
- **Depends on**: –
- **Sections**: GDD "Battle hand-off and auto-resolve" (bullet "Contact deployment"); terrain defence = `defense_bonus` in `data/terrain/*.tres` (forest 1, urban 2, hills 2, others 0), read via `Terrain.definition(t).defense_bonus`
- **Model**: sonnet
- **Topic**: Two-layer game

## Goal

In an operation contact battle the defender starts in a cluster around the objective hex, on the best defensive ground there, while the attacker enters from its edge. Battles become attack-versus-defence, not a race to the objective.

## Acceptance criteria (testable)

Tests in `tests/unit/test_contact_map.gd`; `ContactMap.deploy` gets the terrain through `grid` and the radius as a parameter.

- [ ] New field `defender_radius: int = 3` in `ContactSettings` and `data/operational/contact.tres`; `problem()` returns a message when it is < 1 (0 and -1 rejected, 1 accepted).
- [ ] With a free plains cut and 6 defender companies, every defender tile has hex distance 1..3 to the objective; none is on the objective tile.
- [ ] Defender tiles are pairwise at hex distance >= `deploy_spacing` (2) while the zone has room (radius 3 holds 36 tiles, so 6 companies always fit on plains).
- [ ] Ranking inside the zone: higher `defense_bonus` first, then smaller distance to the objective, then smaller row, then smaller column. Test: one hills tile (bonus 2) at distance 3 and plains at distance 1 -> the first defender takes the hills tile; a forest (1) tile at distance 2 is taken before plains at distance 1.
- [ ] Defenders are placed in setup order, each on the best free tile that keeps the spacing.
- [ ] Spacing fallback: when the zone has fewer spaced tiles than companies, the remaining companies are placed with spacing 1 inside the radius (test: zone reduced to 5 passable tiles in a row, 3 companies).
- [ ] Radius fallback: when the radius has fewer free passable tiles than companies, the zone widens ring by ring (4, 5, ...) up to the whole cut (test: all tiles within 3 are water except 2, 4 companies -> two are placed at distance 4).
- [ ] When even the whole cut cannot hold every company, `deploy` returns fewer coords and `build_with` returns null (as today).
- [ ] Water and impassable tiles are never used; the old far-third fallback for the defender is gone.
- [ ] The attacker's placement is unchanged: same tiles as before this task for the same input (regression test on the existing fixture) and none within the defender zone: no attacker tile equals a defender tile (assert on the shipped 40x30 cut with 6 + 6 companies; the cut's attacker third lies ~13 hexes from the objective).
- [ ] Determinism: two calls with identical input return identical coords; no RNG is drawn.
- [ ] Scenario battles (attacker = -1: default, objective_battle, Suwalki) are not changed: `ContactMap` is not involved, existing scenario tests stay green.
- [ ] `ContactMap.build_with` still sets `objectives` exactly as before (objective hex, defender holds, attacker takes).

## Playtest (for the human)

1. Start an operation, make a contact in which the defender's hex has forest or hills nearby (the staff-map contact preview shows the cut).
2. Play the battle: the defending companies stand in a cluster within 3 hexes of the objective, preferring forest/hill/urban tiles; the attacker's companies enter from its own edge, ~13 hexes away.
3. Check that the briefing and notice text are unchanged and the preview outline matches the cut.
4. Swap roles (let the AI attack you): you start around the objective.

## Player manual

Edit docs/MANUAL.md section "Contact", paragraph "The battlefield": add that the defender starts clustered around the objective hex (within 3 hexes), on the best defensive terrain available there, and the attacker enters from the edge of the map facing its approach. Scenario battles keep their opposite-edge starts (done by the designer together with this specification; re-check against the implementation).

## Out of scope

- Scenario battles (opposite-edge deployment stays).
- Changing the attacker's zone, the objective choice, the turn limit or terrain defence numbers.
- Visual changes: the contact preview (`staff_map_contact_preview.gd`) and `ContactRules.build` / `ContactBattle` go through `ContactMap` and need no change (verified by grep: the only other `ContactMap` use is `battle_controller.gd` demo, which calls `objectives` only).

## Decisions (human interview, 2026-11-17)

1. Defender zone: a cluster within hex distance 1..3 of the objective hex (the objective tile itself excluded), nearest the objective first, spacing `deploy_spacing` kept. The attacker keeps its edge third unchanged.
2. Terrain: within the zone candidates are ranked by terrain defence bonus first (higher is better), then hex distance to the objective, then row, then column.
3. Scope: contact battles only (`ContactMap.deploy`); scenario battles keep their opposite-edge deployment.

## Assumptions

- **[ASSUMPTION]** The radius is the data field `defender_radius` (3) in `ContactSettings` / `contact.tres`, validated >= 1 in `problem()`.
- **[ASSUMPTION]** Fallback when the zone is too small: spacing 1 inside the radius, then widen the radius ring by ring (4, 5, ...) to the whole cut; the old far-third fallback is dropped; if still impossible `build_with` returns null.
- **[ASSUMPTION]** Defenders are placed in setup order; no RNG; fully deterministic and pure.
- **[ASSUMPTION]** The attacker keeps its thirds (the third's middle is ~13 hexes from the objective, so it never meets the radius-3 zone); placement order guarantees no shared tile.

## Implementation notes

- `ContactMap.deploy` now places the attacker as before (nearest its third, attackers first) and the defender via `_deploy_defender`: candidates ranked by `defense_bonus` desc, distance to the objective, row, column; from `defender_radius` (new field, 3, in `ContactSettings` / `contact.tres`) it tries spacing `deploy_spacing`, then 1, then widens the radius ring by ring to the whole cut. The far-third fallback for the defender is gone.
- Tests: new `tests/unit/test_contact_deployment.gd` (radius, spacing, ranking, both fallbacks, no room, determinism); `test_contact_map.gd` north-south test now expects the defender near the middle rows.
- `test_auto_resolve_record.gd` depended on the attacker winning the played battle; the defender now wins, so a second formation (`ru_mr_5`) is sent in and the contact wait is 20 turns.
- Known limitation: the radius-3 zone holds ≤ 36 tiles; very large forces widen the radius. Not playtested in the game.

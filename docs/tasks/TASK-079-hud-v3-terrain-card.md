# TASK-079: HUD v3 – terrain card and operation label

- **Status**: done
- **Layers**: presentation (`TerrainPanel` rebuilt, `TerrainPanelModel` extended), scenario data (operation name), localisation, tests. Role: **presentation-engineer**.
- **Depends on**: **TASK-076**
- **Model**: sonnet

## Goal

Bottom-left terrain card in the handoff look (README section 03), plus the `■ OP. <NAME>` label above it.

## Design

- Column at left 24 / bottom 24, gap 10: operation label (amber mono 10.5, ls .18em + 150×3 thin hatch) above the card; card 262 px, chamfer 12 (top-right + bottom-left), tab `TEREN` + `HEKS 07·04` right, title 20 px, city line `◆ Name` (amber 12 mono) when the hex is a city (cities do not exist yet – TASK-035; show only if the model provides a name), rows with dotted leaders (`KOSZT RUCHU`, `MOD. OBRONY`, `WYSOKOŚĆ`), bracket tags, path row (1 px border + text in active faction colour, `TRASA · 3 / 5 PR`) only for a reachable hover hex.
- **Operation name**: add an optional `operation_name` to the scenario (core `Scenario` / match setup; default scenario "Iron Shore" = `ŻELAZNY BRZEG` in pl, GDD "Scenario flavour"). Pure data + test; label hidden if empty. Also used by the loading screen in TASK-080.
- Dotted leader: a small `Control` drawing dots between caption and value.

## Acceptance criteria (testable)

- [ ] `TerrainPanelModel` tests: rows/labels/tags unchanged numerically; hex text format `07·04`; path row only when `path_cost >= 0`; city name passed through when present.
- [ ] `Scenario` test: default battle has an operation name; saved/loaded matches keep it (check `MatchRecord` compatibility – old saves without it must still load).
- [ ] No raw keys in en/pl; `tools/check.sh` passes; screenshot + README screenshot checked.

## Playtest (for the human)

1. Hover hexes: card values match the terrain; with a unit selected, hovering a reachable hex shows the path row in the faction colour.
2. The operation label sits above the card; compare with the HTML.

## Player manual

Terrain card fields.

## Out of scope

Cities/roads (TASK-035).

## Implementation notes

- `GameState.operation_name` (set by `Scenario.default_battle` = "Iron Shore", not in `snapshot()`); replays rebuild it, `MatchRecord` is unchanged so old saves load as before.
- `TerrainPanelModel.build` gained an optional `city_name` → `"city"` key (no cities yet, so never shown in game).
- `TerrainPanel` is now a `FramedPanel` (tab, chamfer, dotted `_Leader` rows, bracket tags, path row in the selected unit's faction colour); new `OperationLabel` (amber label + 150×3 hatch) in the bottom-left stack; margin 16 → 24, gap 10. New strings in strings.csv.
- Not seen in-game: the city line (no data) and the tooltip-free hover with a Polish locale; the README screenshot shows the card with the path row.

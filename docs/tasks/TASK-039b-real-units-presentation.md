# TASK-039b: Real units and countries – presentation and translations

- **Status**: ready
- **Layers**: presentation (labels, popup, locomotion/model choice by class and mobility), translations, faction camo data
- **Depends on**: **TASK-039a**. Design and decisions: `TASK-039a-real-units-core.md`.
- **Model**: sonnet

## Goal

The view shows the real units properly: short designations on labels, the translated class and the real name in the popup, locomotion chosen by class/mobility instead of hard-coded ids, and the faction camouflage palettes from the catalog.

## Acceptance criteria (testable)

- [ ] Unit label shows `tr(short_name)`: `M1A2`, `T-72B3`, `HOMAR`, `BM-27`, `INF` (pl `PIECH`) – `test_unit_definitions.gd` checks the short names.
- [ ] `test_unit_popup_model.gd`: popup for an Abrams shows class label key `CLASS_TANK` and name "M1A2 SEPv3 Abrams" (done ahead 2026-10-19); for a Polish squad the name is `tr("Mechanised Infantry Squad")`.
- [ ] `assets/i18n/strings.csv` gets en + pl rows `Mechanised Infantry Squad` / Drużyna piechoty zmechanizowanej, `Motor Rifle Squad` / Drużyna zmotoryzowana (already there since 2026-10-19: `CLASS_TANK` Tank / Czołg, `CLASS_MLRS` Rocket Artillery / Artyleria rakietowa – matches the `ART` label, `CLASS_INFANTRY` Infantry / Piechota, `TNK` / CZOŁ); obsolete rows `Cavalry`, `Rocket Artillery`, `Infantry` removed if unused.
- [ ] `grep` finds no unit-id-specific branches in `src/presentation/` for locomotion/model choice (`UnitModels.VEHICLES` keyed by id removed); vehicles are chosen by `unit_class` / `mobility`.
- [ ] Faction camo palettes in `data/factions/*.tres` match the catalog factions (`docs/design/units/factions/*.json`).

## Playtest (for the human)

1. Start a battle: labels above units read `INF`, `M1A2`, `HOMAR` / `INF`, `T-72B3`, `BM-27`; check the 6-character `T-72B3` label fits.
2. Hover each unit: the popup shows the class (Tank / MLRS / Infantry) and the real name; switch to Polish – class labels and squad names translate, vehicle names don't.
3. Move the tanks and trucks: they still drive (wheels turn, hull tilts); squads march.

## Out of scope

- New 3D models (TASK-031 … TASK-033, `/model-unit`), faction selection UI.

## Implementation notes

_Filled in by the agent when done._

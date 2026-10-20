# TASK-039b: Real units and countries – presentation and translations

- **Status**: done
- **Layers**: presentation (labels, popup, locomotion/model choice by class and mobility), translations, faction camo data
- **Depends on**: **TASK-039a**. Design and decisions: `TASK-039a-real-units-core.md`.
- **Model**: sonnet

## Goal

The view shows the real units properly: short designations on labels, the translated class and the real name in the popup, locomotion chosen by class/mobility instead of hard-coded ids, and the faction camouflage palettes from the catalog.

## Acceptance criteria (testable)

- [x] Unit label shows `tr(short_name)`: `M1A2`, `T-72B3`, `HOMAR`, `BM-27`, `INF` (pl `PIECH`) – `test_unit_definitions.gd` checks the short names.
- [x] `test_unit_popup_model.gd`: popup for an Abrams shows class label key `CLASS_TANK` and name "M1A2 SEPv3 Abrams" (done ahead 2026-10-19); for a Polish squad the name is `tr("Mechanised Infantry Squad")`.
- [x] `assets/i18n/strings.csv` gets en + pl rows `Mechanised Infantry Squad` / Drużyna piechoty zmechanizowanej, `Motor Rifle Squad` / Drużyna zmotoryzowana (already there since 2026-10-19: `CLASS_TANK` Tank / Czołg, `CLASS_MLRS` Rocket Artillery / Artyleria rakietowa – matches the `ART` label, `CLASS_INFANTRY` Infantry / Piechota, `TNK` / CZOŁ); obsolete rows `Cavalry`, `Rocket Artillery`, `Infantry` removed if unused.
- [x] `grep` finds no unit-id-specific branches in `src/presentation/` for locomotion/model choice (`UnitModels.VEHICLES` keyed by id removed); vehicles are chosen by `unit_class` / `mobility`.
- [x] Faction camo palettes in `data/factions/*.tres` match the catalog factions (`docs/design/units/factions/*.json`).

## Playtest (for the human)

1. Start a battle: labels above units read `INF`, `M1A2`, `HOMAR` / `INF`, `T-72B3`, `BM-27`; check the 6-character `T-72B3` label fits.
2. Hover each unit: the popup shows the class (Tank / Rocket Artillery / Infantry) and the real name; switch to Polish – class labels and squad names translate, vehicle names don't.
3. Move the tanks and trucks: they still drive (wheels turn, hull tilts); squads march.

- [x] Generic models left over from TASK-039a are removed: `src/presentation/models/{infantry,cavalry,rocket_artillery}.gd`, their `UnitModels` constants and `VEHICLES` entries, and the `KINDS` / `WAIVERS` entries in `test_unit_model_contract.gd`; presentation tests build the real unit ids.
- [x] The second T-72B3 at offset (10,8) is not hidden behind the controls help panel at the default camera.

## Out of scope

- New 3D models (TASK-031 … TASK-033, `/model-unit`), faction selection UI.

## Implementation notes

_Filled in by the agent when done._

- **Done (2026-10-20):**
  - Vehicle locomotion is chosen by data: `UnitModels.is_vehicle(definition)` is true for `mobility` wheeled / tracked; `VEHICLES` and all unit-id constants are gone from `unit_models.gd`, `unit_view.gd` passes the definition.
  - Generic models `src/presentation/models/{infantry,cavalry,rocket_artillery}.gd` deleted; presentation tests (`test_unit_models`, `test_locomotion`, `test_launcher_pose`, `test_unit_model_contract`) build the real ids. `WAIVERS` in the contract test is now empty (kept for future models). `Fixtures.generic_infantry()` removed.
  - Labels and the popup already used `tr(short_name)` / `tr(display_name)`; tests added for `INF` → `PIECH` and the Polish squad names.
  - `strings.csv`: added `Mechanised Infantry Squad`, `Motor Rifle Squad`; removed unused `Infantry`, `Cavalry`, `Rocket Artillery`.
  - Faction `camo` / `vest_color` set to the catalog JSON values (`color` already matched); `test_unit_catalog_consistency.gd` checks them.
  - The controls hint moved from bottom-right to bottom-centre (`battle_hud.gd`, 440 px wide), so the second T-72B3 is visible at the default camera; checked with `tools/screenshot.sh`. README screenshot regenerated.
  - MANUAL: camo per army, unit card names, controls hint position.
  - Playtested by the human (2026-10-20): all good.

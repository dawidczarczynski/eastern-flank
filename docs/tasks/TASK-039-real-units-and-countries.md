# TASK-039: Real countries and real units – unit classes, per-vehicle definitions, first rosters

- **Status**: idea – era, countries and rosters are decided (below); still needs the game-designer pass for the **stat derivation rules** and the human's approval of the resulting stats before it becomes `ready`
- **Layers**: core (`UnitDefinition`, data), presentation (labels, popup), ai (unit class roles if needed)
- **Depends on**: **TASK-038**, **TASK-037** (catalog entries with real-world data for every unit in the first rosters). GDD: "Factions and units", open questions "Setting" (era) and "Stat derivation rules".
- **Model**: opus

## Goal

The battle is fought between two real countries with real equipment ("M1A2 SEPv3 Abrams" vs "T-72B3"), each unit with its own stats derived from real-world data by written rules, so more units and countries can be added the same way.

## Decisions (2026-10-18)

1. **Era: present day** – a unit qualifies if it is in active service today (older designs still fighting, e.g. in Ukraine, count).
2. **First factions and rosters** (one unit per current class; catalog ids seeded by TASK-037):

   | Class (replaces) | Poland | Russia |
   |---|---|---|
   | Tank (`cavalry`) | `m1a2_sepv3` – M1A2 SEPv3 Abrams | `t72b3` – T-72B3 |
   | Rocket artillery (`rocket_artillery`) | `homar_k` – Homar-K (K239 Chunmoo on Jelcz 8×8) | `bm27_uragan` – 9K57 Uragan (ZIL-135 8×8) |
   | Infantry (`infantry`) | `pl_mech_infantry` – mechanised infantry squad, wz. 93 Pantera, MSBS Grot | `ru_motor_rifle` – motor rifle squad, EMR digital camo, AK-74M / AK-12 |

   Infantry display names and their AT weapons (e.g. Carl Gustaf / Javelin vs. RPG-7 / RPG-26) are confirmed in the catalog.
3. **Still open – game-designer**: stat derivation rules written into the GDD (which catalog facts map to which stat bands – main gun / rocket calibre and guidance → attack, protection → defense, speed → move points, fire range → attack range in hexes, vehicle size / crew → HP), using the current three generic units as calibration points; whether new stats are needed now (hard/soft attack, armour type) or stay GDD ideas. The two countries **may differ in strength per unit** (Abrams vs. T-72B3, Homar-K's guided rockets vs. Uragan) – balance comes from the scenario (e.g. unit counts), to be proposed by the designer and checked with `tools/simulate.sh`.

## Planned design (to confirm in the designer pass)

- `UnitDefinition` gains `unit_class: StringName` (ids from `docs/design/units/classes.json`), `mobility: StringName` (`foot`/`wheeled`/`tracked`); `display_name` holds the **real name** and is not translated; the class label is translated (`CLASS_TANK` …). `short_name` becomes a class abbreviation (`TANK`, `INF`, `MLRS`) or a short real designation – decide.
- One `data/units/<catalog_id>.tres` per real unit; the three generic definitions (`infantry`, `cavalry`, `rocket_artillery`) are replaced (keep ids readable in old replays: a mapping or a note that pre-039 records are unsupported – decide and record in an ADR).
- `data/factions/poland.tres` / `russia.tres` (created in TASK-038) get the real rosters and the camo palettes from the catalog; `Scenario.default_battle` picks units by class from each roster.
- Presentation: locomotion and model contract by `mobility`/`unit_class` instead of hard-coded ids (`UnitModels.VEHICLES`); popup shows class label + real name.
- A consistency test: every `UnitDefinition` has a catalog entry `docs/design/units/units/<id>/unit.json` whose `real_name == display_name` and `class == unit_class`, and every roster faction is listed in the entry's `operators`. (Reads JSON from `docs/` in a test only – the game never reads the catalog.)

## Acceptance criteria (draft)

- [ ] GDD updated with era, countries, rosters and derivation rules; the stats of every first-roster unit are traceable to those rules (table in the GDD).
- [ ] Definitions, factions, scenario and consistency test as above; `tools/simulate.sh 200` shows neither country winning more than ~60 % in the default battle (balanced by scenario composition if per-unit strength differs), or the imbalance is intentional and documented.
- [ ] HUD/popup show country names and real unit names; class labels translated (en + pl).

## Out of scope

- Faction selection UI, more than two players, the 3D models (TASK-031 … TASK-033 and `/model-unit`).

## Implementation notes

_Filled in by the agent when done._

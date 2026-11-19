# TASK-187: 2S19 Msta-S self-propelled howitzer playable in the Russian army

- **Status**: done
- **Layers**: core (data) / presentation (catalog, model)
- **Depends on**: TASK-176 (class `sp_artillery`), TASK-181
- **Sections**: GDD "Units", GDD "Stat derivation rules", GDD "Formations"
- **Model**: sonnet
- **Topic**: Units

## Goal

Russia and Belarus field the 2S19 Msta-S, a tracked 152 mm self-propelled howitzer (class `sp_artillery`), in the Russian tank battalion. It shoots indirectly like the K9 but with a shorter reach. Its 3D model is built procedurally from a reference GLB (`/model-unit`).

## Acceptance criteria (testable)

- [x] `data/units/2s19_msta_s.tres`: HP 8, move 3, attack 5, defense 2, effective / max range 21.6 / 24.7 km, min 750 m, indirect fire, K9 sounds.
- [x] The unit is in the Russian and Belarusian rosters and in the in-game catalog.
- [x] A Russian battalion has either gun or rocket artillery: `ru_tank_battalion` fields 1 x Msta-S instead of the Uragan (strength 60); `ru_motor_rifle_battalion` keeps the Uragan.
- [x] Tests for the definition, rosters, catalog, sounds, reach and auto-resolve; `test_operation_balance` stays green.
- [x] GDD (units, derivation, battalions) and MANUAL updated.

## Playtest (for the human)

1. The catalog lists the 2S19 Msta-S for Russia and Belarus.
2. A Russian tank battalion fights with an Msta-S company: indirect fire from 3 to 98 hexes, turret traverses, barrel recoils.

## Player manual

Done (unit table, damage table, battalion tables).

## Out of scope

- Retuning the Suwałki Gap order of battle (data/operations/suwalki_gap.tres).

## Implementation notes

- Model: `src/presentation/models/2s19_msta_s.gd` (commit eae2e9b); silhouette IoU side 0.74 / front 0.84 / top 0.86 against the GLB, limited by the GLB's raised barrel and +14 % width (see blueprint.md).
- Stats follow the K9 derivation; effective range 21.6 km is the K9's 0.875 ratio of the max range **[ASSUMPTION]**. An extra company in both Russian battalions was tried first and broke `test_operation_balance` (NATO 4 of 20 wins, Russia/Poland 1.2), hence the replace-the-Uragan rule: Russia 420 vs. Poland 392 (~1.07).
- Belarus contribution 178 → 180 (it includes the tank battalion).

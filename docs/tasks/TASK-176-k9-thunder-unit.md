# TASK-176: K9 Thunder (K9PL) self-propelled howitzer playable in Poland's army

- **Status**: done
- **Layers**: core (data) / presentation (class tables)
- **Depends on**: – (model `src/presentation/models/k9_thunder.gd` and catalog entry `docs/design/units/units/k9_thunder/` exist, status modeled)
- **Sections**: GDD "Units", GDD "Stat derivation rules", GDD "Combat" (Ranged units), GDD "Formations"
- **Model**: sonnet
- **Topic**: Units

## Goal

Poland fields the K9 Thunder, a tracked 155 mm self-propelled howitzer (new class `sp_artillery`), in its tank battalions; it shoots indirectly at the whole battlefield like the Homar-K, but with a gun's single heavy shell instead of a rocket salvo.

## Decisions (human accepted the catalog assumptions, 2026-11-17)

- **Class**: new `sp_artillery` (already named in GDD "Move" modifiers, `docs/design/units/classes.json` and `test_unit_model_contract.gd`). Reusing `mlrs` is rejected: `mlrs` triggers the rocket volley (`UnitModels.VOLLEY_CLASS`), wheeled dust/tyre marks and the label "Rocket Artillery".
- **Derivation** (GDD rules; catalog: tracked, 47 t, 155 mm/52 cal, fire_range 40 km, crew 5; engine power is not in the catalog, so no power-to-weight modifier):

| Stat | Rule | Value |
|---|---|---|
| max_hp | tracked armoured vehicle 8; weight 47 t < 60 (no +1); ammunition in the hull, not isolated (no +1) | **8** |
| move_points | tracked 4; −1 indirect-fire class | **3** |
| attack | gun artillery, one 155 mm HE shell, unguided: 5 (guided Homar rockets 6 stay stronger); **new table row "Gun artillery 152-155 mm, unguided: 5"** | **5** |
| defense | light armour, proof against fragments and small arms: band 2 | **2** |
| fire_mode | indirect | `indirect` |
| effective range | catalog 40 km is the maximum; Uragan ratio 30/35 km → 35 km | 35000 m = 140 hexes (250 m) |
| max range | catalog `fire_range_km` | 40000 m = 160 hexes |
| min range | artillery rule [ASSUMPTION] | 750 m = 3 hexes |

  Both ranges exceed the map (~30 x 24 hexes): beyond 3 hexes it covers the whole battlefield, like Homar-K. Damage on plains: vs squad (D3) 2, vs Abrams/T-72B3 (D4) 1, vs Uragan/Homar (D1) 4, vs another K9 (D2) 3; Homar-K → K9 = 4.
- `display_name` "K9 Thunder", `short_name` "K9" (≤ 6), `mobility` tracked, `fire_sound` `tank_cannon` (reused, no howitzer recording yet), `engine_sound` `diesel_heavy`, `move_sound` `tracks` (all ids already in `data/audio/sound_bank.tres`).
- **Placement**: Poland roster + `pl_tank_battalion` (4 tank + 2 squads + 1 Homar-K becomes 4 tank + **1 squad + 1 K9** + 1 Homar-K, still 7 companies, 1 `mlrs`); `pl_mech_battalion`, `default_force` and `Scenario.default_battle` unchanged (balance measured 2026-11-17 stays valid). Strength 66 → 64 (HP sum), Poland in `suwalki_gap` 396 → 392, ratio 488/392 = 1.245 (test bound 1.25).
- No `data/strike/` means or looks entry (not a strike weapon). `data/operations/suwalki_gap.tres` needs **no edit** (it only references formation types); another session has uncommitted changes there and in the staff-map files: do not touch or revert them, commit only your own files.

## Acceptance criteria (testable)

- [ ] `data/units/k9_thunder.tres` loads: id `k9_thunder`, "K9 Thunder", "K9", class `sp_artillery`, `tracked`, HP 8, move 3, attack 5, defense 2; `indirect`, 35000 / 40000 / 750 m = 140 / 160 / 3 hexes; sounds `tank_cannon` / `diesel_heavy` / `tracks`. `test_unit_definitions.gd` TABLE and RANGES get the row (the "exactly the six units" test becomes seven; rename it).
- [ ] `poland.tres` roster contains `k9_thunder`; `default_force` is unchanged (`test_factions.gd`: roster 4 ids, default force unchanged).
- [ ] `pl_tank_battalion` = 4 `m1a2_sepv3` + 1 `pl_mech_infantry` + 1 `k9_thunder` + 1 `homar_k` (7 companies, strength 64); `pl_mech_battalion` unchanged (66). The "exactly 1 `mlrs` company" test stays green; `test_operational_data.gd` tables and `suwalki_gap` Poland total (392, 6 formations) and Russia/Poland ratio (1.15-1.25) updated.
- [ ] Damage: K9 → Motor Rifle Squad 2, → T-72B3 1, → Uragan 4; Homar-K → K9 4 (`_damage` tests).
- [ ] A K9 attack at distance 2 is rejected `too_close`, at 3 and at 160 accepted, at 161 `out_of_range`; no line of sight needed (indirect), AI treats it as artillery (`is_indirect`): behind the line, ignores objectives (extend an `test_ai_artillery.gd` case with a K9).
- [ ] `sp_artillery` in presentation tables: `MotionEffects` emits dust/exhaust like `tank` (`emits(&"sp_artillery")` true, same dust, exhaust and cloud values as `tank`); `GroundMarks.track_segments(..., &"sp_artillery")` gives tread marks like `tank`; `UnitModels` does **not** treat it as volley class (`is_volley` false); `CatalogUnits.CLASS_ORDER` = infantry, tank, mlrs, sp_artillery so the catalog lists K9 (`test_unit_catalog`).
- [ ] i18n: `CLASS_SP_ARTILLERY` = "Self-Propelled Howitzer" / "Haubica samobieżna" in `assets/i18n/strings.csv` (no other new strings); the unit popup header shows it (`test_unit_popup.gd` id list gets `k9_thunder`).
- [ ] `test_unit_models.gd` / `test_unit_model_contract.gd` pass for `k9_thunder` (already modelled); `test_sound_planner`: K9 loops are `engine_diesel_heavy` + `move_tracks`, shot `tank_cannon`.
- [ ] Auto-resolve of a contact battle with `pl_tank_battalion` vs `ru_motor_rifle_battalion` completes, is deterministic for a fixed seed and `ResolveBattleCommand` accepts it; `tools/simulate.sh 50 --scenario=contact_battle` shows 0 rejected AI commands.
- [ ] Docs: GDD "Units" table row + "Stat derivation rules" gets the Attack row "Gun artillery 152-155 mm, unguided: 5", the K9 line in "First rosters" and the tank-battalion composition; MANUAL (below). No ARCHITECTURE change (no new event/command).

## Playtest (for the human)

1. Start the Suwałki Gap operation as NATO and open a Polish tank battalion: its companies include a K9 Thunder; the strength is 64.
2. Play that battle: the K9 spawns in the back column, shows tracks and dust when moving, engine and track sound; hover card header "Self-Propelled Howitzer", stats 8 / 3 / 5 / 2.
3. Fire the K9 at an enemy 10+ hexes away: it needs no line of sight, a shot with recoil is heard and the enemy loses HP; at 2 hexes the ring says TARGET TOO CLOSE.
4. Check what the shot looks like (no rocket volley expected; if the single shell has no visible flight, report it for a follow-up, not a failure of this task).
5. Unit catalog: K9 appears under its own class with its model.

## Player manual

docs/MANUAL.md: add K9 Thunder (Poland) to the unit table (8 / 3 / 5 / 2, 35 km effective, 40 km max, min 750 m, "tracked howitzer, fires over everything like rocket artillery but one shell, weaker than Homar-K"); extend the "Roles in short" and the minimum-range lines from "rocket artillery" to "artillery (rocket and howitzer)"; mention the K9 in the Polish tank battalion composition and Suwałki strength numbers (392); ground marks (tracks), catalog class list. Take numbers from `data/units/k9_thunder.tres`.

## Out of scope

- A howitzer sound recording, shell-flight or muzzle-blast effects beyond what existing direct/indirect shot code does, K9 in the Russian roster (the Lithuanian roster does get it, see Implementation notes), class orders for `sp_artillery`, ammunition (48 rounds) and 6 rpm, `data/strike/` entries, wheeled/tracked movement cost differences.

## Implementation notes

Done 2026-11-17. New unit `data/units/k9_thunder.tres` (class `sp_artillery`, 8/3/5/2, indirect 35000/40000/750 m, `tank_cannon` / `diesel_heavy` / `tracks`), added to the Polish and Lithuanian rosters; `pl_tank_battalion` is now 4 tank + 1 squad + 1 K9 + 1 Homar-K (strength 64). `sp_artillery` entries in MotionEffects (as `tank`), GroundMarks (tread marks), CatalogUnits.CLASS_ORDER/PATHS and `CLASS_SP_ARTILLERY` in strings.csv. GDD and MANUAL updated. Strength sums: Poland in `suwalki_gap` 396 → 392, Lithuanian contribution 198 → 196, outside NATO support 132 → 130 (tests updated).

Decisions: the K9 is also in the Lithuanian roster because Lithuania's contribution reuses `pl_tank_battalion` and the operation does not build otherwise (the alternative was a separate Lithuanian formation or an edit of `suwalki_gap.tres`, another session's file); `lithuania` was added to the operators in the catalog entry. Open recommendations accepted: attack 5, move 3.

Known limitations / not covered by tests: `test_auto_resolve_k9` checks determinism of `AutoResolve.resolve`, not `ResolveBattleCommand` acceptance; the K9 AI test checks distance and one attack, not "behind the front / ignores objectives". `tools/simulate.sh 50 --scenario=contact_battle`: 0 errors, 0 rejected AI commands (Poland 29 : Russia 21). Whether a lone indirect shell is visibly flying in battle is unverified (no volley by design).

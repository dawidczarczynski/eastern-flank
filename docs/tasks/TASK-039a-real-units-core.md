# TASK-039a: Real units and countries – core, data, scenario, balance

- **Status**: ready
- **Layers**: core (`UnitDefinition`, `FactionDefinition.default_force`, `Scenario`, match record), ai (`MatchRunner` factions), tools (`simulate.sh --factions`), data
- **Depends on**: **TASK-038** (factions as data), **TASK-037** (catalog entries – done). GDD: "Factions and units", "Stat derivation rules", "Balance of the default battle".
- **Model**: opus

## Goal

The battle is fought between Poland and Russia with real equipment ("M1A2 SEPv3 Abrams" vs "T-72B3"), each unit with its own stats derived from real-world data by the rules in the GDD, and the default battle balanced by unit counts per country.

## Decisions (approved by the human 2026-10-18)

1. **Era: present day**; factions Poland and Russia; rosters below (2026-10-18, human).
2. **Stats** follow GDD "Stat derivation rules"; no new stats (hard/soft attack stays a GDD option).
3. **Names**: `display_name` = real designation, not translated; squads have descriptive English names that are translated. `short_name` = short designation (≤ 6 chars), squads use the class abbreviation `INF`. Squad AT weapons are flavour (no stat effect). See GDD "Naming conventions".
4. **Balance by composition**, stored per faction as data (`default_force`); measured over both side assignments.
5. **Pre-039 match records are unsupported** (rejected with a clear error, no id mapping; record in an ADR). Existing local saves are deleted (human, 2026-10-18).
6. **T-72B3 = obr. 2016** (move 5); infantry dealing 1 damage to tanks and the Abrams one-shotting an MLRS are accepted (revisit after simulations).

## Design

- `UnitDefinition` gains `unit_class: StringName` (`infantry`, `tank`, `mlrs` – ids from `docs/design/units/classes.json`) and `mobility: StringName` (`foot` / `wheeled` / `tracked`).
- Six `data/units/<id>.tres` replace `infantry.tres`, `cavalry.tres`, `rocket_artillery.tres` (deleted; tests/fixtures that need generic units use the new ids or fixture-local definitions).
- `FactionDefinition` gains `default_force: Array[UnitDefinition]` (ordered); every entry must be in the faction's `roster`.
- `Scenario.default_battle(seed, factions := [&"poland", &"russia"])` spawns each player's faction `default_force` in list order: units with `attack_range == 1` fill the front slots, others the back slots.

  | Player | Front column | Front rows (fill order) | Back column | Back rows (fill order) |
  |---|---|---|---|---|
  | 0 | 1 | 3, 5, 7, 1, 9 | 0 | 5, 3, 7 |
  | 1 | `MAP_WIDTH − 2` (10) | 2, 4, 6, 8, 0 | `MAP_WIDTH − 1` (11) | 4, 2, 6 |

  (With Poland as player 0 this reproduces today's player-0 layout.) A force larger than the slots → `push_error`, extra units skipped.
- `MatchRunner.play(seed, max_turns, factions := [&"poland", &"russia"])`; `tools/simulate.sh` gets `--factions=<p0>,<p1>` and prints a line `Factions: <p0> vs <p1>` after the `Matches:` line (other lines unchanged).
- Match record format version bump; older records are rejected with a readable error (ADR).
- Presentation: locomotion and model contract chosen by `mobility` / `unit_class` instead of hard-coded ids (`UnitModels.VEHICLES`); unit label shows `tr(short_name)`; popup shows the translated class label and `tr(display_name)`.

## Acceptance criteria (testable)

- [ ] `tests/unit/test_unit_definitions.gd` (or the existing definitions test): each of the six files loads and has exactly these values:

  | id | display_name | short_name | unit_class | mobility | max_hp | move_points | attack | defense | attack_range |
  |---|---|---|---|---|---|---|---|---|---|
  | `m1a2_sepv3` | M1A2 SEPv3 Abrams | M1A2 | tank | tracked | 10 | 5 | 7 | 4 | 1 |
  | `t72b3` | T-72B3 | T-72B3 | tank | tracked | 8 | 5 | 6 | 4 | 1 |
  | `homar_k` | Homar-K | HOMAR | mlrs | wheeled | 6 | 3 | 6 | 1 | 6 |
  | `bm27_uragan` | 9K57 Uragan | BM-27 | mlrs | wheeled | 6 | 3 | 6 | 1 | 5 |
  | `pl_mech_infantry` | Mechanised Infantry Squad | INF | infantry | foot | 10 | 3 | 4 | 3 | 1 |
  | `ru_motor_rifle` | Motor Rifle Squad | INF | infantry | foot | 10 | 3 | 4 | 3 | 1 |

  and `infantry.tres`, `cavalry.tres`, `rocket_artillery.tres` no longer exist in `data/units/`.
- [ ] Damage spot checks on plains via `AttackCommand.compute_damage`: Abrams → T-72B3 = 3; T-72B3 → Abrams = 2; Abrams → Uragan = 6; Homar-K → Uragan = 5; Motor Rifle Squad → Abrams = 1; T-72B3 → Mechanised Infantry Squad = 3; on hills (+2) Abrams → squad = 2.
- [ ] `test_factions.gd`: Poland roster = {`pl_mech_infantry`, `m1a2_sepv3`, `homar_k`}, Russia roster = {`ru_motor_rifle`, `t72b3`, `bm27_uragan`}; Poland `default_force` ids = [`pl_mech_infantry`, `m1a2_sepv3`, `pl_mech_infantry`, `homar_k`]; Russia `default_force` ids = [`ru_motor_rifle`, `t72b3`, `ru_motor_rifle`, `t72b3`, `bm27_uragan`]; every `default_force` entry is in its roster.
- [ ] `test_scenario.gd`: `default_battle(1)` has 4 player-0 units at offset (1,3) squad, (1,5) Abrams, (1,7) squad, (0,5) Homar-K and 5 player-1 units at (10,2) squad, (10,4) T-72B3, (10,6) squad, (10,8) T-72B3, (11,4) Uragan; all spawn tiles are plains. `default_battle(1, [&"russia", &"poland"])` puts the 5 Russian units on player 0's slots ((1,3), (1,5), (1,7), (1,1), back (0,5)) and the 4 Polish units on player 1's slots.
- [ ] Consistency test: every `data/units/*.tres` has `docs/design/units/units/<id>/unit.json` with `real_name == display_name`, `class == unit_class`, and its roster factions listed in `operators` (test-only JSON read).
- [ ] `test_match_runner.gd`: `play(7, 50, [&"russia", &"poland"])` is deterministic (two calls equal) and never `error`; existing cases still pass (update expectations that depended on the old armies).
- [ ] `test_simulate_options.gd`: `--factions=russia,poland` parses to `[&"russia", &"poland"]`; `--factions=poland` (one id) and an unknown faction id → usage error, exit code 2.
- [ ] Old match record: loading a record with the previous format version fails with a readable error and does not crash (`test_match_saver.gd` / `test_replay.gd`); the replay fixture is regenerated (`tools/make_replay_fixture.sh`). The local `user://matches/last_match.json` (on Linux `~/.local/share/godot/app_userdata/<project name>/matches/`; also check the Windows build's `%APPDATA%\Godot\app_userdata\<project name>\matches\`) is deleted. ADR in `docs/adr/`.
- [ ] **Balance**: run `tools/simulate.sh 200` and `tools/simulate.sh 200 --factions=russia,poland` (seeds 1..200, max 50 turns). Poland wins / decided matches over both runs together is **between 40 % and 60 %**, errors 0, draws ≤ 15 % in each run. If missed, follow the tuning ladder in GDD "Balance of the default battle" (only `default_force` changes, never unit stats) and record every run's output in the implementation notes; if no step lands in the band, stop and report to the human.
- [ ] GDD "Units" table replaced by the six units (or pointing to "Stat derivation rules"), starting armies sentence updated; `ARCHITECTURE.md` mentions `unit_class` / `mobility` / `default_force`.

## Playtest (for the human)

1. Start a battle: left side (blue, Poland) 2 squads, an Abrams and a Homar-K; right side (red, Russia) 2 squads, 2 T-72B3 and an Uragan. Labels above units read `INF`, `M1A2`, `HOMAR` / `INF`, `T-72B3`, `BM-27`; check the 6-character `T-72B3` label fits.
2. Attack a T-72B3 with the Abrams on plains: 3 damage, 2 back. Move the Homar-K to 6 hexes from the Uragan and fire: 5 damage, no counter.

3. Run `tools/simulate.sh 20` – it prints a `Factions: poland vs russia` line and finishes without errors.
4. Press F5 in a battle, then try loading an old record (if you kept one) – a clear "unsupported record" message, no crash.

## Out of scope

- Faction selection UI, more than two players, new 3D models (TASK-031 … TASK-033, `/model-unit`), hard/soft attack, roads, carriers for mechanised infantry, fixing the simulation side bias.

- Presentation and translations (TASK-039b) – until then the view may show the new units with interim labels; it must not crash (`tools/screenshot.sh` works).

## Implementation notes

_Filled in by the agent when done._

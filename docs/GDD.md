# Eastern Flank – Game Design Document

> Living document. Assumptions marked **[ASSUMPTION]** are the starting point for the prototype – to be confirmed or changed.

## Vision

- **Genre**: turn-based tactical 3D strategy on a hex grid.
- **One sentence**: _[to be filled in – what makes this game unique?]_
- **Inspirations**: _[e.g. Battle for Wesnoth, Into the Breach, Civilization, Heroes]_
- **Platform**: PC (Linux/Windows) **[ASSUMPTION]**

## Gameplay loop

1. On their turn, the player gives orders to units (move, attack).
2. They end the turn; the opponent (AI) takes theirs.
3. The last side with living units wins – eliminate all enemy units **[ASSUMPTION]** (see Open questions).

## Map

- Hexes, procedural rectangular map from a seed (12×10 in the prototype battle) **[ASSUMPTION]**.
- Terrain:

  | Terrain | Move cost | Defense bonus | Status |
  |---|---|---|---|
  | Plains | 1 | 0 | implemented |
  | Forest | 2 | +1 | implemented |
  | Hills | 2 | +2 | implemented |
  | Water | impassable | – | implemented |

  Terrain numbers (move cost, impassable, defense bonus) and look (colour, height) live in `data/terrain/*.tres` (`TerrainDefinition`), the source of truth; see ADR 0002.

- **Terrain generation** (TASK-016a, implemented): terrain is derived from a deterministic per-hex **elevation** and **moisture** (fbm/ridged value noise ported from the visual design, `TerrainNoise`; the map seed only picks a world-space offset). Elevation = base + rolling hills + ridged mountains (inside a large-scale mask) + fine detail − lakes (a separate noise; there is no sea edge). Classification: elevation below `water_level` → water; above `hills_level` → hills, or forest when moisture > `highland_forest_moisture`; otherwise forest when moisture > `forest_moisture`, else plains. Spawn tiles are forced to plains with their elevation clamped into the land band (`MapGenerator.force_terrain`). The same height field, corrected around forced tiles, is exposed as a continuous surface (`TerrainSurface.height_at` / `ground_height`) for the 3D view. Elevation has **no rule effect** yet (see Open questions).
- Generator numbers live in `data/map/terrain_generation.tres` (`TerrainGenerationSettings`), hex size 1.0. Current values (the design's starting values; no tuning was needed):

  | group | values |
  |---|---|
  | height | base 0.2; hills freq 0.11, gain 2.4, weight 0.85; mountain mask freq 0.05, from 0.62, to 0.85; mountain freq 0.17, gain 2.1; lake freq 0.09, from 0.6, to 0.75, depth 1.0; detail freq 0.7, amplitude 0.07 |
  | moisture | freq 0.13 |
  | classification | water level 0.02, hills level 0.7, forest moisture 0.61, highland forest moisture 0.66 |
  | forcing bands | land [0.12, 0.7], hills [0.71, 2.2], water [−0.75, −0.05] |

  Resulting mix on 12×10 maps over seeds 1–50: water ≈ 11 %, forest ≈ 18 %, hills ≈ 5.5 %, plains ≈ 66 %; in 46 of 50 maps ≥ 90 % of the land is one connected region. Hills sit at the low end of the tested 5–25 % band – a candidate for tuning once elevation affects rules.
- Tiles without generated elevation (hand-made maps, tests) use a per-type default from `data/terrain/*.tres` (`default_elevation`: plains 0.2, forest 0.25, hills 0.9, water −0.3).

## Visual direction

Target look of the battle screen: `docs/design/` (mock-up made in Claude Design, key values in `docs/design/README.md`). Ported by TASK-013 … TASK-024 **onto the current mechanics** ("look first, rules later"). Gameplay ideas visible in the mock-up are not adopted automatically – they are listed under "Ideas from the visual design" below and wait for a decision.

**Unit feel** (presentation only, no rule effect): moving units walk tile by tile along their path and turn to face it (TASK-022); while moving, infantry marches (per-soldier step bob and sway, kneeling soldiers stand up and kneel again on arrival) and the tank drives (wheels turn with the distance covered, the hull rocks slightly and tilts with the terrain slope, also at rest) (TASK-025). Before a volley the Homar-K raises its launcher pod on hydraulic actuators and turns it towards the target on its turntable, and stows it after the salvo; launchers without a turntable turn the whole vehicle. Dust and track tread animation are possible follow-ups.

**Visual direction: realism (requested 2026-10-20, TASK-049 … TASK-066):** the battle scene moves from the stylised tabletop look toward a realistic one, as a **Steel Division / Combat Mission-like compromise**: realistic terrain, light, vegetation and weathered vehicles, but a clean, minimal UI and units that stay easy to find and click. Principles: overlays outline areas instead of painting tiles (TASK-049); light and haze of an overcast-to-partly-cloudy Eastern European day, muted olive palette, AgX tonemapping (TASK-051, TASK-054); a camera that sees the horizon when zoomed in and looks down when zoomed out, and **no depth-of-field / tilt-shift** (it makes the scene look like a miniature) (TASK-052); events leave visual traces – tracks, craters, wrecks – with no rule effect (TASK-058, TASK-065). Every effect degrades on a LOW quality preset (TASK-050). CC0 assets are allowed (decided 2026-10-22: textures, HDRI skies, vegetation models; unit models stay procedural – TASK-053). **Unit/tree scale (decided 2026-10-22, TASK-059): preset `balanced`** – units × 1.1 (was 1.3), trees × 1.8, bushes × 1.4, rocks × 1.0 (`VisualScale`); forests read as forests, units in a forest are found mostly by their label. Open decision: performance budget (see Open questions).

**Planned (TASK-041 … TASK-048, decided 2026-10-19):** how a unit animates is a property of the real vehicle, declared per unit in the unit catalog as **mechanisms** with parameters (registry `docs/design/units/mechanisms.json`), not per class – the Homar-K and the 9K57 Uragan are both MLRS but are built differently. Mechanisms: `wheels`, `squad_march`, `launcher` (traverse range – full or limited, the vehicle turns first when the target is outside it; stowed tube direction; firing elevation), `stabilisers` (jacks lowered before a volley), `blast_shields` (cab window shields, if the Uragan research confirms them (?)), `turret_traverse` (tank turret and gun aim before firing, also on counters), `gun_recoil` (idea). The model file copies the unit's mechanisms; the game still reads only `data/` and the models.

## Units

| Unit (id) | Country | Class | Mobility | HP | Move | Attack | Defense | Range | Status |
|---|---|---|---|---|---|---|---|---|---|
| M1A2 SEPv3 Abrams (`m1a2_sepv3`) | Poland | tank | tracked | 10 | 5 | 7 | 4 | 1 | implemented |
| T-72B3 (`t72b3`) | Russia | tank | tracked | 8 | 5 | 6 | 4 | 1 | implemented |
| Homar-K (`homar_k`) | Poland | mlrs | wheeled | 6 | 3 | 6 | 1 | 6 | implemented |
| 9K57 Uragan (`bm27_uragan`) | Russia | mlrs | wheeled | 6 | 3 | 6 | 1 | 5 | implemented |
| Mechanised Infantry Squad (`pl_mech_infantry`) | Poland | infantry | foot | 10 | 3 | 4 | 3 | 1 | implemented |
| Motor Rifle Squad (`ru_motor_rifle`) | Russia | infantry | foot | 10 | 3 | 4 | 3 | 1 | implemented |

Source of truth for the numbers: `data/units/*.tres`; how they are derived: "Stat derivation rules" below (TASK-039a).

Starting armies (default battle, `Scenario.default_battle` from each faction's `default_force`): Poland 2 × Mechanised Infantry Squad, 1 × M1A2 SEPv3 Abrams, 1 × Homar-K; Russia 2 × Motor Rifle Squad, 2 × T-72B3, 1 × 9K57 Uragan – on opposite map edges, direct-fire units in front, rocket artillery behind; spawn tiles are always plains. See "Balance of the default battle".

The former generic units (Infantry 10/3/4/3/1, Cavalry 8/5/5/2/1, Rocket Artillery 6/3/5/1/5) are gone from the game data; they remain the **calibration points** of the derivation rules.

## Factions and units (decided 2026-10-18)

- **Factions are real countries** (e.g. Poland, Germany, USA, Russia …), more than two over time. A faction has a name, a UI colour, a camouflage palette and a **roster** of units it can field. Players pick (or a scenario assigns) a faction; two players may not need to be enemies in reality – it's a game. Implemented as data: `data/factions/*.tres` (TASK-038).
- **Units are real equipment with real names** ("Leopard 2A4", "T-72B3", "BM-21 Grad", "Mechanised infantry squad (Bundeswehr)" …), **each with its own stats** in its own `data/units/<id>.tres`. A unit belongs to a **class** (infantry, tank, IFV, MLRS …) that groups shared behaviour (movement type, model contract, AI role, translated class label); the real name is shown as-is and is not translated. The same vehicle may appear in several factions' rosters (e.g. Leopard 2A4: Poland, Germany) with the faction's camouflage. (TASK-039a)
- **Stats are derived from real-world data** (armament, protection, mobility, crew, range) collected in the unit catalog, by explicit rules the game-designer writes down (e.g. main gun calibre → attack band, armour class → defense band), so new units can be added consistently.
- **Unit catalog** (`docs/design/units/`, edited with `tools/unit_catalog.sh`, TASK-037): one entry per real unit with identity, real-world facts, dimensions, silhouette features and reference images. It is the input for the game-designer (stats) and for the `unit-modeler` agent (3D models). It is reference data, not game data: the game reads only `data/`.
- **Era: present day.** A unit qualifies if it is in active service today – older designs still fighting (e.g. in the war in Ukraine) count; the variant is the one in service (T-72B3, not T-72A).
- **First factions and rosters** (prototype battle, one unit per current class):

  | Class | Poland (player 0) | Russia (player 1) |
  |---|---|---|
  | Tank | M1A2 SEPv3 Abrams | T-72B3 |
  | Rocket artillery | Homar-K (K239 Chunmoo launcher on a Jelcz 8×8 chassis) | 9K57 Uragan (BM-27, ZIL-135 8×8) |
  | Infantry | Mechanised infantry squad, wz. 93 Pantera camouflage, MSBS Grot rifles | Motor rifle squad, EMR ("Tsifra") digital camouflage, AK-74M / AK-12 rifles |

  UI colours follow NATO symbology: Poland (the player's default side) blue `#5b93d6`, Russia red `#d76a52`. Camouflage palettes come from each faction's data (Pantera woodland and Polish vehicle green/brown/black vs. EMR digital and Russian vehicle green/black/sand). Stats: see "Stat derivation rules".
- **Naming conventions** (approved by the human 2026-10-18):
  - `display_name` = the real designation in its common English form ("M1A2 SEPv3 Abrams", "T-72B3", "Homar-K", "9K57 Uragan"), shown as-is in every language. Units without a designation (squads) get a **descriptive English name** that *is* translated: Poland "Mechanised Infantry Squad" (pl "Drużyna piechoty zmechanizowanej"), Russia "Motor Rifle Squad" (pl "Drużyna zmotoryzowana"). The view always calls `tr(display_name)`; only the descriptive names have CSV rows, designations fall through unchanged.
  - `short_name` (the label above the unit, ≤ 6 characters) = a short real designation: `M1A2`, `T-72B3`, `HOMAR`, `BM-27`; squads and the generic placeholder units use the translated class abbreviation: `INF` (pl `PIECH`), `TNK` (pl `CZOŁ`), `ART`. With several vehicles per class in one roster later, the designation is what tells them apart; the side is already shown by colour.
  - The **hover card** shows the translated class (`CLASS_TANK` "Tank" / "Czołg", `CLASS_MLRS`, `CLASS_INFANTRY`) as its header and `tr(display_name)` below it, so the class is never only implied by the label (confirmed by the human 2026-10-19).
  - **Squad AT weapons are flavour, not stats**: a squad's unguided AT weapons are part of the infantry base attack; only a guided ATGM carried *by the squad itself* adds to attack (see rules). Poland: RPG-7 (Carl Gustaf M4 entering service (?)); Russia: RPG-7V2 plus disposable RPG-26 / RShG-2. Javelin / Spike (Poland) and Kornet / Metis (Russia) are platoon/company assets and are not counted. The `unit-modeler` may show the AT weapon on one soldier.
- **3D models**: one procedural model per unit (`src/presentation/models/<unit_id>.gd`), camouflage from the faction, built and checked by the `unit-modeler` agent against the catalog (`/model-unit`, TASK-036).

## Stat derivation rules

> Proposed by the game-designer and **approved by the human on 2026-10-18** (TASK-039a). Uses the existing stat set (HP, move, attack, defense, attack range) and the current damage formula `max(1, attack − (defense + terrain bonus))`.

### Principles

1. **Stats come from catalog facts** (`docs/design/units/units/<id>/unit.json`) through the tables below: a class base plus named modifiers, each reading one catalog field. Changing one unit's stat means changing a rule, so every unit it applies to changes consistently.
2. **Balance between countries comes from scenario composition** (unit counts), never from bending a unit's stats. Real-world asymmetry is kept.
3. **Calibration points** are the generic units: infantry (HP 10, move 3, attack 4, defense 3, range 1) = a foot squad; cavalry (8 / 5 / 5 / 2 / 1) = the fast armoured strike unit, the base of the tank band (HP 8, move 5); rocket artillery (6 / 3 / 5 / 1 / 5) = a truck-mounted unguided MLRS.
4. **Defense bands are coarse.** With a subtractive formula every defense point changes every matchup, so defense has only four bands and armour generations differ through **HP** (weight, ammunition isolation) instead. Attack may be finer.
5. **Unknown fact → no modifier.** Facts marked (?) must be confirmed in the catalog before the stats are approved.
6. **Standard equipment only**: the variant in service and its standard munition (no special rounds, no strategic missiles).

### Tables

**HP** (catalog: `class`, `weight_t`, `notes` on ammunition stowage)

| Base | HP |
|---|---|
| Foot squad (any size of 6–10 dismounts) | 10 |
| Tracked armoured vehicle (MBT) | 8 |
| Unarmoured wheeled vehicle | 6 |

Modifiers: +1 combat weight ≥ 60 t; +1 ammunition stowed isolated from the crew with blow-out panels.

**Move** (catalog: `mobility`, engine power and `weight_t`, `class`)

| Base | Move |
|---|---|
| Foot | 3 |
| Wheeled | 4 |
| Tracked | 4 |

Modifiers: +1 tracked with power-to-weight ≥ 20 hp/t; −1 indirect-fire classes (`mlrs`, `sp_artillery`: emplacement, reload and displacement eat into the turn). Road speed is not used until roads exist (see "Ideas from the visual design"); then wheeled units should profit from roads.

**Attack** (catalog: `armament`, fire control in `notes`)

| Base | Attack |
|---|---|
| Infantry squad: rifles, MG, unguided AT weapons | 4 |
| MBT with a 120/125 mm smoothbore and a thermal gunner's sight | 6 |
| MLRS, unguided rockets < 200 mm | 5 |
| (generic cavalry – the future light tank / recon band) | 5 |

Modifiers: infantry +1 guided ATGM organic to the squad (not platoon/company assets); MBT +1 hunter-killer fire control (commander's independent thermal sight), −1 no thermal gunner's sight; MLRS +1 calibre ≥ 200 mm **or** guided rockets (one step at most – both mean a heavier effect of one salvo on one hex, the stat does not stack them).

**Defense** (catalog: `protection`)

| Band | Defense |
|---|---|
| Soft-skinned vehicle (trucks, wheeled launchers – also with an armoured cab, the launcher and ammunition stay exposed) | 1 |
| Light armour, proof against small arms / heavy MG (APC, IFV, recon); generic cavalry | 2 |
| Dismounted infantry (dispersion, cover; body armour does not add a band) | 3 |
| MBT (composite and/or ERA) | 4 |

**Attack range** (catalog: `armament`, `fire_range_km`) – a banded scale, not km per hex, because direct and indirect fire ranges differ by an order of magnitude:

| Fire | Range |
|---|---|
| Direct fire (rifles, MG, tank guns, squad AT, ATGM ≤ ~5 km) | 1 |
| Indirect, standard munition < 25 km | 4 |
| Indirect, 25–60 km | 5 |
| Indirect, > 60 km (cap) | 6 |

### First rosters (TASK-039a)

Facts are the ones used by the rules; sources are starting points, the catalog (TASK-037) is where they are confirmed. (?) = uncertain.

| Unit (id) | Facts used | HP | Move | Attack | Defense | Range |
|---|---|---|---|---|---|---|
| **M1A2 SEPv3 Abrams** (`m1a2_sepv3`, Poland) | 120 mm M256 smoothbore; gunner's thermal sight + Commander's Independent Thermal Viewer (hunter-killer); composite armour (Polish export package without DU (?)); ≈ 66–67 t (?); AGT1500 1500 hp → ≈ 22.5 hp/t; turret-bustle ammunition behind doors with blow-out panels. [M1 Abrams](https://en.wikipedia.org/wiki/M1_Abrams) | 8 +1 (≥ 60 t) +1 (isolated ammo) = **10** | 4 +1 (≥ 20 hp/t) = **5** | 6 +1 (hunter-killer) = **7** | MBT **4** | direct **1** |
| **T-72B3** (`t72b3`, Russia) | 125 mm 2A46M-5 smoothbore, carousel autoloader; Sosna-U gunner's sight with thermal channel, no independent commander's thermal sight (?); Kontakt-5 ERA (obr. 2016: Relikt (?)); ≈ 46 t; V-92S2F 1130 hp (obr. 2016; 2011 batch V-84-1 840 hp) → ≈ 24.6 hp/t (?); ammunition in the crew compartment, no blow-out panels. [T-72 – T-72B3](https://en.wikipedia.org/wiki/T-72) | **8** | 4 +1 (≥ 20 hp/t, obr. 2016) = **5** | **6** | MBT **4** | direct **1** |
| **Homar-K** (`homar_k`, Poland) | K239 Chunmoo launcher on a Jelcz 8×8 (?) truck; 2 pods × 6 239 mm CGR-080 GPS/INS-guided rockets, ≈ 80 km (?) (KTSSM missile pods not counted); soft-skinned launcher (armoured cab (?), ignored by the rule). [K239 Chunmoo](https://en.wikipedia.org/wiki/K239_Chunmoo) | wheeled **6** | 4 −1 (indirect) = **3** | 5 +1 (≥ 200 mm / guided) = **6** | **1** | > 60 km **6** |
| **9K57 Uragan** (`bm27_uragan`, Russia) | 9P140 launcher on ZIL-135LM 8×8; 16 × 220 mm unguided 9M27 rockets, max ≈ 35 km; unarmoured. [BM-27 Uragan](https://en.wikipedia.org/wiki/BM-27_Uragan) | wheeled **6** | 4 −1 (indirect) = **3** | 5 +1 (≥ 200 mm) = **6** | **1** | 25–60 km **5** |
| **Mechanised Infantry Squad** (`pl_mech_infantry`, Poland) | ≈ 8 dismounts (?); MSBS Grot 5.56 mm rifles, squad MG, RPG-7 (Carl Gustaf M4 (?)), no squad-level ATGM; body armour; wz. 93 Pantera. [MSBS Grot](https://en.wikipedia.org/wiki/MSBS_Grot), [wz. 93 Pantera](https://en.wikipedia.org/wiki/Wz._93_Pantera) | foot squad **10** | foot **3** | **4** | **3** | direct **1** |
| **Motor Rifle Squad** (`ru_motor_rifle`, Russia) | ≈ 6–9 dismounts (?); AK-74M / AK-12 5.45 mm, PKM/Pecheneg MG, RPG-7V2 + RPG-26 / RShG-2, no squad-level ATGM; Ratnik body armour; EMR camouflage. [AK-12](https://en.wikipedia.org/wiki/AK-12), [Ratnik](https://en.wikipedia.org/wiki/Ratnik_(program)) | foot squad **10** | foot **3** | **4** | **3** | direct **1** |

The carrier (Rosomak / BMP / BTR) is not modelled: both squads are class `infantry` (foot). A future `mech_infantry` class with a carrier would get a vehicle move band.

**Resulting matchups on plains** (damage, attacker row → defender column):

| Attacker \ defender | Infantry (D3, 10 HP) | Abrams (D4, 10 HP) | T-72B3 (D4, 8 HP) | MLRS (D1, 6 HP) |
|---|---|---|---|---|
| Infantry (A4) | 1 | 1 | 1 | 3 |
| Abrams (A7) | 4 | 3 | 3 | 6 (kills) |
| T-72B3, Homar-K, Uragan (A6) | 3 | 2 | 2 | 5 |

Consequences to watch: tanks dominate infantry (infantry deals the minimum 1 to every tank); an Abrams reaching an MLRS destroys it in one attack; Homar-K out-ranges the Uragan (6 vs 5) and can hit it without a counter; 1 Abrams ≈ 2 T-72B3 by HP × damage (10 × 3 vs 8 × 2).

### Balance of the default battle

- **Composition by faction** (quality vs. mass): Poland 2 × Mechanised Infantry Squad, 1 × M1A2 SEPv3, 1 × Homar-K (4 units, 36 HP); Russia 2 × Motor Rifle Squad, 2 × T-72B3, 1 × 9K57 Uragan (5 units, 42 HP). The second T-72B3 compensates the Abrams; nothing compensates the Homar-K's range on purpose (it is the guided-rocket advantage) – the simulation decides whether that needs more Russian units.
- The composition is balance data: an ordered `default_force` list in each faction's `.tres`, not code. Spawn slots: units with range 1 fill the front column, others the back column, in list order (exact slots in TASK-039a).
- **Verification**: the AI-vs-AI simulation already shows a side bias with mirrored armies (TASK-012: player 1 won 59 % vs 34 %), so balance is measured with **both side assignments**: `tools/simulate.sh 200` (Poland = player 0) and `tools/simulate.sh 200 --factions=russia,poland`. Target: Poland's share of the decided matches over both runs together is 40–60 %, no errors, draws ≤ 15 % per run.
- **Measured** (TASK-039a, 2026-10-20, seeds 1..200, 50 turns, compositions above, no ladder step needed): Poland as player 0 won 90, Russia 104, 6 draws; Russia as player 0 won 80, Poland 115, 5 draws → Poland 205 of 389 decided matches = **52.7 %**, errors 0, draws 3.0 % / 2.5 %. The player-1 side bias persists in both assignments.
- **Tuning ladder** if the target is missed (stats stay untouched; one step at a time, re-run both): Poland > 60 % → add a third Motor Rifle Squad; still > 60 % → add a third T-72B3. Russia > 60 % → replace the second T-72B3 with a Motor Rifle Squad; still > 60 % → mirrored counts (2 squads, 1 tank, 1 MLRS each). If no step lands in the band, record the results and ask the human (a rule change is needed, not a count change).

### Option, not adopted: hard/soft attack

Split `attack` into `attack_soft` (vs. infantry and soft-skinned targets) and `attack_hard` (vs. armoured), with an `armored` tag on units. **Gains**: squads with ATGMs and the Javelin-vs-RPG difference become meaningful against tanks; unguided rockets get weak against MBTs, guided ones less so; infantry stops being uniformly 1 damage against tanks. **Costs**: every unit gets two attack values and a tag, the damage formula and counterattack read the target type, the AI target choice and the popup change, all rules above need a second attack table, and every balance number gets re-derived. **Recommendation**: not now. Revisit after the TASK-039a simulations if infantry turns out useless against tanks – the cheaper alternative to try first is the "Damage scale" question (e.g. HP and attack ×2 with defense unchanged, which widens the spread between matchups so that fewer of them sit at the minimum of 1).

## Combat

Implemented in TASK-001 and TASK-002 (`AttackCommand`):

- **Attack**: a unit may attack one living enemy unit within its `attack_range` (hex distance; 1 = adjacent). Rejection codes: `game_over`, `unit_not_found`, `not_your_unit`, `not_an_enemy`, `already_attacked`, `out_of_range`.
- **Once per turn**: each unit attacks at most once per turn. Attacking sets the attacker's remaining movement to 0 – a unit can move then attack, but not attack then move. Both are reset at the start of the owner's turn.
- **Damage** = `max(1, attack − (defense + defense bonus of the defender's tile))` (`AttackCommand.compute_damage`; the attacker's tile doesn't matter), **deterministic**, no RNG **[ASSUMPTION]** (see Open questions: randomness). Matchups on plains: see "Resulting matchups on plains" under "Stat derivation rules".
- **Death**: a unit whose HP drops to 0 dies (`unit_died`), is removed from the map and no longer blocks its tile.
- **Victory**: when exactly one player has living units left, that player wins (`game_over`, `GameState.winner`); after that every command is rejected with `game_over` **[ASSUMPTION]**.

Implemented in TASK-010 and TASK-011:

- **Counterattack** (TASK-010): a defender that survives and has the attacker within its own `attack_range` hits back once with the same formula; deterministic **[ASSUMPTION]**; doesn't use the defender's attack for the turn; a unit counters every attack it survives; a counter never triggers another counter and can kill the attacker (and end the game).
- **Ranged units** (TASK-011): self-propelled rocket artillery with range 5 can attack melee units (range 1) from distance 2 to 5 without being countered. There is **no minimum range**: artillery can also attack at distance 1 (and is then countered), and it counters any attacker within 5 hexes. Range ignores terrain and units (no line of sight).

Player-facing description of these rules: docs/MANUAL.md.

## Open questions

Each question lists the tasks that depend on the answer.

- **Victory condition**: elimination of all enemy units is the current **[ASSUMPTION]**. Alternatives: hold objectives, kill the leader, turn limit with points. → TASK-012 uses a harness-only turn limit (draw) and would change if a turn limit becomes a real rule; future scenario tasks.
- **Turn limit as a game rule?** Not in the game yet; only the AI-vs-AI simulation (TASK-012) stops matches after N turns. → TASK-012.
- **Randomness in combat**: deterministic (like Into the Breach) or with rolls (like Wesnoth)? Currently deterministic **[ASSUMPTION]**. → TASK-002 (flat defense bonus vs. hit-chance modifier), TASK-010 (deterministic counter), TASK-011 (rocket artillery balance). Replays (TASK-005) work either way, because all randomness goes through `GameState.rng`.
- **Damage scale**: with the subtractive formula and current stats, most matchups deal 1–3 damage, and terrain bonuses (TASK-002) push many of them to the minimum of 1, which makes terrain differences between units disappear. Should HP/attack be scaled up (e.g. ×2) or the formula changed? → revisit with TASK-012 statistics after TASK-002/-010/-011.
- **Forest vs. hills**: with the proposed numbers hills (+2) strictly dominate forest (+1) at the same move cost. Should they differ in another way (e.g. forest blocks rocket fire, hills give +1 range)? → TASK-002, TASK-011 follow-ups.
- **Scale**: tactical skirmishes (a few units) or strategy with an economy and cities? → TASK-007 (fog of war), map size, AI scope.
- **Setting**: modern military with real countries and real equipment (decided 2026-10-18). Era: present day; first factions Poland and Russia with their rosters (see "Factions and units"). → TASK-039a.
- **Old match records** (decided 2026-10-18): records made before TASK-039a are unsupported – the loader rejects them with a clear message, and existing local saves are simply deleted. → TASK-039a.
- **Modes**: vs AI only, hot-seat, network multiplayer? → TASK-005 (command serialization is the groundwork for network/replays), `HUMAN_PLAYER` constant in the battle controller, TASK-007 (hot-seat fog needs a hand-off screen).
- **Fog of war**: yes/no, and per player vision rules? → TASK-007 (stays `idea` until scale and modes are decided).
- **Cavalry's look**: the mock-up has no cavalry; TASK-019 uses the mock-up's **tank** model for cavalry as an interim (both are the fast 5-move unit). Answered by the setting decision: cavalry is replaced by the tank class in TASK-039a. → TASK-019, TASK-039a.
- **Stat derivation rules**: proposed 2026-10-18 (see "Stat derivation rules"), no new stats; hard/soft attack recorded as a non-adopted option. Approved by the human on 2026-10-18 (the section header says so; this entry previously still said "waiting for approval"). → TASK-039a.
- **Rocket artillery at close range** (found while writing the manual, 2026-10-18): the code has no minimum range, so artillery fires at adjacent enemies and counters adjacent attackers with its full attack 5 – e.g. cavalry attacking artillery takes 3 counter damage, as much as from a cavalry. The visual-design idea (indirect fire at range 3–6, no firing after moving) would change that. Keep it, add a minimum range (e.g. 2, which also removes the close-range counter), or reduce close-range damage? → TASK-039a balance / follow-up task.
- **T-72B3 variant** (decided 2026-10-18): obr. 2016 (V-92S2F 1130 hp → move 5). The 2011 batch could become a separate unit later.
- **Squad facts to confirm**: Polish mechanised squad size and whether Carl Gustaf M4 is a squad weapon; whether either side has a squad-level guided ATGM (it would give +1 attack). → TASK-039a (catalog).
- **Infantry vs. tanks** (accepted 2026-10-18, revisit after simulations): with the derived stats infantry deals the minimum 1 damage to every tank and takes 3–4. Acceptable for now (tanks *should* beat infantry in the open), but if simulations show infantry is pointless, look at the "Damage scale" question or hard/soft attack. → TASK-039a follow-up.
- **One-shot kills** (accepted 2026-10-18, revisit after simulations): an Abrams destroys a full-HP MLRS in one attack on plains (7 − 1 = 6 HP). Kept as the reward for reaching the artillery; revisit if it dominates the AI matches. → TASK-039a.
- **Side bias in the simulation**: mirrored armies gave player 1 a 59 % vs 34 % win rate (TASK-012), cause unknown. TASK-039a measures balance over both side assignments; the bias itself is a separate follow-up. → TASK-012, TASK-039a.
- **UI scaling**: HUD sizes are the mock-up's CSS pixels 1:1 (matches 1280×720 screenshots). Stretch mode / scaling for larger or smaller windows is undecided. → TASK-014, TASK-020.
- **Does elevation matter for rules?** TASK-016a generates an elevation per hex (shown in metres in the terrain panel, TASK-024). Possible uses: defense bonus for the higher unit, vision/line of sight, ranged bonus. → future tasks; TASK-011 (rocket artillery) could use it.
- **Unit mechanisms (animation)**: real values to verify – Uragan launcher traverse range, maximum elevation, stowed facing forward over the cab, rear jacks, cab blast shields (?); Homar-K jack count/position and real maximum elevation (keep 40° for the look?) (?); tank gun elevation limits (?). Behaviour choices proposed but not confirmed: a limited-traverse launcher's vehicle stays turned after the volley; the launcher always fires at its maximum elevation (not scaled with range); durations are global, not per unit; the turret returns to the front after firing; feet of jacks may float slightly on slopes; the catalog ↔ model contract test fails on any parameter drift. → TASK-041 … TASK-047.
- ~~**Third-party CC0 assets**~~ – decided 2026-10-22: the human allows downloaded CC0 assets – textures and HDRI skies (Poly Haven, ambientCG), vegetation / tree glTF models (TASK-060 option B possible); unit models stay procedural. Recorded in an ADR by TASK-053. → TASK-053, TASK-054, TASK-055, TASK-060.
- **Performance budget** (2026-10-20): target a D3D12 GPU (Windows, Forward+); the WSLg software renderer is preview-only. Every realism feature must switch off on the LOW preset. Which GPU is the minimum target, and is a MEDIUM preset or a settings screen needed? → TASK-050 and every realism task.
- **Wrecks** (2026-10-20): proposed **[ASSUMPTION]** – destroyed vehicles leave a cosmetic wreck that hides when a unit enters its tile, smoke for 3 turns, infantry leaves none. Wrecks never affect rules unless a separate rules task decides otherwise. → TASK-065.
- **Russian vehicle markings** (2026-10-20): proposed **[ASSUMPTION]** – tactical numbers only, no national insignia, never "Z"/"V" symbols; Polish vehicles carry the red-white checkerboard. → TASK-063.
- **Map size**: the mock-up map is 26×18 hexes; the prototype battle is 12×10. Bigger maps change pacing and AI cost. → scale question above.

### Ideas from the visual design

Seen in the mock-up (`docs/design/game_screen.scene.js`), **not** part of the visual tasks. Each needs a decision before it gets a task.

- **More terrain types**: *fields* (cost 1, small defense bonus), *mountains* (cost 3, high defense, impassable for wheeled units), *urban* / named cities (cost 1, high defense, buildings scatter), plains vs. fields split. The terrain colouring already shows "mountain" heights as rock/snow on HILLS tiles.
- **Roads** (cost 1 on any terrain, AI/pathfinding preference) and **rivers** (+1 move cost to enter a river hex without a road, river valley carving in the height field).
- **Sea coast** on one map edge (the mock-up's land mask) – would need spawn rules that keep both armies on land.
- **Defense as a percentage** (`+25 %` forest, `+30 %` hills, `+50 %` mountains, `+40 %` urban) instead of the flat bonus of TASK-002 – ties to the "Randomness in combat" question.
- **Hard/soft attack** (separate attack values against armoured and unarmoured targets) and unit **tags** (armoured, tracked, wheeled, infantry, indirect fire) that drive terrain costs per movement type.
- **Ammunition** (`ammo / ammoMax`, consumed by attacks; resupply rules unknown).
- **Vision range** per unit (2–3 hexes) – ties to fog of war (TASK-007).
- **Experience ranks**: Recruits → Regulars → Experienced → Veterans (3 pips), gained in combat; effect on stats undecided.
- **Rocket artillery (MLRS)**: indirect fire at range 3–6, cannot fire after moving, cannot enter mountains, forest costs 3, 6 HP, 2 ammo.
- **Modern-military setting** with factions "Northern Alliance" (`#5b93d6`) and "Eastern Pact" (`#d76a52`), units as tank / mechanised infantry / MLRS – would answer the "Setting" question and rename the roster.
- **Unit identity**: names ("Platoon 'Lynx'"), formation designations ("3rd Mech. Battalion · 1st platoon"), portraits rendered from the 3D model.
- **Scenario flavour**: operation name and a loading screen ("Operation Iron Shore"), city labels on the map.

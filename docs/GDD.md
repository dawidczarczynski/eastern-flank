# Eastern Flank – Game Design Document

> Living document. Assumptions marked **[ASSUMPTION]** are the starting point for the prototype – to be confirmed or changed.

## Vision

Full vision: [VISION.md](VISION.md) (2026-10-30). It moves the game from a single tactical battle to **two layers**: an operational map (formations, logistics, reconnaissance, air defence, deep strikes, political events) as the main scene, and tactical battles that start on contact and are fought in the conditions the operation created. Everything below this section describes the tactical layer as implemented so far, except the section "Operational layer" (specified, not implemented yet).

- **Genre**: turn-based (I-go-you-go) 3D operational + tactical strategy on hex grids.
- **One sentence**: run a real present-day NATO vs. Russia operation on Europe's eastern flank, where deep strikes, supply and command shape every battle before it starts.
- **Inspirations**: WARNO (zoom from symbols to models), Combat Mission / Steel Division (look), Panzer General / Steel Panthers (turn-based combat), operational wargames.
- **Platform**: PC (Linux/Windows) **[ASSUMPTION]**

## Vision decisions (2026-10-30)

Taken by the human while reviewing VISION.md; tasks in the backlog section "Two-layer game (vision)".

- **Unit scale**: a tactical unit is a **company**; the 3D model (a squad, one tank, one launcher) only represents it. HP is the company's **strength**, not one vehicle's health. An operational formation (battalion / brigade) enters a battle as a set of companies whose HP follows the formation's state; battle losses flow back into the formation.
- **Tactical maps come from real geography**: operational and tactical maps are generated from real map data (land use, roads, rivers, elevation – e.g. OpenStreetMap + a DEM), imported offline and committed as data; the game stays offline and deterministic. A battle's map is the real terrain around the contact point. The random generator stays only for tests and quick battles; it is not tuned further.
- **Victory conditions and turn limits are per battle** (`BattleObjectives`): a list of conditions (hold / take objectives, destroy a share of the enemy, survive N turns, exit through a map edge) plus a turn limit. Authored for scenario battles, derived from the operational situation for contact battles. Replaces "eliminate all enemy units".
- **C2 delay = command points**: each turn a side has N command points; activating a unit (its first move or attack in the turn) costs 1. N comes from the battle conditions – a damaged C2 (e.g. by a deep strike) lowers it.
- ~~**Battles are always played** – no auto-resolve for now.~~ Superseded 2026-11-01: see "Auto-resolve" below.
- **Fog of war** is in the MVP (both layers); reconnaissance drives deep strike accuracy.
- **Priorities**: the core loop "operation → deep strikes → battle → consequences" comes first; new visual polish waits (TASK-048, TASK-063, TASK-066 and further model reworks move down the backlog).
- **Tactical randomness** – decided 2026-10-30 (TASK-089a, numbers in "Combat" → "Per-element rolls"): per-element rolls (each strength point of the attacking company rolls to inflict a loss, so a full company has a small spread and a battered one a large spread; a damaged company deals less), with the expected range shown before the attack; later suppression / morale checks from fire (TASK-090) and indirect-fire accuracy from spotting. All through `GameState.rng`.
- **First theatre** – **decided 2026-11-01**: a regional theatre of about 300 × 300 km around the Suwałki Gap – north-east Poland, the Kaliningrad oblast, southern Lithuania and western Belarus (GDD "Operational layer" → "Theatre").
- **Operational freedom** – **decided 2026-11-01**: the player gets real strategic choices beyond the front – attack the Kaliningrad oblast or Belarus, or keep them out of the war; escalate or de-escalate. Modelled by a stance per country and one shared escalation ladder (GDD "Countries and stances", "Escalation ladder", "Strategic options").
- **Two player roles** – **decided 2026-11-01**: the two layers are also two roles played by the same person. On the operational layer the player is, in one person, the **head of government** (politics) and the **chief of the general staff** (the operation); in a battle the player takes the role of the **lower-rank commanders** (battalion / company level) who fight it. Details in "Operational layer" → "Player roles".
- **Auto-resolve** – **decided 2026-11-01** (replaces "battles are always played"): at every contact the player chooses to play the battle or to auto-resolve it. Auto-resolve computes the result from the same forces, postures, terrain and battle conditions, deterministically, and hands back the same kind of `BattleResult` as a played battle, so the operation treats both alike. AI-vs-AI battles (simulation, TASK-103) are always auto-resolved. Rules in "Operational layer" → "Battle hand-off and auto-resolve"; task [TASK-120](tasks/TASK-120-battle-auto-resolve.md).
- **Both sides playable, sides are blocs** – **decided 2026-11-01**: the player picks a side when starting an operation and the AI plays the other one (its leader and its commanders). The two sides are blocs – the **North Atlantic Alliance (NATO)** vs **Russia** – and **third countries** take part only through the political game: **Belarus** (on the map, aligned with Russia), possible **North Korean units** and possible **Chinese and Iranian weapons** (off the map). Nothing of the off-map third group is present or fixed at the start; it comes in (or not) through the escalation level, stances, decisions and incidents. Details in "Operational layer" → "Sides" and "Outside support".
- **Build order: the core loop first, politics after** – **decided 2026-11-01**: the loop "move → contact → battle (played or auto-resolved) → consequences" is closed before the political layer (TASK-113 … TASK-118) is built; the political rules then hook into the finished loop (e.g. the border rule for battles is added by TASK-116 to TASK-094's contact rule). Order and milestone in docs/tasks/BACKLOG.md ("Two-layer game").

## Gameplay loop

1. On their turn, the player gives orders to units (move, attack).
2. They end the turn; the opponent (AI) takes theirs.
3. The battle ends by its own objectives (`BattleObjectives`, TASK-088, ADR 0016): an optional turn limit and a list of victory conditions per player – `eliminate` (no enemy units left → immediate win), `take_hexes` (own units on all listed hexes at the end of an own turn → immediate win), `hold_hexes` (owns all listed hexes when the turn limit ends the battle; exactly one qualifying player wins, otherwise a **draw**), `destroy_share` (the enemy lost ≥ X % of its starting total HP → immediate win). An objective hex is owned by the last side that **ended a move** on it (passing through does not capture; initial owner from the data). The turn limit ends the battle after the last player's turn of turn `turn_limit`. The default battle keeps "eliminate for both, no turn limit"; the objective test battle is `data/scenarios/objective_battle.tres` (see Open questions: Victory condition).

## Map

- Hexes, procedural rectangular map from a seed (12×10 in the prototype battle) **[ASSUMPTION]**.
- **Hex size: 250 m** between neighbouring hex centres (a company frontage) on every tactical map – real-terrain maps (ADR 0018) and generated maps alike (decided 2026-10-31); one world unit (centre to corner) = 250 / √3 ≈ 144.3 m. The battle scene is drawn at real size on this scale (see "Visual direction").
- Terrain:

  | Terrain | Move cost | Defense bonus | Status |
  |---|---|---|---|
  | Plains | 1 | 0 | implemented |
  | Forest | 2 | +1 | implemented |
  | Hills | 2 | +2 | implemented |
  | Water | impassable | – | implemented |
  | Fields | 1 | 0 | specified (TASK-108) – real-terrain maps only |
  | Urban | 1 | +2 | specified (TASK-108) – real-terrain maps only |
  | Marsh | 2 | 0 | specified (TASK-108) – real-terrain maps only |

  Proposed for fog of war (TASK-007, no rule yet): forest, hills and urban block sight; plains, fields, marsh and water don't.

- **Roads and rivers** (specified, [TASK-108](tasks/TASK-108-terrain-types-from-real-data.md); real-terrain maps only): each tile stores a 6-bit link mask per feature (a line from its centre across a hex side into the neighbour). **Roads apply per link**: a step from A to B costs 1 when A has a road link towards B, whatever B's terrain (water stays impassable). **Rivers apply per hex**: a tile with a river link is a river hex; entering it costs +1 on top of its terrain, unless the step follows a road link (bridge); leaving is free. Numbers in `data/terrain/features.tres`. Invariant: the most expensive passable step (2 + 1 = 3) never exceeds the smallest unit movement (3), so every unit can enter every passable hex from a full move. Importer: urban when ≥ 20 % of the hex is built-up, marsh when ≥ 25 % is wetland (after water/forest dominance, before hills and fields); rule roads = `highway` motorway … residential (not `track`); rivers = `waterway` river, canal, named stream.

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

**Unit feel** (presentation only, no rule effect): moving units walk tile by tile along their path and turn to face it (TASK-022); while moving, infantry marches (per-soldier step bob and sway, kneeling soldiers stand up and kneel again on arrival) and the tank drives (wheels turn with the distance covered, the hull rocks slightly and tilts with the terrain slope, also at rest) (TASK-025). Before a volley a rocket launcher raises its pod on hydraulic actuators and turns it towards the target on its turntable, and stows it after the salvo; how far the turntable turns, how high it elevates and which way the tubes face when stowed are per unit (the Homar-K turns freely; the Uragan only ±30°, so for a target outside that range the whole vehicle turns first and stays turned); launchers without a turntable turn the whole vehicle. A tank turns its turret and elevates or depresses its gun towards the target before firing, also for a counterattack, and returns the turret to the front afterwards (TASK-047). Implemented (TASK-048): as the shot lands, the barrel kicks back and runs out (a per-unit, mildly exaggerated length: Abrams 0.5 m, T-72B3 0.4 m) and a short flash bursts at the muzzle – the flash is the main cue, the recoil a secondary twitch; one flash and at most one light per shot (the light on HIGH only), inside the existing 0.4 s hit step, so attacks don't get longer. Infantry has no firing flash (too small at this scale). Muzzle smoke, tracers, sound and track tread animation are possible follow-ups.

**Visual direction: realism (requested 2026-10-20, TASK-049 … TASK-066):** the battle scene moves from the stylised tabletop look toward a realistic one, as a **Steel Division / Combat Mission-like compromise**: realistic terrain, light, vegetation and weathered vehicles, but a clean, minimal UI and units that stay easy to find and click. Principles: overlays outline areas instead of painting tiles (TASK-049); light and haze of an overcast-to-partly-cloudy Eastern European day, muted olive palette, AgX tonemapping (TASK-051, TASK-054); a camera that sees the horizon when zoomed in and looks down when zoomed out, and **no depth-of-field / tilt-shift** (it makes the scene look like a miniature) (TASK-052); events leave visual traces – tracks, craters, wrecks – with no rule effect (TASK-058, TASK-065). Every effect degrades on a LOW quality preset (TASK-050). CC0 assets are allowed (decided 2026-10-22: textures, HDRI skies, vegetation models; unit models stay procedural – TASK-053). **Unit/tree scale (decided 2026-10-22, TASK-059): preset `balanced`** – units × 1.1 (was 1.3), trees × 1.8, bushes × 1.4, rocks × 1.0 (`VisualScale`); forests read as forests, units in a forest are found mostly by their label. **Open ground (TASK-070)**: a late-summer Central-Eastern European meadow – short and tall grass patches, dry stalks where the ground is dry, nettle along forest edges, sparse single-species flower clusters (white, yellow, violet, rare blue; no poppies), isolated thorn thickets on tile borders; vegetation never taller than ≈ 1/3 of a standing soldier and kept out of tile centres, purely cosmetic. Open decision: performance budget (see Open questions).

**Realistic scale (decided by the human 2026-10-31):** everything in the battle scene is drawn at its **real size**, true to the real hex (250 m between hex centres; one world unit = 144.3 m) – unit models, buildings, roads, rivers, field strips, trees, bushes, grass, textures and effects. This supersedes the TASK-059 unit/tree scale for the long term. Today units are ~12× and trees ~3–4× too large for the map, and ground textures repeat as if a unit were 7.7 m. Units stay readable through **fixed-pixel on-screen unit markers** (icon + label) and a **much closer minimum camera distance** for looking at the real-size models – no enlarged units (decided 2026-10-31). **TASK-110** (study first) measures what real scale means (a real tank is ~3 px at the default zoom), sets the marker and camera targets, decides from screenshots how a company is shown (one vehicle or a small group) and whether the relief stays 1.5×, covers terrain detail and performance, and splits the work; **TASK-111** implements the markers and the closer camera. New look work gives sizes in metres through one constant, `MapScale.metres_per_unit` (real maps: from the import; generated maps: the same 250 m hex, decided 2026-10-31), so it is right at any scale. Limits: the terrain mesh has a vertex every 36 m, so per-vertex ground weights can't show anything under ~70 m (smaller features need per-pixel textures or geometry); on screen 1 px ≈ 1.0 / 3.5 / 6.7 m at the closest / default / farthest zoom, so thin lines (roads, rivers) get a 1.5 px minimum on-screen width.

**Real-terrain look v2 (specified 2026-10-31, TASK-108b … TASK-108e; real-terrain maps only, purely visual; after the operational core loop):** on top of TASK-108's basic look, all at real size. *Ground* (108b): two more CC0 ground layers – harvested stubble and ploughed soil; field hexes become a patchwork of real **20–50 m** strips in 300 m blocks (stubble 45 %, soil 30 %, green crop 25 %, from position hashes, drawn per pixel from a baked parcel texture), villages show farmyard soil, roads are **5 m** gravel carriageways with ruts and **2.5 m** verges inside the road ribbon. *Rivers* (108c): an **8 m** water ribbon (± 25 %) with **3 m** mud banks, ripples drifting downhill (static on LOW), and a real-size concrete bridge (7 m wide, ≤ 40 m span, ≤ 60 triangles) wherever a drawn road crosses a drawn river – it marks the no-penalty crossing of the river rule. *Villages* (108d): procedural farmsteads – house **10–12 × 7–9 m**, barn 15–24 × 9–12 m, shed 4–7 × 3–5 m – along the village road on urban hexes; the hex centre and the six centre-to-side lines units move along stay clear (clearance from the unit scale, so it shrinks once units are real-size); buildings stay on LOW (they mark the +2 villages) without shadows. *Reeds* (108e): a `REED` grass kind on marshes (60–75 % of clumps, density × 1.3) and within 10 m of river banks; their size follows the grass scale (2–2.5 m once grass is real-size); none on LOW. Each task has a "don't make it worse" frame budget (≤ +0.3 … +0.5 ms on Suwałki, default battle unchanged).

**Planned (TASK-041 … TASK-048, decided 2026-10-19):** how a unit animates is a property of the real vehicle, declared per unit in the unit catalog as **mechanisms** with parameters (registry `docs/design/units/mechanisms.json`), not per class – the Homar-K and the 9K57 Uragan are both MLRS but are built differently. Mechanisms: `wheels`, `squad_march`, `launcher` (traverse range – full or limited, the vehicle turns first when the target is outside it; stowed tube direction; firing elevation), `stabilisers` (jacks lowered before a volley) and `blast_shields` (cab window shields closed before a volley) – both implemented in TASK-045 (Homar-K jacks, Uragan jacks and shields), `turret_traverse` (tank turret and gun aim before firing, also on counters; implemented in TASK-047), `gun_recoil` (barrel recoil `recoil_m` + muzzle flash on direct fire; implemented in TASK-048). The model file copies the unit's mechanisms; the game still reads only `data/` and the models.

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

Consequences to watch: tanks dominate infantry (infantry deals the minimum 1 to every tank); an Abrams reaching an MLRS destroys it in one attack (since TASK-089a only 63 % of the time on plains); Homar-K out-ranges the Uragan (6 vs 5) and can hit it without a counter; 1 Abrams ≈ 2 T-72B3 by HP × damage (10 × 3 vs 8 × 2).

### Balance of the default battle

- **Composition by faction** (quality vs. mass): Poland 2 × Mechanised Infantry Squad, 1 × M1A2 SEPv3, 1 × Homar-K (4 units, 36 HP); Russia 2 × Motor Rifle Squad, 2 × T-72B3, 1 × 9K57 Uragan (5 units, 42 HP). The second T-72B3 compensates the Abrams; nothing compensates the Homar-K's range on purpose (it is the guided-rocket advantage) – the simulation decides whether that needs more Russian units.
- The composition is balance data: an ordered `default_force` list in each faction's `.tres`, not code. Spawn slots: units with range 1 fill the front column, others the back column, in list order (exact slots in TASK-039a).
- **Verification**: the AI-vs-AI simulation already shows a side bias with mirrored armies (TASK-012: player 1 won 59 % vs 34 %), so balance is measured with **both side assignments**: `tools/simulate.sh 200` (Poland = player 0) and `tools/simulate.sh 200 --factions=russia,poland`. Target: Poland's share of the decided matches over both runs together is 40–60 %, no errors, draws ≤ 15 % per run.
- **Measured** (TASK-039a, 2026-10-20, seeds 1..200, 50 turns, compositions above, no ladder step needed): Poland as player 0 won 90, Russia 104, 6 draws; Russia as player 0 won 80, Poland 115, 5 draws → Poland 205 of 389 decided matches = **52.7 %**, errors 0, draws 3.0 % / 2.5 %. The player-1 side bias persists in both assignments.
- **Measured with per-element rolls** (TASK-089a, 2026-10-30, seeds 1..200, 50-turn harness limit). Columns: P0 wins / P1 wins / draws by the rules / matches cut by the harness / average length of decided matches (turns).

  | Run | Before (deterministic damage, lowest-HP AI) | Rolls + old AI | Rolls + expected-value AI (shipped) |
  |---|---|---|---|
  | default poland,russia | 94 / 98 / 0 / 8 / 10.5 | 76 / 117 / 0 / 7 / 11.5 | 88 / 105 / 0 / 7 / 11.2 |
  | default russia,poland | 34 / 158 / 0 / 8 / 10.7 | 91 / 101 / 0 / 8 / 11.6 | 75 / 116 / 0 / 9 / 11.5 |
  | **Poland's share of decided (both default runs)** | 252/384 = **65.6 %** (outside 40–60 %) | **46.0 %** | 204/384 = **53.1 %** |
  | default poland,poland (P0 share) | 88 / 106 / 0 / 6 / 10.2 (45.4 %) | 84 / 107 / 0 / 9 / 11.1 (44.0 %) | 78 / 113 / 0 / 9 / 10.5 (40.8 %) |
  | default russia,russia (P0 share) | 83 / 103 / 0 / 14 / 10.4 (44.6 %) | 85 / 98 / 0 / 17 / 11.6 (46.4 %) | 79 / 105 / 0 / 16 / 11.2 (42.9 %) |
  | objective poland,russia | 32 / 77 / 91 / 0 / 6.8 | 29 / 96 / 75 / 0 / 7.3 | 32 / 84 / 84 / 0 / 7.4 |
  | objective russia,poland | 73 / 53 / 74 / 0 / 6.8 | 48 / 62 / 90 / 0 / 7.0 | 42 / 61 / 97 / 0 / 6.9 |

  Default battle with the shipped rules: Poland **53.1 %**, inside the 40–60 % target (master before the change was at 65.6 %, outside it); draws (all harness cuts) 3.5–8 % per run, within ≤ 15 %. Matches got about one turn longer, as expected (battered companies deal less). The player-1 side bias persists in the mirrors (P0 41–43 % of decided matches). **objective_battle draws are far above 15 %** (42 % and 49 % with the shipped AI, all by the turn limit) – they already were before this change (46 % and 37 %); not caused by the rolls, open in the objective battle balance question (Open questions → Victory condition).
- **Tuning ladder** if the target is missed (stats stay untouched; one step at a time, re-run both): Poland > 60 % → add a third Motor Rifle Squad; still > 60 % → add a third T-72B3. Russia > 60 % → replace the second T-72B3 with a Motor Rifle Squad; still > 60 % → mirrored counts (2 squads, 1 tank, 1 MLRS each). If no step lands in the band, record the results and ask the human (a rule change is needed, not a count change).

### Option, not adopted: hard/soft attack

Split `attack` into `attack_soft` (vs. infantry and soft-skinned targets) and `attack_hard` (vs. armoured), with an `armored` tag on units. **Gains**: squads with ATGMs and the Javelin-vs-RPG difference become meaningful against tanks; unguided rockets get weak against MBTs, guided ones less so; infantry stops being uniformly 1 damage against tanks. **Costs**: every unit gets two attack values and a tag, the damage formula and counterattack read the target type, the AI target choice and the popup change, all rules above need a second attack table, and every balance number gets re-derived. **Recommendation**: not now. Revisit after the TASK-039a simulations if infantry turns out useless against tanks – the cheaper alternative to try first is the "Damage scale" question (e.g. HP and attack ×2 with defense unchanged, which widens the spread between matchups so that fewer of them sit at the minimum of 1).

## Combat

Implemented in TASK-001 and TASK-002 (`AttackCommand`):

- **Attack**: a unit may attack one living enemy unit within its `attack_range` (hex distance; 1 = adjacent). Rejection codes: `game_over`, `unit_not_found`, `not_your_unit`, `not_an_enemy`, `already_attacked`, `out_of_range`.
- **Once per turn**: each unit attacks at most once per turn. Attacking sets the attacker's remaining movement to 0 – a unit can move then attack, but not attack then move. Both are reset at the start of the owner's turn.
- **Damage** = `max(1, attack − (defense + defense bonus of the defender's tile))` (`AttackCommand.compute_damage`; the attacker's tile doesn't matter) – since TASK-089a this is the **average** damage of a full-strength attacker, rolled per element (see "Per-element rolls" below). Matchups on plains: see "Resulting matchups on plains" under "Stat derivation rules".
- **Death**: a unit whose HP drops to 0 dies (`unit_died`), is removed from the map and no longer blocks its tile.
- **Victory**: when exactly one player has living units left, that player wins (`game_over`, `GameState.winner`); after that every command is rejected with `game_over` **[ASSUMPTION]**.

Implemented in TASK-010 and TASK-011:

- **Counterattack** (TASK-010): a defender that survives and has the attacker within its own `attack_range` hits back once with the same formula (since TASK-089a: the same roll, with the HP left after the hit); doesn't use the defender's attack for the turn; a unit counters every attack it survives; a counter never triggers another counter and can kill the attacker (and end the game).
- **Ranged units** (TASK-011): self-propelled rocket artillery with range 5 can attack melee units (range 1) from distance 2 to 5 without being countered. There is **no minimum range**: artillery can also attack at distance 1 (and is then countered), and it counters any attacker within 5 hexes. Range ignores terrain and units (no line of sight).

Player-facing description of these rules: docs/MANUAL.md.

### Per-element rolls (approved 2026-10-30)

Implemented in [TASK-089a](tasks/TASK-089a-company-combat-rolls.md) (core, forecast API, AI): replaces the deterministic damage and counter above; the HUD forecast is [TASK-089b](tasks/TASK-089b-combat-forecast-hud.md) (not implemented yet). Measured balance: "Balance of the default battle". Full design, worked table and decisions: TASK-089a.

- **Roll**: `base = max(1, attack − (defense + tile bonus))` (today's damage). The striker rolls one die with `max_hp` faces per current HP (`shots = hp`); a roll `<= min(base, max_hp)` hits; **damage = hits**. Hit chance `p = min(base, max_hp) / max_hp`, so a full-strength company deals today's damage on average and a company at x % strength x % of it. Integer rolls only, through `GameState.rng.randi_range(1, max_hp)`; no new balance data.
- **No minimum damage**: a strike may deal 0 (infantry vs. a tank: 35 % of strikes); the old minimum of 1 survives as the mean.
- **Counter**: the same roll, with the defender's HP left after the hit as `shots`.
- **Spread at full strength** (examples, plains): Abrams → squad 4.0, 10–90 % range 2–6; Abrams → T-72B3 3.0 (1–5), counter 1.25 instead of 2; T-72B3 → squad 3.0 (1–5); squad → tank 1.0 (0–2); Abrams → full MLRS destroys it 63 % of the time (today always); Homar-K → Uragan 5.0 (4–6), destroys it 33 %.
- **Forecast** (pure, no rng): expected damage, 10–90 % range, destroy chance, expected counter and its range; shown in the hover card over an attackable enemy; used by the AI.
- **AI**: picks the target with the highest `expected damage + 2 × destroy chance − expected counter` (ties: lowest HP, lowest id).
- **Determinism**: per attack the attacker rolls exactly `hp` times (even after the target is dead), then – only if the counter happens – the defender rolls exactly its remaining `hp` times; `validate()` and the forecast never use the rng. The replay fixture is regenerated.
- **Check**: `tools/simulate.sh 200` before/after with `--factions=poland,russia`, `russia,poland` and the mirrors `poland,poland` / `russia,russia` (side bias); target Poland 40–60 % of decided matches, draws ≤ 15 %.

## Operational layer

Specified 2026-11-01 in [TASK-092a](tasks/TASK-092a-operational-map-import.md) (map), [TASK-092b](tasks/TASK-092b-operational-state-formations.md) (state, formations, turns), [TASK-092c](tasks/TASK-092c-move-formation.md) (movement costs and route planning), [TASK-092d](tasks/TASK-092d-formation-orders.md) (orders and postures) and [TASK-092e](tasks/TASK-092e-order-execution.md) (order execution); not implemented yet. Architecture: ADR 0015 (separate `OperationalState` / `OperationalSimulation`, own RNG stream, `BattleSetup` / `BattleResult` as the only channels to battles). Contact → battle is TASK-094, auto-resolve [TASK-120](tasks/TASK-120-battle-auto-resolve.md), battle results → formations TASK-095, the view TASK-093. The political layer (countries, stances, escalation, decisions; added 2026-11-01 after the human's "operational freedom" decision) is specified in [TASK-113](tasks/TASK-113-country-per-hex-import.md) (country per hex), [TASK-114](tasks/TASK-114-country-stances.md) (stances in the state), [TASK-115](tasks/TASK-115-escalation-ladder.md) (escalation ladder), [TASK-116](tasks/TASK-116-borders-in-movement.md) (borders and incidents in movement), [TASK-117](tasks/TASK-117-political-decisions.md) (player decisions) and [TASK-118](tasks/TASK-118-allied-contributions.md) (allies' formations); outside support from off-map third parties in [TASK-121](tasks/TASK-121-outside-support.md) and [TASK-122](tasks/TASK-122-support-strike-means.md); both sides playable as blocs ("Sides"). Numbers marked **[ASSUMPTION]** wait for the human (Open questions → "Operational layer v1", "Political layer v1").

**The operational layer must feel clearly different from the battle** (the human, 2026-11-01): the same hexes underneath (`ImportedMap`, hex pathfinding, 5 km hexes), but (1) it looks like a **paper staff map**, not a 3D world, and (2) the player gives **multi-turn orders** to formations instead of moving them hex by hex. Turns stay alternating (I-go-you-go); simultaneous resolution of both sides' orders was considered and rejected.

### Player roles

Decided by the human 2026-11-01: the two layers are two roles of **one person**. Points marked **[ASSUMPTION]** are open questions for the human (Open questions → "Player roles").

| | **Leader** – head of government + chief of the general staff (operational layer) | **Commander** – battalion / company level (tactical battle) |
|---|---|---|
| Where | the operational staff map (TASK-093) | the 3D battle |
| Decides | **politics**: stances, escalation, alliances, ultimatums, whether to widen the war into a neighbouring country or keep it out (NATO: the Kaliningrad oblast, Belarus; Russia: Lithuania) (TASK-117), whether to request outside support (TASK-121); **the operation**: formation orders and postures (TASK-092d), deep strikes as a tool (TASK-097), supply (TASK-096), forces and replacements (TASK-105); at each contact: **play the battle or auto-resolve it** (TASK-120) | how the companies in this battle move and fight (move, attack, later unit orders – TASK-081) to fulfil the mission |
| Cannot | move or fight companies inside a battle; change a battle's forces, terrain or conditions once it has started | change the political situation (stances, escalation level, decisions), order formations outside the battle, call deep strikes, bring reinforcements, change the mission or the objectives; a battle never raises the escalation level ("Escalation ladder") |
| Gets from the other role | the **after-action result**: losses per company, who holds the field, who retreats (`BattleResult`, TASK-095 applies it) | the **mission and intent**: what the leader's order means for this battle (below) |

- **Hand-over, leader → commander**: the order the leader gave becomes the commander's **mission** (the task – *attack*, *defend*, or *hold out* for a formation caught on the march – with the battle's measurable objectives and turn limit, `BattleObjectives`) and the **intent** (why: the formation's order destination, e.g. "open the S61 towards Suwałki for the 15th Brigade"). Both are carried in `BattleSetup` (TASK-094) and shown when the battle starts and in the battle HUD. The commander fights only with what the operation created: the companies at their current strength, the terrain at the contact point, the postures and the battle conditions (command points, later ammunition, morale, fire support – TASK-099).
- **Hand-over, commander → leader**: the battle ends by its objectives; the end screen is the commander's report to the staff ("Report to staff" returns to the staff map), and the result flows back only through `BattleResult` (ADR 0015). The commander's only influence on the operation is what the battle gives: losses, ground, retreat.
- **The same person**: there is no separate AI general above the player and no AI subordinate deciding for the player – formations carry out the leader's orders mechanically (TASK-092e), and in battle the player commands every own company **[ASSUMPTION]**. The player chooses per contact whether to play the battle as the commander or to auto-resolve it (no AI commander plays it instead – auto-resolve is a calculation from the same inputs, "Battle hand-off and auto-resolve"). The player chooses the side when starting an operation (NATO or Russia – "Sides"); the opponent is an AI on both layers whichever side it gets (TASK-102 plays its leader, the tactical AI its commanders). The leader of the **NATO side** is the alliance's leadership for the theatre – in the Suwałki operation the Polish government and General Staff acting for the alliance; the leader of the **Russia side** is the Russian government and General Staff **[ASSUMPTION – wording only]**.
- **Wording**: the operational view and its texts address the leader (staff map, orders, decisions, "the government" / "the General Staff"); battle texts address the commander ("Mission", "Intent", "Report to staff"). The leader's political panel (TASK-119) is never shown inside a battle.

### Sides

Decided by the human 2026-11-01: **both sides are playable** and they are **blocs**. Specified in TASK-092b (sides as data), TASK-114 … TASK-118 (symmetric political rules), [TASK-121](tasks/TASK-121-outside-support.md) / [TASK-122](tasks/TASK-122-support-strike-means.md) (outside support), hooks in TASK-093 / TASK-102 / TASK-103 / TASK-107. Points marked **[ASSUMPTION]** wait for the human (Open questions → "Sides and outside support v1").

- **A side is a player** (0 or 1) and a bloc, defined as data (`data/sides/<id>.tres`, `SideDefinition`): id, name, **lead faction** (colours, HUD, the default formation types) and the **factions** whose formation types it may field. In the Suwałki operation: side 0 **NATO** (`nato`, lead faction Poland) and side 1 **Russia** (`russia`, lead faction Russia). A **country** is not a side: Poland, Lithuania, Belarus and Russia are countries on the map with a stance towards the sides ("Countries and stances"); the **off-map supporters** (NATO allies, North Korea, China, Iran) are neither on the map nor countries with a stance – they act only through support packages ("Outside support").
- **Members of each bloc** in the Suwałki operation:

  | | NATO (side 0) | Russia (side 1) |
  |---|---|---|
  | On the map, fighting from the start | Poland (belligerent) | Russia – the Kaliningrad oblast (belligerent) |
  | On the map, aligned (staging, transit), joins by decision or the ladder | Lithuania (3 formations when belligerent) | Belarus (hosts the Russian Belarus group; 3 formations when belligerent) |
  | Off the map, by support packages (TASK-121 / 122) | NATO allies (USA, Germany, …): 2 battalions, extra cruise missiles | North Korea: 2 battalions; China: missile components (cruise missiles); Iran: strike drones |

  Allies' and supporters' formations use the side's formation types with their own names (e.g. "US Armored Battalion" as a `pl_tank_battalion`, "North Korean Infantry Battalion" as a `ru_motor_rifle_battalion`) until they become factions with their own rosters **[ASSUMPTION]**.
- **The side choice changes nothing in the rules or the start situation**: the operation (order of battle, positions, start stances, start level *Limited war*, Russia moving first as the attacker) is the same whichever side the human plays; the choice only says which player the human controls and from whose point of view the staff map is drawn. It lives outside the operational state (session, `CampaignRecord`), so an operation and its replay are identical for both choices. Chosen when starting the operation (TASK-107; the staff map takes it as a parameter from the start, TASK-093); **NATO is listed first** in the choice **[ASSUMPTION – only the order]**.
- **What differs by side** – data, never code (no rule asks "is this NATO?"):

  | | NATO | Russia |
  |---|---|---|
  | Order of battle | 8 formations, 276 strength – quality (TASK-092b) | 10 formations, 332 – mass, two groups (Kaliningrad, Belarus) |
  | Initiative | moves second | moves first (`first_player` 1) |
  | Aligned partner | Lithuania – **refuses an ultimatum** (a NATO member with allied troops on its soil, `accepts_ultimatum` false) **[ASSUMPTION]** | Belarus – accepts an ultimatum (a sovereign regime that prefers to stay out of a direct war) |
  | Enemy sanctuary to respect | the Kaliningrad oblast (Russian soil) | none on the map |
  | Off-map support | NATO allies: reinforcements, strike means | North Korea, China, Iran |
  | Name of *Invoke alliance* | "Invoke collective defence" | "Invoke the Union State" |
  | Objectives (TASK-107) | keep the Gap open | close the Gap (a land link Kaliningrad – Belarus) |

- **Sanctuary asymmetry – decided by the designer, to confirm [ASSUMPTION]**: only **Russian soil** is a sanctuary; Polish and Lithuanian soil is not. Reasons: (1) the war is a Russian attack on NATO territory – fighting on Polish soil *is* the war, while striking or entering the soil of a nuclear power is the step real decision-makers fear most; NATO's nuclear members (USA, UK, France) are off the map, so the mirror of the sanctuary (strikes on their soil or on NATO's rear outside the theatre) does not exist on this map; (2) it gives each side a different restraint instead of the same one: NATO must weigh the **sanctuary** (Kaliningrad is the source of Russian fire but closed until *Open war*), Russia must weigh **Lithuania** (a closed country until a *Declare hostilities* that brings in its army) and the **price of outside support** (North Korean troops cost escalation and hand NATO a casus belli against Belarus). The rule itself is symmetric: `sanctuary` is a country flag in data, and any side facing an enemy sanctuary gets the same gate (tests use a hand-made map where Poland is a sanctuary).
- **Decisions by side**: the five decisions of "Political decisions" and *Request support* are the same commands for both sides with the same conditions and costs; side differences come only from data (which countries are aligned with whom, `accepts_ultimatum`, which support packages belong to which side, the decision's display name).
- **Victory** (TASK-107) **[ASSUMPTION]**: the same scoring for both (objective points, −3 per net escalation step caused, the threshold defeat for whoever takes the last step), different objectives: NATO keeps a road link between Poland and Lithuania through the Gap (Suwałki – Marijampolė) open to the end of the operation; Russia closes it (holds the Gap's road hexes or links the Kaliningrad oblast to Belarus by land). Optional objectives worth points to each side: Kaliningrad / Chernyakhovsk (NATO), Białystok / Vilnius (Russia), Grodno (either – it makes attacking Belarus worth it).
- **The AI plays either side** (TASK-102): it reads the side, the countries' relations and the packages from the state and data; no side-specific code. Balance is measured with the AI on both sides (TASK-103), and both sides must come out playable: each side wins 40–60 % of the decided operations **[ASSUMPTION]**.

### Theatre

- **Decided by the human 2026-11-01**: a regional theatre of about 300 × 300 km – north-east Poland, the Kaliningrad oblast, southern Lithuania, western Belarus and the Suwałki Gap between them – so that attacking Kaliningrad or Belarus, or keeping them out, are real options on the map.
- **Map** (TASK-092a): id `suwalki_theatre`, **68 × 64 hexes** (4 352 hexes, ≈ 340 km west–east × 277 km north–south; 5 km between columns, 4.33 km between rows) centred on **54.20 N, 22.90 E**, one UTM zone 34N projection (EPSG:32634; the east edge lies ~4.4° east of the zone's central meridian – the Krüger series stays mm-accurate, the grid north there is ~3.5° off true north). Slightly more than 60 × 60 so that both capitals of the area sit ≥ 2 hexes inside the edge **[ASSUMPTION – exact size for the human; 60 × 60 would put Kaliningrad and Vilnius on the edge columns]**. Must contain, each ≥ 2 hexes from the edge: Kaliningrad, Chernyakhovsk, Sovetsk, Olsztyn, Białystok, Ełk, Suwałki, Augustów, Grodno, Lida, Marijampolė, Kaunas, Vilnius; the tactical Suwałki sample map lies inside it. Sea in the north-west corner (the Baltic off the Sambian peninsula, the Curonian Lagoon).
- **Every land hex has a country** (TASK-113): Poland, Lithuania, Belarus or Russia, from the OSM country borders (`admin_level=2`), by majority of the hex's land; water hexes have none. The country is a rule input (stances, below).
- **Import**: the TASK-087 importer with `--profile=operational`: 250 m sample lattice (~350 points per hex), Copernicus GLO-90 DEM (90 m is enough for 5 km relief; ~1/9 of GLO-30's download), Overpass downloaded in 0.5° × 0.5° tiles cached separately (resumable; the result does not depend on the tiling), sea from the OSM coastline. First download and import time are measured in TASK-092a.

### Operational map

- **Hex 5 km** between neighbouring hex centres (ADR 0018: a 250 m tactical battle map covers about 1.5 × 1 operational hexes). Same offset layout, UTM projection and `ImportedMap` format as tactical maps, imported by `tools/import_map.py --profile=operational` from the same sources (Copernicus + OSM).
- **Terrain per operational hex** (shares of the hex's sample points, first match wins) **[ASSUMPTION – tuned on the real import]**: water ≥ 50 % → WATER; urban ≥ 15 % → URBAN; forest ≥ 50 % → FOREST; marsh ≥ 25 % → MARSH; relief (90th − 10th percentile of the open heights) ≥ 60 m → HILLS; otherwise PLAINS (fields are not told apart at this scale). Targets for the tuning: water ≤ 15 % of the hexes, hills 5–25 % of the land, the hexes of Kaliningrad, Vilnius, Kaunas, Białystok, Grodno, Olsztyn and Suwałki URBAN.
- **Roads and rivers** per link as on tactical maps, but only major ones: roads = `highway` motorway, trunk, primary, secondary (+ `_link`); rivers = `waterway` river and canal (no streams).
- **Countries per hex** are imported (TASK-113) and used by the rules (stances). Fine border lines for drawing, place names and a fine relief raster for the paper map: TASK-112 (view data only).

### Formations

- A **formation** is the operational counter: a **battalion-sized** group of companies **[ASSUMPTION]**; the brigade is only a label (`parent`, e.g. "15th Mechanised Brigade") until a rule needs it (command, supply).
- A formation **type** is data (`data/formations/<id>.tres`): faction, echelon, class (mechanised / armoured / artillery – read by TASK-093's map symbols), operational move points and an ordered list of companies (unit types from the faction roster). An operation (`data/operations/<id>.tres`) places named formations of these types on its map.
- Each company has a **strength** (its battle HP, 1 … the unit's `max_hp`) and a ref `<formation id>/<n>` (n from 1), the `BattleSetup.Company.ref` it fights under. Formations start at full strength. A formation's strength = the sum of its companies.
- **First types and order of battle** of the Suwałki Gap operation (id `suwalki_gap`, played on the `suwalki_theatre` map) **[ASSUMPTION]** (quality vs. mass, like the default battle; Russia ≈ 1.2× Poland's strength):

  | Type (id) | Faction | Class | Companies | Strength |
  |---|---|---|---|---|
  | Mechanised Battalion (`pl_mech_battalion`) | Poland | mechanised | 3 × Mechanised Infantry Squad, 1 × M1A2 SEPv3 | 40 |
  | Tank Battalion (`pl_tank_battalion`) | Poland | armoured | 3 × M1A2 SEPv3, 1 × Mechanised Infantry Squad | 40 |
  | Rocket Artillery Squadron (`pl_mlrs_squadron`) | Poland | artillery | 3 × Homar-K | 18 |
  | Motor Rifle Battalion (`ru_motor_rifle_battalion`) | Russia | mechanised | 3 × Motor Rifle Squad, 1 × T-72B3 | 38 |
  | Tank Battalion (`ru_tank_battalion`) | Russia | armoured | 3 × T-72B3, 1 × Motor Rifle Squad | 34 |
  | MLRS Battalion (`ru_mlrs_battalion`) | Russia | artillery | 3 × 9K57 Uragan | 18 |

  Order of battle on the theatre map (reworked 2026-11-01 for the 340 × 277 km theatre) **[ASSUMPTION – balance guess]**:
  - **NATO side – Poland** (8 formations, 276): 4 mechanised battalions, 2 tank battalions, 2 rocket artillery squadrons – facing Kaliningrad around Bartoszyce / Braniewo–Lidzbark (15th / 20th Mechanised Brigade labels), in the Gap around Suwałki / Augustów, and facing Belarus around Białystok / Sokółka.
  - **Russia side – Russia** (10 formations, 332 ≈ 1.2× Poland): the **Kaliningrad group** – 3 motor rifle battalions, 1 tank battalion, 1 MLRS battalion (166) in the oblast (Gusev / Chernyakhovsk / Sovetsk area, labels of the 11th Army Corps); the **Belarus group** – 3 motor rifle battalions, 1 tank battalion, 1 MLRS battalion (166) staged in Belarus around Grodno (a Russian force hosted by an aligned Belarus).
  - **Allies that may join** (TASK-118, enter play only when their country goes to war on its leaning side): Lithuania – 2 mechanised battalions ("Iron Wolf" Brigade) + 1 tank battalion ("NATO Brigade Lithuania") around Kaunas / Rukla / Vilnius (120); Belarus – 2 motor rifle battalions + 1 tank battalion ("6th Mechanised Brigade") around Grodno / Lida (110). Represented with the side's formation types and flavour names until Lithuania and Belarus are factions.
  - **Off-map support that may arrive** (TASK-121, only through "Outside support"): NATO allies – 1 armoured + 1 mechanised battalion (80) at the west edge of Poland; North Korea – 1 infantry + 1 artillery battalion (56) at the east edge of Belarus.
  - The order of battle and the positions are the same whichever side the human plays ("Sides").
  - Every formation starts in a country open to its side (Polish ones in Poland, Russian ones in the Kaliningrad oblast or Belarus), ≥ 3 hexes from every enemy formation. The theatre is deliberately not filled: with ~18–24 formations on 4 352 hexes there are open flanks – the operational freedom the human asked for.

### Operational turns

- **I-go-you-go** like the battle (kept by the human 2026-11-01): during their turn the current player gives, changes and cancels orders; **ending the turn executes that player's orders**, then the other side plays. The turn number grows when play returns to the operation's **first player** – **Russia** in the Suwałki Gap operation (the attacker has the initiative), whichever side the human plays **[ASSUMPTION]**. One operational turn ≈ **12 hours** **[ASSUMPTION]** (no rule reads it yet; shown by TASK-093). No end of the operation yet (operation victory: TASK-107), except the escalation threshold (TASK-115, "Escalation ladder"). At the round boundary (play returning to the first player) the ladder's calm counter is checked.
- There are **no direct moves**: a formation moves only by carrying out an order.

### Orders and postures

- An **order** = a **destination** hex + a **posture**. Each formation has at most one order and always has a posture (start: `defend`, data per operation). Commands: issue order (destination + posture; replaces the old order), cancel order, set posture (keeps the order). Issuing never moves the formation; the order is rejected when no route exists for that posture, another formation stands on the destination, or (TASK-116) the destination lies in a country closed to the side.
- **Postures** (data `data/operational/postures/<id>.tres`, TASK-092d) **[ASSUMPTION]** – a minimal set; their battle effects come with contact battles (TASK-094):

  | Posture | Move points spent per turn | Route | On contact | Planned battle effect (TASK-094) |
  |---|---|---|---|---|
  | **March** (`march`) | 100 % (8) | avoids enemy zones of control | never plans into contact | caught in column: defends without preparation, position bonus −1 |
  | **Advance** (`advance`) | 75 % (6) | straight, through enemy zones of control | halts next to the enemy, keeps the order | attacker, position bonus 0 |
  | **Defend** (`defend`) | 50 % (4) – moving into position | avoids enemy zones of control | never plans into contact | defender in prepared positions, position bonus +1 |

  The **position bonus** **[ASSUMPTION]** (posture data, TASK-094) is added to the defense of every company of that side in its battle – played and auto-resolved alike ("Battle hand-off and auto-resolve").

  A formation's per-turn budget = `move_points × share`, rounded down, at least 1. A `delay` posture (fall back while fighting) needs retreat rules and waits for TASK-095 (open question).
- **Route**: the cheapest path by step cost to the destination, **re-planned every turn** from the current situation (nothing is stored but the destination), ties broken deterministically. Enemy hexes are impassable; own formations' hexes can be passed through but never ended on; postures that avoid contact treat hexes next to an enemy as impassable except the destination.
- **Execution** (at the end of the owner's turn, TASK-092e): the side's formations act one after another in order-of-battle order. Each walks its route while it can pay the next step; **the first step of a turn is always made**, whatever it costs; unused points are lost. It never stops on another formation's hex (it stops on the last free hex before it).
- **How an order ends**:
  - *arrived* – the order is done (the posture stays);
  - *contact* – an advancing formation that enters a hex next to an enemy halts there and keeps the order (contact → battle is TASK-094);
  - *interrupted* (order removed, reported to the player): the destination is held by another formation (`destination_occupied`), no route is left for the posture (`no_route`), or own formations block the way so it cannot move at all (`blocked`); with countries (TASK-116) also when the destination's country has become closed to the side (`closed_country`).
  - otherwise it continues next turn.
- **Forecast**: for any order the player sees where the formation will stand after each turn, assuming nothing else moves (TASK-092c `forecast`, drawn by TASK-093).
- Later rules lower the budget: out of supply (TASK-096), fatigue / readiness (TASK-095). No fog yet: routes are planned on all enemies, both sides see every formation (operational fog: TASK-100 – routes will be planned on known enemies only).

### Movement costs

- **Move points**: 8 per turn for every motorised formation type (data per type) **[ASSUMPTION]**; the posture decides how many of them a formation uses per turn.
- **Step cost** (data `data/operational/movement.tres`) **[ASSUMPTION]**: along a road link 1 (whatever the terrain); otherwise by the entered hex: plains / fields / urban 2, forest / hills 3, marsh 4, water impassable; entering a river hex not along a road link +2. So a marching formation (8 points) covers 40 km on roads, 20 km across open ground, 10–15 km through forest per turn; an advancing one 30 / 15 km; a defending one 20 / 10 km.
- **One formation per hex**: own formations can be passed through but not stopped on; enemy hexes are impassable.
- **Zone of control**: the hexes next to an enemy formation. Marching and defending formations plan around them (a destination inside one is allowed); an advancing formation that enters one halts for the turn. A formation that starts next to an enemy may move away.

### Battle hand-off and auto-resolve

Specified in [TASK-120](tasks/TASK-120-battle-auto-resolve.md) (auto-resolve, shared result fields); the contact rule and the setup are TASK-094, the consequences TASK-095 (both still ideas – this section is the contract they must keep). Pure logic in `src/core/`, randomness only from the battle's own seed.

- **Contact rule** (TASK-094): after order execution, a formation that halted on contact attacks the adjacent enemy formation; the contact rule asks one predicate, `ContactRules.battle_allowed(state, attacker, defender)` – always true in TASK-094; TASK-116 adds the border rule (no battle against a formation in a country closed to the attacker). Further rules (e.g. fog, TASK-100) extend the same predicate.
- **`BattleSetup` additions** (TASK-094): `attacker` (player, −1 in scenario battles), `terrain` (terrain id of the defending formation's operational hex; `&""` = plains in scenario battles), per player in `Conditions`: `posture` (`&""` in scenario battles) and `position_bonus` (the posture's bonus from the posture data, resolved by the operation – the tactical layer never reads operational data), and per player a `Mission` (`task` `&"attack"` / `&"defend"` / `&"hold_out"`, `intent` text, the formation's display name) for the commander's briefing ("Player roles").
- **`BattleResult` additions** (TASK-120, used by both kinds of battle): `resolution` (`&"played"` / `&"auto"`), `field_holder` (the winner; on a draw the defender, `1 − attacker`; −1 in scenario battles without an attacker) and `retreat` (the loser when there is a winner and the loser has a company left, else −1). One helper fills `field_holder` / `retreat` for both paths, so the rule exists once. TASK-095 reads only these fields and the per-company strengths – **never `resolution`** – so a played and an auto-resolved battle with the same outcome have the same consequences.
- **The choice**: when a battle is pending, the human chooses on the contact notice **Play battle** or **Auto-resolve** (TASK-120 adds the button). The AI never chooses for the human; a battle between two AI sides (simulation) is always auto-resolved. A played battle cannot be switched to auto-resolve halfway **[ASSUMPTION]**.
- **Auto-resolve rules** **[ASSUMPTION – numbers in `data/battle/auto_resolve.tres`]**: the companies fight in **rounds** (the setup's turn limit, else `default_rounds` 8). In each round every living company fires once, **simultaneously** (damage is applied after all rolls; a company destroyed in the round has already fired), at the living enemy company with the highest hit chance (ties: lowest strength at the start of the round, then lowest setup index). The roll is the tactical one ("Per-element rolls"): `shots` = strength at the start of the round, `hit_on = min(max(1, attack − (defense + bonus)), max_hp)`; the bonus is the side's `position_bonus`, plus the terrain's defense bonus for the defending side. With `command_points` > 0 only the first that many living companies of the side (setup order) fire in a round – the same C2 limit as in a played battle. After each round a side whose losses reach **`break_share` 50 %** of its starting strength **breaks**; a side with no strength left is eliminated. One side broken / eliminated → the other wins (`reason` `broken` / `eliminated`); both in the same round → draw; no break after the last round → draw (`turn_limit`). Ammunition, morale and fire support are not read – like in a played battle today; TASK-099 / TASK-090 must change both resolvers together.
- **Determinism**: auto-resolve seeds its own `RandomNumberGenerator` from `setup.seed` – the same seed a played battle's `GameState.rng` gets – and never draws from the operational RNG, so the operation's random stream is the same whether a battle was played or auto-resolved. It changes no state: the result enters the operation only through `ResolveBattleCommand` (TASK-094 v0, consequences TASK-095), which re-computes an `auto` result and rejects a mismatch (`auto_mismatch`, added by TASK-120). A `CampaignRecord` battle entry stores `"resolution": "auto"` and no tactical commands (ADR 0015 amendment in TASK-120).

### Countries and stances

Specified in TASK-113 (country per hex), TASK-114 (stances in the state), TASK-116 (borders in movement), TASK-118 (allies' formations). Pure rules in `src/core/operational/`, numbers in data, every change through operational commands or the end-of-turn step – deterministic, no `rng`.

- **Countries** are data (`data/countries/<id>.tres`): id, ISO code, name and `sanctuary` – the sovereign soil of a nuclear power (Russia: `true`; Poland, Lithuania, Belarus: `false`). A player is a **side** – a bloc ("Sides"; 0 = NATO, 1 = Russia in the Suwałki operation); a country is not a player. The sanctuary flag is data and works the same for both sides (only Russia has it in the shipped data – "Sides" → sanctuary asymmetry).
- **Stance** – each country has exactly one (stored in the operation data at start and in `OperationalState`):

  | Stance | Side | Meaning |
  |---|---|---|
  | `neutral` | none | stays out of the war |
  | `aligned` | 0 or 1 | supports that side without fighting: hosts its forces, transit, supply; not a battlefield |
  | `belligerent` | 0 or 1 | at war on that side; a battlefield for both |

  Seen from a player the stance reads as **own** (aligned or belligerent on my side), **hostile** (aligned with the enemy), **enemy** (belligerent on the enemy side) or **neutral** – the labels the view and the AI use.
- **What a stance allows** a side (a hex is "open" to a side when the side may enter it):

  | For my side the country is | Enter / route through | Supply (TASK-096) | Strike targets there (TASK-097) | Battle on its soil (TASK-116 hook in TASK-094's contact rule) |
  |---|---|---|---|---|
  | own | yes | yes | – (own soil) | yes |
  | enemy | yes – but an enemy **sanctuary** only from *Open war* or after this side has breached it | no | yes, within the ROE of the level | yes |
  | hostile (aligned with the enemy) | no | no | no | no |
  | neutral | no | no | no | no |

  Closed hexes are impassable for route planning and for retreat after a battle (TASK-095's retreat, the check added by TASK-116; a formation standing on one may always step off it). Orders to a destination in a closed country are rejected (`closed_country`). A battle starts only when the defending formation's hex is open to the attacker (TASK-116 adds this to `ContactRules.battle_allowed`, TASK-094). Hexes without a country (water) are open to everyone but impassable anyway.
- **Start stances of the Suwałki operation** **[ASSUMPTION]**: Poland belligerent (side 0); Russia belligerent (side 1); Lithuania **aligned with side 0** (NATO ally: Polish transit and supply, its own army not yet fighting); Belarus **aligned with side 1** (Union State hosting the Russian Belarus group). Start level: *Limited war*. Each country also has a **leaning** side (Lithuania 0, Belarus 1) – where it goes when the war widens.
- **Legal transitions** (anything else is a rule error; `belligerent` is final in v1 – wars don't end inside one operation):

  | From | To | Caused by |
  |---|---|---|
  | neutral | aligned with its leaning | the ladder reaching *Regional war*; political events (TASK-106) |
  | neutral | belligerent against the declarer | *Declare hostilities* |
  | aligned (S) | belligerent (S) | *Invoke alliance* by S; *Declare hostilities* by the other side; the ladder reaching *Regional war* |
  | aligned (S) | neutral | *Demand neutrality* by the other side |

- **Incidents** (detected by the rules, TASK-116; strikes by TASK-097; battles cause none – they are fought only on soil open to the attacker):
  - *Sanctuary breach*: the first time a side's formation enters (or its strike hits) the soil of an enemy sanctuary, the level rises by 1 and that country stays open to that side for the rest of the operation (a formation is never trapped behind a closing border).
  - *Launching from aligned soil*: when a formation steps from a hex of a country aligned (not belligerent) with its side straight into an enemy country's hex, the other side gains a **casus belli** against that country: declaring hostilities on it then costs no escalation. (Russia attacking out of Belarus hands NATO a free hand against Belarus; NATO attacking out of Lithuania does the same for Russia. Outside support delivered into an aligned country does the same – "Outside support".)
- **Allies join with forces** (TASK-118): when a country becomes belligerent on its leaning side, its formations (operation data, see "Formations") enter play on their start hexes (or the nearest free open hex of that country within 3 hexes), owned by that side, at full strength, without orders.

### Escalation ladder

Specified in TASK-115 (ladder, automatic effects, calm, threshold), TASK-116 (incidents in movement), TASK-117 (decisions). One level **shared by both sides**, data in `data/operational/escalation.tres` **[ASSUMPTION – names and numbers]**:

| Level | Id | Name | Strike target classes allowed (ROE, TASK-097) | Enemy sanctuary soil | Automatic on reaching it |
|---|---|---|---|---|---|
| 0 | `contained` | Contained clash | formation | closed | – |
| 1 | `limited_war` | Limited war (start) | formation, air defence, depot | closed | – |
| 2 | `open_war` | Open war | + airfield, command post (C2) | open to ground entry and strikes (first breach +1) | – |
| 3 | `regional_war` | Regional war | as Open war | open | every **aligned** country becomes **belligerent** on its side; every **neutral** country becomes **aligned** with its leaning |
| 4 | `strategic_threshold` | Strategic threshold | – | – | **the operation ends: the side whose action raised the level to 4 loses** |

- **Raises** (each step is attributed to the side that caused it – `caused[side]`): the decision *Escalate* (+1), *Declare hostilities* (+1, 0 with a casus belli), *Invoke alliance* (+1), *Request support* (the package's cost, 0 for a response – "Outside support"), a sanctuary breach (+1, once per side and country), a strike on a target in an **urban** hex (+1 each – civilian areas; TASK-097). Battles and ordinary moves on open soil never raise it.
- **Lowers**: the decision *Stand down* (−1, attributed as `deescalated[side]`), and **calm**: after **3 consecutive full rounds** without any raise, the level drops by 1, but not below the operation's start level (*Limited war*); calm steps are attributed to nobody. Counted at the round boundary (when play returns to the first player); no randomness.
- **Deliberate decisions never reach the top**: *Escalate*, *Declare hostilities*, *Invoke alliance* and *Request support* are rejected when they would raise the level to 4. Only incidents (an order that breaches a sanctuary, a strike on a town) can – the view and the AI warn about them before the order is given (TASK-116 `route_incidents`).
- **After the operation ends** (`operation_ended`) every operational command is rejected (`operation_over`).
- **Victory hooks for TASK-107** **[ASSUMPTION]**: the threshold rule above; each side's score loses 3 points per **net** step it caused (`caused − deescalated`, at least 0).

### Political decisions

Specified in TASK-117 (the five below) and TASK-121 (*Request support*). Commands like every other operational action (`OperationalSimulation.execute`, codec, replay), **the same for both sides** ("Sides"). **One decision per side per own turn** **[ASSUMPTION]**. A side that stood down cannot take an escalating decision (*Escalate*, *Declare hostilities*, *Invoke alliance*, *Request support* with a cost > 0) during its next 2 own turns. The view names *Invoke alliance* from the side's data (NATO "Invoke collective defence", Russia "Invoke the Union State").

| Decision | Target | Allowed when | Effect |
|---|---|---|---|
| **Escalate** (authorise wider ROE) | – | level + 1 < 4; not standing down | level +1 (unlocks the next level's ROE for **both** sides) |
| **Stand down** | – | level > 0; the side raised nothing in this or the previous round; none of its formations stands in a country it breached or declared hostilities on | level −1; 2-turn cooldown on escalating decisions |
| **Declare hostilities** | a neutral or hostile country | the level after the cost < 4; not standing down | the country becomes belligerent **against the declarer** (a neutral joins the enemy side); +1, or 0 with a casus belli; its soil opens to the declarer |
| **Invoke alliance** | an own **aligned** country | level + 1 < 4; not standing down | the country becomes belligerent on the declarer's side, its formations join (TASK-118); +1 |
| **Demand neutrality** (ultimatum) | a hostile country (aligned with the enemy) that **accepts ultimatums** (data: Belarus yes, Lithuania no **[ASSUMPTION]**) | level ≤ Open war; **no enemy formation stands in that country** | the country becomes neutral: the enemy loses its staging area and transit there (and the entry route of outside support through it); no escalation |
| **Request support** (TASK-121) | a support package of the own side | the package is available ("Outside support"); level + cost < 4; not standing down when the cost > 0 | the package is on its way (arrives after its delay); the package's escalation cost (0 for a response); the other side sees it and may get a response option |

### Outside support

Decided by the human 2026-11-01 (third countries come in through the political game); mechanism designed 2026-11-01, specified in [TASK-121](tasks/TASK-121-outside-support.md) (supporters, packages, the request decision, formations arriving) and [TASK-122](tasks/TASK-122-support-strike-means.md) (strike means for TASK-097's stocks). All numbers **[ASSUMPTION]**. Pure rules in `src/core/operational/`, everything as data, changes only through commands and the end-of-turn step, **no `rng`**.

- **Supporters** (`data/supporters/<id>.tres`): off-map actors with a fixed side – `nato_allies` (USA, Germany, … – NATO), `north_korea`, `china`, `iran` (Russia). Not countries: no hexes, no stance. Their **status** is computed from the packages, seen the same by both sides (no fog yet): **uninvolved** (none of its packages is available or requested), **considering** (a package is available to its side, or requested and on its way), **supporting** (at least one package delivered); always with its side. A withdrawn package counts as never requested.
- **Support packages** (`SupportPackage`, listed per operation in `OperationDefinition.support_packages`): id, supporter, side (the recipient – the supporter's side), and
  - **conditions** (all must hold): `min_level` ≤ escalation level ≤ `max_level`; `max_caused` (−1 = none): the requester's **net** escalation caused (`caused − deescalated`) is at most this;
  - **response**: `response_to` – packages of the other side; once the other side has **requested** any of them, this package is available whatever its conditions and costs **no escalation** – the visible consequence that the other bloc gets an answer;
  - **cost**: `escalation_cost` steps, attributed to the requester (cause `support_request`; waived for a response); `entry_casus_belli` – formations delivered into a country **aligned** (not belligerent) with the recipient give the other side a casus belli against that country;
  - **delay**: `delay_turns` – delivered at the start of the recipient's own turn in round `request turn + delay`;
  - `withdraw_if_unmet` – the conditions are checked again at delivery; unmet → the package is **withdrawn** (nothing arrives, a paid cost is not refunded);
  - **effects**: `formations` (placements – the same `FormationPlacement` as the order of battle; the coord is the **entry hex**) and (TASK-122) `strike_means` (means id + count added to the side's strike stock of TASK-097). No new formation types and no new means types: formations use the side's types, means the TASK-097 types.
- **Request** = the decision *Request support* (one per turn with the other decisions). One request per package; it cannot be cancelled.
- **Delivery of formations** uses the same placement rule as allies joining (TASK-118): on the entry hex, else the nearest free passable hex of the same country within 3 hexes; additionally the hex must be **open** to the side. When no hex is found, the formation **waits off the map** and is retried at the start of each own turn (an ally's contribution, in contrast, is lost) – e.g. North Korean troops cannot arrive while Belarus is neutral. Delivered formations are full-strength, in the operation's start posture, without orders, and can get orders in the same turn.
- **Delivery of means** (TASK-122): added to the side's stock; TASK-097 consumes stock without knowing where it came from.
- **Shipped packages of the Suwałki operation** **[ASSUMPTION – balance guess, checked by TASK-103]**:

  | Package (id) | Side ← supporter | Effect | Conditions | Cost | Delay | Response to |
  |---|---|---|---|---|---|---|
  | Allied reinforcements (`allied_reinforcements`) | NATO ← NATO allies | US Armored Battalion (`pl_tank_battalion`) + NATO Mechanised Battalion (`pl_mech_battalion`), 80, west edge of Poland | level 1–3 | +1 | 4 | `nk_troops` |
  | North Korean expeditionary force (`nk_troops`) | Russia ← North Korea | North Korean Infantry Battalion (`ru_motor_rifle_battalion`) + North Korean Artillery Battalion (`ru_mlrs_battalion`), 56, east edge of Belarus; `entry_casus_belli` | level 2–3 (only once the war is open) | +1 | 4 | `allied_reinforcements` |
  | Chinese missile components (`china_components`, TASK-122) | Russia ← China | +4 `cruise` | level 1–2; Russia's net caused ≤ 1; `withdraw_if_unmet` | 0 | 6 | – |
  | Iranian strike drones (`iran_drones`, TASK-122) | Russia ← Iran | +8 `strike_drone` | level 1–3 | 0 | 2 | – |
  | Allied strike means (`allied_strike_means`, TASK-122) | NATO ← NATO allies | +4 `cruise` | level 2–3 | 0 | 2 | `china_components`, `iran_drones` |

  Means counts are relative to TASK-097's starting stocks (about +50 % of a side's stock of that means) and are re-set when TASK-097 fixes the stocks.

### Strategic options

The design goal: attacking Kaliningrad or Belarus, or keeping them out, is a **trade**, never a free switch. What each option buys and what it costs, for the start situation above **[ASSUMPTION – to be balanced with TASK-103 simulations]**:

**NATO (side 0 – Poland holds the Gap, Lithuania aligned)**

| Option | Military gain | Cost / risk |
|---|---|---|
| Fight only on Polish (and Lithuanian) soil, level 1 | no escalation penalty; Lithuania stays a safe transit area | Kaliningrad and Belarus are **sanctuaries**: Russian rocket artillery, depots and staging formations there cannot be struck or attacked; beaten Russian formations retreat into them |
| *Demand neutrality* of Belarus | closes Russia's Belarus staging area and transit for good (until *Regional war*) | only when no Russian formation stands in Belarus – a timing play once the Belarus group has crossed; one decision |
| *Invoke alliance* with Lithuania | +3 formations (120 strength) around Kaunas / Vilnius | +1 attributed; Lithuania becomes a battlefield – Russia may now enter it (the Lithuanian half of the Gap and the short road link Kaliningrad – Belarus open up) |
| *Escalate* to *Open war* | strikes on airfields and C2; Kaliningrad's soil opens to strikes and ground attack | +1 attributed; Russia gets the same ROE against Polish airfields and C2 |
| **Attack the Kaliningrad oblast** (needs *Open war*) | destroy the northern jaw, depots and airfields at the source; Kaliningrad objectives (TASK-107) | the first entry is a sanctuary breach: +1 → *Regional war*: Belarus joins Russia (+110) and Lithuania joins Poland (+120) automatically; Poland has caused 2 net steps and the ladder is one step from the threshold – any later Polish sanctuary or urban-strike incident loses the operation |
| **Attack Belarus** (*Declare hostilities*) | hit the Russian Belarus group in its staging area, cut its roads, flank through Grodno | Belarus joins Russia with its army (+110); +1 attributed – **free if Russia has launched an attack out of Belarus** (casus belli) |
| *Stand down* | −1 level, cuts the net escalation penalty; brings the ladder away from the threshold | lower ROE for both sides; Poland must first leave any country it breached or declared on; 2-turn cooldown |

**Russia (side 1 – wants to close the Gap, Belarus aligned)**

| Option | Military gain | Cost / risk |
|---|---|---|
| Close the Gap on Polish soil only, Belarus group kept in Belarus | Belarus stays a sanctuary and a threat-in-being that ties Polish forces to the Białystok border; blocks a Polish ultimatum | the Belarus group does not fight |
| Attack out of Belarus while Belarus stays aligned | a second axis from Grodno – the classic pincer on the Gap | hands Poland a **casus belli** (a free declaration against Belarus); once the group has left Belarus, Poland may demand its neutrality |
| *Invoke alliance* with Belarus | +3 Belarusian formations (110) | +1 attributed; Belarus loses sanctuary status for Russian forces – Polish strikes and attacks may follow |
| *Declare hostilities* on Lithuania | the Lithuanian half of the Gap and the short road link between Kaliningrad and Belarus | Lithuania joins Poland (+120); +1 attributed (0 if Poland launched out of Lithuania) |
| *Escalate* to *Open war* | deep strikes on Polish airfields and C2 | +1 attributed; opens the Kaliningrad oblast to Polish strikes and ground attack |
| *Demand neutrality* of Lithuania | – | not possible: Lithuania refuses ultimatums (NATO member) **[ASSUMPTION]** – Russia's levers are Belarus and outside support instead |

**Third countries – draw them in or keep them out** (both sides; "Outside support", TASK-118 / TASK-121 / TASK-122):

| Third party | What it brings | Russia: draw in / keep out | NATO: draw in / keep out |
|---|---|---|---|
| **Belarus** (on the map, aligned with Russia) | staging area and transit for the Russian Belarus group; 3 formations (110) when belligerent on Russia's side; the entry route of North Korean troops | *keep aligned*: closed to NATO, a threat-in-being; *invoke the Union State*: +110 but Belarus becomes a battlefield open to NATO (+1) | *keep out*: an ultimatum once the Belarus group has left (also closes the North Korean route); *draw in* (declare, free with a casus belli): its staging area opens to strikes and attack, but Belarus fights for Russia (+110) |
| **North Korea** (off the map) | 2 battalions (56) at the east edge of Belarus after 4 turns, from *Open war* | *draw in*: +56, but +1 attributed, a casus belli for NATO against an aligned Belarus, and NATO's allied reinforcements (+80) become a **free** response; *keep out*: no cost, no NATO reinforcements for free | cannot request it; *keeps it out* by keeping the war below *Open war* or by neutralising Belarus (no entry hex – the troops wait off the map); if it comes, answers for free |
| **China / Iran** (off the map, weapons only) | China: +4 cruise missiles after 6 turns; Iran: +8 strike drones after 2 turns | *draw in*: no escalation, but NATO's allied strike means become a free response; China delivers only to a **restrained** Russia (level ≤ *Open war*, net caused ≤ 1) and withdraws otherwise – escalating costs Russia the Chinese missiles | cannot stop the request; *cuts China off* by pushing the level to *Regional war* – at the price of its own escalation record; answers with allied strike means for free |
| **NATO allies** (off the map) | 2 battalions (80) at the west edge of Poland after 4 turns; +4 cruise missiles from *Open war* | cannot request them; *keeps them out* by not requesting North Korean troops (that makes the reinforcements free for NATO) | *draw in*: +80 for +1 attributed (free as a response); the cost is the ladder – a request at *Open war* takes it to *Regional war* (all aligned countries join) |

The core dilemmas: the **sanctuary** (strike the source or respect the border), the **ally's army vs. a new front** (invoking an ally adds formations but turns its soil into a battlefield), the **casus belli** (using an aligned country as a launch pad makes it fair game), the **threshold** (every step brings a ruinous defeat closer for whoever takes the last one) and **internationalising the war** (outside help arrives late, and whoever brings it in first pays, while the other bloc answers for free).

### Operational map view (TASK-093, planned)

Deliberately unlike the 3D battle scene – a **paper staff map**, the leader's map (head of government + chief of the general staff, "Player roles") **[ASSUMPTION – details for the human to confirm]**. Built **before** TASK-094 as v0 without politics (recommended 2026-11-01 **[ASSUMPTION]**, see BACKLOG "Two-layer game"): the loop must be visible to the human when it closes, and TASK-094's contact notice and scene change live in this scene. Country borders, stance tints and the escalation level come later with the political layer (TASK-119, data from TASK-112 / TASK-113).

- **Flat and top-down**: no 3D terrain or models. A 2D view with a **fixed top-down camera**: pan (drag / keys / screen edge) and zoom (wheel) clamped to the map; no rotation or tilt.
- **Base map**: pale paper tint with **shaded relief** (grey hillshade, low contrast) and flat land-cover fills drawn as real geography: forests green, lakes and wide rivers blue, marshes with a blue hatch, towns as grey blocks. Land cover comes from the hex terrain in v0 (smoothed across hex edges); finer shapes are a later refinement.
- **Lines**: roads as red / orange lines along the road links (major roads only), rivers as blue lines along the river links, **country borders** as a dash-dot line (TASK-119), **place names** (towns, villages) as map labels. Fine border lines, names and a fine relief raster need importer data – TASK-112; until then borders follow the hex edges between hexes of different countries (per-hex country, TASK-113) and the relief comes from the per-hex elevation.
- **Countries and politics** (TASK-114 / 115 state, drawn by TASK-119): each country gets a faint tint by its stance seen from the player (own / hostile / enemy / neutral) and its name; closed countries are hatched; the **escalation level** (name + number, e.g. "1 · Limited war") sits in the turn bar. The full political panel (ladder with ROE per level, decisions with the reason a decision is unavailable, route warnings for sanctuary breaches) is TASK-119.
- **Hex grid hidden** by default, a very faint grid on a toggle (G, as in battle) – the hexes stay the rules underneath.
- **Seen from the human's side** ("Sides"): the view takes the human's player index as a parameter from v0 (NATO or Russia); friendly / hostile, stance tints and orders are relative to it.
- **Formations as NATO APP-6 counters**: friendly frame (blue rectangle) / hostile (red diamond), branch icon by formation class (mechanised infantry, armour, rocket artillery), echelon mark above (battalion `II`), short designation beside (e.g. `1/15`), a small strength bar. No 3D models.
- **Front line drawn as a line** **[ASSUMPTION]**: each land hex within 3 hexes of a formation belongs to the side of the nearest formation (hex distance; ties belong to nobody); the front line is drawn along the edges between hexes of different sides (a thick line with small teeth towards the enemy), recomputed after every event. A pure helper in core, tested.
- **Orders on the map**: selecting a formation and clicking a destination shows the planned route as an arrow with a tick at each per-turn stop (forecast); posture chosen with keys 1 march / 2 advance / 3 defend or a small picker; arrow style per posture (march dashed, advance solid, defend ending in a defence arc). Existing orders stay drawn as arrows; cancel with Delete / X. End turn executes the orders and the counters slide along their paths; interrupted orders are listed in a short report.
- **Turn bar**: turn number, date and time of day (12 h per turn), the side to play.
- **Contact notice** (TASK-094 / TASK-120): when a battle is pending, a notice names the formations, the attacker and the place, and offers **Play battle** (the battle scene, as the commander) or **Auto-resolve** (the result at once); afterwards a short after-action report lists losses, who holds the field and who retreats.

## Open questions

Each question lists the tasks that depend on the answer.

- **Victory condition** (decided 2026-10-30: per-battle `BattleObjectives`, implemented in TASK-088 – see "Vision decisions" and "Gameplay loop"): eliminate / take hexes / hold hexes / destroy a share, plus a turn limit with draws. Still open: kill the leader, survive N turns, exit through a map edge, victory points per unit type. Assumptions taken in TASK-088 (ADR 0016) **[ASSUMPTION]**:
  - elimination is not implicit: a side wiped out while the opponent has no `eliminate` condition does not end the battle; it runs to the turn limit (both shipped battles list `eliminate` for both players, so this is not reachable today);
  - a strike that ends the battle gets no counterattack (matters for `destroy_share`);
  - objective battle balance (Poland must take both hexes past the fords by turn 8, Russia holds them at start): AI simulation of 50 matches gave Poland 6 wins, Russia 21, 23 draws – the attacker is weak. Tuning (turn limit, hex placement, a `destroy_share` alternative for the attacker) is open. → TASK-094 (derived objectives), a follow-up balance task.
- **Turn limit as a game rule?** (decided 2026-10-30: yes, per battle, implemented in TASK-088) The battle ends after the last player's turn of turn `turn_limit`. The simulation (TASK-012) reports such rule draws separately from matches cut by its harness `--max-turns`. → TASK-012.
- **Randomness in combat** (decided 2026-10-30: per-element rolls, exact calibration, no minimum damage, TASK-089a; numbers in "Combat" → "Per-element rolls"): deterministic (like Into the Breach) or with rolls (like Wesnoth)? Implemented with rolls in TASK-089a. → TASK-002 (flat defense bonus vs. hit-chance modifier), TASK-010 (deterministic counter), TASK-011 (rocket artillery balance). Replays (TASK-005) work either way, because all randomness goes through `GameState.rng`.
- **Damage scale**: with the subtractive formula and current stats, most matchups deal 1–3 damage, and terrain bonuses (TASK-002) push many of them to the minimum of 1, which makes terrain differences between units disappear. Should HP/attack be scaled up (e.g. ×2) or the formula changed? → revisit with TASK-012 statistics after TASK-002/-010/-011.
- **Forest vs. hills**: with the proposed numbers hills (+2) strictly dominate forest (+1) at the same move cost. Should they differ in another way (e.g. forest blocks rocket fire, hills give +1 range)? → TASK-002, TASK-011 follow-ups.
- **Scale** (decided 2026-10-30: two layers – operational formations, tactical companies; see "Vision decisions"): tactical skirmishes (a few units) or strategy with an economy and cities? → TASK-007 (fog of war), map size, AI scope.
- **Setting**: modern military with real countries and real equipment (decided 2026-10-18). Era: present day; first factions Poland and Russia with their rosters (see "Factions and units"). → TASK-039a.
- **Old match records** (decided 2026-10-18): records made before TASK-039a are unsupported – the loader rejects them with a clear message, and existing local saves are simply deleted. → TASK-039a.
- **Modes**: vs AI only, hot-seat, network multiplayer? → TASK-005 (command serialization is the groundwork for network/replays), `HUMAN_PLAYER` constant in the battle controller, TASK-007 (hot-seat fog needs a hand-off screen).
- **Fog of war** (decided 2026-10-30: yes, in the MVP on both layers; vision rules still open): yes/no, and per player vision rules? → TASK-007 (stays `idea` until scale and modes are decided).
- **Cavalry's look**: the mock-up has no cavalry; TASK-019 uses the mock-up's **tank** model for cavalry as an interim (both are the fast 5-move unit). Answered by the setting decision: cavalry is replaced by the tank class in TASK-039a. → TASK-019, TASK-039a.
- **Stat derivation rules**: proposed 2026-10-18 (see "Stat derivation rules"), no new stats; hard/soft attack recorded as a non-adopted option. Approved by the human on 2026-10-18 (the section header says so; this entry previously still said "waiting for approval"). → TASK-039a.
- **Rocket artillery at close range** (found while writing the manual, 2026-10-18): the code has no minimum range, so artillery fires at adjacent enemies and counters adjacent attackers with its full attack 5 – e.g. cavalry attacking artillery takes 3 counter damage, as much as from a cavalry. The visual-design idea (indirect fire at range 3–6, no firing after moving) would change that. Keep it, add a minimum range (e.g. 2, which also removes the close-range counter), or reduce close-range damage? → TASK-039a balance / follow-up task.
- **T-72B3 variant** (decided 2026-10-18): obr. 2016 (V-92S2F 1130 hp → move 5). The 2011 batch could become a separate unit later.
- **Squad facts to confirm**: Polish mechanised squad size and whether Carl Gustaf M4 is a squad weapon; whether either side has a squad-level guided ATGM (it would give +1 attack). → TASK-039a (catalog).
- **Infantry vs. tanks** (accepted 2026-10-18, revisit after simulations): with the derived stats infantry deals the minimum 1 damage to every tank and takes 3–4. Acceptable for now (tanks *should* beat infantry in the open), but if simulations show infantry is pointless, look at the "Damage scale" question or hard/soft attack. → TASK-039a follow-up.
- ~~**One-shot kills**~~ – answered 2026-10-30 (approved by the human with TASK-089a): kills are no longer certain. With per-element rolls a full Abrams destroys a full MLRS on plains 63 % of the time instead of always (Homar-K → Uragan from 6 hexes: 33 %). Originally (2026-10-18): an Abrams destroyed a full-HP MLRS in one attack on plains (7 − 1 = 6 HP). → TASK-039a, TASK-089a.
- **Side bias in the simulation**: mirrored armies gave player 1 a 59 % vs 34 % win rate (TASK-012), cause unknown. TASK-039a measures balance over both side assignments; the bias itself is a separate follow-up. → TASK-012, TASK-039a.
- **UI scaling**: HUD sizes are the mock-up's CSS pixels 1:1 (matches 1280×720 screenshots). Stretch mode / scaling for larger or smaller windows is undecided. → TASK-014, TASK-020.
- **Does elevation matter for rules?** TASK-016a generates an elevation per hex (shown in metres in the terrain panel, TASK-024). Possible uses: defense bonus for the higher unit, vision/line of sight, ranged bonus. → future tasks; TASK-011 (rocket artillery) could use it.
- **Unit mechanisms (animation)**: real values to verify – Uragan launcher traverse range, maximum elevation, stowed facing forward over the cab, rear jacks, cab blast shields (?); Homar-K jack count/position and real maximum elevation (keep 40° for the look?) (?); tank gun elevation limits (?); real recoil strokes of the M256 (≈ 0.33 m ?) and the 2A46M-5 (≈ 0.3 m ?) behind TASK-048's exaggerated `recoil_m` 0.5 / 0.4 m. Behaviour choices proposed but not confirmed: a limited-traverse launcher's vehicle stays turned after the volley; the launcher always fires at its maximum elevation (not scaled with range); durations are global, not per unit; the turret returns to the front after firing; feet of jacks may float slightly on slopes; the catalog ↔ model contract test fails on any parameter drift. → TASK-041 … TASK-047.
- ~~**Third-party CC0 assets**~~ – decided 2026-10-22: the human allows downloaded CC0 assets – textures and HDRI skies (Poly Haven, ambientCG), vegetation / tree glTF models (TASK-060 option B possible); unit models stay procedural. Recorded in an ADR by TASK-053. For trees the human chose (2026-10-22) procedural trees with optional CC0 bark/leaf textures; glTF tree models rejected (too heavy, or stylised low-poly). → TASK-060. → TASK-053, TASK-054, TASK-055, TASK-060.
- **Performance budget** (2026-10-20): target a D3D12 GPU (Windows, Forward+); the WSLg software renderer is preview-only. Every realism feature must switch off on the LOW preset. Which GPU is the minimum target, and is a MEDIUM preset or a settings screen needed? → TASK-050 and every realism task.
- **Wrecks** (2026-10-20): proposed **[ASSUMPTION]** – destroyed vehicles leave a cosmetic wreck that hides when a unit enters its tile, smoke for 3 turns, infantry leaves none. Wrecks never affect rules unless a separate rules task decides otherwise. → TASK-065.
- **Rocket salvo pacing** (2026-10-23): a full salvo (12 Homar-K / 16 Uragan rockets with visible pauses) makes an MLRS attack ≈ 10 s. Proposed **[ASSUMPTION]**: salvos are left out of the AI-turn animation speed-up and play at most 1.5× faster; counter salvos are full salvos; a very small camera shake near the camera. Alternatives: shorter counter salvos, a "fast animations" key, a shorter rocket interval. Purely visual – the salvo size is not a game quantity (ammunition stays an idea). → [TASK-074](tasks/TASK-074-mlrs-salvo-sequence.md) (pacing), [TASK-075](tasks/TASK-075-mlrs-salvo-effects.md) (camera shake).
- **Russian vehicle markings** (2026-10-20): proposed **[ASSUMPTION]** – tactical numbers only, no national insignia, never "Z"/"V" symbols; Polish vehicles carry the red-white checkerboard. → TASK-063.
- **Real-terrain types (TASK-108)** – proposed **[ASSUMPTION]**, revisit after playtests and `tools/simulate.sh --scenario=suwalki_battle`:
  - *Fields* have the plains rules (look only). Should they matter later – concealment under fog of war (TASK-007), seasonal mud? Unmapped open ground in OSM (mostly fields in rural Poland) stays plains.
  - *Urban* +2 like hills; +3 would push most attacks to the minimum damage (see "Damage scale").
  - *Field and forest tracks* (`highway=track`) are not roads – they would erase forest's movement cost on dense networks. A lower-grade "track" link (e.g. cost of the terrain − 1) is possible.
  - *Bridges over water hexes* (a road across a lake narrows or a wide river mapped as water) are lost: water stays impassable even with a road.
  - *Streams*: only named streams count as rivers; if real maps get too many river hexes, drop streams.
- ~~**Frame rate on large real-terrain maps**~~ – decided 2026-10-31 by the human: the real-terrain look tasks (TASK-108b … 108e) only have "don't make it worse" budgets; no quality trade now. TASK-110 (realistic scale) re-measures performance. Original question: the Suwałki battle (720 hexes) renders at 23.8 ms (~42 FPS) at the default camera on the RX 580, HIGH, against the 60 FPS rule – the rest is content (much more LOD0 forest near the camera than in the default battle). TASK-108b … TASK-108e only promise not to make it worse beyond their small budgets. Reaching 60 needs a quality trade the human must choose; measured options (TASK-108 notes): MSAA 4x → 2x ≈ −2 ms, 2 shadow splits ≈ −1.5 ms, LOD1 tree shadows off ≈ −0.7 ms, shorter LOD0 tree range ≈ −0.5 ms (together ≈ −4.7 ms → ~19 ms, still above 16.7 ms), or TASK-072's distance budgets. Also open: is the RX 580 the minimum target, and does a MEDIUM preset make sense (see "Performance budget"). → a follow-up performance task, TASK-072.
- **Realistic scale** (decided 2026-10-31: everything at real size relative to the real hex – see "Visual direction"; replaces the tree-scale house proposal). Sub-decisions (the human, 2026-10-31, "use recommended options"):
  - *Readability* – **decided**: unit models at real size (no enlarged-unit compromise); units are found through **on-screen unit markers** (icon + label at a fixed pixel size, always readable) and the camera gets a **much closer minimum distance** to see the real models. → TASK-110 (marker / camera targets in the study), TASK-111 (implementation).
  - *A unit is a company* – **decided in TASK-110**: one real-size vehicle per hex or a small formation (e.g. 3–4 vehicles or 3 squads) spread in the hex, chosen from TASK-110's screenshots.
  - *Thin features* – **decided**: roads and rivers keep a 1.5 px minimum on-screen width (TASK-108b/108c) so they don't flicker or vanish when zoomed out; true width whenever wider.
  - *Generated maps' hex size* – **decided**: 250 m, the same tactical hex as real maps (`MapScale.DEFAULT_METRES_PER_UNIT` = 250 / √3 m per world unit).
  - *Vertical scale* – **decided in TASK-110**: keep the 1.5× relief of real maps (ADR 0018) or go to strictly real 1.0×.
  - *Performance* – open: real forest density (~2 000 trees per hex) needs impostors / distance budgets (TASK-072 overlap); TASK-110 measures and proposes.
  → TASK-110, TASK-111, then TASK-110's follow-up tasks; TASK-108b … 108e use `MapScale` and are right at any scale.
- ~~**Buildings and road classes from OSM**~~ – decided 2026-10-31: procedural villages and one road look first; an importer task (`building=*` footprints, road class / `surface`) only if the procedural look is not convincing. Original note (TASK-108b/108d): the importer stores only a dominant class per hex and road link masks, so villages are drawn procedurally inside urban hexes, scattered farmsteads in non-urban hexes are missing, and every road looks the same (gravel). Importing `building=*` footprints (per-hex counts or positions) and the road class / `surface` tag would make both real – a later importer + look task if the procedural look is not enough.
- **Map size**: the mock-up map is 26×18 hexes; the prototype battle is 12×10. Bigger maps change pacing and AI cost. → scale question above.
- **Operational layer v1** (2026-11-01, TASK-092a–e; the specs follow the recommended options, marked **[ASSUMPTION]** in "Operational layer" – waiting for the human):
  - *Feel* – **decided** by the human 2026-11-01: clearly different from the battle through presentation (paper map, NATO counters, front lines, top-down camera) and multi-turn orders (destination + posture, executed over several turns); hexes stay underneath; alternating turns kept, simultaneous resolution rejected. → TASK-092c–e, TASK-093.
  - *Postures*: the minimal set march / advance / defend with 100 / 75 / 50 % of the move points, march and defend planning around enemy zones of control, advance halting on contact and keeping its order (recommended). Alternatives: two postures only (move / attack); a `delay` posture now (fall back one hex when contacted – needs TASK-095's retreat rule, so recommended later). → TASK-092d, TASK-094 (battle effects).
  - *Execution timing*: at the end of the owner's turn, formations in order-of-battle order, first step always allowed, unused points lost (recommended). Alternatives: at the start of the owner's next turn (the opponent sees the orders' arrows for a turn first – only meaningful with fog), or the player choosing the execution order. → TASK-092e.
  - *Map view*: a 2D view (recommended – simplest, sharp lines and labels) vs. an orthographic 3D camera over a flat plane (reuses the battle's map-to-world code); the front-line rule (nearest formation within 3 hexes); counter style (blue / red APP-6 frames, battalion `II`). → TASK-093.
  - *Map area and size* – **decided** by the human 2026-11-01: a regional theatre of ~300 × 300 km (north-east Poland, Kaliningrad oblast, southern Lithuania, western Belarus). Proposed exact extent **[ASSUMPTION]**: 68 × 64 hexes centred on 54.20 N, 22.90 E (GDD "Theatre") – alternative exactly 60 × 60 (Kaliningrad and Vilnius end up on the edge columns). The earlier 20 × 16 Suwałki Gap map is dropped. → TASK-092a.
  - *Formation level*: battalion-sized counters with the brigade as a label (recommended) vs. brigade counters (12–15 companies – too many for one 30 × 24 battle) vs. both levels with split / merge. → TASK-092b.
  - *Order of battle*: the six formation types and, on the theatre map, 8 Polish vs. 10 Russian formations (Kaliningrad group + Belarus group) plus the allies' formations that join with their country (Lithuania 3, Belarus 3) in "Formations"; real unit designations (e.g. Poland's 15th Mechanised Brigade) only as flavour labels. → TASK-092b, TASK-118.
  - *Movement*: 8 move points, road 1 / open 2 / forest and hills 3 / marsh 4 / river +2, one formation per hex, zone of control (planned around, or halting an advance), Russia moving first, 12-hour turns. → TASK-092b, TASK-092c.
  - *Country borders and hex control* – **decided** 2026-11-01: every hex has a country, imported with the map (TASK-113) and used by the rules through stances (GDD "Countries and stances"); TASK-112 keeps only the fine border lines for drawing. Hex *control* (who holds a hex of an enemy country – supply TASK-096, objectives TASK-107) stays open.
  - *Tactical maps for contacts anywhere* (revised for the theatre): the 340 × 277 km theatre is ≈ 1 360 × 1 280 ≈ 1.7 million tactical hexes, so the earlier recommendation (a) – one big tactical import cut by `BattleSetup.map_region` – no longer fits (several GB of full-detail OSM, hours of import, tens of MB committed). Options: (b) pre-import one 30 × 24 tactical map per operational hex (~4 000 maps, ~200 MB – too big); (c) allow contacts only where a tactical map exists (kills operational freedom); (d) a **chunked theatre-wide tactical layer** – a resumable offline batch import (land hexes only) into compact per-chunk files (≈ 1 byte terrain + 2 link bytes + 1 elevation byte per tactical hex ≈ 7 MB raw, a few MB compressed), cut per battle; (e) battle maps derived at battle time from the operational hex (breaks "real geography"). Recommended **(d), measured first** (download size, import time, committed size) as a study step of TASK-094 or a split-off task. → TASK-094.
  - *Campaign record*: `CampaignRecord` (ADR 0015 §4) is left for TASK-094, where the first battle enters the record; TASK-092e only proves that replaying the operational commands gives the same state.
- **Political layer v1** (2026-11-01, TASK-113–119; the human decided: regional theatre, per-country stance + one shared escalation ladder, new tasks on top of 092b. The details below follow the recommended options, marked **[ASSUMPTION]** in "Countries and stances", "Escalation ladder", "Political decisions", "Strategic options" – waiting for the human):
  - *Stance set*: neutral / aligned / belligerent with a side, shown player-relative as own / hostile / enemy / neutral (recommended – the smallest set that tells "may stage and transit" from "is a battlefield"). Alternative: a per-side relation pair (each country's attitude to each side separately) – more expressive, more states to test. → TASK-114.
  - *Belligerent is final*: no peace or armistice inside one operation (recommended). → TASK-114, TASK-106.
  - *Crossing into a closed country*: only after an explicit *Declare hostilities* decision; routes never cross closed borders by themselves (recommended – no accidental widening of the war by the route planner). Alternative: an order may target a closed country and the first entry declares automatically (closer to "crossing a border changes the stance", but one mis-click widens the war). → TASK-116, TASK-117.
  - *Start stances*: Lithuania aligned with Poland (not fighting), Belarus aligned with Russia and hosting the Russian Belarus group, start level 1 *Limited war* (recommended). Alternatives: Belarus neutral at start (Russia must first win Belarus over – needs a "request access" decision); Lithuania belligerent from the start (NATO Article 5 fully invoked – removes Poland's invoke choice). → TASK-114.
  - *Ladder*: five levels with the ROE table in "Escalation ladder"; sanctuary soil opens at *Open war*; allies join at *Regional war*; reaching the top loses for the side that caused it; calm decay after 3 quiet rounds down to the start level; urban strikes +1 each. Alternatives: the top ends in a draw for both (weaker deterrent); no automatic joining (allies only by decision). → TASK-115.
  - *Decisions*: five (Escalate, Stand down, Declare hostilities, Invoke alliance, Demand neutrality), one per own turn, 2-turn cooldown after standing down, decisions can never take the ladder to the top. Not included: "guarantee neutrality", "request access" (neutral → aligned by decision), peace offers – candidates for TASK-106 events. → TASK-117.
  - *Allies' forces*: represented with the side's formation types and flavour names (Lithuanian brigades with Polish types, Belarusian with Russian types) until Lithuania / Belarus are factions with their own rosters. → TASK-118.
  - *Scoring*: −3 victory points per net escalation step caused, plus the threshold defeat. → TASK-107.
  - *Contacts at a closed border*: zones of control work across borders (a formation in a hostile country still halts an advance next to it), but no battle starts against a formation in a country closed to the attacker (recommended). Alternative: no zone of control across a closed border. → TASK-116 (adds the rule to TASK-094's `ContactRules.battle_allowed`; decided 2026-11-01 that the loop comes first, so TASK-094 no longer waits for the political layer).
- **Player roles** (2026-11-01; the two roles are decided, "Operational layer" → "Player roles"; the details below are recommendations **[ASSUMPTION]** waiting for the human):
  - *Which units the commander commands*: every own company in the battle (recommended – the battle stays the game it is today; the player is "the commanders" of the engaged battle group). Alternative: the player picks one company or battalion and the tactical AI commands the rest (closer to "a lower-rank commander", but needs a friendly tactical AI and orders between AI and player units). → TASK-094.
  - ~~*Playing as Russia*~~ – **decided by the human 2026-11-01**: both sides are selectable when starting an operation, and both belong to the MVP; the sides are blocs (NATO vs Russia, "Sides"). Only the order of the choice is open: NATO listed first **[ASSUMPTION]**. → TASK-092b (sides as data), TASK-093 (perspective parameter), TASK-102 (AI for either side), TASK-103 (balance of both), TASK-107 (the choice).
  - *Personal / political cost of losing a battle*: none in v1 – a lost battle costs only losses, ground and the retreat; the operation's score (TASK-107) counts the outcome (recommended). Alternative: a "public support" or "government confidence" track that lost battles and losses lower (dismissal of the leader as a defeat condition) – a candidate for TASK-106 events once the loop works. → TASK-106, TASK-107.
  - *Auto-resolve availability*: every contact, for the human's side, chosen on the contact notice; not switchable once a battle is played; no fidelity penalty for auto-resolving (recommended; TASK-120 compares auto-resolve with headless AI-vs-AI played battles and reports the gap). Alternative: a small penalty (e.g. +10 % own losses) to reward playing. → TASK-120.
  - *Commander's view of politics*: the battle HUD shows mission and intent only, no political panel or escalation level (recommended – the commander cannot act on them). → TASK-094.
- **Sides and outside support v1** (2026-11-01; the human decided both sides playable, blocs NATO vs Russia, third countries only through politics – "Sides", "Outside support"; the details below are the designer's recommendations **[ASSUMPTION]**):
  - *Sanctuary asymmetry*: only Russian soil is a sanctuary (reasons in "Sides"); the rule is symmetric in code. Alternative: make Poland a sanctuary for Russia too (symmetric "homeland" rule – but then Russia could not fight on Polish soil below *Open war*, which contradicts the scenario). → TASK-114, TASK-115.
  - *Lithuania refuses ultimatums* (`accepts_ultimatum` false; Belarus true). Alternative: symmetric – Russia may demand Lithuania's neutrality like NATO Belarus's (more mirror-like, less plausible for a NATO member). → TASK-117.
  - *Supporters as off-map packages* instead of on-map countries with stances: North Korea, China, Iran and the NATO allies never get hexes or stances; status uninvolved / considering / supporting is computed. Alternative: off-map countries with stances (heavier, no gain while they have no soil). → TASK-121.
  - *Response rule*: requesting a package with a `response_to` link makes the other bloc's answer available and free of escalation. Alternative: no free responses (each bloc pays for its own help). → TASK-121.
  - *Numbers*: the five packages in "Outside support" (entry hexes, delays 2–6 turns, +1 for troops, 0 for weapons, China's restraint condition). → TASK-121, TASK-122, TASK-103.
  - *Supporters' formations* use the side's types with own names until North Korean / US / German factions exist. → TASK-121.
  - *Objectives per side* ("Sides" → victory: the Gap road link open vs closed, optional city objectives). Depends on the open "hex control" rule. → TASK-107.
  - *MVP*: outside support (TASK-121, TASK-122) is recommended **in** the MVP – the two blocs need their own levers for both sides to be balanced and interesting to play (without them Russia has fewer political options than NATO), and both tasks are small additions to TASK-117 / TASK-118 / TASK-097. Alternative: after the MVP, with Russia's political game limited to Belarus and Lithuania. → BACKLOG `mvp` tag.
- **Auto-resolve numbers** (TASK-120) **[ASSUMPTION]**: rounds = the battle's turn limit (else 8), break at 50 % losses, simultaneous fire with focus on the highest hit chance, position bonus defend +1 / advance 0 / march −1, the defender's operational hex terrain as the terrain bonus (not the tactical map – auto-resolve must not load a battle map, for speed); range, movement and objective hexes are not modelled (artillery fires like any company). Alternatives: a terrain mix from the tactical map cut (more faithful, slower); a lower break share for formations at low readiness (TASK-095). → TASK-120, TASK-094.
- **Seeing the loop** (2026-11-01, build order "loop first"): the human needs a view to playtest the vertical slice "move → contact → battle (played or auto-resolved) → consequences". Recommended **[ASSUMPTION]**: build TASK-093 (staff map v0, without the political overlays, which move to TASK-119) right after TASK-092e and before TASK-094 – no throwaway debug view, and TASK-094's contact notice and scene change need the operational scene anyway. Alternative: a minimal debug view (formations as text / dots on a grid, an end-turn key) before TASK-095, with TASK-093 after the political layer. → TASK-093, TASK-094.

### Ideas from the visual design

Seen in the mock-up (`docs/design/game_screen.scene.js`), **not** part of the visual tasks. Each needs a decision before it gets a task.

- **More terrain types** (fields, urban, roads and rivers adopted with other numbers in TASK-108; mountains still open): *fields* (cost 1, small defense bonus), *mountains* (cost 3, high defense, impassable for wheeled units), *urban* / named cities (cost 1, high defense, buildings scatter), plains vs. fields split. The terrain colouring already shows "mountain" heights as rock/snow on HILLS tiles.
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

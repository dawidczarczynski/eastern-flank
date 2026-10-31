# Eastern Flank – Game Design Document

> Living document. Assumptions marked **[ASSUMPTION]** are the starting point for the prototype – to be confirmed or changed.

## Vision

Full vision: [VISION.md](VISION.md) (2026-10-30). It moves the game from a single tactical battle to **two layers**: an operational map (formations, logistics, reconnaissance, air defence, deep strikes, political events) as the main scene, and tactical battles that start on contact and are fought in the conditions the operation created. Everything below this section describes the tactical layer as implemented so far.

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
- **Battles are always played** – no auto-resolve for now.
- **Fog of war** is in the MVP (both layers); reconnaissance drives deep strike accuracy.
- **Priorities**: the core loop "operation → deep strikes → battle → consequences" comes first; new visual polish waits (TASK-048, TASK-063, TASK-066 and further model reworks move down the backlog).
- **Tactical randomness** – decided 2026-10-30 (TASK-089a, numbers in "Combat" → "Per-element rolls"): per-element rolls (each strength point of the attacking company rolls to inflict a loss, so a full company has a small spread and a battered one a large spread; a damaged company deals less), with the expected range shown before the attack; later suppression / morale checks from fire (TASK-090) and indirect-fire accuracy from spotting. All through `GameState.rng`.
- **First theatre** – proposed **[ASSUMPTION]**: the Suwałki Gap (Poland / Lithuania / Kaliningrad / Belarus).

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

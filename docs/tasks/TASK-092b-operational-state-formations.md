# TASK-092b: Formations on the staff map – operational state, formations as data, the Suwałki Gap operation, APP-6 counters, selection panel

- **Status**: done
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data + presentation (counters, panel)
- **Depends on**: TASK-092a, TASK-086, TASK-093a
- **Model**: opus (new simulation facade, state snapshot and RNG stream every later operational task builds on; plus the first view of it)
- **Topic**: Two-layer game

## Goal

The operation exists as a deterministic state: named battalions made of real companies stand on the real Suwałki theatre map (`suwalki_theatre`, 68 × 64 hexes – TASK-092a) and the two sides take operational turns (GDD "Operational layer" → "Formations", "Operational turns"). The human **sees** them: NATO APP-6 counters stand on the staff map (TASK-093a) at their real start positions and clicking one opens its order of battle. Formations never move step by step: they get multi-turn orders – route planning is TASK-092c, orders and postures TASK-092d, order execution at the end of a turn TASK-092e (human decision 2026-11-01).

## Acceptance criteria (testable)

Shape (ADR 0015 §1–2; all pure logic, no `Node`):

- [x] `src/core/operational/`: `OperationalState`, `OperationalSimulation` (`execute(command) -> bool`: validate → reject with `command_rejected(command, reason)` or append to `history`, apply and emit each event through `event_emitted`; mirrors `GameSimulation`), `OperationalCommand` (base: `validate(state: OperationalState) -> String`, `apply(state) -> Array[Dictionary]`, `to_dict()`), `OperationalCommandCodec.from_dict(d) -> OperationalCommand` (null on anything unknown or malformed, same number rules as `CommandCodec`), `Formation` (runtime), `Operation` (builds a state from data).
- [x] The operational layer never references `GameState`, `GameSimulation` or tactical `Command`s (a test greps `src/core/operational/` for those class names).

Data (`src/core/data/`, `data/`):

- [x] `FormationDefinition` (Resource, `data/formations/<id>.tres`): `id`, `display_name` (English, a translation key), `faction`, `echelon` (`&"battalion"`), `formation_class` (`&"mechanised"`, `&"armoured"`, `&"artillery"`), `move_points`, `companies: Array[UnitDefinition]` (ordered).
- [x] `SideDefinition` (Resource, `data/sides/<id>.tres`; GDD "Operational layer" → "Sides", human decision 2026-11-01: both sides playable, sides are blocs): `id`, `display_name` (English, translation key), `lead_faction` (StringName – colours, HUD), `factions: Array[StringName]` (factions whose formation types the side may field; contains `lead_faction`). Two files: `nato` ("NATO", lead `poland`, factions [poland]) and `russia` ("Russia", lead `russia`, factions [russia]). `SideDefinition.find(id)` (null when unknown).
- [x] `OperationDefinition` (Resource, `data/operations/<id>.tres`): `id`, `display_name`, `map_id`, `sides: Array[SideDefinition]` (index = player; replaces a plain faction list), `first_player`, `formations: Array[FormationPlacement]`; `FormationPlacement` (sub-resource): `id` (unique, e.g. `&"pl_mech_1"`), `display_name` (e.g. "1st Mechanised Battalion"), `parent` (brigade label, e.g. "15th Mechanised Brigade"), `player`, `definition`, `coord` (axial on the map).
- [x] The six types of GDD "Formations" as `.tres` with these companies and `move_points` 8: `pl_mech_battalion` (3 × `pl_mech_infantry`, 1 × `m1a2_sepv3` → strength 40), `pl_tank_battalion` (3 × `m1a2_sepv3`, 1 × `pl_mech_infantry` → 40), `pl_mlrs_squadron` (3 × `homar_k` → 18), `ru_motor_rifle_battalion` (3 × `ru_motor_rifle`, 1 × `t72b3` → 38), `ru_tank_battalion` (3 × `t72b3`, 1 × `ru_motor_rifle` → 34), `ru_mlrs_battalion` (3 × `bm27_uragan` → 18). Test: each type's strength sum and that every company is in its faction's roster.
- [x] `data/operations/suwalki_gap.tres` (reworked 2026-11-01 for the theatre map, GDD "Formations" – order of battle **[ASSUMPTION]**): map `suwalki_theatre`, sides `[nato, russia]`, `first_player` 1 (Russia – whichever side the human plays). **NATO side (Poland)** 4 × `pl_mech_battalion`, 2 × `pl_tank_battalion`, 2 × `pl_mlrs_squadron` (8 formations, total 276): two facing the Kaliningrad oblast (Bartoszyce / Braniewo–Lidzbark area), three in the Gap (Suwałki / Augustów / Ełk), three facing Belarus (Białystok / Sokółka). **Russia side** 10 formations (total 332): the Kaliningrad group – 3 × `ru_motor_rifle_battalion`, 1 × `ru_tank_battalion`, 1 × `ru_mlrs_battalion` (Gusev / Chernyakhovsk / Sovetsk area) – and the Belarus group – the same five types around Grodno. Every formation on a land hex of its group's country (checked on a real map by the agent; the rule check comes with countries in TASK-114), every Polish formation ≥ 3 hexes from every Russian one (test), strength sums 276 / 332 (test); coordinates and labels (`parent`, e.g. "15th Mechanised Brigade", "11th Army Corps") picked by the agent on the real map and listed in the implementation notes with the place names. Allied formations that join later are TASK-118, off-map support TASK-121 – not placed here.

Building (`Operation`):

- [x] `Operation.NAMES` = `["suwalki_gap"]`; `Operation.build(id, seed) -> OperationalState` loads the definition and the map (`ImportedMap.find(map_id).to_grid()`); `Operation.from_definition(definition, seed, grid = null)` builds from given data (tests use a small hand-made `HexGrid`).
- [x] One `Formation` per placement, in placement order (this order is also the order in which TASK-092e executes orders): `id`, `owner_id` (= `player`), `definition`, `coord`, `companies: Array[Formation.Company]` (`unit_type`, `strength` = the unit's `max_hp`, `ref` = `"<formation id>/<n>"`, n from 1 – e.g. `pl_mech_1/4` is the Abrams company), `strength()` = sum.
- [x] Rejected with `push_error` and null (one test each): unknown operation id, unknown map, a placement off the map or on an impassable tile, two placements on one tile, a duplicate formation id, a placement whose type's faction is not one of its player's side's `factions`, a company outside the faction roster, `first_player` not 0 or 1, `sides` not exactly 2, a side whose `factions` lacks its `lead_faction`, the same faction in both sides.
- [x] **The human's side is not part of the operation**: `Operation.build` / `from_definition` take no human-side parameter and the state stores none (the choice lives in the session and `CampaignRecord` – TASK-094 / TASK-107), so the state, its snapshot and a replay are identical whichever side the human plays. Nothing in `src/core/operational/` compares a side or faction id with a literal (`nato`, `russia`, `poland`) – a test greps for those literals.
- [x] `OperationalState`: `operation_id`, `grid`, `player_sides` (side ids by player), `player_factions` (each side's `lead_faction`), `first_player`, `current_player` (= `first_player`), `turn` (1), `formations`, `rng` (seeded with the campaign seed; nothing draws from it yet), `pending_battles: Array[BattleSetup]` (empty; filled by TASK-094), `get_formation(id)`, `formation_at(coord)`, `snapshot()` → `{turn, current_player, rng_state (String), formations: [{id, player, coord: [q, r], companies: [[unit_type, strength], ...]}] sorted by id}`. Static data (definitions, map) is not in the snapshot. There is no `moves_left`: move points are spent automatically when orders execute (TASK-092e), so nothing carries between turns. TASK-092d adds `posture` and `order` to `Formation` and to each snapshot entry – keep the snapshot built in one place so it can grow.

Determinism and docs:

- [x] `Operation.build("suwalki_gap", 7).snapshot()` equals a second build with seed 7; seeds 7 and 8 differ only in `rng_state`. `OperationalCommandCodec.from_dict` returns null for any unknown or malformed dictionary (no command exists yet – 093b adds the first; test the null cases).
- [x] docs/ARCHITECTURE.md: "Two layers" names the new classes and data (the "Operational events" table is created by TASK-093b).

View (counters and selection, `src/presentation/operational/`):

- [x] `OperationalSimulation` is created by the staff map scene (`Operation.build("suwalki_gap", seed)`), the scene reads state and reacts to `event_emitted` only (rule 3). The view takes a `viewer_player` parameter (0 = first side listed, 1 = second; `--side=nato|russia` override, default NATO **[ASSUMPTION]**); frames are friendly (blue rectangle) / hostile (red diamond) relative to it. TASK-093b makes the viewer follow turns.
- [x] Counters: NATO APP-6 style – frame, branch icon by `formation_class` (mechanised infantry, armour, rocket artillery), echelon mark `II` above, short designation beside (e.g. `1/15`), a small strength bar (current / max). Drawn flat on the map at a fixed pixel size (readable at full zoom-out, not scaled with the map), one per formation at its hex centre, declutter when two sit within a few pixels (stack with a count; the agent documents the rule).
- [x] Click a counter: selection ring and a **formation panel** (HUD v3 style): name, parent, type, strength, the companies list with `ref`, unit type and strength bar. Click empty map or Esc deselects. Enemy formations can be inspected (v0: full information, fog is TASK-100) but the panel marks them hostile.
- [x] Hover: a counter highlights; the hex card of TASK-093a still works.
- [x] Translations for formation names, parents, panel labels (`tr()`); `test_localization.gd` green.
- [x] A scene-level smoke test (like the existing presentation tests) builds the staff map with the shipped operation and asserts one counter node per formation and that selecting one fills the panel.

## Look (Claude Design)

Reference: [docs/design/operational_map/README.md](../design/operational_map/README.md) ("Counters", "Panels"). Everything below is **screen-space** (counters on a `CanvasLayer`, positions projected from the hex centre on the relief) and must work under the 2.5D camera of [TASK-125](TASK-125-staff-map-restyle-2-5d.md); picking a counter is a 2D hit test, the hex under the cursor is picked by ray.

- [x] Own formation = rectangle **40 × 26 px**, enemy = **diamond 38 × 38 px** (shape and colour both encode the side); style A "HUD": side fill (`side.own #5b93d6` / `side.enemy #d76a52`), ink glyph (`#0f1a26` / `#2a110b`), cut corner; APP-6 branch icons stay. Colours from `StaffMapPalette`; own / enemy decided by one view function (`viewer_relation(owner, viewer)`; TASK-114 turns it into the reference's `stance(country, player_side)`), test: swapping the viewer swaps shape and colour.
- [x] Strength = **5 slanted segments** under the frame, HP colours `#b9d38a` (≥ 75 %), `#e2c069` (≥ 50 %), `ui.alert #e07c5e` below **[ASSUMPTION]**. **Conflict:** replaces the "small strength bar" above (same data). Test: segments lit for strength 40 / 30 / 20 / 10 of 40 = 5 / 4 / 3 / 1 **[ASSUMPTION: nearest fifth, halves up, at least one while alive – plain round-up would give 2 for 10 / 40]**.
- [x] States in this task: normal, hover (brighter), selected (2 px corner brackets), low strength (< 50 %), stack (count badge). Later tasks add "has order" (092d), "moved" (092e), "in contact" (dashed `ui.alert` ring, 092e / 094). **NOT adopted:** estimated / detected enemy (dashed frame, "?", "EST.") – needs fog, TASK-100.
- [x] Declutter: the stack rule above stays; the reference's Z0 "brigade counters ×n" (aggregate by `parent` label when zoomed out) is **[ASSUMPTION]** optional here – flagged: it conflicts with "one counter per formation"; the agent documents the choice. Battalion counters from Z1 (≥ 1.6 px/km).
- [x] Formation panel on the **right edge**: strength, location (nearest place name or coordinate), companies list. Posture / order rows come with 092d. **NOT adopted:** supply days, cohesion, mortar "Firing" status (no rules). Hex card (TASK-093a) stays `pointer-events: none`. Keys: **Tab** cycles own formations **[ASSUMPTION]**; "F centre on formation" **not adopted** (F is the front-line toggle in the reference too – clash).

## Playtest (for the human)

1. Start → **Operation**. Counters appear: eight blue ones in Poland (two near Bartoszyce / Braniewo, three in the Gap, three near Białystok) and ten red ones in Kaliningrad and Belarus.
2. Zoom in on Suwałki: a mechanised battalion shows a frame, the mechanised-infantry icon, `II`, a designation and five lit strength segments.
3. Click a Polish battalion: the panel lists its four companies (three infantry, one Abrams) with strengths and total 40; click a Russian one: marked hostile.
4. Start with `--side=russia`: colours swap (your formations are blue-framed, NATO's red).
5. Check that every counter stands on land and that the start positions make sense on the map (details in the implementation notes).

## Player manual

Section "Formations" in the "Operational map" chapter (TASK-093a): what a counter shows, the six formation types with their companies and strength, reading the panel.

## Out of scope

- Operational turns and End turn (TASK-093b), route planning (TASK-092c), orders and postures (TASK-092d), executing orders (TASK-092e), contact and battles (TASK-094), losses (TASK-095), operational AI (TASK-102), end of the operation (TASK-107).
- Countries, stances, escalation and allied formations (TASK-113 … TASK-118): this task places the formations by coordinates only.
- `CampaignRecord` and the `Session` autoload (TASK-094).

## Implementation notes


### Logic + data (gameplay-engineer, 2026-11-07)

- Core: `src/core/operational/` – `OperationalState`, `OperationalSimulation`, `OperationalCommand`, `OperationalCommandCodec` (no command types yet, every dict gives null), `Formation` (+ `Formation.Company`, also `max_strength` per company and `Formation.max_strength()` for the strength bar), `Operation`. Data classes in `src/core/data/`: `FormationDefinition` (`strength()` = full strength), `SideDefinition` (`find`), `OperationDefinition` (`find`), `FormationPlacement`. `OperationalState.operation_name` keeps the operation's display name for the view (static, not in the snapshot). `Formation.snapshot()` builds each snapshot entry (the one place TASK-092d extends).
- Tests: `tests/unit/test_operation.gd` (building, every rejection, snapshot, determinism, simulation, codec, grep for tactical classes and side / faction literals), `tests/unit/test_operational_data.gd` (types, sides, the shipped order of battle, ≥ 3 hexes between the sides, every placement on a passable tile of the map).
- Start positions on `suwalki_theatre` (axial `(q, r)`), picked by projecting the towns' WGS84 coordinates to the map's UTM 34N grid and checking the tile is land. Braniewo lies west of the map (bbox from 20.24° E), so the second Kaliningrad-facing battalion stands at Lidzbark Warmiński. Brigade / corps labels are **[ASSUMPTION]** flavour, not a researched order of battle.

  | Id | Name | Parent | Type | Place | Coord |
  |---|---|---|---|---|---|
  | `pl_mech_1` | 1st Mechanised Battalion | 20th Mechanised Brigade | pl_mech_battalion | Bartoszyce | (-9, 31) |
  | `pl_tank_1` | 1st Tank Battalion | 20th Mechanised Brigade | pl_tank_battalion | Lidzbark Warmiński | (-13, 34) |
  | `pl_mech_2` | 2nd Mechanised Battalion | 15th Mechanised Brigade | pl_mech_battalion | Suwałki | (17, 34) |
  | `pl_mech_3` | 3rd Mechanised Battalion | 15th Mechanised Brigade | pl_mech_battalion | Augustów | (15, 41) |
  | `pl_mlrs_1` | 1st Rocket Artillery Squadron | 16th Artillery Regiment | pl_mlrs_squadron | Ełk | (7, 41) |
  | `pl_mech_4` | 4th Mechanised Battalion | 18th Mechanised Brigade | pl_mech_battalion | Białystok | (9, 59) |
  | `pl_tank_2` | 2nd Tank Battalion | 18th Mechanised Brigade | pl_tank_battalion | Sokółka | (17, 51) |
  | `pl_mlrs_2` | 2nd Rocket Artillery Squadron | 18th Artillery Regiment | pl_mlrs_squadron | Mońki | (7, 52) |
  | `ru_mr_1` | 1st Motor Rifle Battalion | 11th Army Corps | ru_motor_rifle_battalion | Chernyakhovsk | (9, 21) |
  | `ru_mr_2` | 2nd Motor Rifle Battalion | 11th Army Corps | ru_motor_rifle_battalion | Gusev | (14, 22) |
  | `ru_mr_3` | 3rd Motor Rifle Battalion | 11th Army Corps | ru_motor_rifle_battalion | Sovetsk | (16, 9) |
  | `ru_tank_1` | 1st Tank Battalion | 11th Army Corps | ru_tank_battalion | Nesterov | (19, 21) |
  | `ru_mlrs_1` | 1st MLRS Battalion | 11th Army Corps | ru_mlrs_battalion | Gvardeysk | (0, 20) |
  | `ru_mr_4` | 4th Motor Rifle Battalion | 1st Guards Tank Army | ru_motor_rifle_battalion | Grodno | (24, 45) |
  | `ru_mr_5` | 5th Motor Rifle Battalion | 1st Guards Tank Army | ru_motor_rifle_battalion | Skidel | (29, 46) |
  | `ru_mr_6` | 6th Motor Rifle Battalion | 1st Guards Tank Army | ru_motor_rifle_battalion | Shchuchyn | (36, 46) |
  | `ru_tank_2` | 2nd Tank Battalion | 1st Guards Tank Army | ru_tank_battalion | Vyalikaya Byerastavitsa | (21, 57) |
  | `ru_mlrs_2` | 2nd MLRS Battalion | 1st Guards Tank Army | ru_mlrs_battalion | Masty | (31, 51) |

  Closest Polish – Russian pair: Sokółka – Grodno, 7 hexes. Totals 276 (NATO) / 332 (Russia).
- Limitation: there is no place gazetteer in the data, so "location" in the panel can only show the coordinate (or the start place, which is not stored) until place names exist.


### View (presentation-engineer, 2026-11-07)

- `StaffMap` builds the state with `Operation.from_definition(OperationDefinition.find(operation_id), seed, grid)` on the grid it already loaded (the map is not converted twice) and wraps it in an `OperationalSimulation`; it only reads the state and refreshes counters / panel on `event_emitted`. `build_now()` is the synchronous build (`auto_build = false` + `build_now()` lets a headless test build the scene outside the tree; the viewport is then 1280 × 720). Seed: `StaffMap.DEFAULT_SEED` (1) until the session carries one (TASK-094).
- Viewer: `StaffMap.viewer_player` (-1 = from `--side=nato|russia`, default NATO, `StaffMapFormations.viewer_from_args`); `set_viewer(player)` swaps everything live. Friend / foe is decided only by `StaffMapFormations.viewer_relation(owner, viewer)`.
- `StaffMapCounters` (a `Control` on its own `CanvasLayer` under the HUD) holds one `StaffMapCounter` per formation, named by formation id; positions are the screen projections of the hex centres on the relief (cached 3D anchors, re-projected only from `_apply_camera`, i.e. when the camera moved – an idle frame costs nothing; the per-frame hover hit test is 18 point tests). Picking is a 2D hit test (rectangle / diamond / gauge), topmost first; own counters draw above enemy ones, the selected one on top.
- Look: style A "HUD" – own rectangle 40 × 26 with a cut top-right corner, enemy diamond 38 × 38, side fill and ink glyph from `StaffMapPalette`; APP-6 glyphs: mechanised = cross + oval, armoured = oval, artillery (rocket) = dot between two rockets; `II` above, designation (`1/15`, from the leading numbers of name and parent) to the right; 5 slanted segments under the frame (`lit_segments` rounds to the nearest fifth, halves up, at least one while strength > 0 – the task's "round up" would give 2 for 10 / 40, so the stated 5 / 4 / 3 / 1 is what is tested). States: hover (fill +20 % white, light outline), selected (2 px amber corner brackets), low strength < 50 % (fill 30 % darker, `ui.alert` outline, red gauge), stack (amber count badge).
- **Declutter rule** (`StaffMapFormations.stack_leaders`): counters of the same owner whose screen centres are closer than 24 px stack – greedy in placement order, a counter joins the first earlier stack leader of its owner in range. A stack shows the selected member if any, else the leader, with a count badge; the other members are hidden and not pickable (Tab still reaches them and brings the selected one to the top). Own and enemy never stack. The reference's Z0 "brigade counters × n" aggregation is **not adopted**: one counter per formation on every zoom level (also before Z1), the stack handles zoomed-out clutter – at the full-theatre zoom on 1280 × 720 no stack forms with the shipped order of battle.
- `StaffMapFormationPanel` (right edge, HUD v3 `FramedPanel`): tab FORMATION + OWN / HOSTILE in the side colour, name, parent, type, side (hostile: "RUSSIA · HOSTILE" in red, red frame line), strength with the gauge, location (hex coordinate, no gazetteer yet), companies (unit type, strength, ref, gauge). The panel stops the mouse; the hex card stays mouse-transparent.
- Input: left click without a drag (< 5 px travel) selects / deselects; Esc deselects first, then goes back to the menu; Tab (read in `_input` so GUI focus cannot eat it) cycles own formations and centres the camera only when the counter is off screen. The hint line lists the new keys.
- Translations: formation names, parents, type names, NATO and the panel labels in `assets/i18n/strings.csv` (en / pl); unit names that are proper names (Abrams, Homar-K, T-72B3, Uragan) are not translated.
- Tools: `SCREENSHOT_STAFF_MAP` tokens `side:<player>`, `select:<formation id>`, `hovercounter:<formation id>`.
- Tests: `tests/unit/test_staff_map_formations.gd` – view rules (relation, segments 40/30/20/10 of 40 = 5/4/3/1, colours, designation, `--side`, stack rule, Tab cycle), viewer swap on a counter (shape hit area and colours swap), shipped names are CSV keys, and a scene smoke test (one counter node per formation, select fills the panel, click picks / empty click deselects, viewer swap on the scene).

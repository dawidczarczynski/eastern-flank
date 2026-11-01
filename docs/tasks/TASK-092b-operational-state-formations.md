# TASK-092b: Operational state – formations as data, the Suwałki Gap operation, operational turns

- **Status**: blocked
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data
- **Depends on**: TASK-092a, TASK-086
- **Model**: opus (new simulation facade, state snapshot and RNG stream every later operational task builds on)
- **Topic**: Two-layer game

## Goal

The operation exists as a deterministic state: named battalions made of real companies stand on the real Suwałki theatre map (`suwalki_theatre`, 68 × 64 hexes – TASK-092a) and the two sides take operational turns (GDD "Operational layer" → "Formations", "Operational turns"). Formations never move step by step: they get multi-turn orders – route planning is TASK-092c, orders and postures TASK-092d, order execution at the end of a turn TASK-092e (human decision 2026-11-01).

## Acceptance criteria (testable)

Shape (ADR 0015 §1–2; all pure logic, no `Node`):

- [ ] `src/core/operational/`: `OperationalState`, `OperationalSimulation` (`execute(command) -> bool`: validate → reject with `command_rejected(command, reason)` or append to `history`, apply and emit each event through `event_emitted`; mirrors `GameSimulation`), `OperationalCommand` (base: `validate(state: OperationalState) -> String`, `apply(state) -> Array[Dictionary]`, `to_dict()`), `OperationalCommandCodec.from_dict(d) -> OperationalCommand` (null on anything unknown or malformed, same number rules as `CommandCodec`), `Formation` (runtime), `Operation` (builds a state from data).
- [ ] The operational layer never references `GameState`, `GameSimulation` or tactical `Command`s (a test greps `src/core/operational/` for those class names).

Data (`src/core/data/`, `data/`):

- [ ] `FormationDefinition` (Resource, `data/formations/<id>.tres`): `id`, `display_name` (English, a translation key), `faction`, `echelon` (`&"battalion"`), `formation_class` (`&"mechanised"`, `&"armoured"`, `&"artillery"`), `move_points`, `companies: Array[UnitDefinition]` (ordered).
- [ ] `SideDefinition` (Resource, `data/sides/<id>.tres`; GDD "Operational layer" → "Sides", human decision 2026-11-01: both sides playable, sides are blocs): `id`, `display_name` (English, translation key), `lead_faction` (StringName – colours, HUD), `factions: Array[StringName]` (factions whose formation types the side may field; contains `lead_faction`). Two files: `nato` ("NATO", lead `poland`, factions [poland]) and `russia` ("Russia", lead `russia`, factions [russia]). `SideDefinition.find(id)` (null when unknown).
- [ ] `OperationDefinition` (Resource, `data/operations/<id>.tres`): `id`, `display_name`, `map_id`, `sides: Array[SideDefinition]` (index = player; replaces a plain faction list), `first_player`, `formations: Array[FormationPlacement]`; `FormationPlacement` (sub-resource): `id` (unique, e.g. `&"pl_mech_1"`), `display_name` (e.g. "1st Mechanised Battalion"), `parent` (brigade label, e.g. "15th Mechanised Brigade"), `player`, `definition`, `coord` (axial on the map).
- [ ] The six types of GDD "Formations" as `.tres` with these companies and `move_points` 8: `pl_mech_battalion` (3 × `pl_mech_infantry`, 1 × `m1a2_sepv3` → strength 40), `pl_tank_battalion` (3 × `m1a2_sepv3`, 1 × `pl_mech_infantry` → 40), `pl_mlrs_squadron` (3 × `homar_k` → 18), `ru_motor_rifle_battalion` (3 × `ru_motor_rifle`, 1 × `t72b3` → 38), `ru_tank_battalion` (3 × `t72b3`, 1 × `ru_motor_rifle` → 34), `ru_mlrs_battalion` (3 × `bm27_uragan` → 18). Test: each type's strength sum and that every company is in its faction's roster.
- [ ] `data/operations/suwalki_gap.tres` (reworked 2026-11-01 for the theatre map, GDD "Formations" – order of battle **[ASSUMPTION]**): map `suwalki_theatre`, sides `[nato, russia]`, `first_player` 1 (Russia – whichever side the human plays). **NATO side (Poland)** 4 × `pl_mech_battalion`, 2 × `pl_tank_battalion`, 2 × `pl_mlrs_squadron` (8 formations, total 276): two facing the Kaliningrad oblast (Bartoszyce / Braniewo–Lidzbark area), three in the Gap (Suwałki / Augustów / Ełk), three facing Belarus (Białystok / Sokółka). **Russia side** 10 formations (total 332): the Kaliningrad group – 3 × `ru_motor_rifle_battalion`, 1 × `ru_tank_battalion`, 1 × `ru_mlrs_battalion` (Gusev / Chernyakhovsk / Sovetsk area) – and the Belarus group – the same five types around Grodno. Every formation on a land hex of its group's country (checked on a real map by the agent; the rule check comes with countries in TASK-114), every Polish formation ≥ 3 hexes from every Russian one (test), strength sums 276 / 332 (test); coordinates and labels (`parent`, e.g. "15th Mechanised Brigade", "11th Army Corps") picked by the agent on the real map and listed in the implementation notes with the place names. Allied formations that join later are TASK-118, off-map support TASK-121 – not placed here.

Building (`Operation`):

- [ ] `Operation.NAMES` = `["suwalki_gap"]`; `Operation.build(id, seed) -> OperationalState` loads the definition and the map (`ImportedMap.find(map_id).to_grid()`); `Operation.from_definition(definition, seed, grid = null)` builds from given data (tests use a small hand-made `HexGrid`).
- [ ] One `Formation` per placement, in placement order (this order is also the order in which TASK-092e executes orders): `id`, `owner_id` (= `player`), `definition`, `coord`, `companies: Array[Formation.Company]` (`unit_type`, `strength` = the unit's `max_hp`, `ref` = `"<formation id>/<n>"`, n from 1 – e.g. `pl_mech_1/4` is the Abrams company), `strength()` = sum.
- [ ] Rejected with `push_error` and null (one test each): unknown operation id, unknown map, a placement off the map or on an impassable tile, two placements on one tile, a duplicate formation id, a placement whose type's faction is not one of its player's side's `factions`, a company outside the faction roster, `first_player` not 0 or 1, `sides` not exactly 2, a side whose `factions` lacks its `lead_faction`, the same faction in both sides.
- [ ] **The human's side is not part of the operation**: `Operation.build` / `from_definition` take no human-side parameter and the state stores none (the choice lives in the session and `CampaignRecord` – TASK-094 / TASK-107), so the state, its snapshot and a replay are identical whichever side the human plays. Nothing in `src/core/operational/` compares a side or faction id with a literal (`nato`, `russia`, `poland`) – a test greps for those literals.
- [ ] `OperationalState`: `operation_id`, `grid`, `player_sides` (side ids by player), `player_factions` (each side's `lead_faction`), `first_player`, `current_player` (= `first_player`), `turn` (1), `formations`, `rng` (seeded with the campaign seed; nothing draws from it yet), `pending_battles: Array[BattleSetup]` (empty; filled by TASK-094), `get_formation(id)`, `formation_at(coord)`, `snapshot()` → `{turn, current_player, rng_state (String), formations: [{id, player, coord: [q, r], companies: [[unit_type, strength], ...]}] sorted by id}`. Static data (definitions, map) is not in the snapshot. There is no `moves_left`: move points are spent automatically when orders execute (TASK-092e), so nothing carries between turns. TASK-092d adds `posture` and `order` to `Formation` and to each snapshot entry – keep the snapshot built in one place so it can grow.

Operational turns (`EndOperationalTurnCommand`, `{"type": "end_operational_turn"}`):

- [ ] Rejected with `battle_pending` while `pending_battles` is not empty (test: append a `BattleSetup` by hand).
- [ ] Apply: event `operational_turn_ended` (`player`), the other player becomes current, `turn` + 1 when the new current player is `first_player`, then event `operational_turn_started` (`player`, `turn`). Keep the apply as small steps (e.g. a private `_switch_side`) – TASK-092e inserts order execution before `operational_turn_ended`.
- [ ] Example (test, `first_player` 1): start turn 1 / player 1 → end → turn 1 / player 0 → end → turn 2 / player 1; events in that order with these fields.
- [ ] Codec round trip: `OperationalCommandCodec.from_dict(cmd.to_dict())` gives an equal command; `{"type": "end_turn"}` (the tactical type), a missing or unknown `type` → null.
- [ ] Determinism: `Operation.build("suwalki_gap", 7).snapshot()` equals a second build with seed 7; seeds 7 and 8 differ only in `rng_state`.
- [ ] docs/ARCHITECTURE.md: "Two layers" names the new classes and data; a new table "Operational events" lists `operational_turn_ended` and `operational_turn_started`.

## Playtest (for the human)

None – no view yet (TASK-093). Review the order of battle and the start positions listed in the implementation notes.

## Player manual

None – not visible to the player before TASK-093. TASK-093 describes formations (types, companies, strength) and operational turns from GDD "Operational layer". The `move_points` field stays: it is the per-turn budget that postures scale (TASK-092d / 092e).

## Out of scope

- Route planning (TASK-092c), orders and postures (TASK-092d), executing orders (TASK-092e), contact and battles (TASK-094), losses (TASK-095), the view (TASK-093), operational AI (TASK-102), end of the operation (TASK-107).
- Countries, stances, escalation and allied formations (TASK-113 … TASK-118): this task places the formations by coordinates only.
- `CampaignRecord` and the `Session` autoload (TASK-094).
- Translation rows for formation names: added when TASK-093 shows them (unless `test_localization.gd` already requires them for `data/` strings – then add them here).

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

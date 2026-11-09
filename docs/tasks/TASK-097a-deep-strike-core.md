# TASK-097a: Deep strike v1 (1/2, core) – means with range and a per-side stock, installations as targets, resolution (accuracy / interception / rng), ROE and escalation through TASK-115, resupply and repair per round

- **Status**: idea
- **Layers**: core (`src/core/operational/`, `src/core/data/`) + data + presentation (installation markers, hover card, F9 debug strike)
- **Depends on**: TASK-092b, TASK-115, TASK-093c (soft: TASK-100, TASK-098)
- **Sections**: GDD "Deep strikes", "Escalation ladder", "Countries and stances", "Outside support"; ARCHITECTURE "Two layers", "Operational events"
- **Model**: sonnet (the one determinism point is the fixed `rng` draw order below; tests pin it)
- **Topic**: Two-layer game
- **Tags**: mvp

## Decisions (human, 2026-11-09)

Q1 three means only (cruise, ballistic, strike drone); Q2 finite stock **plus a small fixed resupply per round (data)**; Q3 **range per means in hexes, measured from the side's own or aligned countries' hexes**, "out of range" is a rejection and a UI reason; Q4 installations (integrity 0-100) + formations as targets; Q5 formations can be struck; Q6 **slow repair of damaged, not destroyed, installations (data, +5 per round)**; Q7 per-missile rolls, two fixed draws each; Q8 recon only as a hook, minimal built-in air defence (TASK-098 replaces it); Q9 every accepted strike is an escalation incident; Q10 a strike may reach the threshold, the view warns; Q11 free except stock and `strikes_per_turn` (2), separate from the political decision; Q12 strike mode with click targets (TASK-097b); Q13 split into 097a (this) and 097b (view); Q14 placeholder numbers, balanced by TASK-103.

## Goal

The core of the leader's deep strikes: a strike from a side's stock at an enemy installation or formation within range, the ladder deciding what may be hit and what it costs, damage that lasts and heals slowly, and every number as data. The same rules for both sides; the AI (TASK-102) and outside support (TASK-122) use the same entry points; TASK-097b adds the strike mode on the map. Clickable here: installation markers and a debug strike (GDD "Deep strikes").

## Acceptance criteria (testable)

Data (`src/core/data/`, `data/strike/`):

- [ ] `StrikeMeansDefinition` (Resource, `data/strike/<id>.tres`): `id`, `display_name` (English, translation key), `accuracy_pct` 0-100, `interceptability_pct` 0-200, `damage` (installation integrity per hit), `formation_damage` (company strength per hit), `max_salvo`, `range_hexes`. `problem() -> String` ("" when valid; one test per case: empty id, a percentage out of range, `damage` or `formation_damage` ≤ 0, `max_salvo` < 1, `range_hexes` < 1). Shipped **[ASSUMPTION]** (test reads the files), accuracy / interceptability / damage / formation damage / max salvo / range: `cruise` 80 / 100 / 35 / 2 / 4 / 50; `ballistic` 70 / 40 / 45 / 3 / 2 / 80; `strike_drone` 55 / 150 / 15 / 1 / 6 / 20.
- [ ] `InstallationPlacement` (sub-resource): `id`, `display_name`, `class_id` (`airfield`, `depot`, `c2`, `air_defence` – the TASK-115 ids; formations are class `formation`), `owner`, `coord`. `OperationDefinition` gains `installations`, `strike_stock` (per player `{means_id: count}`), `strike_resupply` (per player `{means_id: count per round}`), `strikes_per_turn` (default 2), `air_defence_radius` (default 4 hexes), `air_defence_intercept_pct` (default 40), `repair_per_round` (default 5). `Operation.from_definition` rejects (`push_error`, null – one test each): an unknown class or means id, a duplicate installation id, two installations on one hex, an off-map or water coord, `owner` outside 0 / 1, a negative stock or resupply, `strikes_per_turn` < 1, `repair_per_round` < 0.

State (`OperationalState`):

- [ ] `installations: Array[Installation]` (`id`, `display_name`, `class_id`, `owner`, `coord`, `integrity` 0-100 start 100, `destroyed()` = 0), `strike_stock`, `strikes_left` (`strikes_per_turn` at start and for the next player in `EndOperationalTurnCommand`, like `decisions_left`). Snapshot gains `installations` (sorted by id), `strike_stock`, `strikes_left`; the determinism test of TASK-092b still passes.

Stock (`StrikeRules`, static, `src/core/operational/strike_rules.gd`) – **the interface TASK-122 builds on**:

- [ ] `add_stock(state, player, means_id, count, source: StringName) -> Array[Dictionary]` is the **only** way the stock grows: unknown means or `count` ≤ 0 → `[]`; else event `strike_stock_changed` (`player`, `means`, `count`, `total`, `source`). A strike spends stock through the same event with a **negative** `count` and `source` `&"strike"` (TASK-122's `count` is then signed). `stock(state, player, means_id) -> int`. Example (player 1 `cruise` 8): `add_stock(state, 1, &"cruise", 3, &"china_components")` → total 11.
- [ ] **Resupply and repair at the round boundary** – inside `EndOperationalTurnCommand.apply`, when play returns to `first_player`, after TASK-115's calm decay: for each player (0, then 1) and each means in `strike_resupply` order, `add_stock(…, &"resupply")`; then every installation with 0 < integrity < 100 gains `repair_per_round` (cap 100, setup order) with event `installation_changed` (`cause` `repair`); destroyed ones never recover. Example (resupply player 1 `strike_drone` 2, repair 5): after one full round drones +2, a 60 installation shows 65, a 0 stays 0, a 98 shows 100. No `rng` draws.

Targets, range and ROE (TASK-115 is called, its logic is not repeated):

- [ ] `targets(state, player) -> Array[Dictionary]` `{kind (&"installation" / &"formation"), id, coord, class_id}` of every non-destroyed enemy installation and enemy formation, setup order; formations only if `StrikeRules.is_known(state, player, target)` (hook, always true until TASK-100).
- [ ] `in_range(state, player, means_id, coord) -> bool`: the hex distance from `coord` to the **nearest hex of a country that is own to the player** (aligned or belligerent on its side, `CountryRules`) is ≤ the means' `range_hexes`. Examples on TASK-115's strip grid (player 0's country 5 hexes from the target): `strike_drone` (20) true, a made-up means with range 4 false; a target on own soil is distance 0; a country aligned with the **enemy** is not an origin; a country that becomes aligned with the player counts from then on.
- [ ] `target_problem(state, player, target_id, means_id := &"") -> String`: `""` or, in this order, `unknown_target`, `target_destroyed`, TASK-115's `strike_allowed` code unchanged (`own_soil`, `closed_country`, `roe_class`), then `out_of_range` (only when a means is given). Examples (strip grid, player 0, Russian airfield A1 on (6, 0), player 1's formation R on (0, 0)): level 1 → A1 `closed_country`; level 2 → `""`; level 1 player 1 → R `""`, a Polish airfield `roe_class`, at level 2 `""`; own installations `unknown_target`; an enemy installation in a country aligned with the enemy `closed_country`.
- [ ] `escalation_preview(state, player, target_id) -> int` = `EscalationRules.strike_escalation(state, player, target.coord)`.

Resolution (`StrikeRules.resolve`, pure, only `state.rng`):

- [ ] Per missile **two draws, always, in this order**: `randi_range(1, 100)` for interception, then `randi_range(1, 100)` for the hit (the draw count never depends on outcomes). Intercepted when roll ≤ `p_intercept`; hit when not intercepted and roll ≤ `p_hit`. `p_hit = accuracy_pct + recon_modifier` (hook, 0 until TASK-100), clamped 0-100. `p_intercept = min(90, Σ over the target owner's intact air-defence installations within `air_defence_radius` hexes of the target of `air_defence_intercept_pct × integrity / 100) × interceptability_pct / 100` (integer, rounded down; TASK-098 replaces it with coverage zones). Examples (test means with accuracy 100 / 0, no other randomness): no air defence, accuracy 100 → all hit, 0 → none; one site at integrity 100 within 4 hexes: `cruise` 40, `ballistic` 16, `strike_drone` 60; sites at 100 and 50 → 60 for cruise; a destroyed or out-of-radius site contributes 0.
- [ ] A hit: an installation loses `damage` (min 0, event `installation_changed` with `cause` `strike`: `id`, `before`, `after`, `destroyed`); a formation loses `formation_damage` strength from its strongest company per hit (ties: lowest company index), and one whose companies are all 0 is removed by TASK-095's destroyed-formation path (event `formation_destroyed`; add the helper if TASK-095 has none).

Command (`StrikeCommand`, `{"type": "strike", "means": "<id>", "target": "<id>", "count": N}`; issuer `state.current_player`):

- [ ] Rejections in this order: `operation_over` (the common gate), `battle_pending`, `unknown_means`, `bad_count` (< 1 or > `max_salvo`), `out_of_stock`, `no_strikes_left`, then `target_problem` (including `out_of_range`). A rejected strike changes nothing and draws nothing.
- [ ] Apply in this order: spend the stock (`strike_stock_changed`, source `strike`); `strikes_left` − 1; `strike_launched` (`player`, `means`, `count`, `target`, `coord`, `class_id`); the rolls and damage (`strike_resolved`: `intercepted`, `hits`, `misses`, `p_intercept`, `p_hit`, `damage_dealt`, `target_destroyed`; then `installation_changed` / `formation_destroyed`); then `EscalationRules.on_strike(state, player, target.coord)` with its events (sanctuary breach, +1 for an URBAN hex) **even if every missile was intercepted or missed**. A strike whose incident reaches the top is allowed and ends the operation (`operation_ended`, the striker loses).
- [ ] Example (strip grid, player 0, level 2, A1 integrity 100, `cruise` 4, test means accuracy 100 / damage 35 / range 50, no air defence): `StrikeCommand(cruise, A1, 2)` → stock 2, integrity 30, events `strike_stock_changed`, `strike_launched`, `strike_resolved` (hits 2), `installation_changed`, then TASK-115's `sanctuary_breached` and `escalation_changed` (2 → 3, `sanctuary_breach`, caused [1, 0]); a second strike on A1 the same turn → integrity 0 (destroyed), no new escalation; a third → `no_strikes_left`; next turn a strike on the destroyed A1 → `target_destroyed`. The same on an URBAN hex adds `urban_strike` +1 per strike. At level 3 a strike whose incident reaches level 4 → `operation_ended`, winner 1.
- [ ] Determinism: same seed + same commands → same snapshot and events; `rng_state` advances by exactly 2 × `count` per accepted strike and 0 per rejected one; a strike from granted stock (`add_stock` source `china_components`) gives the same result as one from starting stock. Mirrored: every example with the sides swapped gives the mirrored result (no code reads a side id).
- [ ] `OperationalCommandCodec`: `strike` round trip; missing or wrong-typed fields → null; unknown strings decode (rejected `unknown_means` / `unknown_target`). Operational replay (TASK-117's scripted `suwalki_gap` sequence) extended with one strike by each side and a full round (resupply, repair) → decode + replay identical snapshot and events.
- [ ] `StrikeRules.capability(state, player, class_id) -> int` (0-100): the mean integrity of the side's installations of that class, **100 when it has none** – the number TASK-099 reads (airfield → air support, depot → ammunition, c2 → command points). No battle rule changes in this task.

Shipped data (`suwalki_gap.tres`, **[ASSUMPTION]**; the agent picks hexes on the real map and lists them with place names in the notes; the test checks counts, owners, passable coords, countries):

- [ ] Starting stock: NATO `cruise` 8, `ballistic` 4, `strike_drone` 6; Russia `cruise` 8, `ballistic` 6, `strike_drone` 16. Resupply per round: NATO `cruise` 1, `strike_drone` 1; Russia `cruise` 1, `strike_drone` 2. `strikes_per_turn` 2, `air_defence_radius` 4, `air_defence_intercept_pct` 40, `repair_per_round` 5.
- [ ] 7 installations per side. NATO: airfields near Olsztyn and Białystok, depots at Ełk and Kaunas (Lithuania, aligned), c2 at Białystok, `air_defence` at Białystok and Suwałki. Russia: airfields at Chernyakhovsk and Lida (Belarus), depots at Kaliningrad and Grodno (Belarus), c2 at Kaliningrad, `air_defence` at Kaliningrad and Grodno. Effect: at level 1 NATO reaches only Russian formations in Poland; Kaliningrad targets open at *Open war* (breach +1, urban +1), Belarus targets at *Regional war*. A test checks that every Russian-side target is `closed_country` at level 1 for NATO and `""` / `roe_class` as listed in the ladder at level 2.
- [ ] Docs: ARCHITECTURE "Two layers" (means, range, installations, stock, resupply / repair at the round boundary, `StrikeRules`, `StrikeCommand` with rejection codes, draw order); "Operational events": `strike_launched`, `strike_resolved`, `installation_changed` (causes `strike`, `repair`), `strike_stock_changed` (sources `strike`, `resupply`, `debug`, package ids), `formation_destroyed` (if new).

View (clickable, small – the strike mode is TASK-097b):

- [ ] **Installation markers** on the staff map, one per non-destroyed installation of both sides (no fog yet): glyph by class (airfield, depot, c2, air defence), side colour like the counters, thin **integrity bar**; destroyed ones as a grey crossed glyph; markers update on `installation_changed`. Hover card (existing `StaffMapCard` style): name, class, country, integrity %, what it gives ("Airfield – fire support in nearby battles").
- [ ] Debug block "Strikes" in the F9 politics panel (only with `--debug`, same commands / functions as real play): player, means, salvo, target dropdown (all `targets`), **Strike** (executes `StrikeCommand`; a rejection is shown as a toast with its code) and **+stock** (`add_stock`, source `debug`); the result of a strike shows as a toast from `strike_resolved`. A scene-level smoke test: the debug strike on an airfield lowers its bar and the stock line.

## Look (Claude Design)

No mockup for strikes in `docs/design/operational_map`. Reuse the counter frame, side colours, `StaffMapCard` and toast components (grep CODEMAP `StaffMapCounter`, `StaffMapCard`); state the deviation in the notes.

## Playtest (for the human)

1. **Operation** (`--debug`): installation glyphs with integrity bars appear for both sides; hover one: card with name, class, country, integrity.
2. F9 → Strikes: pick NATO, `cruise` ×2, a Russian airfield: rejected `closed_country`; Raise to *Open war*, again: toast "2 hits / 1 intercepted …", the bar drops, the level goes up (sanctuary breach), stock 8 → 6.
3. Target far from own soil with `strike_drone`: rejected `out_of_range`; with `cruise`: accepted.
4. End a full round: stock +resupply, the damaged installation's bar +5; a destroyed one stays grey.
5. A third strike in one turn: rejected `no_strikes_left`; at level 3 a strike on a town hex ends the operation (end notice).
6. Review shipped numbers (means, stocks, installations).

## Player manual

New chapter **Deep strikes** (part 1): the three means with accuracy, damage, range and stock for each side; strikes per turn; resupply each round; target classes and the escalation level that allows each; closed soil and range from own / allied soil; interception by air defence; the extra escalation for a sanctuary breach and an urban target (also when the missiles are intercepted); damage is lasting but heals 5 per round unless destroyed; what installation markers show. Controls of the strike mode come with TASK-097b.

## Out of scope

Aircraft sorties and other means; reconnaissance and known / stale targets (TASK-100, hooks only); coverage zones, SEAD (TASK-098); the strike mode, forecast and strike report (TASK-097b / TASK-101); outside-support deliveries (TASK-122); battle effects of damaged installations (TASK-099 reads `capability`); AI strikes (TASK-102); technology (TASK-104); moving or building installations; stock cap.

## Implementation notes

_Filled in by the agent when done: what was done, decisions, known limitations._

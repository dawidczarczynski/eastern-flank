class_name StaffMapObjectivesModel
extends RefCounted
## Texts of the objectives window of the staff map: what the viewer's side is scored on, who holds
## each objective now and the round counter. Pure functions of the state (OperationVictory is the
## one scoring rule); the words are translated here.

const MINE := &"mine"
const THEIRS := &"theirs"
const NONE := &"none"

const MAIN := &"main"
const SIDE := &"side"
## The two main objectives (`kind` of a MAIN row): NATO's Suwałki - Kaunas link, Russia's
## Kaliningrad - Belarus link (the corridor).
const GAP := &"gap"
const CORRIDOR := &"corridor"
## The side whose main objective each link is (GDD "Sides": NATO 0 keeps Suwałki connected with
## Kaunas, Russia 1 connects Kaliningrad with Belarus).
const OWNER := {GAP: 0, CORRIDOR: 1}


## Rows for `viewer`: only what the viewer's own side plays for (TASK-177: the enemy's objectives
## are never shown) - the viewer's main objective (tier `main`), then the side objectives of the
## viewer's side and the neutral ones (holder rule `any`, tier `side`). Each is {label, tier, hex
## (a main row: its first end), hexes (what a click frames: the hex, a main row: both ends),
## selected (row index == `selected`), status (MINE / THEIRS / NONE), holder (translated), chip
## (HELD BY US / CONNECTED / CUT ...), points, yours (always true), sub (the "scores for" line)};
## the main row adds {kind (GAP / CORRIDOR), ends_text ("SUWAŁKI ↔ KAUNAS"), connected (bool),
## alert (the link is in the state that hurts NATO: cut, or the corridor connected), closed_rounds,
## need (0: no counter), progress ("k / 5", "" without a counter), rule, tag (the map layer's
## tag)}. No route is part of a row: any route counts (connection objectives).
static func rows(state: OperationalState, viewer: int, selected := -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var def := state.definition
	if def == null:
		return result
	var own := CORRIDOR if viewer == 1 else GAP
	if _exists(def, own):
		result.append(_main_row(state, own))
	for objective in def.objectives:
		var any := objective.holder_rule == OperationObjective.ANY
		if not any and objective.side != viewer:
			continue
		var hex := objective.hex_in(state)
		var holder := HexControl.holder(state, hex)
		(
			result
			. append(
				{
					"label": _t(objective.display_name),
					"tier": SIDE,
					"hex": hex,
					"hexes": [hex] as Array[Vector2i],
					"status": _status(holder, viewer),
					"holder": _holder_text(state, holder),
					"chip": _chip_text(holder, viewer),
					"points": objective.points,
					"yours": true,
					"sub":
					(
						_t("Scores for whoever holds it")
						if any
						else _t("Scores for %s") % StaffMapTurnBar.side_name(state, viewer)
					),
				}
			)
		)
	for i in result.size():
		result[i]["selected"] = i == selected
	return result


## Header of the main section.
static func main_header() -> String:
	return _t("Main objective")


## "Side objectives - scored at the end, round 30".
static func side_header(state: OperationalState) -> String:
	var limit := 0 if state.definition == null else state.definition.round_limit
	return _t("Side objectives - scored at the end, round %d") % limit


## The two hexes that stand for the ends of a main objective's link on the map: NATO's
## `nato_link_from` / `nato_link_to`; for the corridor a hex of each country - the biggest place of
## the map's place data inside it (Kaliningrad, Grodno), else the country's first land hex. [] when
## the objective does not exist.
static func link_ends(state: OperationalState, kind: StringName) -> Array[Vector2i]:
	var ends: Array[Vector2i] = []
	var def := state.definition
	if def == null or not _exists(def, kind):
		return ends
	if kind == GAP:
		ends.append(def.nato_link_from)
		ends.append(def.nato_link_to)
		return ends
	var map := ImportedMap.find(state.map_id)
	for country in [def.corridor_from_country, def.corridor_to_country]:
		var hex := _main_place_hex(state, map, country)
		if hex == Vector2i.MAX:
			var hexes := OperationVictory.country_hexes(state, country)
			if hexes.is_empty():
				return [] as Array[Vector2i]
			hex = hexes[0]
		ends.append(hex)
	return ends


## The hex of the highest-ranked place (then the first listed: the biggest) on a land hex of
## `country`; Vector2i.MAX when the map has none.
static func _main_place_hex(
	state: OperationalState, map: ImportedMap, country: StringName
) -> Vector2i:
	if map == null:
		return Vector2i.MAX
	var best := Vector2i.MAX
	var best_rank := 1 << 30
	for i in map.place_count():
		var place := map.place_at(i)
		var rank := int(place["rank"])
		if rank >= best_rank:
			continue
		var position: Vector2 = place["position"]
		var hex := Hex.from_world(Vector3(position.x, 0.0, position.y), 1.0)
		if state.country_at(hex) != country or not state.grid.has_tile(hex):
			continue
		if state.grid.move_cost(hex) == Terrain.IMPASSABLE:
			continue
		best = hex
		best_rank = rank
	return best


static func _exists(def: OperationDefinition, kind: StringName) -> bool:
	return OperationVictory.has_gap_link(def) if kind == GAP else OperationVictory.has_corridor(def)


static func _main_row(state: OperationalState, kind: StringName) -> Dictionary:
	var def := state.definition
	var gap := kind == GAP
	var connected: bool
	var status: StringName
	var chip: String
	if gap:
		connected = OperationVictory.gap_status(state, def) == OperationVictory.OPEN
		chip = _t("CONNECTED") if connected else _t("CUT")
		status = MINE if connected else THEIRS
	else:
		connected = OperationVictory.corridor_status(state, def) == OperationVictory.CLOSED
		chip = _t("CONNECTED") if connected else _t("NOT CONNECTED")
		status = MINE if connected else NONE
	var need := 0 if gap else def.closed_rounds_to_win
	var points := def.gap_open_points if gap else def.corridor_points
	var ends := link_ends(state, kind)
	var ends_text := _t("SUWAŁKI ↔ KAUNAS") if gap else _t("KALININGRAD ↔ BELARUS")
	var progress := "" if gap else "%d / %d" % [state.corridor_closed_rounds, need]
	var tag := (
		"%s ▪ %s +%d" % [ends_text, chip, points]
		if gap
		else "%s ▪ %d/%d" % [ends_text, state.corridor_closed_rounds, need]
	)
	return {
		"label":
		_t("Keep Suwałki connected with Kaunas") if gap else _t("Connect Kaliningrad with Belarus"),
		"tier": MAIN,
		"kind": kind,
		"hex": ends[0] if not ends.is_empty() else Vector2i.MAX,
		"hexes": ends,
		"status": status,
		"holder": chip,
		"chip": chip,
		"points": points,
		"yours": true,
		"sub": "",
		"ends_text": ends_text,
		"connected": connected,
		"alert": connected != gap,
		"closed_rounds": 0 if gap else state.corridor_closed_rounds,
		"need": need,
		"progress": progress,
		"rule":
		(
			(
				_t("Any land route without enemy hexes counts. +%d at the end while connected.")
				% points
			)
			if gap
			else (
				_t(
					(
						"Any route of land held by us counts. Connected %d rounds in a row: "
						+ "we win at once; otherwise +%d at the end while connected."
					)
				)
				% [need, points]
			)
		),
		"tag": tag,
	}


static func _chip_text(holder: int, viewer: int) -> String:
	if holder < 0:
		return _t("NOBODY")
	return _t("HELD BY US") if holder == viewer else _t("HELD BY ENEMY")


## "ROUND 4 / 30".
static func round_line(state: OperationalState) -> String:
	var limit := 0 if state.definition == null else state.definition.round_limit
	return _t("ROUND %d / %d") % [maxi(state.turn, 1), limit]


## Whether `viewer` follows the objective of an `objective_changed` event (TASK-177): each side sees
## only its own objectives - NATO the Suwałki - Kaunas link (kind `gap`), Russia the corridor (kinds
## `corridor` / `corridor_counter`), a side objective when it is the viewer's or neutral.
static func concerns(state: OperationalState, viewer: int, event: Dictionary) -> bool:
	match event.get("kind"):
		&"gap":
			return viewer == OWNER[GAP]
		&"corridor", &"corridor_counter":
			return viewer == OWNER[CORRIDOR]
		&"holder":
			var objective := _objective(state, event.get("objective_id"))
			return (
				objective != null
				and (objective.holder_rule == OperationObjective.ANY or objective.side == viewer)
			)
	return false


## Toast / journal text of an `objective_changed` event as `viewer` reads it; "" when the event is
## not understood or concerns an objective of the other side only (`concerns`).
static func event_text(state: OperationalState, viewer: int, event: Dictionary) -> String:
	var def := state.definition
	if def == null or not concerns(state, viewer, event):
		return ""
	match event.get("kind"):
		&"holder":
			var objective := _objective(state, event.get("objective_id"))
			var taker := int(event.get("new", -1))
			var who := _t("you") if taker == viewer else StaffMapTurnBar.side_name(state, taker)
			return _t("%s taken by %s") % [_t(objective.display_name), who]
		&"gap":
			if event.get("new") == OperationVictory.CUT:
				return _t("The Suwałki–Kaunas link is cut")
			return _t("The Suwałki–Kaunas link is restored")
		&"corridor":
			if event.get("new") == OperationVictory.CLOSED:
				return _t("The Kaliningrad–Belarus link is established")
			return _t("The Kaliningrad–Belarus link is broken")
		&"corridor_counter":
			var count := int(event.get("new", 0))
			if count == 0:
				return _t("Kaliningrad–Belarus link broken - counter reset")
			return (
				_t("Kaliningrad–Belarus link held %d/%d rounds") % [count, def.closed_rounds_to_win]
			)
	return ""


## Journal line of an `objective_changed` event as `viewer` reads it: like `event_text` but with no
## bloc named (the journal's rule), "us" / "the enemy" instead.
static func journal_text(state: OperationalState, viewer: int, event: Dictionary) -> String:
	if state.definition == null or not concerns(state, viewer, event):
		return ""
	if event.get("kind") == &"holder":
		var objective := _objective(state, event.get("objective_id"))
		var taker := _t("us") if int(event.get("new", -1)) == viewer else _t("the enemy")
		return _t("%s taken by %s") % [_t(objective.display_name), taker]
	return event_text(state, viewer, event)


static func _objective(state: OperationalState, id: Variant) -> OperationObjective:
	if state.definition == null:
		return null
	for objective in state.definition.objectives:
		if objective.id == id:
			return objective
	return null


static func _status(holder: int, viewer: int) -> StringName:
	if holder < 0:
		return NONE
	return MINE if holder == viewer else THEIRS


static func _holder_text(state: OperationalState, holder: int) -> String:
	return _t("NOBODY") if holder < 0 else StaffMapTurnBar.side_name(state, holder).to_upper()


static func _t(key: String) -> String:
	return TranslationServer.translate(key)

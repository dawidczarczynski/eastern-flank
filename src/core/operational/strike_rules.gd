class_name StrikeRules
extends RefCounted
## Pure deep-strike rules of the operational layer (TASK-097a, GDD "Deep strikes"): the stock (the
## only way it changes is `add_stock`), targets, range, rules of engagement through
## EscalationRules, the resolution of a salvo and the resupply / repair at the round boundary.
## The only randomness is `state.rng`: two draws per missile, always (interception, then hit).

## The strike classes that are not installations.
const FORMATION_CLASS := &"formation"
const MAX_INTERCEPT_PCT := 90

# --- stock ---


## `player`'s stock of a means.
static func stock(state: OperationalState, player: int, means_id: StringName) -> int:
	return int(state.strike_stock[player].get(means_id, 0))


## Adds `count` of a means to the stock (the only way it grows) and returns `strike_stock_changed`.
## [] for an unknown means, a count <= 0 or a weapon of the other side (TASK-141a, with a
## warning: no grant gives a side the other side's weapon). `source`: resupply, debug, a package
## id ...
static func add_stock(
	state: OperationalState, player: int, means_id: StringName, count: int, source: StringName
) -> Array[Dictionary]:
	if count <= 0 or not state.strike_means.has(means_id) or (player != 0 and player != 1):
		return []
	var means: StrikeMeansDefinition = state.strike_means[means_id]
	if not means.usable_by(player):
		push_warning("strike means '%s' cannot be given to player %d" % [means_id, player])
		return []
	return [_change_stock(state, player, means_id, count, source)]


## Spends `count` of the stock for a strike (StrikeCommand): `strike_stock_changed`, negative count.
static func spend(
	state: OperationalState, player: int, means_id: StringName, count: int
) -> Dictionary:
	return _change_stock(state, player, means_id, -count, &"strike")


static func _change_stock(
	state: OperationalState, player: int, means_id: StringName, delta: int, source: StringName
) -> Dictionary:
	var total := stock(state, player, means_id) + delta
	state.strike_stock[player][means_id] = total
	return {
		"type": &"strike_stock_changed",
		"player": player,
		"means": means_id,
		"count": delta,
		"total": total,
		"source": source,
	}


# --- targets, range, ROE ---


## Hook for reconnaissance (TASK-100): whether `player` knows the target. Always true for now.
static func is_known(_state: OperationalState, _player: int, _target: Dictionary) -> bool:
	return true


## Hook for reconnaissance (TASK-100): percentage points added to the hit chance. 0 for now.
static func recon_modifier(_state: OperationalState, _player: int, _target: Dictionary) -> int:
	return 0


## Every non-destroyed enemy installation, then every known enemy formation, in setup order:
## {kind (&"installation" / &"formation"), id, coord, class_id}.
static func targets(state: OperationalState, player: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for installation in state.installations:
		if installation.owner != player and not installation.destroyed():
			result.append(_installation_target(installation))
	for formation in state.formations:
		if formation.owner_id != player:
			var target := _formation_target(formation)
			if is_known(state, player, target):
				result.append(target)
	return result


## The target (as in `targets`) with this id, enemy of `player`; {} when there is none. A destroyed
## installation is still found (so that it can be reported as destroyed).
static func find_target(state: OperationalState, player: int, target_id: StringName) -> Dictionary:
	for installation in state.installations:
		if installation.id == target_id:
			return {} if installation.owner == player else _installation_target(installation)
	for formation in state.formations:
		if formation.id == target_id and formation.owner_id != player:
			var target := _formation_target(formation)
			return target if is_known(state, player, target) else {}
	return {}


static func _installation_target(installation: Installation) -> Dictionary:
	return {
		"kind": &"installation",
		"id": installation.id,
		"coord": installation.coord,
		"class_id": installation.class_id,
	}


static func _formation_target(formation: Formation) -> Dictionary:
	return {
		"kind": &"formation",
		"id": formation.id,
		"coord": formation.coord,
		"class_id": FORMATION_CLASS,
	}


## Whether the hex lies within the means' range of the nearest hex of a country own to `player`.
static func in_range(
	state: OperationalState, player: int, means_id: StringName, coord: Vector2i
) -> bool:
	var means: StrikeMeansDefinition = state.strike_means.get(means_id)
	if means == null:
		return false
	var own := {}
	for country in state.countries:
		own[country.id] = CountryRules.relation(state, player, country.id) == &"own"
	for hex: Vector2i in state.country_map:
		if own.get(state.country_map[hex], false) and Hex.distance(hex, coord) <= means.range_hexes:
			return true
	return false


## The launch hex of a strike (TASK-147): see StrikeLaunch.launch_origin. Pure, no rng draw.
static func launch_origin(
	state: OperationalState, player: int, means_id: StringName, target_coord: Vector2i
) -> Vector2i:
	return StrikeLaunch.launch_origin(state, player, means_id, target_coord)


## "" when `player` may strike the target (with `means_id` when given), else why not, in this
## order: `unknown_target`, `target_destroyed`, `own_soil` / `closed_country` / `roe_class`
## (EscalationRules.strike_allowed), `out_of_range`.
static func target_problem(
	state: OperationalState, player: int, target_id: StringName, means_id: StringName = &""
) -> String:
	var target := find_target(state, player, target_id)
	if target.is_empty():
		return "unknown_target"
	if target["kind"] == &"installation" and state.get_installation(target_id).destroyed():
		return "target_destroyed"
	var coord: Vector2i = target["coord"]
	var reason := EscalationRules.strike_allowed(state, player, coord, target["class_id"])
	if reason != "":
		return reason
	if means_id != &"" and not in_range(state, player, means_id, coord):
		return "out_of_range"
	return ""


## Escalation steps a strike on the target would cause (0 for an unknown target).
static func escalation_preview(state: OperationalState, player: int, target_id: StringName) -> int:
	var target := find_target(state, player, target_id)
	if target.is_empty():
		return 0
	return EscalationRules.strike_escalation(state, player, target["coord"])


## Mean integrity (0-100) of `player`'s installations of a class; 100 when there are none.
static func capability(state: OperationalState, player: int, class_id: StringName) -> int:
	var total := 0
	var count := 0
	for installation in state.installations:
		if installation.owner == player and installation.class_id == class_id:
			total += installation.integrity
			count += 1
	return 100 if count == 0 else total / count


# --- resolution ---


## The air-defence sites that count against a weapon on `target_coord`, for a strike by
## `striker`: [{id, p}] in setup order. A site counts when it belongs to the enemy of `striker`,
## is not destroyed, not suppressed, covers the hex (the exact radius counts) and its chance
## `p` = type chance for the weapon class x integrity / 100 (rounded down) is above 0.
static func interceptors(
	state: OperationalState, striker: int, weapon_id: StringName, target_coord: Vector2i
) -> Array[Dictionary]:
	var sites: Array[Dictionary] = []
	var means: StrikeMeansDefinition = state.strike_means.get(weapon_id)
	if means == null:
		return sites
	for installation in state.installations:
		if (
			installation.owner == striker
			or installation.class_id != &"air_defence"
			or installation.destroyed()
			or installation.suppressed()
		):
			continue
		var type: AirDefenceDefinition = state.air_defence_types.get(installation.ad_type)
		if type == null or Hex.distance(installation.coord, target_coord) > type.radius_hexes:
			continue
		var p := type.chance_against(means.weapon_class) * installation.integrity / 100
		if p > 0:
			sites.append({"id": installation.id, "p": p})
	return sites


## Interception chance (%, 0 - 90) of `weapon_id` fired by `striker` at `target_coord`: the
## covering sites combine independently (1 - product of (1 - p)), capped at 90 %, then scaled by
## the weapon's interceptability. Integer arithmetic in 1/10 000 units. 0 for an unknown weapon.
static func interception_chance(
	state: OperationalState, striker: int, weapon_id: StringName, target_coord: Vector2i
) -> int:
	var means: StrikeMeansDefinition = state.strike_means.get(weapon_id)
	if means == null:
		return 0
	var survive := 10000
	for site in interceptors(state, striker, weapon_id, target_coord):
		survive = survive * (100 - int(site["p"])) / 100
	var combined := mini((10000 - survive) / 100, MAX_INTERCEPT_PCT)
	return combined * means.interceptability_pct / 100


## The non-destroyed air-defence sites of `player`, setup order, for the view (TASK-098b):
## {id, coord, ad_type, radius_hexes, integrity, suppressed, suppressed_rounds}.
static func coverage(state: OperationalState, player: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for installation in state.installations:
		if (
			installation.owner != player
			or installation.class_id != &"air_defence"
			or installation.destroyed()
		):
			continue
		var type: AirDefenceDefinition = state.air_defence_types.get(installation.ad_type)
		(
			result
			. append(
				{
					"id": installation.id,
					"coord": installation.coord,
					"ad_type": installation.ad_type,
					"radius_hexes": 0 if type == null else type.radius_hexes,
					"integrity": installation.integrity,
					"suppressed": installation.suppressed(),
					"suppressed_rounds": installation.suppressed_rounds,
				}
			)
		)
	return result


## Resolves a salvo of `count` missiles of `means_id` on the target: two `state.rng` draws per
## missile (interception, then hit), damage to the target. Events: `strike_resolved`, then
## `installation_changed` (cause `strike`) or `formation_damaged` / `formation_destroyed`.
static func resolve(
	state: OperationalState, player: int, means_id: StringName, target: Dictionary, count: int
) -> Array[Dictionary]:
	var means: StrikeMeansDefinition = state.strike_means[means_id]
	var target_id: StringName = target["id"]
	var coord: Vector2i = target["coord"]
	var interceptor_ids: Array[StringName] = []
	for site in interceptors(state, player, means_id, coord):
		interceptor_ids.append(site["id"])
	var p_intercept := interception_chance(state, player, means_id, coord)
	var p_hit := hit_chance(state, player, means, target)
	var intercepted := 0
	var hits := 0
	for i in count:
		var intercept_roll := state.rng.randi_range(1, 100)
		var hit_roll := state.rng.randi_range(1, 100)
		if intercept_roll <= p_intercept:
			intercepted += 1
		elif hit_roll <= p_hit:
			hits += 1
	var effects: Array[Dictionary] = []
	var dealt := 0
	var destroyed := false
	if hits > 0:
		if target["kind"] == &"installation":
			var installation := state.get_installation(target_id)
			var before := installation.integrity
			installation.integrity = maxi(0, before - hits * means.damage)
			dealt = before - installation.integrity
			destroyed = installation.destroyed()
			effects.append(_installation_event(installation, before, &"strike"))
			if installation.class_id == &"air_defence" and not destroyed:
				effects.append(_suppress(installation, state.suppression_rounds))
			elif installation.class_id == &"air_defence" and installation.suppressed():
				# A site destroyed while suppressed is no longer counting down.
				effects.append(_suppress(installation, 0))
		else:
			var result := _damage_formation(state, state.get_formation(target_id), hits, means)
			dealt = result["dealt"]
			destroyed = result["destroyed"]
			effects.append(result["event"])
	var events: Array[Dictionary] = [
		{
			"type": &"strike_resolved",
			"player": player,
			"means": means_id,
			"target": target_id,
			"count": count,
			"intercepted": intercepted,
			"hits": hits,
			"misses": count - intercepted - hits,
			"p_intercept": p_intercept,
			"interceptor_ids": interceptor_ids,
			"p_hit": p_hit,
			"damage_dealt": dealt,
			"target_destroyed": destroyed,
		}
	]
	events.append_array(effects)
	return events


## The hit chance (%, 0 - 100) of a missile that was not intercepted: accuracy plus the
## reconnaissance modifier. Shared by `resolve` and `forecast`.
static func hit_chance(
	state: OperationalState, player: int, means: StrikeMeansDefinition, target: Dictionary
) -> int:
	return clampi(means.accuracy_pct + recon_modifier(state, player, target), 0, 100)


## The company strengths after `hits` hits of `damage` each: every hit takes `damage` from the
## strongest company (ties: lowest index), floor 0. Pure; shared by `resolve` and `forecast`.
static func strengths_after_hits(strengths: Array[int], hits: int, damage: int) -> Array[int]:
	var result := strengths.duplicate()
	for i in hits:
		var strongest := 0
		for j in result.size():
			if result[j] > result[strongest]:
				strongest = j
		result[strongest] = maxi(0, result[strongest] - damage)
	return result


## Exact forecast of a salvo (TASK-101), no randomness and no state change; {} for an unknown
## weapon, a weapon of the other side, an unknown target, a target the strike may not hit
## (`target_problem`) or no stock. Otherwise {count (effective salvo), p_intercept, p_hit (%),
## p_hit_missile (0 - 1), expected_hits, p_at_least_one, kind, p_destroyed and, for an
## installation, integrity_before / expected_integrity_after, for a formation strength_before /
## expected_strength_lost}. The hits are binomial(count, p_hit_missile).
static func forecast(
	state: OperationalState, player: int, means_id: StringName, salvo: int, target_id: StringName
) -> Dictionary:
	var means: StrikeMeansDefinition = state.strike_means.get(means_id)
	if means == null or not means.usable_by(player):
		return {}
	var available := stock(state, player, means_id)
	if available < 1 or target_problem(state, player, target_id, means_id) != "":
		return {}
	var target := find_target(state, player, target_id)
	var count := clampi(salvo, 1, mini(means.max_salvo, available))
	var p_intercept := interception_chance(state, player, means_id, target["coord"])
	var p_hit := hit_chance(state, player, means, target)
	var p := (1.0 - minf(p_intercept, 100.0) / 100.0) * p_hit / 100.0
	var result := {
		"count": count,
		"p_intercept": p_intercept,
		"p_hit": p_hit,
		"p_hit_missile": p,
		"expected_hits": count * p,
		"p_at_least_one": 1.0 - pow(1.0 - p, count),
		"kind": target["kind"],
		"p_destroyed": 0.0,
	}
	var expected := 0.0
	var destroyed := 0.0
	var binomial := 1.0  # C(count, k)
	var strengths: Array[int] = []
	var before := 0
	if target["kind"] == &"installation":
		before = state.get_installation(target_id).integrity
		result["integrity_before"] = before
	else:
		for company in state.get_formation(target_id).companies:
			strengths.append(company.strength)
			before += company.strength
		result["strength_before"] = before
	for k in count + 1:
		var weight := binomial * pow(p, k) * pow(1.0 - p, count - k)
		var after := 0
		if target["kind"] == &"installation":
			after = maxi(0, before - k * means.damage)
		else:
			after = 0
			for value in strengths_after_hits(strengths, k, means.formation_damage):
				after += value
		expected += weight * (after if target["kind"] == &"installation" else before - after)
		if after <= 0:
			destroyed += weight
		binomial = binomial * (count - k) / (k + 1)
	result["p_destroyed"] = destroyed
	if target["kind"] == &"installation":
		result["expected_integrity_after"] = expected
	else:
		result["expected_strength_lost"] = expected
	return result


## A hit silences the site for `rounds` (a refresh, never added to): `installation_suppressed`.
static func _suppress(installation: Installation, rounds: int) -> Dictionary:
	var before := installation.suppressed_rounds
	installation.suppressed_rounds = rounds
	return _suppression_event(installation, before, &"strike")


static func _suppression_event(
	installation: Installation, before: int, cause: StringName
) -> Dictionary:
	return {
		"type": &"installation_suppressed",
		"id": installation.id,
		"before": before,
		"after": installation.suppressed_rounds,
		"cause": cause,
	}


static func _installation_event(
	installation: Installation, before: int, cause: StringName
) -> Dictionary:
	return {
		"type": &"installation_changed",
		"id": installation.id,
		"before": before,
		"after": installation.integrity,
		"destroyed": installation.destroyed(),
		"cause": cause,
	}


## Each hit takes `formation_damage` from the strongest company (ties: lowest index). Returns
## {dealt, destroyed, event}; a formation with no strength left is removed.
static func _damage_formation(
	state: OperationalState, formation: Formation, hits: int, means: StrikeMeansDefinition
) -> Dictionary:
	var before := formation.strength()
	var strengths: Array[int] = []
	for company in formation.companies:
		strengths.append(company.strength)
	var left := strengths_after_hits(strengths, hits, means.formation_damage)
	for i in formation.companies.size():
		formation.companies[i].strength = left[i]
	var after := formation.strength()
	var destroyed := after <= 0
	var event := {
		"type": &"formation_destroyed" if destroyed else &"formation_damaged",
		"formation_id": formation.id,
		"player": formation.owner_id,
		"at": formation.coord,
		"before": before,
		"after": after,
		"cause": &"strike",
	}
	if destroyed:
		state.formations.erase(formation)
	return {"dealt": before - after, "destroyed": destroyed, "event": event}


# --- round boundary ---


## Resupply (player 0, then 1, each means in `strike_resupply` order), repair of damaged, not
## destroyed, installations (setup order), then the suppression countdown. No randomness.
static func end_round(state: OperationalState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for player in 2:
		for means_id: StringName in state.strike_resupply[player]:
			events.append_array(
				add_stock(
					state, player, means_id, state.strike_resupply[player][means_id], &"resupply"
				)
			)
	for installation in state.installations:
		if installation.integrity > 0 and installation.integrity < Installation.MAX_INTEGRITY:
			var before := installation.integrity
			installation.integrity = mini(
				Installation.MAX_INTEGRITY, before + state.repair_per_round
			)
			if installation.integrity != before:
				events.append(_installation_event(installation, before, &"repair"))
	for installation in state.installations:
		if installation.suppressed_rounds > 0:
			installation.suppressed_rounds -= 1
			events.append(
				_suppression_event(installation, installation.suppressed_rounds + 1, &"lapse")
			)
	return events

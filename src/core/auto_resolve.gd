class_name AutoResolve
extends RefCounted
## Battle auto-resolve (TASK-120, GDD "Battle hand-off and auto-resolve"): the BattleResult of a
## contact battle computed from the same setup – forces, postures, terrain, command points –
## without loading a map. Pure and static: it changes no state and draws only from its own
## RandomNumberGenerator seeded with `setup.seed`, so the same setup always gives the same result.
## The companies fight in rounds; in each round every living company fires once at the living
## enemy company it hits best, the damage lands after all of them fired.


## The result of fighting `setup` out; null (push_error) when the setup cannot be fought.
static func resolve(setup: BattleSetup, rules: AutoResolveRules = null) -> BattleResult:
	return _fight(setup, rules, PackedInt32Array(), 0, setup.seed, BattleResult.AUTO)


## The result of finishing the unfinished battle `state` (started from `setup` with
## `Scenario.from_setup`) by auto-resolve: the fight goes on from the companies' current strengths
## (a destroyed one stays destroyed), for the turns the limit still allows (at least one round),
## and a side's break share counts from its strength at the start of the battle. Used when the
## player leaves a campaign battle. The dice are seeded from the setup seed and the turn reached,
## never from `state.rng`. Resolution `concluded`; a battle that is already over gives its played
## result. Null (push_error) when the setup cannot be fought.
static func resolve_from(
	setup: BattleSetup, state: GameState, rules: AutoResolveRules = null
) -> BattleResult:
	if state.is_over():
		return BattleResult.from_battle(setup, state)
	var current := PackedInt32Array()
	for i in setup.companies.size():
		var unit := state.get_unit(i + 1)
		current.append(maxi(unit.hp, 0) if unit != null else 0)
	return _fight(
		setup, rules, current, state.turn, hash([setup.seed, state.turn]), BattleResult.CONCLUDED
	)


## Fights `setup` out from `current` strengths (empty = the planned ones) after `turns_played`
## turns; the dice come from `seed_value`.
static func _fight(
	setup: BattleSetup,
	rules: AutoResolveRules,
	current: PackedInt32Array,
	turns_played: int,
	seed_value: int,
	resolution: StringName
) -> BattleResult:
	if rules == null:
		rules = AutoResolveRules.shipped()
	var defs := _definitions(setup)
	if defs.is_empty():
		return null
	var count := setup.companies.size()
	var bonus: Variant = _terrain_bonus(setup.terrain)
	if bonus == null:
		return null
	var hit_on := _hit_table(setup, defs, bonus as int)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var sides := setup.factions.size()
	var owner := PackedInt32Array()
	var dice := PackedInt32Array()
	var strength := PackedInt32Array()
	var side_start := PackedInt32Array()
	side_start.resize(sides)
	for i in count:
		owner.append(setup.companies[i].player)
		dice.append(defs[i].max_hp)
		strength.append(current[i] if not current.is_empty() else setup.companies[i].strength)
		side_start[owner[i]] += setup.companies[i].strength
	var rounds := setup.objectives.turn_limit
	if rounds <= 0:
		rounds = rules.default_rounds
	elif turns_played > 0:
		rounds = maxi(rounds - turns_played, 1)
	var winner := -1
	var reason := &"turn_limit"
	var fought := 0
	var damage := PackedInt32Array()
	damage.resize(count)
	var fired := PackedInt32Array()
	fired.resize(sides)
	while fought < rounds:
		fought += 1
		damage.fill(0)
		fired.fill(0)
		var before := strength.duplicate()
		for i in count:
			if before[i] <= 0:
				continue
			var points := setup.conditions[owner[i]].command_points
			if points > 0 and fired[owner[i]] >= points:
				continue
			fired[owner[i]] += 1
			var target := _target(owner, before, hit_on, i)
			if target < 0:
				continue
			var die := dice[i]
			var needed := hit_on[i * count + target]
			var hits := 0
			for roll in before[i]:
				if rng.randi_range(1, die) <= needed:
					hits += 1
			damage[target] += hits
		for i in count:
			strength[i] = maxi(strength[i] - damage[i], 0)
		var ended := _end_of_round(owner, strength, side_start, rules)
		if ended.x != -2:
			winner = ended.x
			reason = &"eliminated" if ended.y == 0 else &"broken"
			break
	var result := BattleResult.new()
	result.resolution = resolution
	result.winner = winner
	result.reason = reason
	result.turns = turns_played + fought
	for i in count:
		var planned := setup.companies[i]
		var company := BattleResult.Company.new()
		company.player = planned.player
		company.unit_type = planned.unit_type
		company.ref = planned.ref
		company.strength_start = planned.strength
		company.strength_end = strength[i]
		result.companies.append(company)
	result.settle(setup)
	return result


## (winner, reason index 0 = eliminated / 1 = broken) when the round ended the battle (winner -1 =
## draw); (-2, 0) when it goes on.
static func _end_of_round(
	owner: PackedInt32Array,
	strength: PackedInt32Array,
	side_start: PackedInt32Array,
	rules: AutoResolveRules
) -> Vector2i:
	var left := PackedInt32Array()
	left.resize(side_start.size())
	for i in strength.size():
		left[owner[i]] += strength[i]
	var broken: Array[int] = []
	for player in side_start.size():
		var lost := side_start[player] - left[player]
		if left[player] <= 0 or lost * 100 >= rules.break_share * side_start[player]:
			broken.append(player)
	if broken.is_empty():
		return Vector2i(-2, 0)
	if broken.size() == 1:
		var loser := broken[0]
		return Vector2i(1 - loser, 0 if left[loser] <= 0 else 1)
	var wiped := left[0] <= 0 and left[1] <= 0
	return Vector2i(-1, 0 if wiped else 1)


## Index of the living enemy company `shooter` hits best (ties: lowest strength at the start of
## the round, then lowest index); -1 when none is left.
static func _target(
	owner: PackedInt32Array, before: PackedInt32Array, hit_on: PackedInt32Array, shooter: int
) -> int:
	var count := owner.size()
	var side := owner[shooter]
	var base := shooter * count
	var best := -1
	var best_hit := 0
	for j in count:
		if before[j] <= 0 or owner[j] == side:
			continue
		var hit := hit_on[base + j]
		if best < 0 or hit > best_hit or (hit == best_hit and before[j] < before[best]):
			best = j
			best_hit = hit
	return best


## hit_on[i * count + j]: a roll of company i at or below it hits company j
## (min(max(1, attack - (defense + position bonus + terrain bonus if j defends)), max_hp)).
static func _hit_table(
	setup: BattleSetup, defs: Array[UnitDefinition], terrain: int
) -> PackedInt32Array:
	var table := PackedInt32Array()
	for i in defs.size():
		for j in defs.size():
			var target := setup.companies[j]
			var guard := defs[j].defense + setup.conditions[target.player].position_bonus
			if setup.attacker >= 0 and target.player != setup.attacker:
				guard += terrain
			table.append(mini(maxi(1, defs[i].attack - guard), defs[i].max_hp))
	return table


## The UnitDefinition of every company; empty (push_error) when the setup cannot be fought.
static func _definitions(setup: BattleSetup) -> Array[UnitDefinition]:
	var defs: Array[UnitDefinition] = []
	if setup.conditions.size() != setup.factions.size():
		push_error("AutoResolve: conditions must be one per faction")
		return defs
	var seen := {}
	for company in setup.companies:
		if company.player < 0 or company.player >= setup.factions.size():
			push_error("AutoResolve: player %d does not exist" % company.player)
			return []
		var faction := FactionRegistry.get_faction(setup.factions[company.player])
		var definition := faction.find_unit(company.unit_type) if faction != null else null
		if definition == null:
			push_error(
				"Scenario: player %d cannot field '%s'" % [company.player, company.unit_type]
			)
			return []
		if company.strength < 1 or company.strength > definition.max_hp:
			push_error(
				"Scenario: strength %d of '%s' out of range" % [company.strength, company.unit_type]
			)
			return []
		seen[company.player] = true
		defs.append(definition)
	for player in setup.factions.size():
		if not seen.has(player):
			push_error("AutoResolve: player %d has no companies" % player)
			return []
	return defs


## Defence bonus of the defender's terrain (&"" = plains); null (push_error) for an unknown id.
static func _terrain_bonus(id: StringName) -> Variant:
	if id == &"":
		return 0
	for type: Terrain.Type in Terrain.Type.values():
		var definition := Terrain.definition(type)
		if definition != null and definition.id == id:
			return definition.defense_bonus
	push_error("AutoResolve: unknown terrain '%s'" % id)
	return null

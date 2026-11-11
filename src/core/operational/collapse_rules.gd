class_name CollapseRules
extends RefCounted
## Pure collapse rules of the operational layer (TASK-140, GDD "Escalation ladder"): whether a
## side's army is falling apart, from its present strength against its fielded strength
## (OperationalState.fielded_strength) and the readiness of its surviving formations. The same
## rule for both sides; the numbers are in EscalationLadder. Live, no memory, no randomness.


## Sum of the current strength of `player`'s formations on the map.
static func present_strength(state: OperationalState, player: int) -> int:
	var total := 0
	for formation in state.formations:
		if formation.owner_id == player:
			total += formation.strength()
	return total


## 100 × present / fielded strength (integer division); 100 when nothing was fielded.
static func strength_pct(state: OperationalState, player: int) -> int:
	var fielded: int = state.fielded_strength[player]
	if fielded <= 0:
		return 100
	return 100 * present_strength(state, player) / fielded


## Average readiness of `player`'s surviving formations (integer division); 100 when none.
static func avg_readiness(state: OperationalState, player: int) -> int:
	var total := 0
	var count := 0
	for formation in state.formations:
		if formation.owner_id == player:
			total += formation.readiness
			count += 1
	if count == 0:
		return 100
	return total / count


## Whether `player` is in collapse: routed (strength ≤ collapse_strength_pct), or shaken (average
## readiness ≤ collapse_readiness_pct while strength ≤ collapse_readiness_strength_pct), or no
## formation left.
static func in_collapse(state: OperationalState, player: int) -> bool:
	if not state.formations.any(func(f: Formation) -> bool: return f.owner_id == player):
		return true
	var ladder := state.ladder
	var pct := strength_pct(state, player)
	if pct <= ladder.collapse_strength_pct:
		return true
	return (
		avg_readiness(state, player) <= ladder.collapse_readiness_pct
		and pct <= ladder.collapse_readiness_strength_pct
	)

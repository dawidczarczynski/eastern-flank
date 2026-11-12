class_name ProvisionalScore
extends RefCounted
## Provisional winner of an operation that reached its round cap without an ending rule
## (TASK-103a): per side, the sum of the weights of the AI goals (AiGoal, TASK-102a) it holds now.
## A goal is held when a friendly formation stands on its hex, or – for an installation goal – the
## installation is friendly-owned and no enemy formation stands on it. Returns the shape TASK-107's
## real victory will feed ({winner, reason, by}), so the tool can swap the source.

const REASON := &"provisional"


## Per player: total weight of the goals that player's side pursues and currently holds.
static func totals(state: OperationalState) -> Array[int]:
	var sums: Array[int] = [0, 0]
	for goal in state.ai_goals:
		if goal.player != 0 and goal.player != 1:
			continue
		if is_held(state, goal):
			sums[goal.player] += goal.weight
	return sums


## Whether the goal's own side holds it now.
static func is_held(state: OperationalState, goal: AiGoal) -> bool:
	var hex := goal.hex_in(state)
	if hex == Vector2i.MAX:
		return false
	var standing := state.formation_at(hex)
	if standing != null:
		return standing.owner_id == goal.player
	if goal.installation_id == &"":
		return false
	var installation := state.get_installation(goal.installation_id)
	return installation != null and installation.owner == goal.player


## {winner: -1 / 0 / 1, reason: &"provisional", by: -1, totals: [int, int]}. A difference of at
## most `threshold` (default: state.provisional_draw_threshold) is a draw.
static func evaluate(state: OperationalState, threshold: int = -1) -> Dictionary:
	if threshold < 0:
		threshold = state.provisional_draw_threshold
	var sums := totals(state)
	var diff := sums[0] - sums[1]
	var winner := -1
	if absi(diff) > threshold:
		winner = 0 if diff > 0 else 1
	return {"winner": winner, "reason": REASON, "by": -1, "totals": sums}

extends TestCase
## Operation balance regression (TASK-103b): in AI-vs-AI operations on seeds 1..20 each side must
## hold 35-65 % of the decided operations (the target is 40-60 %, the band leaves room for noise).
## A turn-cap result counts as decided by its provisional winner; a draw or a nuclear ending does
## not (TASK-103a report).

const SEEDS := 20
const MIN_SHARE := 0.35
const MAX_SHARE := 0.65
const MAX_UNDECIDED := 0.40


## Whether `wins` ([NATO, Russia]) over `matches` operations lies in the band: both shares of the
## decided operations in MIN_SHARE..MAX_SHARE and the undecided share at most MAX_UNDECIDED.
static func in_band(wins: Array[int], matches: int) -> bool:
	var decided := wins[0] + wins[1]
	if matches <= 0 or decided <= 0:
		return false
	if float(matches - decided) / matches > MAX_UNDECIDED:
		return false
	for side in 2:
		var share := float(wins[side]) / decided
		if share < MIN_SHARE or share > MAX_SHARE:
			return false
	return true


func test_band_helper_rejects_a_lopsided_result() -> void:
	assert_true(in_band([10, 10], 20))
	assert_true(in_band([7, 13], 20))
	assert_false(in_band([0, 20], 20), "one side never wins")
	assert_false(in_band([5, 15], 20), "25 % is below the band")
	assert_false(in_band([14, 6], 20), "70 % is above the band")
	assert_false(in_band([5, 5], 20), "half the operations undecided")
	assert_false(in_band([0, 0], 20))


func test_both_sides_win_a_fair_share_of_operations() -> void:
	var results: Array[Dictionary] = []
	for seed_value in range(1, SEEDS + 1):
		results.append(OperationMatchRunner.play(&"suwalki_gap", seed_value))
	var summary := OperationMatchRunner.summarize(results)
	assert_eq(summary["errors"], 0)
	var wins: Array[int] = [summary["wins"][0], summary["wins"][1]]
	assert_true(in_band(wins, SEEDS), "wins NATO / Russia %s of %d" % [wins, SEEDS])
	# Determinism: the same seed gives the same result twice.
	assert_eq(OperationMatchRunner.play(&"suwalki_gap", 1), results[0])

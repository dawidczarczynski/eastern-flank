extends SceneTree
## Plays a full AI-vs-AI match of the default battle and writes the replay regression fixture
## (MatchRecord + "expected_final" snapshot). Run via tools/make_replay_fixture.sh. Manually:
##   godot --headless --path . --script res://tools/make_replay_fixture.gd
## Regenerating is a deliberate step after an intended rule change – commit the new fixture.
## Exit codes: 0 written, 1 failure.

const SEED := 12345
const MAX_TURN := 30
const OUTPUT := "res://tests/fixtures/replays/default_battle_12345.json"


func _initialize() -> void:
	var sim := GameSimulation.new(Scenario.default_battle(SEED))
	var players: Array[AiPlayer] = [AiPlayer.new(), AiPlayer.new()]
	while not sim.state.is_over() and sim.state.turn <= MAX_TURN:
		var before := sim.history.size()
		players[sim.state.current_player].take_turn(sim)
		if sim.history.size() == before:
			_fail("the AI issued no command – aborting to avoid an endless loop")
			return
	var record := MatchRecord.from_simulation(sim, SEED)
	# Self-check: the record must replay to the same state before it becomes the fixture.
	var replay := Replay.run(MatchRecord.from_json(record.to_json()))
	if not replay["ok"]:
		_fail("the fresh record does not replay: %s" % str(replay))
		return
	var final := sim.state.snapshot()
	if (replay["simulation"] as GameSimulation).state.snapshot() != final:
		_fail("the fresh record replays to a different state")
		return
	var path := ProjectSettings.globalize_path(OUTPUT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(_to_text(record, final))
	file.close()
	print(
		(
			"Wrote %s: %d commands, turn %d, winner %d"
			% [path, record.commands.size(), sim.state.turn, sim.state.winner]
		)
	)
	quit(0)


## The fixture JSON with one command / unit per line (readable diffs when it is regenerated).
func _to_text(record: MatchRecord, final: Dictionary) -> String:
	var commands: Array[String] = []
	for command in record.commands:
		commands.append("\t\t" + JSON.stringify(command, "", false))
	var final_lines: Array[String] = []
	for key: String in final:
		if key != "units":
			final_lines.append('\t\t"%s": %s' % [key, JSON.stringify(final[key])])
	var units: Array[String] = []
	for unit: Dictionary in final["units"]:
		units.append("\t\t\t" + JSON.stringify(unit, "", false))
	final_lines.append('\t\t"units": [\n%s\n\t\t]' % ",\n".join(units))
	var text := "{\n"
	text += '\t"version": %d,\n' % record.version
	text += '\t"scenario": %s,\n' % JSON.stringify(record.scenario)
	text += '\t"seed": %d,\n' % record.seed
	text += '\t"factions": %s,\n' % JSON.stringify(record.to_dict()["factions"])
	text += '\t"commands": [\n%s\n\t],\n' % ",\n".join(commands)
	text += '\t"expected_final": {\n%s\n\t}\n' % ",\n".join(final_lines)
	return text + "}\n"


func _fail(message: String) -> void:
	push_error("make_replay_fixture: " + message)
	quit(1)

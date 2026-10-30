extends TestCase
## The in-game unit catalog (TASK-084): the unit list, every model builds, and the stage's
## animations leave the model in its built pose.

const IDS := preload("res://src/presentation/catalog/catalog_animations.gd")
const TOL := 0.00001

var _stage: CatalogStage


func after_each() -> void:
	if _stage != null:
		_stage.free()
		_stage = null


func _tres_count() -> int:
	var count := 0
	for file in DirAccess.get_files_at("res://data/units"):
		if file.ends_with(".tres"):
			count += 1
	return count


func _make_stage() -> CatalogStage:
	_stage = CatalogStage.new()
	return _stage


func _definition(unit_id: StringName) -> UnitDefinition:
	for definition in CatalogUnits.definitions():
		if definition.id == unit_id:
			return definition
	return null


func _faction(unit_id: StringName) -> FactionDefinition:
	var factions := CatalogUnits.factions_for(_definition(unit_id))
	return factions[0] if not factions.is_empty() else null


## Every transform below the model, to compare poses.
func _snapshot(node: Node, into: Dictionary = {}, prefix := "") -> Dictionary:
	for child in node.get_children():
		var spatial := child as Node3D
		if spatial == null:
			continue
		var path := "%s/%s" % [prefix, child.name]
		into[path] = spatial.transform
		_snapshot(spatial, into, path)
	return into


func _assert_same_pose(actual: Dictionary, expected: Dictionary) -> void:
	assert_eq(actual.size(), expected.size())
	for path: String in expected:
		assert_true(actual.has(path), "missing %s" % path)
		if actual.has(path):
			var a: Transform3D = actual[path]
			var e: Transform3D = expected[path]
			assert_true(a.is_equal_approx(e), "%s differs: %s vs %s" % [path, a, e])


func test_catalog_lists_every_unit_definition() -> void:
	assert_eq(CatalogUnits.definitions().size(), _tres_count())
	var seen := {}
	for definition in CatalogUnits.definitions():
		assert_false(seen.has(definition.id), "%s listed twice" % definition.id)
		seen[definition.id] = true
		assert_true(
			ResourceLoader.exists("res://data/units/%s.tres" % definition.id), "path matches id"
		)


func test_groups_cover_all_units_without_empty_groups() -> void:
	var total := 0
	for group in CatalogUnits.grouped():
		assert_true((group["units"] as Array).size() > 0)
		assert_true(group["label"].begins_with("CLASS_"))
		total += (group["units"] as Array).size()
	assert_eq(total, _tres_count())


func test_every_unit_builds_for_every_faction_that_fields_it() -> void:
	for definition in CatalogUnits.definitions():
		var factions := CatalogUnits.factions_for(definition)
		var variants: Array = [null] if factions.is_empty() else factions
		for faction: FactionDefinition in variants:
			var model := UnitModels.build(definition.id, 0, faction)
			assert_true(model != null, "%s builds" % definition.id)
			if not UnitModels.has_model(definition.id):
				push_warning("catalog: %s has only the placeholder model" % definition.id)
			model.free()


func test_stage_shows_every_unit() -> void:
	var stage := _make_stage()
	for definition in CatalogUnits.definitions():
		var factions := CatalogUnits.factions_for(definition)
		stage.show_unit(definition, factions[0] if not factions.is_empty() else null)
		assert_true(stage.view() != null, "%s has a view" % definition.id)
		assert_true(stage.bounds().size.length() > 0.1, "%s has a size" % definition.id)
		assert_true(stage.model_size_m().x > 1.0, "%s is longer than a metre" % definition.id)
		assert_eq(stage.animations(), IDS.for_model(stage.view().model()))


## The headless test runner has no running scene tree, so tweens cannot advance here: the tests
## set the poses a tween would and use finish_pose(); the tween itself is checked in the game
## (docs/tasks/TASK-084) and by tools/screenshot.sh.
func test_fire_leaves_the_model_in_its_built_pose() -> void:
	for unit_id in [&"homar_k", &"bm27_uragan"]:
		var stage := _make_stage()
		stage.show_unit(_definition(unit_id), _faction(unit_id))
		var view := stage.view()
		var built := _snapshot(view.model())
		stage.play(IDS.FIRE)
		assert_true(stage.is_busy(), "%s fires" % unit_id)
		assert_true(stage.is_on(IDS.FIRE))
		assert_false(stage.can_play(IDS.DEPLOY), "a firing unit takes no other pose button")
		# Poses mid-volley, as the tween sets them.
		view.set_deploy_pose(1.0)
		view.set_launcher_pose(0.7, view.launcher_elevation())
		var posed := _snapshot(view.model())
		assert_false(posed["/Launcher/Pod"].is_equal_approx(built["/Launcher/Pod"]), "pod raised")
		stage.finish_pose()
		assert_false(stage.is_busy(), "%s finished" % unit_id)
		assert_false(stage.is_on(IDS.FIRE))
		_assert_same_pose(_snapshot(view.model()), built)
		assert_true(stage.can_play(IDS.FIRE), "ready to fire again")
		stage.free()
		_stage = null


func test_toggles_flip_and_return_to_the_built_pose() -> void:
	var stage := _make_stage()
	stage.show_unit(_definition(&"homar_k"), _faction(&"homar_k"))
	var built := _snapshot(stage.view().model())
	for id in [IDS.DEPLOY, IDS.RAISE, IDS.TRAVERSE]:
		stage.play(id)
		assert_true(stage.is_on(id), "%s on" % id)
		stage.finish_pose()
		assert_false(stage.is_busy())
	var posed := _snapshot(stage.view().model())
	assert_false(posed["/Launcher/Pod"].is_equal_approx(built["/Launcher/Pod"]))
	assert_false(stage.can_play(IDS.FIRE), "Fire needs the stowed pose")
	for id in [IDS.TRAVERSE, IDS.RAISE, IDS.DEPLOY]:
		stage.play(id)
		stage.finish_pose()
		assert_false(stage.is_on(id), "%s off" % id)
	_assert_same_pose(_snapshot(stage.view().model()), built)
	assert_true(stage.can_play(IDS.FIRE))


func test_tank_traverse_turns_the_turret_and_back() -> void:
	var stage := _make_stage()
	stage.show_unit(_definition(&"t72b3"), _faction(&"t72b3"))
	var built := _snapshot(stage.view().model())
	stage.play(IDS.TRAVERSE)
	stage.finish_pose()
	assert_true(stage.is_on(IDS.TRAVERSE))
	assert_false(_snapshot(stage.view().model())["/Turret"].is_equal_approx(built["/Turret"]))
	stage.play(IDS.TRAVERSE)
	stage.finish_pose()
	_assert_same_pose(_snapshot(stage.view().model()), built)


func test_a_busy_stage_ignores_pose_buttons() -> void:
	var stage := _make_stage()
	stage.show_unit(_definition(&"homar_k"), _faction(&"homar_k"))
	stage.play(IDS.DEPLOY)
	assert_true(stage.is_busy())
	assert_false(stage.can_play(IDS.RAISE))
	stage.play(IDS.RAISE)
	assert_false(stage.is_on(IDS.RAISE))
	stage.finish_pose()


func test_fire_target_is_in_the_traversed_direction() -> void:
	for unit_id in [&"homar_k", &"bm27_uragan"]:
		var stage := _make_stage()
		stage.show_unit(_definition(unit_id), _faction(unit_id))
		stage.play(IDS.FIRE)
		var target := stage.fire_point()
		var model := stage.view().model()
		var yaw := MoveAnimation.facing_yaw(stage.view().position, target)
		var aim := UnitModels.launcher_aim(model, stage.view().facing_yaw(), yaw)
		assert_true(absf(aim.x) < TOL, "the body does not need to turn")
		assert_true(absf(wrapf(aim.y - IDS.traverse_angle(model), -PI, PI)) < 0.001)
		assert_true(absf(target.length() - CatalogStage.TARGET_DISTANCE) < 0.001)
		stage.finish_pose()
		stage.free()
		_stage = null


func test_fire_target_is_far_off_screen() -> void:
	var stage := _make_stage()
	stage.show_unit(_definition(&"homar_k"), _faction(&"homar_k"))
	var target := stage.fire_point()
	assert_true(target.length() > CatalogStage.GROUND_RADIUS * 10.0, "far beyond the ground disc")
	assert_false(stage.framing_bounds().has_point(target), "the camera frames the unit only")
	var bounds := CatalogStage.FX_BOUNDS
	assert_true(
		bounds.grow(-1.0).has_point(Vector2(target.x, target.z)), "inside the fx culling box"
	)


func test_fire_uses_the_battle_salvo_effects_without_impacts() -> void:
	var stage := _make_stage()
	stage.quality = {"particles": true, "fx_lights": true}
	stage.show_unit(_definition(&"homar_k"), _faction(&"homar_k"))
	var pool := stage.salvo_fx()
	assert_true(pool != null, "a launcher gets the salvo pool")
	pool.emitted[&"blast"] = 0
	pool.emitted[&"fire"] = 0
	pool.emitted[&"smoke"] = 0
	pool.emitted[&"debris"] = 0
	stage.play(IDS.FIRE)
	# The pose tween does not run outside the tree: set the salvo up and drive it by hand.
	var volley := stage.find_child("RocketVolley", false, false) as RocketVolley
	assert_true(volley.effects is SalvoFxPool.VolleyFx, "the battle's salvo effects")
	var target := stage.fire_point()
	var plan := VolleyPlayback.plan_for(stage.view(), target)
	var rng := RandomNumberGenerator.new()
	var landings := VolleyPlayback.landing_points(rng, target, plan["count"], 1.0)
	VolleyPlayback.setup_salvo(volley, stage.view(), target, landings, plan)
	var t := 0.0
	while t < volley.duration():
		volley.update(t)
		t += 0.05
	volley.update(volley.duration())
	volley.free()
	assert_true(pool.emitted[&"blast"] > 0, "backblast smoke")
	assert_true(pool.emitted[&"fire"] > 0, "backblast fire")
	assert_true(pool.emitted[&"trail"] > 0, "smoke trails")
	assert_eq(pool.emitted[&"smoke"], 0, "no impact smoke")
	assert_eq(pool.emitted[&"debris"], 0, "no impact debris")
	assert_eq(pool.column_count(), 0, "no smoke column")


func test_a_launcher_without_particles_gets_no_pool() -> void:
	var stage := _make_stage()
	stage.quality = {"particles": false}
	stage.show_unit(_definition(&"homar_k"), _faction(&"homar_k"))
	assert_eq(stage.salvo_fx(), null)


func test_drive_raises_dust_and_exhaust() -> void:
	var stage := _make_stage()
	stage.quality = {"particles": true}
	stage.show_unit(_definition(&"m1a2_sepv3"), _faction(&"m1a2_sepv3"))
	var emitters := stage.view().find_children("Exhaust", "GPUParticles3D", true, false)
	assert_eq(emitters.size(), 1)
	var exhaust := emitters[0] as GPUParticles3D
	assert_false(exhaust.emitting)
	stage.play(IDS.DRIVE)
	stage._process(0.3)
	assert_true(exhaust.emitting, "exhaust while driving")
	assert_true(exhaust.amount_ratio > 0.0)
	stage.play(IDS.DRIVE)
	for i in 20:
		stage._process(0.1)
	assert_false(exhaust.emitting, "off at rest")


func test_show_unit_while_firing_clears_the_salvo() -> void:
	var stage := _make_stage()
	stage.show_unit(_definition(&"homar_k"), _faction(&"homar_k"))
	stage.play(IDS.FIRE)
	assert_true(stage.find_child("RocketVolley", false, false) != null)
	stage.show_unit(_definition(&"m1a2_sepv3"), _faction(&"m1a2_sepv3"))
	assert_false(stage.is_busy())
	assert_false(stage.is_on(IDS.FIRE))


func test_death_then_reset_gives_a_clean_model() -> void:
	var stage := _make_stage()
	stage.show_unit(_definition(&"homar_k"), _faction(&"homar_k"))
	var built := _snapshot(stage.view().model())
	stage.play(IDS.DEPLOY)
	stage.finish_pose()
	stage.play(IDS.DEATH)
	assert_true(stage.is_dead())
	assert_false(stage.can_play(IDS.HIT), "nothing plays on a dead unit")
	assert_false(stage.can_play(IDS.DEPLOY))
	stage.show_unit(stage.definition(), stage.faction())
	assert_false(stage.is_dead())
	assert_false(stage.is_on(IDS.DEPLOY))
	_assert_same_pose(_snapshot(stage.view().model()), built)
	assert_true(stage.can_play(IDS.HIT))


func test_squad_march_and_kneel() -> void:
	var stage := _make_stage()
	stage.show_unit(_definition(&"pl_mech_infantry"), _faction(&"pl_mech_infantry"))
	var rig := stage.view().model().get_node("Soldier0/Rig") as Node3D
	var kneel := rig.get_node_or_null("Kneel") as Node3D
	var built_kneeling := kneel != null and kneel.visible
	stage.play(IDS.KNEEL)
	assert_true(stage.is_on(IDS.KNEEL))
	if kneel != null:
		assert_eq(kneel.visible, not built_kneeling or false)
	stage.play(IDS.KNEEL)
	if kneel != null:
		assert_eq(kneel.visible, built_kneeling)
	stage.play(IDS.MARCH)
	assert_true(stage.is_on(IDS.MARCH))
	stage._process(0.5)
	stage.play(IDS.MARCH)
	assert_false(stage.is_on(IDS.MARCH))


func test_drive_spins_the_wheels_and_stops_at_rest() -> void:
	var stage := _make_stage()
	stage.show_unit(_definition(&"homar_k"), _faction(&"homar_k"))
	assert_true(stage.can_play(IDS.DRIVE) == (IDS.DRIVE in stage.animations()))
	var tank := _definition(&"m1a2_sepv3")
	stage.show_unit(tank, _faction(&"m1a2_sepv3"))
	var wheel := stage.view().model().get_node("Wheel0") as Node3D
	assert_eq(wheel.rotation.z, 0.0)
	stage.play(IDS.DRIVE)
	stage._process(0.3)
	stage._process(0.3)
	assert_true(absf(wheel.rotation.z) > 0.01, "wheels turn")
	stage.play(IDS.DRIVE)
	for i in 20:
		stage._process(0.1)
	assert_true(stage.view().model().rotation.length() < 0.02, "hull at rest")

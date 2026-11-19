extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")


## TASK-176: a Polish tank battalion (with its K9 Thunder) against a Russian motor rifle one.
func test_tank_battalion_with_a_k9_resolves_deterministically() -> void:
	var pl_ru: Array[StringName] = [&"poland", &"russia"]
	var rows: Array = []
	for type_id: StringName in [
		&"m1a2_sepv3",
		&"m1a2_sepv3",
		&"m1a2_sepv3",
		&"m1a2_sepv3",
		&"pl_mech_infantry",
		&"k9_thunder",
		&"homar_k"
	]:
		rows.append([0, type_id, int(load("res://data/units/%s.tres" % type_id).max_hp)])
	for type_id: StringName in [
		&"ru_motor_rifle",
		&"ru_motor_rifle",
		&"ru_motor_rifle",
		&"t72b3",
		&"t72b3",
		&"t72b3",
		&"bm27_uragan"
	]:
		rows.append([1, type_id, int(load("res://data/units/%s.tres" % type_id).max_hp)])
	var setup := Fixtures.auto_setup(pl_ru, rows, [[&"advance", 0], [&"advance", 0]], &"plains", 5)
	var first := AutoResolve.resolve(setup)
	assert_true(first != null, "resolves")
	assert_eq(first.to_dict(), AutoResolve.resolve(setup).to_dict())


## A Russian tank battalion (with its 2S19 Msta-S) against a Polish one resolves deterministically.
func test_tank_battalion_with_a_msta_resolves_deterministically() -> void:
	var pl_ru: Array[StringName] = [&"poland", &"russia"]
	var rows: Array = []
	for type_id: StringName in [&"m1a2_sepv3", &"m1a2_sepv3", &"pl_mech_infantry", &"homar_k"]:
		rows.append([0, type_id, int(load("res://data/units/%s.tres" % type_id).max_hp)])
	for type_id: StringName in [
		&"t72b3", &"t72b3", &"t72b3", &"t72b3", &"ru_motor_rifle", &"ru_motor_rifle", &"2s19_msta_s"
	]:
		rows.append([1, type_id, int(load("res://data/units/%s.tres" % type_id).max_hp)])
	var setup := Fixtures.auto_setup(pl_ru, rows, [[&"advance", 0], [&"advance", 0]], &"plains", 5)
	var first := AutoResolve.resolve(setup)
	assert_true(first != null, "resolves")
	assert_eq(first.to_dict(), AutoResolve.resolve(setup).to_dict())

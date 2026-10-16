extends TestCase

const Fixtures := preload("res://tests/fixtures.gd")
const INFANTRY := preload("res://data/units/infantry.tres")
const CAVALRY := preload("res://data/units/cavalry.tres")


func test_fresh_infantry_lines() -> void:
	var unit := Unit.new(1, 0, INFANTRY, Vector2i.ZERO)
	assert_eq(
		UnitInfo.lines(unit),
		PackedStringArray(
			[
				"Infantry",
				"HP 10/10",
				"Moves 3/3",
				"Attack 4 · Defense 3 · Range 1",
				"Ready to attack",
			]
		)
	)


func test_damaged_cavalry_that_already_attacked() -> void:
	var unit := Unit.new(2, 0, CAVALRY, Vector2i.ZERO)
	unit.hp = 3
	unit.moves_left = 0
	unit.has_attacked = true
	assert_eq(
		UnitInfo.lines(unit),
		PackedStringArray(
			[
				"Cavalry",
				"HP 3/8",
				"Moves 0/5",
				"Attack 5 · Defense 2 · Range 1",
				"Already attacked",
			]
		)
	)


func test_empty_display_name_falls_back_to_id() -> void:
	var unit := Unit.new(3, 0, Fixtures.fighter(4, 2), Vector2i.ZERO)
	var lines := UnitInfo.lines(unit)
	assert_eq(lines.size(), 5)
	assert_eq(lines[0], "test_fighter")

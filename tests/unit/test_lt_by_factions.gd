extends TestCase
## Lithuanian and Belarusian factions (TASK-160): identity only, reuse Polish / Russian rosters.

const Data := preload("res://tests/unit/test_contribution_data.gd")


func test_factions_exist_with_short_names_and_flags() -> void:
	for pair in [[&"lithuania", "LT"], [&"belarus", "BY"]]:
		var faction := FactionRegistry.get_faction(pair[0])
		assert_true(faction != null)
		assert_eq(faction.short_name, pair[1])
		assert_true(faction.flag != null)


func test_rosters_match_the_reused_factions() -> void:
	for pair in [[&"lithuania", &"poland"], [&"belarus", &"russia"]]:
		var own := FactionRegistry.get_faction(pair[0])
		var base := FactionRegistry.get_faction(pair[1])
		assert_eq(own.roster.size(), base.roster.size())
		for i in own.roster.size():
			assert_eq(own.roster[i].id, base.roster[i].id)


func test_flags_share_the_ratio_of_the_others() -> void:
	var ratio := FactionRegistry.get_faction(&"poland").flag.get_size()
	ratio = ratio / ratio.y
	for id in [&"lithuania", &"belarus"]:
		var size := FactionRegistry.get_faction(id).flag.get_size()
		assert_true(absf(size.x / size.y - ratio.x) < 0.01)


func test_colours_differ_from_the_reused_factions() -> void:
	for pair in [[&"lithuania", &"poland"], [&"belarus", &"russia"]]:
		var a := FactionRegistry.get_faction(pair[0]).color
		var b := FactionRegistry.get_faction(pair[1]).color
		var diff := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
		assert_true(diff >= 0.15, "%s too close to %s" % [pair[0], pair[1]])


func test_hud_flags_are_side_then_national() -> void:
	assert_eq(HudModel.flags_of(FactionRegistry.get_faction(&"lithuania")).size(), 2)
	assert_eq(HudModel.flags_of(FactionRegistry.get_faction(&"belarus")).size(), 2)
	assert_eq(HudModel.flags_of(FactionRegistry.get_faction(&"poland")).size(), 2)
	assert_eq(HudModel.flags_of(FactionRegistry.get_faction(&"russia")).size(), 1)


func test_contact_battle_uses_the_formation_faction() -> void:
	var state := Data.build(Data.definition(0))
	var lt := Formation.from_placement(Data.placement(&"lt", 0, Vector2i(4, 0)))
	lt.faction = &"lithuania"
	var by := Formation.from_placement(Data.placement(&"by", 1, Vector2i(5, 0)))
	by.faction = &"belarus"
	state.formations.append(lt)
	state.formations.append(by)
	var setup: BattleSetup = ContactRules._build_setup(state, lt, by)
	assert_eq(setup.factions, [&"lithuania", &"belarus"] as Array[StringName])
	var pl := Formation.from_placement(Data.placement(&"pl", 0, Vector2i(4, 1)))
	var ru := Formation.from_placement(Data.placement(&"ru", 1, Vector2i(5, 1)))
	setup = ContactRules._build_setup(state, pl, ru)
	assert_eq(setup.factions, [&"poland", &"russia"] as Array[StringName])


func test_placement_faction_is_validated() -> void:
	var op := Data.definition()
	assert_true(Data.build(op) != null)
	op.countries[1].contribution[0].faction = &"atlantis"
	assert_true(Data.build(op) == null, "unknown faction id")
	op = Data.definition()
	op.countries[1].contribution[0].faction = &"belarus"
	assert_true(Data.build(op) == null, "faction not on the side")
	op = Data.definition()
	op.sides[0].factions = [&"poland", &"lithuania"] as Array[StringName]
	op.countries[1].contribution[0].faction = &"lithuania"
	assert_true(Data.build(op) != null, "a faction of the side is accepted")

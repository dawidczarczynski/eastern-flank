class_name ConditionsModel
extends RefCounted
## Pure view model of a side's battle conditions (TASK-099b, GDD "Battle conditions"): the lines
## of the contact notice ("Fire support 2") and whether the value is reduced against the shipped
## base. Texts are translated through TranslationServer.


## "Fire support 2", "Fire support none".
static func fire_support_text(conditions: BattleSetup.Conditions) -> String:
	var value: String = (
		str(conditions.fire_support)
		if conditions.fire_support > 0
		else TranslationServer.translate("none")
	)
	return "%s %s" % [TranslationServer.translate("Fire support"), value]


## Fire support below the base.
static func fire_support_reduced(
	conditions: BattleSetup.Conditions, rules: BattleConditionsRules = null
) -> bool:
	return conditions.fire_support < _rules(rules).fire_support_base


static func _rules(rules: BattleConditionsRules) -> BattleConditionsRules:
	return rules if rules != null else BattleConditionsRules.shipped()

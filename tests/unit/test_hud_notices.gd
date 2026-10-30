extends TestCase
## Scene tests for the HUD v3 notices (TASK-080): turn banner, toast, targeting bar and loading
## screen. Timers are plain countdowns driven by advance(), so no scene tree is needed.

const Fixtures := preload("res://tests/fixtures.gd")

var _hud: BattleHud
var _state: GameState


func before_each() -> void:
	_state = GameState.new(Fixtures.plains_grid(3), 2, 1)
	_state.add_unit(0, Fixtures.infantry(), Vector2i(-3, 0))
	_state.add_unit(1, Fixtures.infantry(), Vector2i(3, 0))
	_hud = BattleHud.new()
	_hud.setup(0)
	_hud.refresh(_state)


func after_each() -> void:
	_hud.free()


func _banner() -> TurnBanner:
	return _hud.find_child("TurnBanner", true, false) as TurnBanner


func test_turn_banner_shows_names_the_side_and_hides_after_the_timer() -> void:
	assert_false(_banner().visible)
	_hud.on_turn_started(_state, 1, 1)
	assert_true(_banner().visible)
	assert_eq(_banner().title_text(), _t("Russia").to_upper())
	assert_true(_banner().caption_text().begins_with(_t("TURN").to_upper() + " 01 // "))
	assert_eq(_banner().remaining(), TurnBanner.SECONDS)
	assert_eq(TurnBanner.SECONDS, 1.5)
	_banner().advance(1.0)
	assert_true(_banner().visible)
	_banner().advance(0.6)
	assert_false(_banner().visible)


func test_result_banner_replaces_the_turn_banner_and_stays() -> void:
	_hud.on_turn_started(_state, 1, 1)
	_state.finish(0, &"eliminated")
	_hud.refresh(_state)
	assert_true(_banner().visible)
	assert_true(_banner().held)
	assert_eq(_banner().title_text(), _t("VICTORY").to_upper())
	_banner().advance(5.0)
	assert_true(_banner().visible)
	_state.finish(-1, &"")
	_hud.refresh(_state)
	assert_false(_banner().visible)


func test_banner_ignores_the_mouse() -> void:
	for node in [_banner(), _banner().find_child("Band", true, false)]:
		assert_eq((node as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_toast_shows_restarts_and_hides() -> void:
	var toast := _hud.find_child("Toast", true, false) as Toast
	assert_false(toast.visible)
	_hud.show_toast("TARGET OUT OF RANGE")
	assert_true(toast.visible)
	assert_eq(toast.message(), _t("TARGET OUT OF RANGE"))
	toast.advance(2.0)
	_hud.show_toast("CANNOT REACH THAT TILE")  # restarts the countdown
	assert_eq(toast.remaining(), Toast.SECONDS)
	assert_eq(toast.message(), _t("CANNOT REACH THAT TILE"))
	toast.advance(2.0)
	assert_true(toast.visible)
	toast.advance(1.0)
	assert_false(toast.visible)
	assert_eq(toast.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(Toast.SECONDS, 2.8)


func test_targeting_bar_shows_hides_and_ignores_the_mouse() -> void:
	var bar := _hud.find_child("TargetingBar", true, false) as TargetingBar
	assert_false(bar.visible)
	_hud.show_targeting("BLIND FIRE", "Tank #2", "Pick a hex")
	assert_true(bar.visible)
	assert_eq(bar.title_text(), "BLIND FIRE")
	assert_eq(bar.unit_text(), "TANK #2")
	assert_eq(bar.instruction_text(), "Pick a hex")
	_hud.hide_targeting()
	assert_false(bar.visible)
	for node in [
		bar, bar.find_child("TitleBlock", true, false), bar.find_child("Hatch", true, false)
	]:
		assert_eq((node as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE)


func test_notice_strings_have_polish_translations() -> void:
	TranslationServer.set_locale("pl")
	for key in ["TARGET OUT OF RANGE", "CANNOT REACH THAT TILE", "CONFIRM", "CANCEL"]:
		assert_true(_t(key) != key, key)
	TranslationServer.set_locale("en")


func test_loading_screen_uses_the_operation_name_and_frees_itself() -> void:
	var loading := LoadingScreen.new()
	loading.set_operation("Iron Shore")
	loading.set_status("BUILDING THE BATTLEFIELD")
	assert_eq(loading.operation_text(), _t("Iron Shore").to_upper())
	assert_eq(loading.status_text(), _t("BUILDING THE BATTLEFIELD").to_upper())
	loading.set_operation("")
	assert_eq(loading.operation_text(), "EASTERN FLANK")
	loading.finish()
	assert_false(loading.visible)
	assert_true(loading.is_queued_for_deletion())
	loading.free()


func _t(key: String) -> String:
	return TranslationServer.translate(key)


func test_reject_toasts_match_command_reasons() -> void:
	var toasts: Dictionary = load("res://src/presentation/battle_controller.gd").REJECT_TOASTS
	for reason: String in toasts:
		var found := false
		for path in ["attack_command", "move_unit_command"]:
			var source := FileAccess.get_file_as_string("res://src/core/commands/%s.gd" % path)
			found = found or source.contains('return "%s"' % reason)
		assert_true(found, "no command returns the reason '%s'" % reason)

class_name StaffMapStrikeReports
extends RefCounted
## The strike result reports of the staff map (TASK-097b): the card (StaffMapStrikeReport), its
## collapsed chip (StaffMapStrikeChip), the queue and the timing of the accepted mockup. A card
## shows 0.8 s after the strike's last impact on the map (the HUD passes the delay, TASK-147; the
## launch and the flight play first), stays 9 s (hovering it pauses) and collapses to the chip;
## enemy strikes queue, 3.5 s each ("1 OF n"); the last one stays as a chip; a threshold report
## never collapses by itself. Keys: Enter / a click opens the journal at the strike line
## (TASK-148b), Esc collapse, ◂ ▸ browse; X (card or chip) dismisses the report.
## `tick` is a no-op while nothing is timed, so an idle HUD costs nothing.

signal shown  ## the card is (re)shown – the left dock hands it the place
## Enter, a click on the card or the chip: the journal opens at this report's strike line.
signal log_requested(model: Dictionary)

enum Mode { NONE, CARD, CHIP }

const OWN_SECONDS := 9.0
const ENEMY_SECONDS := 3.5
## Default reveal delay of a card (s); the strike HUD passes the real one: IMPACT_REVEAL_SECONDS
## after the last impact of the strike on the map, so the card never covers the flight (TASK-147).
const REVEAL_DELAY := 0.4
const IMPACT_REVEAL_SECONDS := 0.8
const FADE_SECONDS := 0.15
const NO_TIMEOUT := -1.0
const ORIGIN := Vector2(16, 110)
const SMALL_VIEWPORT_HEIGHT := 700.0
const NARROW_VIEWPORT_WIDTH := 1500.0

var _palette: StaffMapPalette
var _card: StaffMapStrikeReport
var _chip: StaffMapStrikeChip
var _items: Array[Dictionary] = []
var _index := -1
var _mode := Mode.NONE
var _timer := NO_TIMEOUT
var _delay := 0.0
var _fade := FADE_SECONDS
var _hover := false
var _viewport := Vector2(1280, 720)
var _top := 0.0


func _init(palette: StaffMapPalette) -> void:
	_palette = palette
	_card = StaffMapStrikeReport.new(palette)
	_chip = StaffMapStrikeChip.new(palette)
	_card.close_requested.connect(dismiss)
	_chip.close_requested.connect(dismiss)
	_chip.toggle_requested.connect(request_log)
	_card.gui_input.connect(_on_card_input)
	_chip.browse_requested.connect(browse)
	_card.mouse_entered.connect(func() -> void: _hover = true)
	_card.mouse_exited.connect(func() -> void: _hover = false)


func attach(parent: Node) -> void:
	parent.add_child(_card)
	parent.add_child(_chip)


func free_nodes() -> void:
	for node: Control in [_card, _chip]:
		if node.is_inside_tree():
			node.queue_free()
		else:
			node.free()


func card() -> StaffMapStrikeReport:
	return _card


func chip() -> StaffMapStrikeChip:
	return _chip


func count() -> int:
	return _items.size()


func index() -> int:
	return _index


func card_visible() -> bool:
	return _card.visible


func chip_visible() -> bool:
	return _chip.visible


## A new report (a StaffMapStrikeText.report_model()), revealed after `delay` s (the strike's
## impact on the map). Own reports jump in, enemy reports queue behind a card that is showing.
func add(model: Dictionary, delay := REVEAL_DELAY) -> void:
	_items.append(model)
	if model["own"] or (_delay <= 0.0 and _mode != Mode.CARD):
		_index = _items.size() - 1
		_delay = maxf(delay, 0.01)
	elif _mode == Mode.CARD:
		_card.present(_items[_index], _index, _items.size(), _index < _items.size() - 1)
		_place()  # the "k OF n" counter grows


func clear() -> void:
	_items.clear()
	_index = -1
	_delay = 0.0
	_mode = Mode.NONE
	_hover = false
	_card.hide()
	_chip.hide()


func tick(delta: float) -> void:
	if _delay > 0.0:
		_delay -= delta
		if _delay <= 0.0:
			_show(_index, _timeout_of(_index))
		return
	if _fade < FADE_SECONDS:
		_fade = minf(_fade + delta, FADE_SECONDS)
		_card.modulate.a = _fade / FADE_SECONDS
	if _mode == Mode.CARD and _timer >= 0.0 and not _hovered():
		_timer -= delta
		if _timer <= 0.0:
			_expire()


## Keys of the report; false when the key is not for it (Enter then ends the turn, Esc opens the
## menu, the arrows pan).
func handle_key(keycode: Key) -> bool:
	if _items.is_empty():
		return false
	var in_card := _mode == Mode.CARD
	match keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if in_card:
				request_log()
			return in_card
		KEY_ESCAPE:
			if in_card:
				collapse()
			return in_card
		KEY_LEFT, KEY_RIGHT:
			var browsing := in_card and _items.size() > 1
			if browsing:
				browse(-1 if keycode == KEY_LEFT else 1)
			return browsing
		_:
			return false
	return true


## J: card <-> chip (a card the player opened stays until closed).
func toggle() -> void:
	if _items.is_empty():
		return
	if _delay > 0.0:
		_delay = 0.0
		_show(_index, NO_TIMEOUT)
	elif _mode == Mode.CARD:
		collapse()
	else:
		_show(_index, NO_TIMEOUT)


## Enter / a click: asks for the journal line of the shown report.
func request_log() -> void:
	if _index >= 0 and _index < _items.size():
		log_requested.emit(_items[_index])


## Hides the card and the chip without dropping the reports (another left-dock window opened);
## The journal (or the next report) brings it back.
func suspend() -> void:
	if _items.is_empty():
		return
	_delay = 0.0
	_hover = false
	_mode = Mode.CHIP
	_card.hide()
	_chip.hide()


func collapse() -> void:
	if _items.is_empty():
		return
	_mode = Mode.CHIP
	_card.hide()
	_chip.present(_items[_index], _index, _items.size(), _chip_width())
	_place()


## X on the card or the chip: drops the shown report; the others stay as a chip.
func dismiss() -> void:
	if _items.is_empty():
		return
	_items.remove_at(_index)
	_delay = 0.0
	_hover = false
	if _items.is_empty():
		clear()
		return
	_index = mini(_index, _items.size() - 1)
	collapse()


func browse(delta: int) -> void:
	if _items.size() < 2:
		return
	_index = clampi(_index + delta, 0, _items.size() - 1)
	if _mode == Mode.CARD:
		_show(_index, NO_TIMEOUT)
	else:
		_chip.present(_items[_index], _index, _items.size(), _chip_width())
		_place()


## Places the card and the chip (top-left, under the turn bar row; above the bottom strip on a
## small window).
func layout(viewport: Vector2, top := 0.0) -> void:
	_viewport = viewport
	_top = top
	_place()


func covers(point: Vector2) -> bool:
	return (
		(_card.visible and _card.get_global_rect().has_point(point))
		or (_chip.visible and _chip.get_global_rect().has_point(point))
	)


func _on_card_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		request_log()


func _timeout_of(item_index: int) -> float:
	var item := _items[item_index]
	if item["threshold"]:
		return NO_TIMEOUT
	return OWN_SECONDS if item["own"] else ENEMY_SECONDS


func _show(item_index: int, timeout: float) -> void:
	_index = item_index
	_mode = Mode.CARD
	_timer = timeout
	_card.present(_items[item_index], item_index, _items.size(), item_index < _items.size() - 1)
	_chip.hide()
	_fade = 0.0
	_card.modulate.a = 0.0
	_place()
	shown.emit()


func _expire() -> void:
	if not _items[_index]["own"] and _index < _items.size() - 1:
		_show(_index + 1, _timeout_of(_index + 1))
	else:
		collapse()


func _hovered() -> bool:
	if _hover:
		return true
	return (
		_card.is_inside_tree()
		and _card.get_global_rect().has_point(_card.get_global_mouse_position())
	)


## The chip stays clear of the strike panel on the right (330 px + margins).
func _chip_width() -> float:
	return clampf(_viewport.x - 380.0, 160.0, StaffMapStrikeChip.MAX_WIDTH)


func _place() -> void:
	for node: Control in [_card, _chip]:
		var y := ORIGIN.y
		if _viewport.x < NARROW_VIEWPORT_WIDTH:
			y = maxf(y, _top)  # the turn bar's button row reaches further left than at 1440 px
		node.reset_size()
		if _viewport.y < SMALL_VIEWPORT_HEIGHT:
			y = maxf(8.0, _viewport.y - node.size.y - 70.0)
		node.position = Vector2(ORIGIN.x, y)

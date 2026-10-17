extends Control
## Bottom-of-screen dialogue/subtitle panel. Shows one line at a time; click
## anywhere, Enter or Space advances, Esc or Skip ends the conversation.

signal finished

const FocusGuard := preload("res://scripts/ui/focus_guard.gd")
const ADVANCE_GUARD_MS := 120

var _lines: Array = []
var _index := 0
var _opened_at := 0
var _suspended: Array = []
var _speaker: Label
var _text: Label
var _counter: Label
var _continue: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	visible = false
	gui_input.connect(_on_backdrop_input)

	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.custom_minimum_size.y = 170
	panel.grow_vertical = GROW_DIRECTION_BEGIN
	add_child(panel)
	panel.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE, PRESET_MODE_MINSIZE, 24)
	panel.offset_left = 40
	panel.offset_right = -40

	var column := VBoxContainer.new()
	column.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_speaker = Label.new()
	_speaker.theme_type_variation = "HeaderLabel"
	column.add_child(_speaker)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(_text)

	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	_counter = Label.new()
	_counter.theme_type_variation = "DimLabel"
	_counter.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_counter)
	var skip := Button.new()
	skip.text = "Skip (Esc)"
	skip.pressed.connect(skip_all)
	row.add_child(skip)
	_continue = Button.new()
	_continue.pressed.connect(advance)
	row.add_child(_continue)


func is_active() -> bool:
	return visible


func start(lines: Array) -> void:
	if lines.is_empty():
		finished.emit()
		return
	_lines = lines
	_index = 0
	visible = true
	_opened_at = Time.get_ticks_msec()
	_suspended = FocusGuard.suspend(get_parent(), self)
	_show_line()
	_continue.grab_focus()


func advance() -> void:
	if not visible or Time.get_ticks_msec() - _opened_at < ADVANCE_GUARD_MS:
		return
	_index += 1
	if _index >= _lines.size():
		_close()
	else:
		_show_line()


func skip_all() -> void:
	if visible:
		_close()


func _show_line() -> void:
	var line: Dictionary = _lines[_index]
	var speaker := ContentDB.speaker_name(str(line.get("speaker", "narrator")))
	_speaker.text = speaker
	_speaker.visible = speaker != ""
	_text.text = str(line.get("text", ""))
	_counter.text = "%d / %d" % [_index + 1, _lines.size()]
	_continue.text = "Close" if _index == _lines.size() - 1 else "Continue"


func _close() -> void:
	visible = false
	_lines = []
	FocusGuard.restore(_suspended)
	finished.emit()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		advance()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		skip_all()

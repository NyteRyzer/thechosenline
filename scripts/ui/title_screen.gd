extends Control
## Title screen: New Game, Continue, Load, Settings, Quit. Also surfaces any
## content validation errors so broken data is noticed immediately.

const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")
const SaveLoadPanel := preload("res://scripts/ui/save_load_panel.gd")

var _new_game: Button
var _continue: Button
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	GameState.in_game = false

	var background := ColorRect.new()
	background.color = Color("0a0d14")
	background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	var title := Label.new()
	title.text = "THE CHOSEN LINE"
	title.theme_type_variation = "TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var line := ColorRect.new()  # the "line": pale angelic gold
	line.color = Color("e8c87a")
	line.custom_minimum_size = Vector2(420, 2)
	line.size_flags_horizontal = SIZE_SHRINK_CENTER
	column.add_child(line)

	var subtitle := Label.new()
	subtitle.text = "A supernatural mystery"
	subtitle.theme_type_variation = "DimLabel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	column.add_child(spacer)

	_continue = _menu_button(column, "Continue", _on_continue)
	_new_game = _menu_button(column, "New Game", SceneRouter.start_new_game)
	_menu_button(column, "Load Game", func(): _open(SaveLoadPanel.new("load")))
	_menu_button(column, "Settings", func(): _open(SettingsPanel.new()))
	_menu_button(column, "Quit", SceneRouter.quit_game)
	_continue.disabled = not SaveSystem.has_any_save()

	_status = Label.new()
	_status.theme_type_variation = "DimLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 520
	column.add_child(_status)

	var footer := Label.new()
	footer.text = "Prototype %s • placeholder art and text • original work" % ProjectSettings.get_setting("application/config/version", "")
	footer.theme_type_variation = "DimLabel"
	add_child(footer)
	footer.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT, PRESET_MODE_MINSIZE, 16)

	if not ContentDB.errors.is_empty():
		_show_content_errors()

	_default_focus().call_deferred("grab_focus")


func _menu_button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.x = 300
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _default_focus() -> Button:
	return _new_game if _continue.disabled else _continue


func _open(overlay: Control) -> void:
	var opener := get_viewport().gui_get_focus_owner()
	add_child(overlay)
	overlay.closed.connect(func():
		_continue.disabled = not SaveSystem.has_any_save()
		var target: Control = opener if is_instance_valid(opener) and not (opener is BaseButton and opener.disabled) else _default_focus()
		target.grab_focus())


func _on_continue() -> void:
	var err := SceneRouter.continue_game()
	if err != OK:
		_status.text = "Could not continue: " + SaveSystem.last_error


func _show_content_errors() -> void:
	var box := PanelContainer.new()
	add_child(box)
	box.set_anchors_and_offsets_preset(PRESET_TOP_WIDE, PRESET_MODE_MINSIZE, 12)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color("ff8a80"))
	var shown := ContentDB.errors.slice(0, 4)
	label.text = "Content errors (%d) — fix the data files listed below (full list in the console):\n• %s" % [ContentDB.errors.size(), "\n• ".join(shown)]
	box.add_child(label)

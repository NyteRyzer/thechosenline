extends "res://scripts/ui/modal_overlay.gd"
## Settings: text size, contrast, hotspot highlighting, subtitles, display and
## per-category volume. Every change applies and saves immediately.

const InputBindings := preload("res://scripts/core/input_bindings.gd")
const VOLUME_LABELS := {
	"master_volume": "Master volume",
	"music_volume": "Music",
	"sfx_volume": "Effects",
	"ambience_volume": "Ambience",
	"dialogue_volume": "Dialogue",
}

var _controls := {}


func _build() -> void:
	add_title("Settings")

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	var text_size := OptionButton.new()
	for i in Settings.TEXT_SIZE_NAMES.size():
		text_size.add_item(Settings.TEXT_SIZE_NAMES[i], i)
	text_size.item_selected.connect(func(index): Settings.set_value("text_size", index))
	_add_row(grid, "Text size", text_size, "text_size")

	_add_toggle(grid, "High contrast", "high_contrast")
	_add_toggle(grid, "Always highlight objects", "hotspot_highlight")
	_add_toggle(grid, "Subtitles for spoken lines", "subtitles")
	_add_toggle(grid, "Fullscreen", "fullscreen")

	for key in VOLUME_LABELS:
		var row := HBoxContainer.new()
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.custom_minimum_size = Vector2(240, 28)
		slider.size_flags_vertical = SIZE_SHRINK_CENTER
		var readout := Label.new()
		readout.custom_minimum_size.x = 64
		slider.value_changed.connect(func(value):
			readout.text = "%d%%" % int(value)
			Settings.set_value(key, value / 100.0))
		row.add_child(slider)
		row.add_child(readout)
		_add_row(grid, VOLUME_LABELS[key], row, key)
		_controls[key] = [slider, readout]

	var controls_title := Label.new()
	controls_title.text = "Controls"
	controls_title.theme_type_variation = "HeaderLabel"
	grid.add_child(controls_title)
	grid.add_child(Control.new())
	for entry in InputBindings.DESCRIPTIONS:
		var action := Label.new()
		action.text = entry[0]
		grid.add_child(action)
		var keys := Label.new()
		keys.text = entry[1]
		keys.theme_type_variation = "DimLabel"
		grid.add_child(keys)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	add_button("Reset to Defaults", _on_reset, buttons)
	add_button("Back", close, buttons)

	_sync()
	focus_target = text_size


func _add_row(grid: GridContainer, label_text: String, control: Control, key: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(label)
	grid.add_child(control)
	_controls[key] = control


func _add_toggle(grid: GridContainer, label_text: String, key: String) -> void:
	var toggle := CheckButton.new()
	toggle.toggled.connect(func(on): Settings.set_value(key, on))
	_add_row(grid, label_text, toggle, key)


func _sync() -> void:
	_controls.text_size.select(int(Settings.get_value("text_size")))
	for key in ["high_contrast", "hotspot_highlight", "subtitles", "fullscreen"]:
		_controls[key].set_pressed_no_signal(bool(Settings.get_value(key)))
	for key in VOLUME_LABELS:
		var value := float(Settings.get_value(key)) * 100.0
		_controls[key][0].set_value_no_signal(value)
		_controls[key][1].text = "%d%%" % int(value)


func _on_reset() -> void:
	Settings.reset_to_defaults()
	_sync()

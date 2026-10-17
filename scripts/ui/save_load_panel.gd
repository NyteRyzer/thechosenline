extends "res://scripts/ui/modal_overlay.gd"
## Save or load screen. Lists slots with room, chapter, playtime and date.
## Overwriting a used slot needs a second press to confirm.

var mode := "load"
var _rows: VBoxContainer
var _status: Label
var _slot_buttons := {}
var _armed_slot := ""


func _init(p_mode: String = "load") -> void:
	mode = p_mode


func _build() -> void:
	add_title("Save Game" if mode == "save" else "Load Game")
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	content.add_child(_rows)
	_status = add_wrapped_label("", 640, "DimLabel")
	var back := add_button("Back", close)
	_refresh("")
	if focus_target == null:
		focus_target = back


func _refresh(focus_slot: String) -> void:
	for child in _rows.get_children():
		child.queue_free()
	_slot_buttons.clear()
	var slots: Array[String] = SaveSystem.MANUAL_SLOTS if mode == "save" else SaveSystem.all_slots()
	for slot in slots:
		var info := SaveSystem.slot_info(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = "%s — %s" % [info.label, info.description]
		label.custom_minimum_size.x = 560
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size.x = 140
		if mode == "save":
			button.text = "Overwrite?" if slot == _armed_slot else "Save"
		else:
			button.text = "Load"
			button.disabled = not info.valid
		button.pressed.connect(_on_slot_pressed.bind(slot, info.exists))
		row.add_child(button)
		_rows.add_child(row)
		_slot_buttons[slot] = button
		if focus_target == null and not button.disabled:
			focus_target = button
	if _slot_buttons.has(focus_slot):
		_slot_buttons[focus_slot].call_deferred("grab_focus")


func _on_slot_pressed(slot: String, exists: bool) -> void:
	if mode == "load":
		if SceneRouter.load_slot(slot) != OK:
			_status.text = "Could not load: " + SaveSystem.last_error
		return
	if exists and _armed_slot != slot:
		_armed_slot = slot
		_status.text = "%s already has a save. Press Overwrite? again to replace it." % SaveSystem.slot_label(slot)
		_refresh(slot)
		return
	_armed_slot = ""
	if SaveSystem.save_game(slot) == OK:
		_status.text = "Saved to %s." % SaveSystem.slot_label(slot)
	else:
		_status.text = "Save failed: " + SaveSystem.last_error
	_refresh(slot)

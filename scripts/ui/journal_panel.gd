extends "res://scripts/ui/modal_overlay.gd"
## Journal: current objective plus every evidence card the player has found.
## Evidence is journaled automatically, so nothing essential can be lost.

signal deduction_requested

var _card_title: Label
var _card_text: Label


func _build() -> void:
	close_actions.append("toggle_journal")
	add_title("Journal")
	var objective := ContentDB.current_objective(GameState)
	if objective != "":
		add_wrapped_label("Objective: " + objective, 700)
	content.add_child(HSeparator.new())

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	content.add_child(columns)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(400, 220)
	columns.add_child(card)
	var card_box := VBoxContainer.new()
	card.add_child(card_box)
	_card_title = Label.new()
	_card_title.theme_type_variation = "HeaderLabel"
	_card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_box.add_child(_card_title)
	_card_text = Label.new()
	_card_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_text.custom_minimum_size.x = 360
	card_box.add_child(_card_text)

	if GameState.evidence.is_empty():
		_card_title.text = "No evidence yet"
		_card_text.text = "Examine the house. Anything important is recorded here automatically."
	for i in GameState.evidence.size():
		var evidence_id: String = GameState.evidence[i]
		var button := Button.new()
		button.text = "%d. %s" % [i + 1, ContentDB.evidence_title(evidence_id)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_entered.connect(_show.bind(evidence_id))
		button.mouse_entered.connect(_show.bind(evidence_id))
		list.add_child(button)
		if focus_target == null:
			focus_target = button
			_show(evidence_id)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	add_button("Open Deduction Board (B)", _on_deduction_pressed, buttons)
	var close_button := add_button("Close", close, buttons)
	if focus_target == null:
		focus_target = close_button


func _on_deduction_pressed() -> void:
	close()
	deduction_requested.emit()


func _show(evidence_id: String) -> void:
	var entry: Dictionary = ContentDB.evidence.get(evidence_id, {})
	_card_title.text = str(entry.get("title", evidence_id))
	_card_text.text = str(entry.get("text", ""))

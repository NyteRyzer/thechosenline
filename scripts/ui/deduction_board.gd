extends "res://scripts/ui/modal_overlay.gd"
## Deduction board: pick what really happened, connect the evidence that
## proves it, then press Connect. A wrong attempt shows a hint; a right one
## applies the deduction's effects and emits `solved`.

signal solved(deduction_id: String, result: Dictionary)

const DeductionLogic := preload("res://scripts/interactions/deduction_logic.gd")
const InteractionResolver := preload("res://scripts/interactions/interaction_resolver.gd")

var _deduction: Dictionary
var _answer := ""
var _evidence_toggles := {}
var _answer_toggles := {}
var _feedback: Label


func _build() -> void:
	close_actions.append("toggle_deduction")
	_deduction = ContentDB.next_deduction(GameState)
	add_title("Deduction Board")
	if _deduction.is_empty():
		add_wrapped_label("Everything here is already worked out. There's nothing left to piece together for now.", 640)
		focus_target = add_button("Close", close)
		return

	var question := Label.new()
	question.text = str(_deduction.title)
	question.add_theme_color_override("font_color", Color("e8c87a"))
	content.add_child(question)
	add_wrapped_label(str(_deduction.prompt), 900, "DimLabel")

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	content.add_child(columns)

	var answers := _column(columns, "1. What really happened?", 440)
	var group := ButtonGroup.new()
	for answer in _deduction.answers:
		var option := CheckBox.new()
		option.text = str(answer.text)
		option.button_group = group
		option.toggled.connect(func(on): if on: _answer = str(answer.id))
		answers.add_child(option)
		_answer_toggles[str(answer.id)] = option
		if focus_target == null:
			focus_target = option

	var cards := _column(columns, "2. Which evidence proves it?", 400)
	if GameState.evidence.is_empty():
		var none := Label.new()
		none.text = "No evidence yet."
		none.theme_type_variation = "DimLabel"
		cards.add_child(none)
	for evidence_id in GameState.evidence:
		var toggle := CheckBox.new()
		toggle.text = ContentDB.evidence_title(evidence_id)
		toggle.tooltip_text = str(ContentDB.evidence.get(evidence_id, {}).get("text", ""))
		cards.add_child(toggle)
		_evidence_toggles[evidence_id] = toggle

	_feedback = add_wrapped_label("", 860)
	_feedback.add_theme_color_override("font_color", Color("ffb08a"))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	add_button("Connect the Evidence", _on_connect, buttons)
	add_button("Close", close, buttons)


func _column(parent: Control, heading: String, width: float) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = width
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	var label := Label.new()
	label.text = heading
	label.theme_type_variation = "HeaderLabel"
	column.add_child(label)
	return column


func connected_evidence() -> Array:
	var out := []
	for evidence_id in _evidence_toggles:
		if _evidence_toggles[evidence_id].button_pressed:
			out.append(evidence_id)
	return out


## Used by the UI and by tests: selects an answer and evidence, then connects.
func attempt(answer_id: String, evidence_ids: Array) -> bool:
	_answer = answer_id
	if _answer_toggles.has(answer_id):
		_answer_toggles[answer_id].button_pressed = true
	for evidence_id in _evidence_toggles:
		_evidence_toggles[evidence_id].button_pressed = evidence_ids.has(evidence_id)
	return _on_connect()


func _on_connect() -> bool:
	var verdict := DeductionLogic.evaluate(_deduction, _answer, connected_evidence(), Array(GameState.evidence))
	if not verdict.correct:
		_feedback.text = verdict.feedback
		AudioManager.play_sfx("wrong")
		return false
	var result := InteractionResolver.new_result()
	var resolver := InteractionResolver.new(GameState, ContentDB)
	GameState.set_flag(ContentDB.solved_flag(str(_deduction.id)), true)
	resolver.apply_effects(_deduction.get("effects", []), result)
	if _deduction.has("success_dialogue"):
		result.lines = ContentDB.dialogue_lines(str(_deduction.success_dialogue))
	var id := str(_deduction.id)
	close()
	solved.emit(id, result)
	return true

extends Control
## Base for modal panels (pause, settings, inventory, journal, save/load).
## Dims the screen, blocks clicks behind it, keeps keyboard focus inside and
## closes on Esc. Subclasses fill `content` in _build() and set focus_target.

signal closed

const FocusGuard := preload("res://scripts/ui/focus_guard.gd")

var panel: PanelContainer
var content: VBoxContainer
var close_actions: Array[String] = ["ui_cancel"]
var focus_target: Control = null
var _suspended: Array = []
var _closing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

	panel = PanelContainer.new()
	center.add_child(panel)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	panel.add_child(content)

	_suspended = FocusGuard.suspend(get_parent(), self)
	_build()
	if focus_target:
		focus_target.call_deferred("grab_focus")


## Override to add controls to `content`.
func _build() -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	for action in close_actions:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			close()
			return


func close() -> void:
	if _closing:
		return
	_closing = true
	FocusGuard.restore(_suspended)
	closed.emit()
	queue_free()


## Opens another overlay on top of this one and refocuses the opener when it closes.
func open_child(overlay: Control) -> void:
	var opener := get_viewport().gui_get_focus_owner()
	add_child(overlay)
	overlay.closed.connect(func():
		if is_instance_valid(opener) and opener.is_inside_tree():
			opener.grab_focus())


func add_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "HeaderLabel"
	content.add_child(label)
	return label


func add_button(text: String, callback: Callable, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	(parent if parent else content).add_child(button)
	return button


func add_wrapped_label(text: String, min_width: float = 480.0, variation: String = "") -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = min_width
	label.theme_type_variation = variation
	content.add_child(label)
	return label

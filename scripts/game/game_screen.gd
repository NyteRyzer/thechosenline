extends Control
## In-game screen. Owns the room view, HUD, dialogue panel and menus, and
## routes player input to the interaction resolver. Holds no story data.

const RoomView := preload("res://scripts/rooms/room_view.gd")
const DialoguePanel := preload("res://scripts/ui/dialogue_panel.gd")
const InventoryPanel := preload("res://scripts/ui/inventory_panel.gd")
const JournalPanel := preload("res://scripts/ui/journal_panel.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")
const DebugOverlay := preload("res://scripts/ui/debug_overlay.gd")
const InteractionResolver := preload("res://scripts/interactions/interaction_resolver.gd")
const FADE_SECONDS := 0.25
const TOAST_SECONDS := 3.0

var _resolver: RefCounted
var _room_view: Control
var _dialogue: Control
var _debug: Control
var _room_label: Label
var _item_label: Label
var _prompt_panel: PanelContainer
var _prompt: Label
var _toasts: VBoxContainer
var _fade: ColorRect
var _overlay: Control = null
var _transitioning := false
var _pending_room := ""
var _hovered_id := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_resolver = InteractionResolver.new(GameState, ContentDB)
	_build_ui()
	GameState.item_added.connect(func(id): _toast("Picked up: %s   (Inventory: I)" % ContentDB.item_name(id), ContentDB.item_icon(id)))
	GameState.evidence_added.connect(func(id): _toast("Journal updated: %s   (Journal: J)" % ContentDB.evidence_title(id)))
	GameState.selected_item_changed.connect(func(_id): _refresh_hud())
	GameState.in_game = true
	_enter_room(GameState.current_room_id, SceneRouter.last_entry == "load")


func _exit_tree() -> void:
	GameState.in_game = false


func _process(_delta: float) -> void:
	_room_view.highlight_all = bool(Settings.get_value("hotspot_highlight")) or Input.is_action_pressed("highlight_hotspots")


func _input(event: InputEvent) -> void:
	# Right-click cancels a selected item before any hotspot can consume the click.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if GameState.selected_item != "" and not _is_blocked():
			GameState.select_item("")
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug.toggle()
		get_viewport().set_input_as_handled()
		return
	if _is_blocked():
		return
	if event.is_action_pressed("pause_menu"):
		if GameState.selected_item != "":
			GameState.select_item("")
		else:
			_open_overlay(PauseMenu.new())
	elif event.is_action_pressed("toggle_inventory"):
		_open_overlay(InventoryPanel.new())
	elif event.is_action_pressed("toggle_journal"):
		_open_overlay(JournalPanel.new())
	else:
		return
	get_viewport().set_input_as_handled()


# --- Rooms -----------------------------------------------------------------

func _enter_room(room_id: String, from_save: bool) -> void:
	var room := ContentDB.get_room(room_id)
	if room.is_empty():
		push_error("[GameScreen] Room '%s' does not exist; falling back to the start room." % room_id)
		room_id = ContentDB.start_room()
		GameState.goto_room(room_id)
		room = ContentDB.get_room(room_id)
	_room_view.build(room)
	_room_view.refresh_visited()
	_room_label.text = str(room.get("name", room_id))
	_refresh_hud()
	_update_prompt("")

	var on_enter: Dictionary = room.get("on_enter", {})
	var once_flag := str(on_enter.get("once_flag", ""))
	var intro: Array = []
	if on_enter.has("dialogue") and (once_flag == "" or not GameState.has_flag(once_flag)):
		if once_flag != "":
			GameState.set_flag(once_flag, true)
		intro = ContentDB.dialogue_lines(str(on_enter.dialogue))
	if not from_save:
		_autosave()
	if intro.is_empty():
		_room_view.call_deferred("focus_hotspot")
	else:
		_show_lines(intro)


func _transition_to(room_id: String) -> void:
	_transitioning = true
	_fade.visible = true
	_fade.mouse_filter = MOUSE_FILTER_STOP
	var fade_out := create_tween()
	fade_out.tween_property(_fade, "color:a", 1.0, FADE_SECONDS)
	await fade_out.finished
	GameState.goto_room(room_id)
	_enter_room(room_id, false)
	var fade_in := create_tween()
	fade_in.tween_property(_fade, "color:a", 0.0, FADE_SECONDS)
	await fade_in.finished
	_fade.visible = false
	_fade.mouse_filter = MOUSE_FILTER_IGNORE
	_transitioning = false


func _autosave() -> void:
	if SaveSystem.save_game(SaveSystem.AUTOSAVE_SLOT) != OK:
		_toast("Autosave failed: " + SaveSystem.last_error)


# --- Interaction -----------------------------------------------------------

func _on_hotspot_activated(hotspot_id: String) -> void:
	if _is_blocked():
		return
	var used_item := GameState.selected_item
	var result: Dictionary = _resolver.interact(GameState.current_room_id, hotspot_id, used_item)
	if used_item != "":
		GameState.select_item("")
	_room_view.refresh_visited()
	_pending_room = result.goto_room
	if result.lines.is_empty():
		_on_dialogue_finished()
	else:
		_show_lines(result.lines)


func _show_lines(lines: Array) -> void:
	_prompt_panel.visible = false
	_dialogue.start(lines)


func _on_dialogue_finished() -> void:
	if _pending_room != "":
		var target := _pending_room
		_pending_room = ""
		_transition_to(target)
		return
	_update_prompt(_hovered_id)
	_room_view.focus_hotspot()


func _update_prompt(hotspot_id: String) -> void:
	_hovered_id = hotspot_id
	if hotspot_id == "" or _dialogue.is_active():
		_prompt_panel.visible = false
		return
	var target: String = _room_view.hotspot_name(hotspot_id)
	if GameState.selected_item != "":
		_prompt.text = "Use %s on %s" % [ContentDB.item_name(GameState.selected_item), target]
	else:
		_prompt.text = target
	_prompt_panel.visible = true


# --- Overlays & HUD --------------------------------------------------------

func _is_blocked() -> bool:
	return _transitioning or _dialogue.is_active() or (_overlay != null and is_instance_valid(_overlay))


func _open_overlay(overlay: Control) -> void:
	if _is_blocked():
		return
	_overlay = overlay
	add_child(overlay)
	overlay.closed.connect(_on_overlay_closed)


func _on_overlay_closed() -> void:
	_overlay = null
	_refresh_hud()
	_update_prompt(_hovered_id)
	_room_view.call_deferred("focus_hotspot")


func _refresh_hud() -> void:
	if GameState.selected_item == "":
		_item_label.text = ""
	else:
		_item_label.text = "Using: %s — click an object (right-click/Esc cancels)" % ContentDB.item_name(GameState.selected_item)
	_update_prompt(_hovered_id)


func _toast(text: String, icon: Texture2D = null) -> void:
	var box := PanelContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	if icon:
		var picture := TextureRect.new()
		picture.texture = icon
		picture.custom_minimum_size = Vector2(48, 48)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.texture_filter = TEXTURE_FILTER_NEAREST
		row.add_child(picture)
	var label := Label.new()
	label.text = text
	label.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(label)
	_toasts.add_child(box)
	var tween := create_tween()
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(box, "modulate:a", 0.0, 0.5)
	tween.tween_callback(box.queue_free)


func _build_ui() -> void:
	_room_view = RoomView.new()
	add_child(_room_view)
	_room_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_room_view.hotspot_activated.connect(_on_hotspot_activated)
	_room_view.hotspot_focus_changed.connect(_update_prompt)

	var hud := PanelContainer.new()
	add_child(hud)
	hud.set_anchors_and_offsets_preset(PRESET_TOP_WIDE, PRESET_MODE_MINSIZE, 10)
	var hud_row := HBoxContainer.new()
	hud_row.add_theme_constant_override("separation", 12)
	hud.add_child(hud_row)
	_room_label = Label.new()
	_room_label.theme_type_variation = "HeaderLabel"
	hud_row.add_child(_room_label)
	_item_label = Label.new()
	_item_label.size_flags_horizontal = SIZE_EXPAND_FILL
	_item_label.clip_text = true
	_item_label.add_theme_color_override("font_color", Color("e8c87a"))
	hud_row.add_child(_item_label)
	for entry in [["Inventory (I)", InventoryPanel], ["Journal (J)", JournalPanel], ["Menu (Esc)", PauseMenu]]:
		var button := Button.new()
		button.text = entry[0]
		var panel_script: GDScript = entry[1]
		button.pressed.connect(func(): _open_overlay(panel_script.new()))
		hud_row.add_child(button)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.mouse_filter = MOUSE_FILTER_IGNORE
	_prompt_panel.visible = false
	_prompt_panel.grow_horizontal = GROW_DIRECTION_BOTH
	_prompt_panel.grow_vertical = GROW_DIRECTION_BEGIN
	add_child(_prompt_panel)
	_prompt_panel.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM, PRESET_MODE_MINSIZE, 40)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt)

	_dialogue = DialoguePanel.new()
	add_child(_dialogue)
	_dialogue.finished.connect(_on_dialogue_finished)

	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = MOUSE_FILTER_IGNORE
	_toasts.grow_horizontal = GROW_DIRECTION_BEGIN
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	add_child(_toasts)
	_toasts.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT, PRESET_MODE_MINSIZE, 16)
	_toasts.offset_top = 90

	_debug = DebugOverlay.new()
	add_child(_debug)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.visible = false
	_fade.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_fade)
	_fade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

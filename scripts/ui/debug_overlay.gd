extends PanelContainer
## Developer overlay (F3): room, chapter, selected item, inventory, evidence
## and flag IDs. Read-only view of GameState.

const REFRESH_SECONDS := 0.25

var _label: Label
var _elapsed := 0.0


func _ready() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE
	position = Vector2(12, 84)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 520
	add_child(_label)


func toggle() -> void:
	visible = not visible
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed >= REFRESH_SECONDS:
		_elapsed = 0.0
		_refresh()


func _refresh() -> void:
	var flag_text := PackedStringArray()
	var keys := GameState.flags.keys()
	keys.sort()
	for key in keys:
		flag_text.append("%s=%s" % [key, GameState.flags[key]])
	_label.text = "\n".join([
		"DEBUG (F3)",
		"room: %s    chapter: %d    playtime: %s" % [GameState.current_room_id, GameState.chapter, SaveSystem.format_playtime(GameState.playtime_seconds)],
		"selected item: %s" % (GameState.selected_item if GameState.selected_item != "" else "-"),
		"inventory: %s" % ", ".join(PackedStringArray(GameState.inventory)),
		"evidence: %s" % ", ".join(PackedStringArray(GameState.evidence)),
		"flags: %s" % ", ".join(flag_text),
		"content: %d errors, %d warnings" % [ContentDB.errors.size(), ContentDB.warnings.size()],
	])

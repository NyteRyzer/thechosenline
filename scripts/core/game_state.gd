extends Node
## Central, UI-independent game state: room, chapter, inventory, evidence,
## flags and relationships. Everything that is saved lives here.

signal item_added(item_id: String)
signal item_removed(item_id: String)
signal evidence_added(evidence_id: String)
signal flag_changed(flag_id: String, value: Variant)
signal room_changed(room_id: String)
signal selected_item_changed(item_id: String)
signal state_reset

var current_room_id: String = ""
var chapter: int = 1
var inventory: Array[String] = []
var evidence: Array[String] = []
var flags: Dictionary = {}
var relationships: Dictionary = {}
var playtime_seconds: float = 0.0
## Item the player picked in the inventory to use on the next hotspot. Not saved.
var selected_item: String = ""
var in_game: bool = false


func _process(delta: float) -> void:
	if in_game:
		playtime_seconds += delta


func new_game() -> void:
	reset()
	current_room_id = ContentDB.start_room()
	chapter = int(ContentDB.game_config.get("start_chapter", 1))


func reset() -> void:
	current_room_id = ""
	chapter = 1
	inventory.clear()
	evidence.clear()
	flags.clear()
	relationships.clear()
	playtime_seconds = 0.0
	selected_item = ""
	state_reset.emit()


# --- Inventory -------------------------------------------------------------

func has_item(item_id: String) -> bool:
	return inventory.has(item_id)


func give_item(item_id: String) -> bool:
	if inventory.has(item_id):
		return false
	inventory.append(item_id)
	item_added.emit(item_id)
	return true


func remove_item(item_id: String) -> bool:
	if not inventory.has(item_id):
		return false
	inventory.erase(item_id)
	if selected_item == item_id:
		select_item("")
	item_removed.emit(item_id)
	return true


func select_item(item_id: String) -> void:
	if item_id != "" and not has_item(item_id):
		return
	if selected_item == item_id:
		return
	selected_item = item_id
	selected_item_changed.emit(item_id)


# --- Evidence --------------------------------------------------------------

func has_evidence(evidence_id: String) -> bool:
	return evidence.has(evidence_id)


func add_evidence(evidence_id: String) -> bool:
	if evidence.has(evidence_id):
		return false
	evidence.append(evidence_id)
	evidence_added.emit(evidence_id)
	return true


# --- Flags -----------------------------------------------------------------

func set_flag(flag_id: String, value: Variant = true) -> void:
	var old = flags.get(flag_id)
	if typeof(old) == typeof(value) and old == value:
		return
	flags[flag_id] = value
	flag_changed.emit(flag_id, value)


func get_flag(flag_id: String, default: Variant = null) -> Variant:
	return flags.get(flag_id, default)


## Flags are truthy when true, non-zero, or a non-empty string.
func has_flag(flag_id: String) -> bool:
	var value = flags.get(flag_id)
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value != 0
		TYPE_STRING:
			return value != ""
		TYPE_NIL:
			return false
	return true


# --- Rooms -----------------------------------------------------------------

func goto_room(room_id: String) -> void:
	current_room_id = room_id
	room_changed.emit(room_id)


# --- Serialization ---------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"current_room_id": current_room_id,
		"chapter": chapter,
		"inventory": Array(inventory),
		"evidence": Array(evidence),
		"flags": flags.duplicate(true),
		"relationships": relationships.duplicate(true),
		"playtime_seconds": playtime_seconds,
	}


## Restores state from a save. Missing fields fall back to defaults and IDs
## that no longer exist in content are dropped. Returns human-readable warnings.
func apply_dict(data: Dictionary) -> PackedStringArray:
	reset()
	var notes := PackedStringArray()

	var room := str(data.get("current_room_id", ""))
	if not ContentDB.rooms.has(room):
		notes.append("Saved room '%s' no longer exists; starting at '%s'." % [room, ContentDB.start_room()])
		room = ContentDB.start_room()
	current_room_id = room
	chapter = int(data.get("chapter", 1))

	for raw in _as_array(data.get("inventory")):
		var item_id := str(raw)
		if not ContentDB.items.has(item_id):
			notes.append("Dropped unknown item '%s' from save." % item_id)
		elif not inventory.has(item_id):
			inventory.append(item_id)

	for raw in _as_array(data.get("evidence")):
		var evidence_id := str(raw)
		if not ContentDB.evidence.has(evidence_id):
			notes.append("Dropped unknown evidence '%s' from save." % evidence_id)
		elif not evidence.has(evidence_id):
			evidence.append(evidence_id)

	var saved_flags = data.get("flags")
	if saved_flags is Dictionary:
		flags = saved_flags.duplicate(true)
	var saved_relationships = data.get("relationships")
	if saved_relationships is Dictionary:
		relationships = saved_relationships.duplicate(true)
	playtime_seconds = float(data.get("playtime_seconds", 0.0))
	return notes


func _as_array(value) -> Array:
	return value if value is Array else []

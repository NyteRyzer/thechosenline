extends Node
## Versioned JSON save slots in user://saves. Loading tolerates missing
## optional fields and content IDs that were renamed or removed since saving.

signal game_saved(slot: String)
signal game_loaded(slot: String)

const SAVE_VERSION := 1
const AUTOSAVE_SLOT := "autosave"
const MANUAL_SLOTS: Array[String] = ["slot_1", "slot_2", "slot_3"]

var save_dir := "user://saves"
var last_error := ""
var last_warnings := PackedStringArray()


func all_slots() -> Array[String]:
	var slots: Array[String] = [AUTOSAVE_SLOT]
	slots.append_array(MANUAL_SLOTS)
	return slots


func slot_path(slot: String) -> String:
	return save_dir.path_join(slot + ".json")


func slot_label(slot: String) -> String:
	if slot == AUTOSAVE_SLOT:
		return "Autosave"
	return "Slot " + slot.trim_prefix("slot_")


func save_game(slot: String) -> Error:
	last_error = ""
	if not all_slots().has(slot):
		last_error = "Unknown save slot '%s'." % slot
		return ERR_INVALID_PARAMETER
	var dir_err := DirAccess.make_dir_recursive_absolute(save_dir)
	if dir_err != OK:
		last_error = "Could not create save folder %s (error %d)." % [ProjectSettings.globalize_path(save_dir), dir_err]
		return dir_err

	var room: Dictionary = ContentDB.get_room(GameState.current_room_id)
	var data := {
		"save_version": SAVE_VERSION,
		"game": "the_chosen_line",
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"saved_unix": Time.get_unix_time_from_system(),
		"summary": {
			"room_name": room.get("name", GameState.current_room_id),
			"chapter": GameState.chapter,
			"playtime_seconds": GameState.playtime_seconds,
		},
		"state": GameState.to_dict(),
	}

	# Write to a temp file first so a crash mid-write never corrupts a slot.
	var path := slot_path(slot)
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		var open_err := FileAccess.get_open_error()
		last_error = "Could not write %s (error %d)." % [ProjectSettings.globalize_path(tmp_path), open_err]
		return open_err
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		err = DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		last_error = "Could not finalize save %s (error %d)." % [ProjectSettings.globalize_path(path), err]
		return err
	game_saved.emit(slot)
	return OK


func load_game(slot: String) -> Error:
	last_error = ""
	last_warnings = PackedStringArray()
	if not FileAccess.file_exists(slot_path(slot)):
		last_error = "%s is empty." % slot_label(slot)
		return ERR_FILE_NOT_FOUND
	var data := read_save(slot)
	if data.has("_error"):
		last_error = data._error
		return ERR_PARSE_ERROR
	data = migrate(data)
	if data.has("_error"):
		last_error = data._error
		return ERR_FILE_UNRECOGNIZED
	var state = data.get("state")
	if not state is Dictionary:
		last_error = "%s is damaged: it has no game state." % slot_label(slot)
		return ERR_FILE_CORRUPT
	last_warnings = GameState.apply_dict(state)
	for warning in last_warnings:
		push_warning("[SaveSystem] " + warning)
	game_loaded.emit(slot)
	return OK


## Parsed save contents, {} if the slot is empty, or {"_error": ...} if unreadable.
func read_save(slot: String) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {"_error": "%s is corrupted (not valid save data)." % slot_label(slot)}
	return json.data


## Upgrades older save layouts to SAVE_VERSION. Add a step here whenever the
## save format changes so old saves keep loading.
func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("save_version", 0))
	if version > SAVE_VERSION:
		data["_error"] = "This save was made by a newer version of the game (save v%d, this build reads up to v%d)." % [version, SAVE_VERSION]
		return data
	if version < 1:
		# v0: early prototype saves stored the state at the top level.
		if not data.has("state"):
			data = {"state": data.duplicate()}
		data["save_version"] = 1
	return data


func slot_info(slot: String) -> Dictionary:
	var info := {"slot": slot, "label": slot_label(slot), "exists": false, "valid": false, "description": "Empty", "saved_unix": 0.0}
	if not FileAccess.file_exists(slot_path(slot)):
		return info
	info.exists = true
	var data := read_save(slot)
	if data.has("_error"):
		info.description = "Damaged save"
		return info
	var summary = data.get("summary", {})
	if not summary is Dictionary:
		summary = {}
	info.valid = true
	info.saved_unix = float(data.get("saved_unix", 0.0))
	info.description = "%s • Chapter %d • %s played • %s" % [
		summary.get("room_name", "?"),
		int(summary.get("chapter", 1)),
		format_playtime(float(summary.get("playtime_seconds", 0.0))),
		str(data.get("saved_at", "")).replace("T", " "),
	]
	return info


func has_any_save() -> bool:
	return most_recent_slot() != ""


func most_recent_slot() -> String:
	var best := ""
	var best_time := -1.0
	for slot in all_slots():
		var info := slot_info(slot)
		if info.valid and info.saved_unix > best_time:
			best = slot
			best_time = info.saved_unix
	return best


func delete_slot(slot: String) -> Error:
	if not FileAccess.file_exists(slot_path(slot)):
		return ERR_FILE_NOT_FOUND
	return DirAccess.remove_absolute(slot_path(slot))


static func format_playtime(seconds: float) -> String:
	var total := int(seconds)
	if total >= 3600:
		return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]
	return "%d:%02d" % [total / 60, total % 60]

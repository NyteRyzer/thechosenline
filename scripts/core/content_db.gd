extends Node
## Loads all data-driven content (rooms, items, evidence, dialogue, characters)
## from res://data and validates every cross reference at startup.
## Errors name the file and ID to fix; they are printed and shown on the title screen.

const DATA_ROOT := "res://data"
const SCREEN_RECT := Rect2(0, 0, 1280, 720)
const MIN_HOTSPOT_SIZE := 48.0
const EFFECT_TYPES := ["give_item", "remove_item", "add_evidence", "set_flag", "goto_room", "play_sound", "end_chapter"]
const SFX_DIR := "res://assets/audio/sfx/"
const RULE_KEYS := [
	"use_item", "requires_flags", "requires_absent_flags", "requires_items",
	"requires_absent_items", "requires_evidence", "requires_absent_evidence",
	"lines", "dialogue", "effects", "note",
]

var game_config: Dictionary = {}
var rooms: Dictionary = {}
var items: Dictionary = {}
var evidence: Dictionary = {}
var dialogues: Dictionary = {}
var characters: Dictionary = {}
var deductions: Dictionary = {}
var errors := PackedStringArray()
var warnings := PackedStringArray()


func _ready() -> void:
	reload()


func reload() -> void:
	for collection in [rooms, items, evidence, dialogues, characters, deductions]:
		collection.clear()
	errors = PackedStringArray()
	warnings = PackedStringArray()

	var config = _read_json(DATA_ROOT.path_join("game.json"))
	game_config = config if config is Dictionary else {}
	_load_folder("items", "items", items)
	_load_folder("evidence", "evidence", evidence)
	_load_folder("characters", "characters", characters)
	_load_folder("dialogue", "dialogues", dialogues)
	_load_folder("rooms", "rooms", rooms)
	_load_folder("deductions", "deductions", deductions)
	validate()

	for message in errors:
		push_error("[ContentDB] " + message)
	for message in warnings:
		push_warning("[ContentDB] " + message)
	print("[ContentDB] Loaded %d rooms, %d items, %d evidence, %d deductions, %d dialogues, %d characters (%d errors, %d warnings)." % [
		rooms.size(), items.size(), evidence.size(), deductions.size(), dialogues.size(), characters.size(),
		errors.size(), warnings.size(),
	])


# --- Lookups ---------------------------------------------------------------

func start_room() -> String:
	return str(game_config.get("start_room", ""))


func chapter(chapter_id: String) -> Dictionary:
	for entry in game_config.get("chapters", []):
		if str(entry.get("id", "")) == chapter_id:
			return entry
	return {}


## The first deduction the player has not solved yet ({} when all are solved).
func next_deduction(state: Node) -> Dictionary:
	var ids := deductions.keys()
	ids.sort()
	for id in ids:
		if not state.has_flag(solved_flag(id)):
			return deductions[id]
	return {}


static func solved_flag(deduction_id: String) -> String:
	return "solved_" + deduction_id


func get_room(room_id: String) -> Dictionary:
	return rooms.get(room_id, {})


func find_hotspot(room_id: String, hotspot_id: String) -> Dictionary:
	for hotspot in get_room(room_id).get("hotspots", []):
		if str(hotspot.get("id", "")) == hotspot_id:
			return hotspot
	return {}


func item_name(item_id: String) -> String:
	return str(items.get(item_id, {}).get("name", item_id))


func evidence_title(evidence_id: String) -> String:
	return str(evidence.get(evidence_id, {}).get("title", evidence_id))


func speaker_name(character_id: String) -> String:
	return str(characters.get(character_id, {}).get("name", character_id))


func dialogue_lines(dialogue_id: String) -> Array:
	return _normalize_lines(dialogues.get(dialogue_id, {}).get("lines", []))


## Lines for an interaction rule: a referenced dialogue first, then inline lines.
func lines_for(rule: Dictionary) -> Array:
	var out: Array = []
	if rule.has("dialogue"):
		out.append_array(dialogue_lines(str(rule.dialogue)))
	out.append_array(_normalize_lines(rule.get("lines", [])))
	return out


## The newest objective whose requires_flag is set and whose until_flag is not.
func current_objective(state: Node) -> String:
	var text := ""
	for objective in game_config.get("objectives", []):
		var requires := str(objective.get("requires_flag", ""))
		var until := str(objective.get("until_flag", ""))
		if requires != "" and not state.has_flag(requires):
			continue
		if until != "" and state.has_flag(until):
			continue
		text = str(objective.get("text", ""))
	return text


# --- Loading ---------------------------------------------------------------

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("Missing content file %s." % path)
		return null
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		errors.append("%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _load_folder(folder: String, key: String, target: Dictionary) -> void:
	var dir_path := DATA_ROOT.path_join(folder)
	var files := Array(DirAccess.get_files_at(dir_path))
	files.sort()
	var found := false
	for file in files:
		if not str(file).ends_with(".json"):
			continue
		found = true
		var path := dir_path.path_join(file)
		var data = _read_json(path)
		if data == null:
			continue
		if not (data is Dictionary and data.get(key) is Array):
			errors.append("%s: expected a top-level \"%s\" array." % [path, key])
			continue
		for entry in data[key]:
			if not entry is Dictionary:
				errors.append("%s: every entry in \"%s\" must be an object." % [path, key])
				continue
			var id := str(entry.get("id", ""))
			if id == "":
				errors.append("%s: an entry in \"%s\" is missing its \"id\"." % [path, key])
				continue
			if target.has(id):
				errors.append("%s: duplicate id '%s' (already defined in %s)." % [path, id, target[id]._source])
				continue
			entry["_source"] = path
			target[id] = entry
	if not found:
		errors.append("No .json content files found in %s." % dir_path)


func _normalize_lines(lines) -> Array:
	var out: Array = []
	if not lines is Array:
		return out
	for line in lines:
		if line is String:
			out.append({"speaker": "narrator", "text": line})
		elif line is Dictionary:
			out.append({"speaker": str(line.get("speaker", "narrator")), "text": str(line.get("text", ""))})
	return out


# --- Validation ------------------------------------------------------------

func validate() -> void:
	var start := start_room()
	if not rooms.has(start):
		errors.append("data/game.json: start_room '%s' is not a defined room id." % start)

	for id in items:
		_require_fields(items[id], ["name", "description"], "Item '%s'" % id)
		_require_resource(items[id].get("icon"), "Item '%s' (%s) icon" % [id, items[id]._source])
	for id in evidence:
		_require_fields(evidence[id], ["title", "text"], "Evidence '%s'" % id)
	for id in characters:
		_require_fields(characters[id], ["name"], "Character '%s'" % id)
	for id in dialogues:
		var lines = dialogues[id].get("lines")
		var where := "dialogue '%s' (%s)" % [id, dialogues[id]._source]
		if not lines is Array or lines.is_empty():
			errors.append("%s: needs a non-empty \"lines\" array." % where)
		else:
			_validate_lines(lines, where)

	var hotspot_ids := {}
	var set_flags := {}
	var flag_checks: Array = []  # [flag_id, where]
	var room_links := {}

	for room_id in rooms:
		var room: Dictionary = rooms[room_id]
		var where := "room '%s' (%s)" % [room_id, room._source]
		_require_fields(room, ["name"], where)
		_require_resource(room.get("backdrop", {}).get("image"), "%s backdrop image" % where)
		_require_resource(room.get("ambience"), "%s ambience" % where)
		room_links[room_id] = []

		var on_enter = room.get("on_enter", {})
		if on_enter is Dictionary and not on_enter.is_empty():
			if on_enter.has("dialogue") and not dialogues.has(str(on_enter.dialogue)):
				errors.append("%s: on_enter dialogue '%s' does not exist in data/dialogue." % [where, on_enter.dialogue])
			if on_enter.has("once_flag"):
				set_flags[str(on_enter.once_flag)] = true

		var hotspots = room.get("hotspots")
		if not hotspots is Array or hotspots.is_empty():
			errors.append("%s: needs a non-empty \"hotspots\" array." % where)
			continue

		for hotspot in hotspots:
			var hs_id := str(hotspot.get("id", ""))
			if hs_id == "":
				errors.append("%s: a hotspot is missing its \"id\"." % where)
				continue
			var hwhere := "hotspot '%s' in %s" % [hs_id, where]
			if hotspot_ids.has(hs_id):
				errors.append("%s: duplicate hotspot id (also in room '%s')." % [hwhere, hotspot_ids[hs_id]])
			hotspot_ids[hs_id] = room_id
			set_flags["seen_" + hs_id] = true
			if not hotspot.has("name"):
				errors.append("%s: missing \"name\"." % hwhere)
			_validate_rect(hotspot.get("rect"), hwhere)

			var rules = hotspot.get("interactions")
			if not rules is Array or rules.is_empty():
				errors.append("%s: has no \"interactions\"; add at least one so the player gets feedback." % hwhere)
				continue
			var has_plain := false
			for i in rules.size():
				var rule = rules[i]
				var rwhere := "interaction #%d of %s" % [i + 1, hwhere]
				if not rule is Dictionary:
					errors.append("%s: must be an object." % rwhere)
					continue
				for key in rule.keys():
					if not RULE_KEYS.has(key):
						warnings.append("%s: unknown key '%s' (typo? expected one of %s)." % [rwhere, key, ", ".join(RULE_KEYS)])
				if rule.has("use_item"):
					_require_ref(items, rule.use_item, "use_item", rwhere)
				else:
					has_plain = true
				for key in ["requires_flags", "requires_absent_flags"]:
					for flag in _as_array(rule.get(key)):
						flag_checks.append([str(flag), rwhere])
				for key in ["requires_items", "requires_absent_items"]:
					for item_id in _as_array(rule.get(key)):
						_require_ref(items, item_id, key, rwhere)
				for key in ["requires_evidence", "requires_absent_evidence"]:
					for evidence_id in _as_array(rule.get(key)):
						_require_ref(evidence, evidence_id, key, rwhere)

				var gives_feedback := false
				if rule.has("dialogue"):
					gives_feedback = _require_ref(dialogues, rule.dialogue, "dialogue", rwhere)
				if rule.has("lines"):
					if rule.lines is Array:
						_validate_lines(rule.lines, rwhere)
						gives_feedback = gives_feedback or not rule.lines.is_empty()
					else:
						errors.append("%s: \"lines\" must be an array." % rwhere)
				var effects = rule.get("effects", [])
				if not effects is Array:
					errors.append("%s: \"effects\" must be an array." % rwhere)
					effects = []
				for effect in effects:
					if _validate_effect(effect, rwhere, set_flags) and effect.type == "goto_room":
						gives_feedback = true
						room_links[room_id].append(str(effect.id))
				if not gives_feedback:
					errors.append("%s: gives the player no feedback; add \"lines\", a \"dialogue\" id, or a goto_room effect." % rwhere)
			if not has_plain:
				errors.append("%s: only reacts to items; add an interaction without \"use_item\" so examining it gives feedback." % hwhere)

	for id in deductions:
		_validate_deduction(deductions[id], set_flags)

	for check in flag_checks:
		if not set_flags.has(check[0]):
			warnings.append("%s: checks flag '%s', but no content ever sets it (typo?)." % [check[1], check[0]])

	if rooms.has(start):
		var reached := {start: true}
		var queue := [start]
		while not queue.is_empty():
			for next in room_links.get(queue.pop_front(), []):
				if rooms.has(next) and not reached.has(next):
					reached[next] = true
					queue.append(next)
		for room_id in rooms:
			if not reached.has(room_id):
				warnings.append("Room '%s' cannot be reached from start room '%s' through goto_room effects." % [room_id, start])


func _validate_deduction(deduction: Dictionary, set_flags: Dictionary) -> void:
	var where := "deduction '%s' (%s)" % [deduction.id, deduction._source]
	_require_fields(deduction, ["title", "prompt", "answers", "correct_answer", "required_evidence"], where)
	set_flags[solved_flag(deduction.id)] = true
	var answer_ids := []
	for answer in _as_array(deduction.get("answers")):
		answer_ids.append(str(answer.get("id", "")))
		if str(answer.get("text", "")) == "":
			errors.append("%s: every answer needs \"text\"." % where)
	if not answer_ids.has(str(deduction.get("correct_answer", ""))):
		errors.append("%s: correct_answer '%s' is not one of its answers." % [where, deduction.get("correct_answer", "")])
	for key in ["required_evidence", "optional_evidence"]:
		for evidence_id in _as_array(deduction.get(key)):
			_require_ref(evidence, evidence_id, key, where)
	if deduction.has("success_dialogue"):
		_require_ref(dialogues, deduction.success_dialogue, "success_dialogue", where)
	for effect in _as_array(deduction.get("effects")):
		_validate_effect(effect, where, set_flags)


func _require_fields(entry: Dictionary, fields: Array, where: String) -> void:
	for field in fields:
		if not entry.has(field):
			errors.append("%s (%s): missing required field \"%s\"." % [where, entry.get("_source", "?"), field])


func _require_ref(table: Dictionary, id, key: String, where: String) -> bool:
	if table.has(str(id)):
		return true
	errors.append("%s: %s refers to unknown id '%s'." % [where, key, id])
	return false


## Optional art references must point at an imported resource when present.
func _require_resource(path, where: String) -> void:
	if path == null:
		return
	if not ResourceLoader.exists(str(path)):
		errors.append("%s: '%s' not found (run tools/generate_art.py, then reimport in Godot)." % [where, path])


## Loads an optional texture referenced by content; null when absent.
func load_texture(path) -> Texture2D:
	if path == null or not ResourceLoader.exists(str(path)):
		return null
	return load(str(path)) as Texture2D


func item_icon(item_id: String) -> Texture2D:
	return load_texture(items.get(item_id, {}).get("icon"))


func _validate_rect(rect, where: String) -> void:
	if not (rect is Array and rect.size() == 4):
		errors.append("%s: \"rect\" must be [x, y, width, height]." % where)
		return
	for value in rect:
		if not (value is float or value is int):
			errors.append("%s: \"rect\" values must be numbers." % where)
			return
	var r := Rect2(rect[0], rect[1], rect[2], rect[3])
	if r.size.x < MIN_HOTSPOT_SIZE or r.size.y < MIN_HOTSPOT_SIZE:
		errors.append("%s: rect %s is smaller than %d px; hotspots must be generous." % [where, r, MIN_HOTSPOT_SIZE])
	if not SCREEN_RECT.encloses(r):
		errors.append("%s: rect %s extends outside the %dx%d screen." % [where, r, SCREEN_RECT.size.x, SCREEN_RECT.size.y])


func _validate_lines(lines: Array, where: String) -> void:
	for i in lines.size():
		var line = lines[i]
		if line is String:
			continue
		if not line is Dictionary or str(line.get("text", "")) == "":
			errors.append("%s: line %d needs non-empty \"text\"." % [where, i + 1])
			continue
		var speaker := str(line.get("speaker", "narrator"))
		if not characters.has(speaker):
			errors.append("%s: line %d has unknown speaker '%s' (add it to data/characters)." % [where, i + 1, speaker])


func _validate_effect(effect, where: String, set_flags: Dictionary) -> bool:
	if not effect is Dictionary:
		errors.append("%s: each effect must be an object." % where)
		return false
	var type := str(effect.get("type", ""))
	var id := str(effect.get("id", ""))
	if not EFFECT_TYPES.has(type):
		errors.append("%s: unknown effect type '%s' (expected one of %s)." % [where, type, ", ".join(EFFECT_TYPES)])
		return false
	if id == "":
		errors.append("%s: %s effect is missing its \"id\"." % [where, type])
		return false
	match type:
		"give_item", "remove_item":
			return _require_ref(items, id, type, where)
		"add_evidence":
			return _require_ref(evidence, id, type, where)
		"goto_room":
			return _require_ref(rooms, id, type, where)
		"end_chapter":
			if chapter(id).is_empty():
				errors.append("%s: end_chapter refers to unknown chapter '%s' (add it to data/game.json \"chapters\")." % [where, id])
				return false
		"play_sound":
			if not ResourceLoader.exists(SFX_DIR + id + ".wav"):
				errors.append("%s: play_sound '%s' needs %s%s.wav (run tools/generate_audio.py)." % [where, id, SFX_DIR, id])
				return false
		"set_flag":
			set_flags[id] = true
	return true


func _as_array(value) -> Array:
	return value if value is Array else []

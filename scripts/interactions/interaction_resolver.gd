extends RefCounted
## Gameplay logic for hotspot interactions. Picks the first interaction rule
## whose conditions match, applies its effects to the game state, and returns
## what the UI should present. Holds no UI references so it can be unit tested.
##
## Rule format (data/rooms/*.json, hotspot "interactions" array, first match wins):
##   use_item                 item that must be used on the hotspot (omit for plain examine)
##   requires_flags / requires_absent_flags
##   requires_items / requires_absent_items
##   requires_evidence / requires_absent_evidence
##   dialogue                 id in data/dialogue, shown before inline lines
##   lines                    [{speaker, text}]
##   effects                  [{type, id, value?}] where type is one of
##                            give_item, remove_item, add_evidence, set_flag,
##                            goto_room, play_sound (id = assets/audio/sfx/<id>.wav),
##                            end_chapter (id = chapter in data/game.json)
##
## The flag "seen_<hotspot_id>" is set after every interaction, so rules can
## check whether the player has examined something before.

var state: Node
var content: Node


func _init(game_state: Node, content_db: Node) -> void:
	state = game_state
	content = content_db


## Returns {"lines", "goto_room", "end_chapter", "sounds", "matched"}.
func interact(room_id: String, hotspot_id: String, used_item: String = "") -> Dictionary:
	var result := new_result()
	var hotspot: Dictionary = content.find_hotspot(room_id, hotspot_id)
	if hotspot.is_empty():
		push_error("[Interaction] Hotspot '%s' not found in room '%s'." % [hotspot_id, room_id])
		result.lines = [{"speaker": "narrator", "text": "(Missing hotspot '%s'. Check data/rooms.)" % hotspot_id}]
		return result

	var rule := find_rule(hotspot, used_item)
	state.set_flag("seen_" + hotspot_id, true)
	if rule.is_empty():
		var target := str(hotspot.get("name", "that")).to_lower()
		if used_item != "":
			result.lines = [{"speaker": "eli", "text": "Using the %s on the %s won't help." % [content.item_name(used_item).to_lower(), target]}]
		else:
			result.lines = [{"speaker": "eli", "text": "Nothing more to see there."}]
		return result

	result.matched = true
	result.lines = content.lines_for(rule)
	apply_effects(rule.get("effects", []), result)
	return result


static func new_result() -> Dictionary:
	return {"lines": [], "goto_room": "", "end_chapter": "", "sounds": [], "matched": false}


## Applies effects to the game state. Presentation effects (room changes,
## chapter endings, sounds) are recorded in `result` for the UI to perform.
func apply_effects(effects: Array, result: Dictionary) -> void:
	for effect in effects:
		_apply_effect(effect, result)


func find_rule(hotspot: Dictionary, used_item: String = "") -> Dictionary:
	for rule in hotspot.get("interactions", []):
		if str(rule.get("use_item", "")) != used_item:
			continue
		if conditions_met(rule):
			return rule
	return {}


func conditions_met(rule: Dictionary) -> bool:
	for flag in rule.get("requires_flags", []):
		if not state.has_flag(str(flag)):
			return false
	for flag in rule.get("requires_absent_flags", []):
		if state.has_flag(str(flag)):
			return false
	for item_id in rule.get("requires_items", []):
		if not state.has_item(str(item_id)):
			return false
	for item_id in rule.get("requires_absent_items", []):
		if state.has_item(str(item_id)):
			return false
	for evidence_id in rule.get("requires_evidence", []):
		if not state.has_evidence(str(evidence_id)):
			return false
	for evidence_id in rule.get("requires_absent_evidence", []):
		if state.has_evidence(str(evidence_id)):
			return false
	return true


func _apply_effect(effect: Dictionary, result: Dictionary) -> void:
	var id := str(effect.get("id", ""))
	match str(effect.get("type", "")):
		"give_item":
			state.give_item(id)
		"remove_item":
			state.remove_item(id)
		"add_evidence":
			state.add_evidence(id)
		"set_flag":
			state.set_flag(id, effect.get("value", true))
		"goto_room":
			result.goto_room = id
		"end_chapter":
			result.end_chapter = id
		"play_sound":
			result.sounds.append(id)
		var unknown:
			push_error("[Interaction] Unknown effect type '%s'." % unknown)

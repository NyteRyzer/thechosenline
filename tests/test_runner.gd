extends Node
## Headless test suite for content, interactions, progression, save/load,
## settings and a UI smoke test. Run from the project folder:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 when every check passes, 1 otherwise.

const InteractionResolver := preload("res://scripts/interactions/interaction_resolver.gd")
const DeductionLogic := preload("res://scripts/interactions/deduction_logic.gd")
const GAME_SCENE := preload("res://scenes/game/game_screen.tscn")
const TITLE_SCENE := preload("res://scenes/title/title_screen.tscn")
const LIVING := "room_eli_living_room"
const KITCHEN := "room_eli_kitchen"
const SLICE_EVIDENCE := ["ev_glass_outside", "ev_spare_key_missing", "ev_unearthly_feather"]
const DEDUCTION := "ded_staged_entry"
const PROOF := ["ev_glass_outside", "ev_spare_key_missing", "ev_lock_unforced"]

var _passed := 0
var _failed := 0
var _current := ""
var _resolver


func _ready() -> void:
	SaveSystem.save_dir = "user://test_saves"
	_resolver = InteractionResolver.new(GameState, ContentDB)
	_clear_test_saves()

	var tests := [
		"test_content_has_no_errors_or_warnings",
		"test_new_game_defaults",
		"test_slice_has_enough_content",
		"test_every_hotspot_gives_feedback",
		"test_window_gives_clue_once",
		"test_under_couch_needs_flashlight",
		"test_wrong_item_gives_feedback",
		"test_deduction_feedback",
		"test_audio_assets_exist",
		"test_critical_path_completes_slice",
		"test_exhaustive_exploration_never_softlocks",
		"test_save_load_round_trip",
		"test_save_missing_fields_uses_defaults",
		"test_save_drops_unknown_ids",
		"test_save_rejects_newer_version",
		"test_save_corrupt_file_is_reported",
		"test_most_recent_slot",
		"test_settings_round_trip",
	]
	for test in tests:
		_current = test
		GameState.reset()
		call(test)
	_current = "test_ui_smoke"
	await test_ui_smoke()

	_clear_test_saves()
	print("\n%d checks passed, %d failed." % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL [%s] %s" % [_current, message])


# --- Content ---------------------------------------------------------------

func test_content_has_no_errors_or_warnings() -> void:
	check(ContentDB.errors.is_empty(), "content errors: " + "; ".join(ContentDB.errors))
	check(ContentDB.warnings.is_empty(), "content warnings: " + "; ".join(ContentDB.warnings))


func test_new_game_defaults() -> void:
	GameState.new_game()
	check(GameState.current_room_id == LIVING, "new game should start in the living room")
	check(GameState.inventory.is_empty() and GameState.evidence.is_empty(), "new game should start empty-handed")
	check(GameState.chapter == 1, "new game should start in chapter 1")


func test_slice_has_enough_content() -> void:
	var hotspots := 0
	for room_id in ContentDB.rooms:
		hotspots += ContentDB.rooms[room_id].hotspots.size()
	check(ContentDB.get_room(LIVING).hotspots.size() >= 6, "the house's first room needs at least six hotspots")
	check(hotspots >= 6, "slice needs at least six hotspots")
	check(ContentDB.items.size() >= 3, "slice needs at least three collectable items")


func test_every_hotspot_gives_feedback() -> void:
	for room_id in ContentDB.rooms:
		for hotspot in ContentDB.rooms[room_id].hotspots:
			GameState.new_game()
			var result: Dictionary = _resolver.interact(room_id, hotspot.id)
			check(not result.lines.is_empty() or result.goto_room != "", "%s gives no feedback on a fresh game" % hotspot.id)
			check(GameState.has_flag("seen_" + hotspot.id), "%s should mark itself seen" % hotspot.id)


# --- Interactions ----------------------------------------------------------

func test_window_gives_clue_once() -> void:
	GameState.new_game()
	var first: Dictionary = _resolver.interact(LIVING, "hs_living_window")
	check(GameState.has_item("item_glass_shard"), "window should give the glass shard")
	check(GameState.has_evidence("ev_glass_outside"), "window should journal its evidence")
	var second: Dictionary = _resolver.interact(LIVING, "hs_living_window")
	check(GameState.inventory.count("item_glass_shard") == 1, "glass shard must not duplicate")
	check(first.lines != second.lines, "re-examining should give a follow-up line")


func test_under_couch_needs_flashlight() -> void:
	GameState.new_game()
	_resolver.interact(LIVING, "hs_living_under_couch")
	check(not GameState.has_item("item_gold_feather"), "feather must not be found without light")
	GameState.give_item("item_flashlight")
	var result: Dictionary = _resolver.interact(LIVING, "hs_living_under_couch", "item_flashlight")
	check(result.matched, "flashlight should match the under-couch rule")
	check(GameState.has_item("item_gold_feather"), "flashlight should reveal the feather")
	check(GameState.has_evidence("ev_unearthly_feather"), "feather should be journaled")


func test_wrong_item_gives_feedback() -> void:
	GameState.new_game()
	GameState.give_item("item_glass_shard")
	var result: Dictionary = _resolver.interact(KITCHEN, "hs_kitchen_fridge", "item_glass_shard")
	check(not result.matched, "glass shard should not match the fridge")
	check(not result.lines.is_empty(), "using the wrong item should still say something")


# --- Progression -----------------------------------------------------------

func test_critical_path_completes_slice() -> void:
	GameState.new_game()
	var steps := [
		[LIVING, "hs_living_window", ""],
		[LIVING, "hs_living_key_hooks", ""],
		[LIVING, "hs_living_to_kitchen", ""],
		[KITCHEN, "hs_kitchen_drawer", ""],
		[KITCHEN, "hs_kitchen_to_living", ""],
		[LIVING, "hs_living_under_couch", "item_flashlight"],
		[LIVING, "hs_living_front_door", ""],
	]
	for step in steps:
		check(GameState.current_room_id == step[0], "expected to be in %s before %s" % [step[0], step[1]])
		var result: Dictionary = _resolver.interact(step[0], step[1], step[2])
		if result.goto_room != "":
			GameState.goto_room(result.goto_room)
	check(GameState.has_flag("ready_to_deduce"), "gathering the clues should lead to the deduction")
	check(GameState.has_evidence("ev_lock_unforced"), "lock evidence must be auto-journaled")
	check(GameState.inventory.size() >= 3, "critical path should collect at least three items")
	var door: Dictionary = _resolver.interact(LIVING, "hs_living_front_door")
	check(door.end_chapter == "", "the door must stay shut until the deduction is solved")
	_solve_deduction()
	door = _resolver.interact(LIVING, "hs_living_front_door")
	check(door.end_chapter == "ch1", "after the deduction the front door should end chapter 1")
	check(door.sounds.has("bell"), "leaving the house should ring the bell")


## Explores every hotspot in every reachable room with every held item until
## nothing changes. The slice must complete, which proves no ordering softlocks it.
func test_exhaustive_exploration_never_softlocks() -> void:
	GameState.new_game()
	var visited_rooms := {LIVING: true}
	for _round in 20:
		var before := JSON.stringify(GameState.to_dict())
		for room_id in visited_rooms.keys():
			for hotspot in ContentDB.rooms[room_id].hotspots:
				for used in [""] + Array(GameState.inventory):
					var result: Dictionary = _resolver.interact(room_id, hotspot.id, used)
					if result.goto_room != "":
						visited_rooms[result.goto_room] = true
		if JSON.stringify(GameState.to_dict()) == before:
			break
	check(visited_rooms.size() == ContentDB.rooms.size(), "every room should be reachable")
	check(GameState.has_flag("ready_to_deduce"), "exploration should always reach the deduction")
	var verdict := DeductionLogic.evaluate(ContentDB.deductions[DEDUCTION], "ans_spare_key", PROOF, Array(GameState.evidence))
	check(verdict.correct, "exploration should always find enough proof for the deduction")
	for evidence_id in SLICE_EVIDENCE:
		check(GameState.has_evidence(evidence_id), "exploration should find %s" % evidence_id)


func test_deduction_feedback() -> void:
	var ded: Dictionary = ContentDB.deductions[DEDUCTION]
	var owned := PROOF + ["ev_unearthly_feather", "ev_back_door_bolted"]
	var wrong := DeductionLogic.evaluate(ded, "ans_window", PROOF, owned)
	check(not wrong.correct and "porch" in wrong.feedback, "a wrong answer should give its rebuttal")
	check(not DeductionLogic.evaluate(ded, "", PROOF, owned).correct, "no answer is not a solution")
	var missing := DeductionLogic.evaluate(ded, "ans_spare_key", ["ev_glass_outside"], owned)
	check(not missing.correct and missing.feedback == ded.hint_missing, "missing proof should give the missing hint")
	var extra := DeductionLogic.evaluate(ded, "ans_spare_key", PROOF + ["ev_unearthly_feather"], owned)
	check(not extra.correct and extra.feedback == ded.hint_irrelevant, "an unrelated clue should give the irrelevant hint")
	var unfound := DeductionLogic.evaluate(ded, "ans_spare_key", PROOF, ["ev_glass_outside"])
	check(not unfound.correct and unfound.feedback == ded.hint_not_found, "unfound proof should send the player back to search")
	check(DeductionLogic.evaluate(ded, "ans_spare_key", PROOF, owned).correct, "the right answer and proof should solve it")
	check(DeductionLogic.evaluate(ded, "ans_spare_key", PROOF + ["ev_back_door_bolted"], owned).correct, "optional supporting evidence is allowed")


func test_audio_assets_exist() -> void:
	for id in ["pickup", "evidence", "door", "bell", "revelation", "wrong", "click"]:
		check(AudioManager.sfx_exists(id), "missing sound effect " + id)
	check(ResourceLoader.exists("res://assets/audio/music/title.wav"), "missing title music")
	for room_id in ContentDB.rooms:
		check(ResourceLoader.exists(str(ContentDB.rooms[room_id].get("ambience", ""))), "%s needs ambience" % room_id)


func _solve_deduction() -> void:
	GameState.set_flag(ContentDB.solved_flag(DEDUCTION), true)


# --- Save / load -----------------------------------------------------------

func test_save_load_round_trip() -> void:
	GameState.new_game()
	GameState.goto_room(KITCHEN)
	GameState.give_item("item_flashlight")
	GameState.add_evidence("ev_glass_outside")
	GameState.set_flag("got_flashlight")
	GameState.set_flag("counter", 3)
	GameState.relationships["vale"] = 2
	GameState.playtime_seconds = 125.5
	var expected := GameState.to_dict()
	check(SaveSystem.save_game("slot_1") == OK, "save should succeed: " + SaveSystem.last_error)
	GameState.reset()
	check(SaveSystem.load_game("slot_1") == OK, "load should succeed: " + SaveSystem.last_error)
	# Compare through JSON with sorted keys: saves store numbers as floats and key order is irrelevant.
	var actual := GameState.to_dict()
	for key in expected:
		var want := JSON.stringify(JSON.parse_string(JSON.stringify(expected[key])), "", true)
		var got := JSON.stringify(actual[key], "", true)
		check(got == want, "%s should survive save/load (%s vs %s)" % [key, want, got])
	check(SaveSystem.last_warnings.is_empty(), "clean save should load without warnings")
	var info := SaveSystem.slot_info("slot_1")
	check(info.valid and "Kitchen" in info.description, "slot summary should describe the save")


func test_save_missing_fields_uses_defaults() -> void:
	_write_raw_save("slot_2", {"save_version": 1, "state": {"current_room_id": KITCHEN}})
	check(SaveSystem.load_game("slot_2") == OK, "sparse save should load: " + SaveSystem.last_error)
	check(GameState.current_room_id == KITCHEN, "room should load from sparse save")
	check(GameState.inventory.is_empty() and GameState.flags.is_empty(), "missing fields should default to empty")
	check(GameState.chapter == 1, "missing chapter should default to 1")


func test_save_drops_unknown_ids() -> void:
	_write_raw_save("slot_3", {"save_version": 1, "state": {
		"current_room_id": "room_that_was_cut",
		"inventory": ["item_flashlight", "item_that_was_cut"],
		"evidence": ["ev_that_was_cut"],
	}})
	check(SaveSystem.load_game("slot_3") == OK, "save with stale ids should still load")
	check(GameState.current_room_id == LIVING, "unknown room should fall back to the start room")
	check(GameState.inventory == ["item_flashlight"], "unknown items should be dropped")
	check(GameState.evidence.is_empty(), "unknown evidence should be dropped")
	check(SaveSystem.last_warnings.size() == 3, "each dropped id should produce a warning")


func test_save_rejects_newer_version() -> void:
	_write_raw_save("slot_1", {"save_version": 99, "state": {}})
	check(SaveSystem.load_game("slot_1") != OK, "a newer save version must be rejected")
	check("newer version" in SaveSystem.last_error, "error should explain the version problem")


func test_save_corrupt_file_is_reported() -> void:
	DirAccess.make_dir_recursive_absolute(SaveSystem.save_dir)
	var file := FileAccess.open(SaveSystem.slot_path("slot_2"), FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()
	check(SaveSystem.load_game("slot_2") != OK, "corrupt save must not load")
	check(not SaveSystem.slot_info("slot_2").valid, "corrupt save should be listed as damaged")


func test_most_recent_slot() -> void:
	_clear_test_saves()
	check(not SaveSystem.has_any_save(), "no saves after clearing")
	_write_raw_save("slot_1", {"save_version": 1, "saved_unix": 100.0, "state": {}})
	_write_raw_save("slot_3", {"save_version": 1, "saved_unix": 200.0, "state": {}})
	check(SaveSystem.most_recent_slot() == "slot_3", "Continue should pick the newest save")


# --- Settings --------------------------------------------------------------

func test_settings_round_trip() -> void:
	var original_path := Settings.settings_path
	var original_values := Settings.values.duplicate()
	Settings.settings_path = "user://test_settings.cfg"
	Settings.set_value("text_size", 3)
	Settings.set_value("high_contrast", true)
	Settings.set_value("music_volume", 0.25)
	Settings.values = Settings.DEFAULTS.duplicate()
	Settings.load_settings()
	check(Settings.get_value("text_size") == 3, "text size should persist")
	check(Settings.get_value("high_contrast") == true, "high contrast should persist")
	check(is_equal_approx(Settings.get_value("music_volume"), 0.25), "music volume should persist")
	check(get_tree().root.theme.default_font_size == int(round(20 * 1.4)), "text size should scale the theme")
	DirAccess.remove_absolute(Settings.settings_path)
	Settings.settings_path = original_path
	Settings.values = original_values
	Settings.apply(true)


# --- UI smoke --------------------------------------------------------------

func test_ui_smoke() -> void:
	GameState.reset()
	var title := TITLE_SCENE.instantiate()
	add_child(title)
	await get_tree().process_frame
	check(title.get_viewport().gui_get_focus_owner() != null, "title screen should focus a menu button")
	title.queue_free()

	SceneRouter.last_entry = "new"
	GameState.new_game()
	var game := GAME_SCENE.instantiate()
	add_child(game)
	await get_tree().process_frame
	var dialogue: Control = game._dialogue
	check(dialogue.is_active(), "intro dialogue should play on a new game")
	check(SaveSystem.slot_info("autosave").valid, "entering a room should autosave")
	while dialogue.is_active():
		dialogue._opened_at = 0
		dialogue.advance()
	await get_tree().process_frame
	check(game.get_viewport().gui_get_focus_owner() is Button, "a hotspot should have keyboard focus after dialogue")

	game._on_hotspot_activated("hs_living_window")
	check(dialogue.is_active(), "examining a hotspot should open dialogue")
	check(GameState.has_item("item_glass_shard"), "UI interaction should reach game state")
	dialogue.skip_all()

	game._open_overlay(game.InventoryPanel.new())
	await get_tree().process_frame
	check(game._is_blocked(), "inventory overlay should block room input")
	game._overlay.close()
	await get_tree().process_frame
	check(not game._is_blocked(), "closing the overlay should unblock input")

	for script in [game.JournalPanel, game.PauseMenu]:
		game._open_overlay(script.new())
		await get_tree().process_frame
		check(game._overlay != null, "%s should open" % script.resource_path.get_file())
		game._overlay.close()
		await get_tree().process_frame

	for evidence_id in PROOF:
		GameState.add_evidence(evidence_id)
	game._open_deduction_board()
	await get_tree().process_frame
	var board: Control = game._overlay
	check(board != null, "deduction board should open")
	check(not board.attempt("ans_forced_lock", PROOF), "a wrong deduction should be rejected")
	check(game._is_blocked() and not GameState.has_flag("solved_" + DEDUCTION), "a wrong deduction keeps the board open")
	check(board.attempt("ans_spare_key", PROOF), "the right deduction should be accepted")
	await get_tree().process_frame
	check(GameState.has_flag("solved_" + DEDUCTION), "solving should set the solved flag")
	check(dialogue.is_active(), "solving should play the success dialogue")
	dialogue.skip_all()
	await get_tree().process_frame

	game._on_hotspot_activated("hs_living_front_door")
	dialogue.skip_all()
	await get_tree().process_frame
	check(GameState.has_flag("completed_ch1"), "leaving after the deduction should complete chapter 1")
	check(game._overlay != null, "the chapter recap should be shown")
	game._overlay.close()
	await get_tree().process_frame

	game._on_hotspot_activated("hs_living_to_kitchen")
	await get_tree().create_timer(0.8).timeout
	check(GameState.current_room_id == KITCHEN, "doorway should move to the kitchen")
	check(game._room_label.text.contains("Kitchen"), "HUD should show the new room")
	game.queue_free()
	await get_tree().process_frame


# --- Helpers ---------------------------------------------------------------

func _write_raw_save(slot: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(SaveSystem.save_dir)
	var file := FileAccess.open(SaveSystem.slot_path(slot), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _clear_test_saves() -> void:
	if not DirAccess.dir_exists_absolute(SaveSystem.save_dir):
		return
	for file in DirAccess.get_files_at(SaveSystem.save_dir):
		DirAccess.remove_absolute(SaveSystem.save_dir.path_join(file))

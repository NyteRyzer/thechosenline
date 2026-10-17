extends Node
## Scene flow between the title screen and the game. Gameplay scenes read
## GameState on entry, so switching scenes never carries hidden state.

const TITLE_SCENE := "res://scenes/title/title_screen.tscn"
const GAME_SCENE := "res://scenes/game/game_screen.tscn"

## "new" or "load": tells the game screen whether to autosave and play room intros.
var last_entry := "new"


func start_new_game() -> void:
	GameState.new_game()
	last_entry = "new"
	_change(GAME_SCENE)


func continue_game() -> Error:
	var slot := SaveSystem.most_recent_slot()
	if slot == "":
		SaveSystem.last_error = "No saved games found."
		return ERR_FILE_NOT_FOUND
	return load_slot(slot)


func load_slot(slot: String) -> Error:
	var err := SaveSystem.load_game(slot)
	if err == OK:
		last_entry = "load"
		_change(GAME_SCENE)
	return err


func goto_title() -> void:
	GameState.in_game = false
	GameState.select_item("")
	_change(TITLE_SCENE)


func quit_game() -> void:
	get_tree().quit()


func _change(path: String) -> void:
	get_tree().call_deferred("change_scene_to_file", path)

extends "res://scripts/ui/modal_overlay.gd"
## In-game menu: resume, save, load, settings, quit.

const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")
const SaveLoadPanel := preload("res://scripts/ui/save_load_panel.gd")


func _build() -> void:
	add_title("Paused")
	focus_target = add_button("Resume", close)
	add_button("Save Game", func(): open_child(SaveLoadPanel.new("save")))
	add_button("Load Game", func(): open_child(SaveLoadPanel.new("load")))
	add_button("Settings", func(): open_child(SettingsPanel.new()))
	add_button("Quit to Title", SceneRouter.goto_title)
	add_button("Quit Game", SceneRouter.quit_game)
	for child in content.get_children():
		if child is Button:
			child.custom_minimum_size.x = 300

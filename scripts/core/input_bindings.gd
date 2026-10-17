extends RefCounted
## Default key bindings, registered at startup so gameplay does not depend on
## hand-edited project.godot input maps. A remapping screen can rebind these
## actions later without code changes elsewhere.

const BINDINGS := {
	"toggle_inventory": [KEY_I],
	"toggle_journal": [KEY_J],
	"toggle_deduction": [KEY_B],
	"pause_menu": [KEY_ESCAPE],
	"highlight_hotspots": [KEY_H],
	"toggle_debug": [KEY_F3],
}

## Shown in Settings > Controls.
const DESCRIPTIONS := [
	["Examine / confirm", "Left-click, Enter or Space"],
	["Move between objects", "Tab / Shift+Tab or arrow keys"],
	["Inventory", "I"],
	["Journal", "J"],
	["Deduction board", "B"],
	["Highlight all objects (hold)", "H"],
	["Menu / cancel selected item", "Esc (right-click also cancels an item)"],
	["Developer debug overlay", "F3"],
]


static func register_defaults() -> void:
	for action in BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		if not InputMap.action_get_events(action).is_empty():
			continue
		for keycode in BINDINGS[action]:
			var event := InputEventKey.new()
			event.keycode = keycode
			InputMap.action_add_event(action, event)

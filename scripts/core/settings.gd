extends Node
## Persistent player settings (audio, text, accessibility, display).
## Changes apply immediately and are saved to user://settings.cfg.

signal settings_changed

const ThemeBuilder := preload("res://scripts/ui/theme_builder.gd")
const InputBindings := preload("res://scripts/core/input_bindings.gd")

const SETTINGS_VERSION := 1
const TEXT_SIZE_NAMES := ["Small", "Normal", "Large", "Extra Large"]
const TEXT_SIZE_SCALES := [0.85, 1.0, 1.2, 1.4]
const VOLUME_BUSES := {
	"master_volume": "Master",
	"music_volume": "Music",
	"sfx_volume": "SFX",
	"ambience_volume": "Ambience",
	"dialogue_volume": "Dialogue",
}
const THEME_KEYS := ["text_size", "high_contrast"]
const DEFAULTS := {
	"master_volume": 0.8,
	"music_volume": 0.8,
	"sfx_volume": 0.8,
	"ambience_volume": 0.8,
	"dialogue_volume": 1.0,
	"text_size": 1,
	"high_contrast": false,
	"hotspot_highlight": false,
	"subtitles": true,
	"fullscreen": false,
}

var settings_path := "user://settings.cfg"
var values: Dictionary = DEFAULTS.duplicate()


func _ready() -> void:
	InputBindings.register_defaults()
	_ensure_audio_buses()
	load_settings()
	apply(true)


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		push_error("[Settings] Unknown setting '%s'." % key)
		return
	values[key] = _coerce(key, value)
	apply(THEME_KEYS.has(key))
	save_settings()
	settings_changed.emit()


func reset_to_defaults() -> void:
	values = DEFAULTS.duplicate()
	apply(true)
	save_settings()
	settings_changed.emit()


func text_scale() -> float:
	return TEXT_SIZE_SCALES[clampi(int(get_value("text_size")), 0, TEXT_SIZE_SCALES.size() - 1)]


func load_settings() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	for key in DEFAULTS:
		if cfg.has_section_key("settings", key):
			values[key] = _coerce(key, cfg.get_value("settings", key))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SETTINGS_VERSION)
	for key in values:
		cfg.set_value("settings", key, values[key])
	var err := cfg.save(settings_path)
	if err != OK:
		push_error("[Settings] Could not save %s (error %d)." % [ProjectSettings.globalize_path(settings_path), err])


func apply(rebuild_theme: bool = true) -> void:
	for key in VOLUME_BUSES:
		var bus := AudioServer.get_bus_index(VOLUME_BUSES[key])
		if bus < 0:
			continue
		var volume := float(get_value(key))
		AudioServer.set_bus_mute(bus, volume <= 0.001)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
	if rebuild_theme:
		get_tree().root.theme = ThemeBuilder.build(text_scale(), bool(get_value("high_contrast")))
	_apply_fullscreen()


## Keeps a loaded value only if it matches the default's type (ints and floats interchange).
func _coerce(key: String, value: Variant) -> Variant:
	var default = DEFAULTS[key]
	match typeof(default):
		TYPE_FLOAT:
			if value is float or value is int:
				return clampf(float(value), 0.0, 1.0)
		TYPE_INT:
			if value is float or value is int:
				return int(value)
		TYPE_BOOL:
			if value is bool:
				return value
	return default


func _apply_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var want := bool(get_value("fullscreen"))
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if want and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not want and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _ensure_audio_buses() -> void:
	for bus_name in VOLUME_BUSES.values():
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")

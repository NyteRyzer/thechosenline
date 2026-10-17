extends Control
## Draws a room's placeholder backdrop from data and creates one focusable
## hotspot button per hotspot. Emits signals only; gameplay lives elsewhere.
##
## Backdrop (data/rooms/*.json "backdrop"):
##   "image": pixel-art PNG (320x180, drawn at 4x with nearest filtering), and/or
##   "shapes": placeholder primitives drawn on top, for blocking out new rooms:
##   {"type": "rect",   "rect": [x, y, w, h], "color": "#rrggbb[aa]", "label": "..."}
##   {"type": "circle", "center": [x, y], "radius": r, "color": ...}
##   {"type": "line",   "from": [x, y], "to": [x, y], "width": w, "color": ...}
##   {"type": "poly",   "points": [x1, y1, x2, y2, ...], "color": ...}

signal hotspot_activated(hotspot_id: String)
signal hotspot_focus_changed(hotspot_id: String)

const HotspotButton := preload("res://scripts/rooms/hotspot_button.gd")

var room: Dictionary = {}
var highlight_all := false:
	set(value):
		if highlight_all != value:
			highlight_all = value
			for button in _buttons.values():
				button.highlighted = value
var _background: Texture2D = null
var _buttons: Dictionary = {}
var _hover_id := ""
var _focus_id := ""
var _last_focus_id := ""


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST  # keep pixel art crisp at 4x


func build(room_def: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_buttons.clear()
	_hover_id = ""
	_focus_id = ""
	_last_focus_id = ""
	room = room_def
	_background = ContentDB.load_texture(room.get("backdrop", {}).get("image"))
	for hotspot in room.get("hotspots", []):
		var button := HotspotButton.new()
		button.setup(hotspot)
		button.highlighted = highlight_all
		var id: String = button.hotspot_id
		button.pressed.connect(func(): hotspot_activated.emit(id))
		button.mouse_entered.connect(func(): _set_hover(id))
		button.mouse_exited.connect(func(): if _hover_id == id: _set_hover(""))
		button.focus_entered.connect(func(): _set_focus(id))
		button.focus_exited.connect(func(): if _focus_id == id: _set_focus(""))
		add_child(button)
		_buttons[id] = button
	queue_redraw()


func hotspot_name(hotspot_id: String) -> String:
	return _buttons[hotspot_id].display_name if _buttons.has(hotspot_id) else ""


func refresh_visited() -> void:
	for id in _buttons:
		_buttons[id].visited = GameState.has_flag("seen_" + id)


## Focuses the last focused hotspot, or the first one.
func focus_hotspot() -> void:
	if _buttons.is_empty():
		return
	var target: Control = _buttons.get(_last_focus_id, _buttons.values()[0])
	if target.focus_mode != FOCUS_NONE:
		target.grab_focus()


func _set_hover(id: String) -> void:
	_hover_id = id
	hotspot_focus_changed.emit(_hover_id if _hover_id != "" else _focus_id)


func _set_focus(id: String) -> void:
	_focus_id = id
	if id != "":
		_last_focus_id = id
	hotspot_focus_changed.emit(_hover_id if _hover_id != "" else _focus_id)


func _draw() -> void:
	var backdrop: Dictionary = room.get("backdrop", {})
	draw_rect(Rect2(Vector2.ZERO, size), Color(str(backdrop.get("base_color", "#1b2130"))))
	if _background:
		draw_texture_rect(_background, Rect2(Vector2.ZERO, size), false)
	var font := get_theme_default_font()
	for shape in backdrop.get("shapes", []):
		_draw_shape(shape, font)
	draw_string(font, Vector2(16, size.y - 14), "PROTOTYPE ART", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.25))


func _draw_shape(shape: Dictionary, font: Font) -> void:
	var color := Color(str(shape.get("color", "#ffffff")))
	var label_at := Vector2.ZERO
	match str(shape.get("type", "rect")):
		"rect":
			var r: Array = shape.get("rect", [0, 0, 0, 0])
			draw_rect(Rect2(r[0], r[1], r[2], r[3]), color)
			label_at = Vector2(r[0] + 6, r[1] + 16)
		"circle":
			var c: Array = shape.get("center", [0, 0])
			draw_circle(Vector2(c[0], c[1]), float(shape.get("radius", 10)), color)
			label_at = Vector2(c[0], c[1])
		"line":
			var a: Array = shape.get("from", [0, 0])
			var b: Array = shape.get("to", [0, 0])
			draw_line(Vector2(a[0], a[1]), Vector2(b[0], b[1]), color, float(shape.get("width", 2)))
			label_at = Vector2(a[0], a[1])
		"poly":
			var p: Array = shape.get("points", [])
			var points := PackedVector2Array()
			for i in range(0, p.size() - 1, 2):
				points.append(Vector2(p[i], p[i + 1]))
			if points.size() >= 3:
				draw_colored_polygon(points, color)
				label_at = points[0] + Vector2(6, -6)
	if shape.has("label"):
		draw_string(font, label_at, str(shape.label), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.5))

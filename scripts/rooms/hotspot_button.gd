extends Button
## Invisible, generously sized button over an interactive object. When
## hovered, focused or highlighted it shows corner brackets (a shape cue, not
## only color); after it has been examined it shows a small tick.

const MIN_SIZE := 64.0
const ACTIVE_COLOR := Color(1.0, 0.78, 0.4, 0.95)
const HIGHLIGHT_COLOR := Color(0.85, 0.9, 1.0, 0.75)

var hotspot_id := ""
var display_name := ""
var highlighted := false:
	set(value):
		if highlighted != value:
			highlighted = value
			queue_redraw()
var visited := false:
	set(value):
		if visited != value:
			visited = value
			queue_redraw()


func setup(hotspot: Dictionary) -> void:
	hotspot_id = str(hotspot.get("id", ""))
	display_name = str(hotspot.get("name", hotspot_id))
	name = "Hotspot_" + hotspot_id
	var r: Array = hotspot.get("rect", [0, 0, MIN_SIZE, MIN_SIZE])
	var rect := Rect2(r[0], r[1], r[2], r[3])
	rect = rect.grow_individual(
		maxf(0.0, (MIN_SIZE - rect.size.x) / 2.0), maxf(0.0, (MIN_SIZE - rect.size.y) / 2.0),
		maxf(0.0, (MIN_SIZE - rect.size.x) / 2.0), maxf(0.0, (MIN_SIZE - rect.size.y) / 2.0))
	position = rect.position
	size = rect.size
	text = ""
	flat = true
	focus_mode = FOCUS_ALL
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	for style in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())


func _ready() -> void:
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	var active := is_hovered() or has_focus()
	if active or highlighted:
		var color := ACTIVE_COLOR if active else HIGHLIGHT_COLOR
		var width := 3.0 if active else 2.0
		if active:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.8, 0.45, 0.08))
		draw_rect(Rect2(Vector2.ZERO, size), Color(color, 0.35), false, 1.0)
		_draw_brackets(color, width)
		if highlighted and not active:
			var font := get_theme_default_font()
			draw_rect(Rect2(4, 4, font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 8, 20), Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(8, 19), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	if visited:
		var corner := Vector2(size.x - 22, 8)
		draw_circle(corner + Vector2(7, 7), 10, Color(0, 0, 0, 0.6))
		draw_polyline(PackedVector2Array([corner + Vector2(2, 7), corner + Vector2(6, 11), corner + Vector2(13, 3)]), Color(0.7, 1.0, 0.75), 2.0)


func _draw_brackets(color: Color, width: float) -> void:
	var length := minf(22.0, minf(size.x, size.y) * 0.3)
	var corners := [
		[Vector2(0, 0), Vector2.RIGHT, Vector2.DOWN],
		[Vector2(size.x, 0), Vector2.LEFT, Vector2.DOWN],
		[Vector2(0, size.y), Vector2.RIGHT, Vector2.UP],
		[size, Vector2.LEFT, Vector2.UP],
	]
	for corner in corners:
		draw_line(corner[0], corner[0] + corner[1] * length, color, width)
		draw_line(corner[0], corner[0] + corner[2] * length, color, width)

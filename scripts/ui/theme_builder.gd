extends RefCounted
## Builds the global UI theme: dark translucent panels, high-contrast text and
## a clearly visible keyboard-focus outline. Rebuilt when text size or the
## high-contrast setting changes.

const BASE_FONT_SIZE := 20
const ACCENT := Color("e8a64a")  # sodium-orange streetlight
const ACCENT_HIGH_CONTRAST := Color("ffd400")
const FONT_TYPES := [
	"Label", "Button", "CheckBox", "CheckButton", "OptionButton", "LineEdit",
	"ItemList", "PopupMenu", "TooltipLabel", "TabBar", "TabContainer",
]
const BUTTON_TYPES := ["Button", "OptionButton"]
const TOGGLE_TYPES := ["CheckBox", "CheckButton"]


static func build(text_scale: float, high_contrast: bool) -> Theme:
	var theme := Theme.new()
	var font_size := int(round(BASE_FONT_SIZE * text_scale))
	var text_color := Color.WHITE if high_contrast else Color("e6e9f0")
	var dim_color := Color("dddddd") if high_contrast else Color("9aa3b5")
	var accent := ACCENT_HIGH_CONTRAST if high_contrast else ACCENT
	var panel_bg := Color(0, 0, 0, 1) if high_contrast else Color(0.05, 0.06, 0.09, 0.9)
	var border := Color.WHITE if high_contrast else Color(0.42, 0.52, 0.7, 0.55)
	var border_width := 2 if high_contrast else 1

	theme.default_font_size = font_size
	for type in FONT_TYPES:
		theme.set_font_size("font_size", type, font_size)
	for item in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		theme.set_font_size(item, "RichTextLabel", font_size)
	theme.set_color("default_color", "RichTextLabel", text_color)
	theme.set_color("font_color", "Label", text_color)

	theme.set_type_variation("HeaderLabel", "Label")
	theme.set_font_size("font_size", "HeaderLabel", int(font_size * 1.35))
	theme.set_color("font_color", "HeaderLabel", accent)
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font_size("font_size", "TitleLabel", int(font_size * 3.0))
	theme.set_color("font_color", "TitleLabel", text_color)
	theme.set_type_variation("DimLabel", "Label")
	theme.set_font_size("font_size", "DimLabel", int(font_size * 0.85))
	theme.set_color("font_color", "DimLabel", dim_color)

	var panel := _box(panel_bg, border, border_width, 8)
	panel.set_content_margin_all(18)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	theme.set_stylebox("panel", "PopupMenu", panel)

	var button_bg := Color(0.08, 0.08, 0.08, 1) if high_contrast else Color(0.13, 0.16, 0.23, 0.95)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = accent
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(6)
	focus.set_expand_margin_all(2)
	var styles := {
		"normal": _box(button_bg, border, border_width, 6),
		"hover": _box(button_bg.lightened(0.15), accent, border_width, 6),
		"pressed": _box(button_bg.darkened(0.25), accent, border_width, 6),
		"hover_pressed": _box(button_bg.darkened(0.25), accent, border_width, 6),
		"disabled": _box(Color(button_bg, 0.45), Color(border, 0.3), border_width, 6),
		"focus": focus,
	}
	for type in BUTTON_TYPES:
		for style in styles:
			theme.set_stylebox(style, type, styles[style])
	for type in BUTTON_TYPES + TOGGLE_TYPES:
		theme.set_color("font_color", type, text_color)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_focus_color", type, text_color)
		theme.set_color("font_pressed_color", type, accent)
		theme.set_color("font_hover_pressed_color", type, accent)
		theme.set_color("font_disabled_color", type, Color(dim_color, 0.5))
	# Toggles inherit Button styles; keep them flat so only the switch shows.
	for type in TOGGLE_TYPES:
		for style in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			theme.set_stylebox(style, type, StyleBoxEmpty.new())
	for type in TOGGLE_TYPES + ["HSlider"]:
		theme.set_stylebox("focus", type, focus)
	return theme


static func _box(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box

extends "res://scripts/ui/modal_overlay.gd"
## Inventory: lists carried items with descriptions. Choosing an item selects
## it to use on the next object the player clicks.

const ICON_PREVIEW_SIZE := Vector2(128, 128)

var _icon: TextureRect
var _name: Label
var _description: Label


func _build() -> void:
	close_actions.append("toggle_inventory")
	add_title("Inventory")

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	content.add_child(columns)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)

	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 380
	columns.add_child(detail)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = ICON_PREVIEW_SIZE
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = TEXTURE_FILTER_NEAREST
	_icon.size_flags_horizontal = SIZE_SHRINK_BEGIN
	detail.add_child(_icon)
	_name = Label.new()
	_name.theme_type_variation = "HeaderLabel"
	detail.add_child(_name)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size.x = 380
	detail.add_child(_description)

	if GameState.inventory.is_empty():
		var empty := Label.new()
		empty.text = "Nothing yet.\nExamine things to find items."
		empty.theme_type_variation = "DimLabel"
		list.add_child(empty)
	for item_id in GameState.inventory:
		var button := Button.new()
		button.text = ContentDB.item_name(item_id)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = ContentDB.item_icon(item_id)
		button.texture_filter = TEXTURE_FILTER_NEAREST
		button.focus_entered.connect(_show.bind(item_id))
		button.mouse_entered.connect(_show.bind(item_id))
		button.pressed.connect(_use.bind(item_id))
		list.add_child(button)
		if focus_target == null:
			focus_target = button
			_show(item_id)

	add_wrapped_label("Choose an item to use it on the next object you click. Right-click or Esc cancels.", 680, "DimLabel")
	var close_button := add_button("Close", close)
	if focus_target == null:
		focus_target = close_button


func _show(item_id: String) -> void:
	var item: Dictionary = ContentDB.items.get(item_id, {})
	_icon.texture = ContentDB.item_icon(item_id)
	_icon.visible = _icon.texture != null
	_name.text = str(item.get("name", item_id))
	_description.text = str(item.get("description", ""))


func _use(item_id: String) -> void:
	GameState.select_item(item_id)
	close()

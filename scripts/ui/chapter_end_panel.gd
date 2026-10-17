extends "res://scripts/ui/modal_overlay.gd"
## End-of-chapter card: recaps the evidence the player found before moving on,
## as the Game Bible asks for before major story beats.

var chapter_id := ""


func _init(p_chapter_id: String = "") -> void:
	chapter_id = p_chapter_id


func _build() -> void:
	close_actions.clear()  # an ending shouldn't vanish on a stray Esc
	var chapter := ContentDB.chapter(chapter_id)
	var title := Label.new()
	title.text = str(chapter.get("title", "Chapter Complete"))
	title.theme_type_variation = "HeaderLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var line := ColorRect.new()
	line.color = Color("e8c87a")
	line.custom_minimum_size = Vector2(360, 2)
	line.size_flags_horizontal = SIZE_SHRINK_CENTER
	content.add_child(line)
	add_wrapped_label(str(chapter.get("summary", "")), 720)

	var found := GameState.evidence.size()
	add_wrapped_label("Evidence found: %d of %d    •    Time: %s" % [found, ContentDB.evidence.size(), SaveSystem.format_playtime(GameState.playtime_seconds)], 720, "DimLabel")
	var recap := PackedStringArray()
	for evidence_id in GameState.evidence:
		recap.append("•  " + ContentDB.evidence_title(evidence_id))
	add_wrapped_label("\n".join(recap), 720)
	if found < ContentDB.evidence.size():
		add_wrapped_label("Some clues are still hidden in the house. Keep exploring to find them all.", 720, "DimLabel")
	add_wrapped_label(str(chapter.get("teaser", "")), 720, "DimLabel")

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	focus_target = add_button("Keep Exploring", close, buttons)
	add_button("Return to Title", SceneRouter.goto_title, buttons)

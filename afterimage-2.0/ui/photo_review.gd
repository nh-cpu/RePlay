extends Node2D

signal dismissed

const CARD: PackedScene = preload("res://ui/photo_card.tscn")
var service: GenerationService
var photos: Array[Dictionary] = []
var preview_token: String = ""
var preview_folders: PackedStringArray = []
@onready var content: VBoxContainer = $Layer/Root/Panel/Margin/Content
@onready var rows: VBoxContainer = $Layer/Root/Panel/Margin/Content/Scroll/Photos

func _ready() -> void:
	$Layer/Root.resized.connect(_layout_review)
	_layout_review.call_deferred()
	content.get_node("Add").pressed.connect(func() -> void: $Picker.popup_centered_ratio(0.8))
	content.get_node("Buttons/Cancel").pressed.connect(_cancel)
	content.get_node("Buttons/Generate").pressed.connect(_generate)
	content.get_node("TitleInput").text_changed.connect(func(_text: String) -> void: _update())
	$Picker.files_selected.connect(_files_selected)
	service.preview_finished.connect(_preview_finished)
	_update()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()

func _cancel() -> void:
	for token: String in preview_folders:
		service.discard_preview(token)
	dismissed.emit()
	queue_free()

func _files_selected(paths: PackedStringArray) -> void:
	if paths.size() + photos.size() > 30:
		content.get_node("Status").text = "Choose at most 30 photos in total."
		return
	preview_token = service.preview(paths)
	if not preview_token.is_empty():
		preview_folders.append(preview_token)
	content.get_node("Status").text = "Preparing previews locally..." if not preview_token.is_empty() else service.message
	_update()

func _preview_finished(token: String, result: Dictionary) -> void:
	if token != preview_token:
		return
	preview_token = ""
	var errors: PackedStringArray = []
	if result.get("state") == "failed":
		errors.append(str(result.get("stage", "Could not prepare photos.")))
	for value: Dictionary in result.get("photos", []):
		if value.has("error"):
			errors.append(str(value.source).get_file() + ": " + str(value.error))
			continue
		var duplicate: bool = false
		for photo: Dictionary in photos:
			if photo.digest == value.digest or str(photo.source).to_lower() == str(value.source).to_lower():
				duplicate = true
		if duplicate:
			errors.append(str(value.name) + ": already selected.")
		else:
			photos.append(value)
	content.get_node("Status").text = "\n".join(errors)
	content.get_node("Status").tooltip_text = "\n".join(errors)
	_rebuild()

func _rebuild() -> void:
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for index: int in range(photos.size()):
		var row: HBoxContainer = CARD.instantiate()
		rows.add_child(row)
		var image: Image = Image.load_from_file(str(photos[index].thumbnail))
		if image != null:
			row.get_node("Thumbnail").texture = ImageTexture.create_from_image(image)
		row.get_node("Name").text = "%02d  %s" % [index + 1, photos[index].name]
		row.get_node("Earlier").disabled = index == 0
		row.get_node("Later").disabled = index == photos.size() - 1
		row.get_node("Earlier").pressed.connect(_move.bind(index, -1))
		row.get_node("Later").pressed.connect(_move.bind(index, 1))
		row.get_node("Remove").pressed.connect(_remove.bind(index))
	_update()

func _move(index: int, direction: int) -> void:
	var photo: Dictionary = photos[index]
	photos.remove_at(index)
	photos.insert(index + direction, photo)
	_rebuild()

func _remove(index: int) -> void:
	photos.remove_at(index)
	_rebuild()

func _update() -> void:
	content.get_node("Count").text = "%d / 30 PHOTOS  /  YOUR ALBUM STORY" % photos.size()
	content.get_node("Add").disabled = not preview_token.is_empty() or photos.size() >= 30
	content.get_node("Buttons/Generate").disabled = photos.is_empty() or not preview_token.is_empty() or content.get_node("TitleInput").text.strip_edges().is_empty()

func _generate() -> void:
	if content.get_node("Description").text.length() > 4000:
		content.get_node("Status").text = "Keep the description under 4,000 characters."
		return
	if service.start_generation(content.get_node("TitleInput").text, content.get_node("Description").text, photos):
		_cancel()
	else:
		content.get_node("Status").text = service.message

func _layout_review() -> void:
	var compact: bool = $Layer/Root.size.y < 780.0
	content.add_theme_constant_override("separation", 6 if compact else 10)
	content.get_node("Description").custom_minimum_size.y = 56 if compact else 76
	content.get_node("Scroll").custom_minimum_size.y = 64 if compact else 90
	content.get_node("Hint").add_theme_font_size_override("font_size", 14 if compact else 16)
	content.get_node("Count").add_theme_font_size_override("font_size", 14 if compact else 16)
	content.get_node("Disclosure").add_theme_font_size_override("font_size", 13 if compact else 14)

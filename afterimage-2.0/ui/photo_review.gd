extends Node2D

signal dismissed

const CARD: PackedScene = preload("res://ui/photo_card.tscn")
var service: GenerationService
var photos: Array[Dictionary] = []
var preview_token: String = ""
var preview_folders: PackedStringArray = []
var _drag_index: int = -1
var _drag_pointer: int = -2
var _drag_point: Vector2
var _drop_slot: int = 0
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

func _input(event: InputEvent) -> void:
	if _drag_index < 0 or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drag_pointer == -1:
		_drag_point = event.position
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and _drag_pointer == -1 and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		get_viewport().set_input_as_handled()
		_finish_drag(event.position)
	elif event is InputEventScreenDrag and event.index == _drag_pointer:
		_drag_point = event.position
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.index == _drag_pointer and not event.pressed:
		get_viewport().set_input_as_handled()
		if event.canceled:
			_cancel_drag()
		else:
			_finish_drag(event.position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		_cancel_drag()

func _process(delta: float) -> void:
	content.get_node("Status").visible = not content.get_node("Status").text.is_empty()
	if _drag_index < 0:
		return
	var scroll: ScrollContainer = content.get_node("Scroll")
	var rect: Rect2 = scroll.get_global_rect()
	var speed: float = 0.0
	if _drag_point.y < rect.position.y + 40:
		speed = -clampf((rect.position.y + 40 - _drag_point.y) / 40, 0, 1) * 480
	elif _drag_point.y > rect.end.y - 40:
		speed = clampf((_drag_point.y - rect.end.y + 40) / 40, 0, 1) * 480
	var bar: VScrollBar = scroll.get_v_scroll_bar()
	bar.value += speed * delta
	_update_drop_marker()

func _begin_drag(pointer: int, point: Vector2, index: int) -> void:
	if _drag_index >= 0:
		return
	_drag_index = index
	_drag_pointer = pointer
	_drag_point = point
	rows.get_child(index).modulate.a = 0.4
	_update_drop_marker()

func _update_drop_marker() -> void:
	_drop_slot = photos.size()
	var y: float = rows.get_global_rect().end.y
	for index: int in range(rows.get_child_count()):
		var rect: Rect2 = (rows.get_child(index) as Control).get_global_rect()
		if _drag_point.y < rect.get_center().y:
			_drop_slot = index
			y = rect.position.y - 3
			break
	var bounds: Rect2 = (content.get_node("Scroll") as Control).get_global_rect()
	var marker: ColorRect = $Layer/Root/DropMarker
	marker.position = Vector2(bounds.position.x, clampf(y, bounds.position.y, bounds.end.y - 3))
	marker.size = Vector2(bounds.size.x - 12, 3)
	marker.show()

func _finish_drag(point: Vector2) -> void:
	_drag_point = point
	_update_drop_marker()
	var source: int = _drag_index
	var target: int = _drop_slot - 1 if _drop_slot > source else _drop_slot
	var inside: bool = (content.get_node("Scroll") as Control).get_global_rect().has_point(point)
	_cancel_drag()
	if inside and source != target:
		_move(source, target - source)

func _cancel_drag() -> void:
	if _drag_index >= 0 and _drag_index < rows.get_child_count():
		rows.get_child(_drag_index).modulate.a = 1.0
	_drag_index = -1
	_drag_pointer = -2
	$Layer/Root/DropMarker.hide()

func _cancel() -> void:
	_cancel_drag()
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
	_cancel_drag()
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for index: int in range(photos.size()):
		var row: HBoxContainer = CARD.instantiate()
		rows.add_child(row)
		var image: Image = Image.load_from_file(str(photos[index].thumbnail))
		if image != null:
			row.get_node("Thumbnail").texture = ImageTexture.create_from_image(image)
		row.get_node("Handle").grabbed.connect(_begin_drag.bind(index))
		row.get_node("Handle").nudged.connect(_nudge.bind(index))
		row.get_node("Remove").pressed.connect(_remove.bind(index))
	_update()

func _nudge(direction: int, index: int) -> void:
	_move(index, direction)

func _move(index: int, direction: int) -> void:
	var photo: Dictionary = photos[index]
	photos.remove_at(index)
	photos.insert(clampi(index + direction, 0, photos.size()), photo)
	_rebuild()
	rows.get_child(clampi(index + direction, 0, photos.size() - 1)).get_node("Handle").grab_focus.call_deferred()

func _remove(index: int) -> void:
	photos.remove_at(index)
	_rebuild()

func _update() -> void:
	content.get_node("Count").text = "%d / 30 PHOTOS  ·  DRAG ≡ TO REORDER" % photos.size()
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
	content.get_node("Description").custom_minimum_size.y = 48 if compact else 56
	content.get_node("Scroll").custom_minimum_size.y = 64 if compact else 90
	content.get_node("Count").add_theme_font_size_override("font_size", 14 if compact else 16)
	content.get_node("Disclosure").add_theme_font_size_override("font_size", 13 if compact else 14)

class_name SongWheel
extends Control

signal song_selected(song_id: String)
signal difficulty_selected(song_id: String, difficulty_id: String)
signal play_requested(song_id: String, difficulty_id: String)

const CARD: PackedScene = preload("res://ui/song_card.tscn")
const PITCH: float = 104.0
const POOL_SIZE: int = 13
var songs: Array[SongMetadata] = []
var selected_index: int = -1
var scroll_position: float = 0.0
var velocity: float = 0.0
var navigation_enabled: bool = true
var choices: Dictionary = {}
var _cards: Dictionary = {}
var _pool: Array[SongCard] = []
var _weights: Dictionary = {}
var _cache: Dictionary = {}
var _cache_order: Array[String] = []
var _motion: Tween
var _expansion: Tween
var _pointer: int = -2
var _start: Vector2
var _last: Vector2
var _last_msec: int = 0
var _dragged: bool = false
var _tap_id: String = ""
var _tap_msec: int = 0
var _tap_pointer: int = -2
var _tap_point: Vector2
var _held: Vector2i = Vector2i.ZERO
var _repeat_time: float = 0.0

func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	resized.connect(_layout_cards)
	for index: int in range(POOL_SIZE):
		var card: SongCard = CARD.instantiate()
		add_child(card)
		card.hide()
		_pool.append(card)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_cancel_input()
		_set_scroll(float(roundi(scroll_position)))

func _process(delta: float) -> void:
	if not navigation_enabled:
		return
	if not _input_available():
		_held = Vector2i.ZERO
	if _held != Vector2i.ZERO and _input_available():
		_repeat_time -= delta
		if _repeat_time <= 0:
			_repeat_time += 0.1
			_navigate(_held)
	if _pointer == -2 and absf(velocity) > 0:
		var decay: float = exp(-8.0 * delta)
		_set_scroll(scroll_position + velocity * (1.0 - decay) / 8.0)
		velocity *= decay
		if scroll_position <= 0 or scroll_position >= songs.size() - 1 or absf(velocity) < 0.12:
			velocity = 0
			_snap()
	_layout_cards()

func _gui_input(event: InputEvent) -> void:
	if not navigation_enabled or songs.is_empty():
		return
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_unhandled_input(event)
		return
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			step_song(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if event.pressed:
				_begin_pointer(-1, event.position)
			else:
				_end_pointer(-1, event.position)
	elif event is InputEventMouseMotion and _pointer == -1:
		_move_pointer(-1, event.position)
		accept_event()
	elif event is InputEventScreenTouch:
		accept_event()
		if event.pressed:
			_begin_pointer(event.index, event.position)
		else:
			_end_pointer(event.index, event.position, event.canceled)
	elif event is InputEventScreenDrag:
		_move_pointer(event.index, event.position)
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if not _input_available():
		return
	if event is InputEventKey and event.echo:
		return
	if event is InputEventJoypadMotion:
		if event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
			var direction: int = signi(int(signf(event.axis_value))) if absf(event.axis_value) >= 0.5 else 0
			var value: Vector2i = _held
			if event.axis == JOY_AXIS_LEFT_Y:
				value.y = direction
			else:
				value.x = direction
			_set_held(value)
			get_viewport().set_input_as_handled()
		return
	for action: String in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if event.is_action(action):
			var value: Vector2i = _held
			var direction: int = -1 if action in ["ui_up", "ui_left"] else 1
			if action in ["ui_up", "ui_down"]:
				value.y = direction if event.is_pressed() else 0
			else:
				value.x = direction if event.is_pressed() else 0
			_set_held(value)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		request_play()

func set_songs(values: Array[SongMetadata]) -> void:
	var previous: String = selected_song_id()
	_cancel_input()
	if _expansion != null:
		_expansion.kill()
	for card: SongCard in _cards.values():
		card.artwork = null
		card.hide()
		_pool.append(card)
	_cards.clear()
	_weights.clear()
	songs = values
	selected_index = -1
	if songs.is_empty():
		queue_redraw()
		return
	var target: String = previous if _index_of(previous) >= 0 else songs[0].id
	select_song(target, false)

func select_song(song_id: String, animated: bool = true) -> void:
	var index: int = _index_of(song_id)
	if index < 0:
		return
	_choose(index, animated)
	_stop_motion()
	if animated:
		_motion = create_tween()
		_motion.tween_method(_set_scroll, scroll_position, float(index), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		_set_scroll(float(index))
	_layout_cards()

func select_difficulty(difficulty_id: String) -> void:
	if selected_index < 0:
		return
	var song: SongMetadata = songs[selected_index]
	for index: int in range(song.difficulties.size()):
		if song.difficulties[index].id == difficulty_id:
			if int(choices.get(song.id, -1)) != index:
				_tap_id = ""
			choices[song.id] = index
			difficulty_selected.emit(song.id, difficulty_id)
			_layout_cards()
			return

func set_navigation_enabled(enabled: bool) -> void:
	navigation_enabled = enabled
	if not enabled:
		_cancel_input()
		if selected_index >= 0:
			_set_scroll(float(selected_index))

func selected_song_id() -> String:
	return songs[selected_index].id if selected_index >= 0 and selected_index < songs.size() else ""

func selected_difficulty_id() -> String:
	if selected_index < 0 or songs[selected_index].difficulties.is_empty():
		return ""
	var song: SongMetadata = songs[selected_index]
	return song.difficulties[clampi(int(choices.get(song.id, 0)), 0, song.difficulties.size() - 1)].id

func request_play() -> void:
	if navigation_enabled and not selected_difficulty_id().is_empty():
		play_requested.emit(selected_song_id(), selected_difficulty_id())

func step_song(direction: int) -> void:
	if songs.is_empty():
		return
	select_song(songs[clampi(selected_index + direction, 0, songs.size() - 1)].id)

func artwork_for(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		_cache_order.erase(path)
		_cache_order.append(path)
		return _cache[path]
	var texture: Texture2D
	if path.begins_with("res://") and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image: Image = Image.load_from_file(path)
		if image != null and not image.is_empty():
			if maxi(image.get_width(), image.get_height()) > 1280:
				var ratio: float = 1280.0 / maxi(image.get_width(), image.get_height())
				image.resize(maxi(1, int(image.get_width() * ratio)), maxi(1, int(image.get_height() * ratio)))
			texture = ImageTexture.create_from_image(image)
	_cache[path] = texture
	_cache_order.append(path)
	while _cache_order.size() > 16:
		_cache.erase(_cache_order.pop_front())
	return texture

func artwork_for_song(song: SongMetadata) -> Texture2D:
	if not song.artwork_path.is_empty():
		var existing: Texture2D = artwork_for(song.artwork_path)
		if existing != null:
			return existing
	for path: String in song.artwork_candidates:
		var texture: Texture2D = artwork_for(path)
		if texture != null:
			song.artwork_path = path
			return texture
	return null

func _input_available() -> bool:
	if not navigation_enabled or not is_visible_in_tree():
		return false
	var owner: Control = get_viewport().gui_get_focus_owner()
	return owner == null or owner == self

func _set_held(value: Vector2i) -> void:
	if value != _held:
		_held = value
		_repeat_time = 0.3
		if value != Vector2i.ZERO:
			_navigate(value)

func _navigate(value: Vector2i) -> void:
	if value.y != 0:
		step_song(value.y)
	elif value.x != 0 and selected_index >= 0:
		var song: SongMetadata = songs[selected_index]
		if not song.difficulties.is_empty():
			var index: int = clampi(int(choices.get(song.id, 0)) + value.x, 0, song.difficulties.size() - 1)
			select_difficulty(song.difficulties[index].id)

func _choose(index: int, animated: bool) -> void:
	if index == selected_index:
		return
	selected_index = index
	_tap_id = ""
	var song: SongMetadata = songs[index]
	var default_choice: int = 0
	for variant: int in range(song.difficulties.size()):
		if song.difficulties[variant].label.to_lower() == "easy":
			default_choice = variant
	var choice: int = clampi(int(choices.get(song.id, default_choice)), 0, maxi(0, song.difficulties.size() - 1))
	choices[song.id] = choice
	if _expansion != null:
		_expansion.kill()
	_expansion = create_tween().set_parallel(true)
	_expansion.tween_interval(0.0)
	for key: int in _weights.keys():
		if key != index:
			_expansion.tween_method(_set_weight.bind(key), float(_weights[key]), 0.0, 0.2)
	if animated:
		_expansion.tween_method(_set_weight.bind(index), float(_weights.get(index, 0.0)), 1.0, 0.2)
	else:
		_weights[index] = 1.0
	song_selected.emit(song.id)
	if not song.difficulties.is_empty():
		difficulty_selected.emit(song.id, song.difficulties[choice].id)

func _set_weight(value: float, index: int) -> void:
	if value <= 0.0001:
		_weights.erase(index)
	else:
		_weights[index] = value

func _set_scroll(value: float) -> void:
	scroll_position = clampf(value, 0.0, maxf(0, songs.size() - 1))
	if not songs.is_empty() and (_motion == null or not _motion.is_running()):
		_choose(clampi(roundi(scroll_position), 0, songs.size() - 1), true)

func _offset(index: int) -> float:
	var value: float = index * PITCH
	for key: int in _weights.keys():
		if key < index and key < songs.size():
			value += (songs[key].difficulties.size() * 38.0 + 10.0) * float(_weights[key])
	return value

func _layout_cards() -> void:
	if not is_node_ready() or songs.is_empty():
		return
	var middle: int = clampi(roundi(scroll_position), 0, songs.size() - 1)
	var first: int = maxi(0, middle - 6)
	var last: int = mini(songs.size() - 1, middle + 6)
	for index: int in _cards.keys():
		if index < first or index > last:
			var card: SongCard = _cards[index]
			card.artwork = null
			card.hide()
			_pool.append(card)
			_cards.erase(index)
	var lower: int = floori(scroll_position)
	var center_offset: float = lerpf(_offset(lower), _offset(mini(lower + 1, songs.size() - 1)), fmod(scroll_position, 1.0))
	var selected_extent: float = (96 + songs[selected_index].difficulties.size() * 38) * 1.06 if selected_index >= 0 else 86
	var anchor_y: float = maxf(48, minf(size.y * 0.40, size.y - selected_extent + 31))
	for index: int in range(first, last + 1):
		if not _cards.has(index):
			var card: SongCard = _pool.pop_back()
			_cards[index] = card
			card.configure(songs[index], artwork_for_song(songs[index]))
		var card: SongCard = _cards[index]
		var distance: float = float(index) - scroll_position
		var weight: float = float(_weights.get(index, 0.0))
		card.scale = Vector2.ONE * lerpf(1.0, 1.06, weight)
		card.size = Vector2(maxf(120, size.x - 42) / 1.06, 86 + songs[index].difficulties.size() * 38 * weight + 10)
		card.position = Vector2(10 + minf(92, distance * distance * 13), anchor_y + _offset(index) - center_offset - 43)
		card.modulate.a = lerpf(0.55, 1.0, weight)
		card.z_index = 2 if index == selected_index else 0
		card.present(weight, int(choices.get(songs[index].id, 0)))
		card.show()

func _begin_pointer(id: int, point: Vector2) -> void:
	if _pointer != -2:
		return
	grab_focus()
	_stop_motion()
	_pointer = id
	_start = point
	_last = point
	_last_msec = Time.get_ticks_msec()
	_dragged = false

func _move_pointer(id: int, point: Vector2) -> void:
	if id != _pointer:
		return
	var now: int = Time.get_ticks_msec()
	if not _dragged and point.distance_to(_start) >= 10:
		_dragged = true
		_tap_id = ""
	if _dragged:
		var movement: float = -(point.y - _last.y) / PITCH
		velocity = clampf(movement / maxf(0.008, (now - _last_msec) / 1000.0), -8, 8)
		_set_scroll(scroll_position + movement)
	_last = point
	_last_msec = now

func _end_pointer(id: int, point: Vector2, canceled: bool = false) -> void:
	if id != _pointer:
		return
	_pointer = -2
	if canceled:
		velocity = 0
		_tap_id = ""
		_snap()
	elif _dragged:
		if Time.get_ticks_msec() - _last_msec > 100:
			velocity = 0
		if absf(velocity) < 0.12:
			_snap()
	else:
		velocity = 0
		_activate_at(point, id)
		if is_inside_tree() and (_motion == null or not _motion.is_running()):
			_snap()

func _activate_at(point: Vector2, pointer_id: int = -1) -> void:
	# Test selected card first because it is enlarged above neighboring cards.
	var order: Array = _cards.keys()
	order.erase(selected_index)
	order.push_front(selected_index)
	for index: int in order:
		if not _cards.has(index):
			continue
		var card: SongCard = _cards[index]
		var local: Vector2 = (point - card.position) / card.scale
		if not Rect2(Vector2.ZERO, card.size).has_point(local):
			continue
		var difficulty: int = card.difficulty_at(local)
		if index != selected_index or difficulty < 0:
			select_song(songs[index].id)
			_tap_id = ""
			return
		var id: String = songs[index].difficulties[difficulty].id
		var double_tap: bool = id == _tap_id and pointer_id == _tap_pointer and point.distance_to(_tap_point) < 24 and Time.get_ticks_msec() - _tap_msec <= 350
		select_difficulty(id)
		_tap_id = id
		_tap_msec = Time.get_ticks_msec()
		_tap_pointer = pointer_id
		_tap_point = point
		if double_tap:
			_tap_id = ""
			request_play()
		return

func _snap() -> void:
	if not songs.is_empty():
		select_song(songs[clampi(roundi(scroll_position), 0, songs.size() - 1)].id)

func _stop_motion() -> void:
	velocity = 0
	if _motion != null:
		_motion.kill()
		_motion = null

func _cancel_input() -> void:
	_stop_motion()
	_pointer = -2
	_held = Vector2i.ZERO
	_tap_id = ""

func _index_of(song_id: String) -> int:
	for index: int in range(songs.size()):
		if songs[index].id == song_id:
			return index
	return -1

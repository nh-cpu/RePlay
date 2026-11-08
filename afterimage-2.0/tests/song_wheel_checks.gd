extends SceneTree

var checks: int = 0
var failures: int = 0
var wheel: SongWheel
var selections: Array[String] = []
var launches: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func fixture(count: int) -> Array[SongMetadata]:
	var songs: Array[SongMetadata] = []
	for index: int in range(count):
		var song: SongMetadata = SongMetadata.new()
		song.id = "song_%d" % index
		song.title = "Track %d" % index
		song.artist = "Fixture artist"
		for label: String in ["Easy", "Normal", "Hard"]:
			var variant: SongDifficultyMetadata = SongDifficultyMetadata.new()
			variant.id = song.id + "/" + label
			variant.label = label
			variant.best_score = 1000 if label == "Hard" else 0
			song.difficulties.append(variant)
		songs.append(song)
	return songs

func key(code: Key, pressed: bool = true) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	wheel._gui_input(event)

func _run() -> void:
	wheel = load("res://ui/song_wheel.tscn").instantiate()
	root.add_child(wheel)
	wheel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	wheel.size = Vector2(540, 500)
	wheel.song_selected.connect(func(id: String) -> void: selections.append(id))
	wheel.play_requested.connect(func(_id: String, chart: String) -> void: launches.append(chart))
	wheel.set_songs(fixture(1000))
	wheel.grab_focus()
	check(wheel.selected_song_id() == "song_0", "Initial selection")
	check(wheel.selected_difficulty_id() == "song_0/Easy", "Easy default")
	check(wheel._cards.size() <= 13, "Large library uses bounded card pool")
	wheel.select_song("song_30", false)
	check(wheel.selected_song_id() == "song_30", "Stable ID selection")
	wheel.select_difficulty("song_30/Hard")
	check(wheel.selected_difficulty_id() == "song_30/Hard", "Difficulty selection")
	wheel.select_song("song_31", false)
	wheel.select_song("song_30", false)
	check(wheel.selected_difficulty_id() == "song_30/Hard", "Difficulty remembered")
	wheel.set_songs(fixture(1001))
	check(wheel.selected_song_id() == "song_30", "Refresh preserves song")
	check(wheel.selected_difficulty_id() == "song_30/Hard", "Refresh preserves difficulty")
	wheel.step_song(1)
	wheel.step_song(1)
	await create_timer(0.32).timeout
	check(wheel.selected_song_id() == "song_32" and is_equal_approx(wheel.scroll_position, 32), "Interrupted navigation reaches latest target")
	key(KEY_DOWN)
	key(KEY_DOWN, false)
	await create_timer(0.3).timeout
	check(wheel.selected_song_id() == "song_33", "Keyboard navigation")
	key(KEY_RIGHT)
	key(KEY_RIGHT, false)
	check(wheel.selected_difficulty_id() == "song_33/Normal", "Keyboard difficulty")
	var echo: InputEventKey = InputEventKey.new()
	echo.keycode = KEY_DOWN
	echo.pressed = true
	echo.echo = true
	wheel._gui_input(echo)
	check(wheel.selected_song_id() == "song_33", "Keyboard echo suppressed")
	var routed: InputEventKey = InputEventKey.new()
	routed.keycode = KEY_UP
	routed.pressed = true
	Input.parse_input_event(routed)
	await process_frame
	routed.pressed = false
	Input.parse_input_event(routed)
	check(wheel.selected_song_id() == "song_32", "Real viewport keyboard routing")
	wheel.select_song("song_33", false)
	var axis: InputEventJoypadMotion = InputEventJoypadMotion.new()
	axis.axis = JOY_AXIS_LEFT_Y
	axis.axis_value = 0.4
	wheel._unhandled_input(axis)
	check(wheel.selected_song_id() == "song_33", "Stick deadzone")
	axis.axis_value = 1
	wheel._unhandled_input(axis)
	check(wheel.selected_song_id() == "song_34", "Controller stick navigation")
	wheel._process(0.29)
	check(wheel.selected_song_id() == "song_34", "Controller initial delay")
	wheel._process(0.02)
	check(wheel.selected_song_id() == "song_35", "Controller repeat")
	axis.axis_value = 0
	wheel._unhandled_input(axis)
	wheel.select_song("song_10", false)
	wheel.set_process(false)
	wheel.scroll_position = 10.2
	wheel.velocity = 4
	for index: int in range(6):
		wheel._process(1.0 / 30.0)
	var coarse: float = wheel.scroll_position
	wheel._stop_motion()
	wheel.scroll_position = 10.2
	wheel.velocity = 4
	for index: int in range(24):
		wheel._process(1.0 / 120.0)
	check(absf(coarse - wheel.scroll_position) < 0.0001, "Inertia is frame-rate independent")
	wheel._stop_motion()
	wheel.set_process(true)
	wheel.select_song("song_10", false)
	wheel._begin_pointer(7, Vector2(200, 200))
	wheel._begin_pointer(8, Vector2(100, 100))
	check(wheel._pointer == 7, "One finger owns gesture")
	wheel._move_pointer(7, Vector2(200, 80))
	check(wheel._dragged and wheel.scroll_position > 10, "Touch drag scrolls")
	wheel._end_pointer(7, Vector2(200, 80), true)
	await create_timer(0.3).timeout
	check(wheel._pointer == -2 and is_equal_approx(wheel.scroll_position, roundf(wheel.scroll_position)), "Cancellation snaps and releases pointer")
	var emulated: InputEventScreenTouch = InputEventScreenTouch.new()
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	emulated.pressed = true
	emulated.index = 0
	wheel._gui_input(emulated)
	check(wheel._pointer == -2, "Emulated touch suppressed")
	wheel.select_song("song_10", false)
	await create_timer(0.25).timeout
	wheel._layout_cards()
	var card: SongCard = wheel._cards[10]
	var point: Vector2 = card.position + Vector2(50, 86 + 6 + 19) * card.scale
	wheel._activate_at(point)
	check(launches.is_empty(), "Single difficulty click selects only")
	wheel._activate_at(point)
	check(launches.size() == 1 and launches[0] == "song_10/Easy", "Double difficulty click launches correct chart")
	wheel._activate_at(point, 2)
	check(launches.size() == 1, "Mouse and touch do not form a double activation")
	wheel._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(wheel._pointer == -2 and wheel._held == Vector2i.ZERO and wheel.velocity == 0, "Focus loss releases gestures and held navigation")
	wheel.set_navigation_enabled(false)
	key(KEY_DOWN)
	wheel.request_play()
	check(wheel.selected_song_id() == "song_10" and launches.size() == 1, "Modal blocks navigation and play")
	wheel.set_navigation_enabled(true)
	wheel.select_song("song_0", false)
	wheel.step_song(-1)
	await create_timer(0.3).timeout
	check(wheel.selected_song_id() == "song_0", "First endpoint clamped")
	wheel.select_song("song_1000", false)
	wheel.step_song(1)
	check(wheel.selected_song_id() == "song_1000", "Last endpoint clamped")
	for index: int in range(20):
		wheel.artwork_for("res://tests/artifacts/not_present_%d.jpg" % index)
	check(wheel._cache.size() <= 16, "Artwork cache is bounded, including failed paths")
	wheel.set_songs(fixture(1))
	wheel.step_song(1)
	check(wheel.selected_song_id() == "song_0", "Single song")
	var empty: Array[SongMetadata] = []
	wheel.set_songs(empty)
	wheel.request_play()
	check(wheel.selected_index == -1 and launches.size() == 1, "Empty library cannot play")
	wheel.queue_free()
	await process_frame
	await _integration()
	await create_timer(1.2).timeout
	print("SONG WHEEL: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _integration() -> void:
	var service: GenerationService = GenerationService.new()
	service.config_path = "res://tests/artifacts/wheel_preferences.cfg"
	service.jobs_root = "res://tests/artifacts/wheel_jobs"
	root.add_child(service)
	var home: Control = load("res://ui/home_menu.tscn").instantiate()
	home.library = LevelLibrary.new("res://tests/artifacts/wheel_library")
	home.service = service
	root.add_child(home)
	var results: Array[ChartData] = []
	home.play_requested.connect(func(chart: ChartData) -> void: results.append(chart))
	home._play()
	check(results.size() == 1 and results[0].source_path == "res://levels/first_light.json", "Home maps chart ID to existing ChartData")
	home._open_review()
	check(not home.wheel.navigation_enabled and is_instance_valid(home.review), "Photo review disables wheel")
	home.review._cancel()
	await process_frame
	check(home.wheel.navigation_enabled, "Cancel restores wheel navigation")
	home.play_requested.connect(func(_chart: ChartData) -> void: root.remove_child(home))
	var accept: InputEventKey = InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.pressed = true
	home.wheel._gui_input(accept)
	check(not home.is_inside_tree() and results.size() == 2, "Confirm safely allows immediate scene replacement")
	home.queue_free()
	service.queue_free()
	await process_frame

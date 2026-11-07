extends SceneTree

var failures: int = 0
var assertions: int = 0
var outcomes: Array[int] = []
var presses: Array[int] = []
var releases: Array[int] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_loader()
	_test_judgments()
	_test_frame_rates()
	_test_input()
	_test_import()
	await _test_scenes()
	print("AFTERIMAGE: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(message)

func _fixture() -> Dictionary:
	return {"format_version": 1, "song": "song.wav", "bpm": 120.0, "offset_seconds": 0.15, "lane_count": 4,
		"notes": [{"beat": 0.0, "lane": 0, "type": "tap"}, {"beat": 2.0, "lane": 1, "type": "hold", "duration_beats": 2.0}]}

func _test_loader() -> void:
	var loader: ChartLoader = ChartLoader.new()
	var chart: ChartData = loader.parse_data(_fixture(), "C:/music/chart.json")
	_check(chart != null and is_equal_approx(chart.notes[1].time, 1.15), "Beat-to-time conversion")
	_check(is_equal_approx(chart.notes[1].duration, 1.0), "Hold duration")
	_check(chart.song_path == "C:/music/song.wav", "Relative audio resolution")
	for field: String in ["bpm", "offset_seconds", "lane_count", "format_version", "notes", "song"]:
		var data: Dictionary = _fixture()
		data.erase(field)
		_check(loader.parse_data(data) == null, "Missing field: " + field)
	for value: Variant in [0.0, -12.0, INF, NAN, "120"]:
		var data: Dictionary = _fixture()
		data.bpm = value
		_check(loader.parse_data(data) == null, "Invalid BPM rejected")
	for lane: float in [-1.0, 4.0, 1.5]:
		var data: Dictionary = _fixture()
		data.notes[0].lane = lane
		_check(loader.parse_data(data) == null, "Invalid lane rejected")
	var data: Dictionary = _fixture()
	data.notes.append({"beat": 3, "lane": 1, "type": "tap"})
	_check(loader.parse_data(data) == null, "Overlap rejected")
	data = _fixture()
	data.notes.append(data.notes[0].duplicate())
	_check(loader.parse_data(data) == null, "Duplicate rejected")
	data = _fixture()
	data.notes[1].duration_beats = 0
	_check(loader.parse_data(data) == null, "Zero hold rejected")
	data = _fixture()
	data.notes.reverse()
	_check(loader.parse_data(data).notes[0].lane == 0, "Chart sorted")
	data = _fixture()
	data.notes.append({"beat": 0, "lane": 3, "type": "tap"})
	_check(loader.parse_data(data) != null, "Chords accepted")
	_check(loader.load_chart("res://levels/first_light.json") != null, "Bundled demo loads: " + loader.error)

func _test_judgments() -> void:
	for grade: int in range(4):
		var boundary: float = [0.04, 0.08, 0.12, 0.16][grade]
		_check(JudgmentController.grade_for(boundary) == grade, "Inclusive late boundary")
		_check(JudgmentController.grade_for(-boundary) == grade, "Inclusive early boundary")
		_check(JudgmentController.grade_for(boundary + 0.00001) == grade + 1, "Outside boundary")
	var chart: ChartData = ChartLoader.new().parse_data(_fixture())
	var judge: JudgmentController = JudgmentController.new()
	judge.judged.connect(func(_index: int, grade: int) -> void: outcomes.append(grade))
	judge.setup(chart)
	judge.press(0, 0.15)
	judge.press(0, 0.15)
	_check(outcomes == [0], "Tap is scored once")
	judge.press(1, 1.15)
	_check(outcomes.size() == 1 and judge.states[1] == 1, "Hold head defers score")
	judge.release(1, 2.15)
	_check(outcomes == [0, 0], "Release on tail completes")
	outcomes.clear()
	judge.setup(chart)
	judge.press(1, 1.15)
	judge.release(1, 1.5)
	_check(outcomes == [4, 4], "Missed tap and early-release hold")
	judge.advance(5.0)
	_check(outcomes.size() == 2, "No double miss")
	outcomes.clear()
	judge.setup(chart)
	judge.press(3, 0.15)
	_check(outcomes.is_empty(), "Empty press has no penalty")
	judge.free()
	var tracker: ScoreTracker = ScoreTracker.new()
	for grade: int in [0, 1, 2, 3, 4]:
		tracker.record(grade)
	_check(tracker.score == 2500 and tracker.max_combo == 4 and tracker.combo == 0, "Score and combo rules")
	_check(is_equal_approx(tracker.summary(5).accuracy, 50.0), "Weighted accuracy")
	tracker.free()

func _touch(index: int, position: Vector2, down: bool) -> InputEventScreenTouch:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = down
	return event

func _test_frame_rates() -> void:
	var chart: ChartData = ChartLoader.new().load_chart("res://levels/first_light.json")
	for fps: int in [30, 60, 144]:
		var judge: JudgmentController = JudgmentController.new()
		var tracker: ScoreTracker = ScoreTracker.new()
		judge.setup(chart)
		judge.judged.connect(func(_index: int, grade: int) -> void: tracker.record(grade))
		var events: Array[Dictionary] = []
		for note: NoteData in chart.notes:
			events.append({"time": note.time, "lane": note.lane, "down": true})
			events.append({"time": note.end_time() + 0.001, "lane": note.lane, "down": false})
		events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.time < b.time)
		var next: int = 0
		for frame: int in range(38 * fps):
			var time: float = float(frame) / fps
			while next < events.size() and events[next].time <= time:
				var event: Dictionary = events[next]
				if event.down:
					judge.press(event.lane, event.time)
				else:
					judge.release(event.lane, event.time)
				next += 1
			judge.advance(time)
		_check(tracker.counts[0] == chart.notes.size(), "Perfect full demo at %d FPS" % fps)
		_check(tracker.max_combo == chart.notes.size(), "Full combo at %d FPS" % fps)
		judge.free()
		tracker.free()

func _test_input() -> void:
	var controls: LaneInput = LaneInput.new()
	controls.regions = [Rect2(0, 0, 100, 500), Rect2(100, 0, 100, 500), Rect2(200, 0, 100, 500), Rect2(300, 0, 100, 500)]
	controls.pressed.connect(func(lane: int) -> void: presses.append(lane))
	controls.released.connect(func(lane: int) -> void: releases.append(lane))
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	controls._input(key)
	controls._input(_touch(0, Vector2(30, 200), true))
	controls._input(_touch(1, Vector2(130, 200), true))
	_check(presses == [0, 1], "Keyboard and touch merge; multitouch chord")
	key.echo = true
	controls._input(key)
	_check(presses.size() == 2, "Key repeats ignored")
	key.echo = false
	key.pressed = false
	controls._input(key)
	_check(releases.is_empty(), "Touch keeps lane held after keyboard release")
	controls._input(_touch(0, Vector2(330, 200), false))
	_check(releases == [0], "Finger release stays bound to original lane")
	controls.clear()
	_check(not controls.held.has(true), "Pause clears held state")
	controls.free()

func _test_import() -> void:
	var base: String = "user://test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(base)
	var source: String = base.path_join("source.json")
	var data: Dictionary = _fixture()
	data.song = "source.wav"
	var source_audio: String = base.path_join("source.wav")
	var audio_file: FileAccess = FileAccess.open(source_audio, FileAccess.WRITE)
	audio_file.store_buffer(FileAccess.get_file_as_bytes("res://assets/first_light.wav"))
	audio_file.close()
	var file: FileAccess = FileAccess.open(source, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var loader: ChartLoader = ChartLoader.new()
	var chart: ChartData = loader.load_chart(source)
	var library: LevelLibrary = LevelLibrary.new(base)
	var imported: String = library.import_chart(chart)
	_check(not imported.is_empty(), "Chart import succeeds: " + library.error)
	DirAccess.remove_absolute(source)
	DirAccess.remove_absolute(source_audio)
	_check(loader.load_chart(imported) != null, "Imported chart independent of original JSON and audio")
	library.save_best(imported, 1234)
	library.save_best(imported, 12)
	var reopened: LevelLibrary = LevelLibrary.new(base)
	_check(reopened.best(imported) == 1234, "Best score persists and never decreases")
	_check(reopened.list_paths().has(imported), "Library survives restart")
	file = FileAccess.open(source, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	_check(loader.load_chart(source) == null, "Malformed JSON rejected")
	data.song = "missing.wav"
	file = FileAccess.open(source, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	_check(loader.load_chart(source) == null and loader.missing_audio, "Missing audio requests picker")
	_check(loader.load_chart(source, "res://assets/first_light.wav") != null, "Audio picker override")
	DirAccess.remove_absolute(source)
	DirAccess.remove_absolute(imported.get_base_dir().path_join("song.wav"))
	DirAccess.remove_absolute(imported)
	DirAccess.remove_absolute(imported.get_base_dir())
	DirAccess.remove_absolute(library.root_path)
	DirAccess.remove_absolute(library.best_path)
	DirAccess.remove_absolute(base)

func _test_scenes() -> void:
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	_check(app.screen.charts.size() >= 1, "Home lists demo")
	var chart: ChartData = ChartLoader.new().load_chart("res://levels/first_light.json")
	app.start_game(chart)
	await process_frame
	var game: Control = app.screen
	game.clock.freeze(true)
	_check(game.lanes.size() == 4, "Four scene-based lanes")
	var field: PerspectivePlayfield = game.get_node("Playfield")
	for depth: float in [0.05, 0.5, 0.85]:
		for lane_index: int in range(4):
			var source_uv: Vector2 = Vector2((lane_index + 0.5) / 4.0, depth)
			var perspective_scale: float = field.distant_width / (1.0 - (1.0 - field.distant_width) * depth)
			var projected: Vector2 = Vector2(0.5 + (source_uv.x - 0.5) * perspective_scale, depth * perspective_scale)
			var screen_point: Vector2 = field.get_global_transform_with_canvas() * (projected * field.size)
			var mapped: Vector2 = field.screen_to_surface(screen_point)
			_check(mapped.is_equal_approx(source_uv * Vector2(field.surface.size)), "Perspective inverse at lane %d, depth %.2f" % [lane_index, depth])
			game.controls._input(_touch(20, screen_point, true))
			_check(game.controls.held[lane_index], "Projected touch selects correct lane")
			game.controls._input(_touch(20, screen_point, false))
	_check(field.screen_to_surface(field.global_position + Vector2(1, 1)) == Vector2(-1, -1), "Outside trapezoid rejected")
	game.clock.time = 2.0
	game.judge.press(chart.notes[0].lane, 2.0)
	game.scheduler.update(2.0, game.judge.states)
	_check(game.judge.states[0] == 1, "Demo starts with a hold")
	game._pause()
	_check(game.clock.frozen and game.controls.held == [false, false, false, false], "Pause freezes clock and clears input")
	game._resume()
	game.controls.held[chart.notes[0].lane] = true
	game._process(3.1)
	_check(not game.paused and game.judge.states[0] == 1, "Hold re-engaged during countdown")
	game.clock.freeze(true)
	game.scheduler.update(2.25, game.judge.states)
	var view: NoteView = game.scheduler.views[0]
	_check(is_equal_approx(view.position.y, game.lanes[view.data.lane].hit_y), "Active hold anchored to receptor")
	var tap: NoteView = game.scheduler.views[1]
	var initial_y: float = tap.position.y
	game.scheduler.update(2.5, game.judge.states)
	game.scheduler.update(2.25, game.judge.states)
	_check(is_equal_approx(tap.position.y, initial_y), "Note positions depend on song time, not accumulated frames")
	app.start_game(chart)
	await process_frame
	game = app.screen
	_check(game.score.score == 0 and game.scheduler.next_note <= 1, "Retry resets score and scheduler")
	game.clock.freeze(true)
	game.clock.time = 40.0
	# Avoid saving a simulated result into the player's personal bests.
	game.completed.disconnect(app.show_results)
	var results: Array[Dictionary] = []
	game.completed.connect(func(result: Dictionary) -> void: results.append(result))
	game._process(0.0)
	_check(results.size() == 1 and results[0].counts[4] == chart.notes.size(), "Song ends with all missed notes counted")
	app.queue_free()
	await process_frame

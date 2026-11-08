extends SceneTree

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var app: Control = load("res://main.tscn").instantiate()
	root.add_child(app)
	var chart: ChartData = ChartLoader.new().load_chart("res://levels/first_light.json")
	var background: AlbumData = AlbumData.new()
	var image: Image = Image.create(240, 180, false, Image.FORMAT_RGB8)
	image.fill(Color.CORNFLOWER_BLUE)
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var path: String = "res://tests/artifacts/watch_photo.jpg"
	image.save_jpg(path)
	background.photos.append(ProjectSettings.globalize_path(path))
	background.cues = [{"photo": 0, "start": 0.0, "end": 36.0}]
	chart.album = background
	var bests_before: Dictionary = app.library.bests.duplicate()
	app.start_watch(chart)
	await process_frame
	var watch: Control = app.screen
	check(not watch.has_node("JudgmentController") and not watch.has_node("Playfield"), "Watch scene contains no gameplay")
	watch.clock._process(0.01)
	check(watch.music.playing, "Watch starts audio without countdown")
	watch.clock.time = 5.0
	watch._process(0.0)
	check(watch.album.visible and watch.album.first.texture != null, "Watch renders album photos")
	var before: Rect2 = watch.album.first.get_rect()
	watch.clock.time = 15.0
	watch._process(0.0)
	check(watch.album.first.get_rect() != before, "Photos pan as audio time advances")
	watch._show_controls()
	watch._process(2.9)
	check(not watch._controls_hidden, "Controls remain visible before three idle seconds")
	watch._process(0.11)
	await create_timer(0.25).timeout
	check(not watch.get_node("Controls").visible, "Controls disappear after idle timeout")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(4, 0)
	watch._input(motion)
	check(watch.get_node("Controls").visible and watch.get_node("Controls").modulate.a == 1.0, "Mouse movement immediately restores controls")
	watch._process(3.1)
	watch._input(motion)
	await create_timer(0.25).timeout
	check(watch.get_node("Controls").visible, "Input interrupts an in-progress fade")
	watch._process(3.1)
	await create_timer(0.25).timeout
	var tap: InputEventScreenTouch = InputEventScreenTouch.new()
	tap.pressed = true
	watch._input(tap)
	check(not watch._controls_hidden, "Touch reveals controls")
	watch.toggle_pause()
	check(watch.paused and watch.clock.frozen and watch.music.stream_paused, "Pause freezes audio and photo clock")
	var frozen: float = watch.clock.time
	watch.clock._process(1.0)
	check(watch.clock.time == frozen, "Pause does not advance photo timeline")
	watch.toggle_pause()
	check(not watch.paused and not watch.clock.frozen, "Resume is immediate")
	watch._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(watch.paused, "Focus loss pauses Watch Mode")
	watch._ended()
	check(watch.finished and watch.get_node("Controls/Content/Buttons/Pause").text == "REPLAY", "End offers replay")
	watch.toggle_pause()
	check(not watch.finished and watch.clock.time == 0 and not watch.clock.started, "Replay resets audio and photo clock")
	watch.get_node("Controls/Content/Buttons/Back").pressed.emit()
	await process_frame
	check(app.screen.has_node("Wheel"), "Back returns to song selection")
	check(app.library.bests == bests_before, "Watch Mode does not change best scores")
	app.screen.get_node("Footer/Actions/Watch").pressed.emit()
	await process_frame
	watch = app.screen
	check(watch.has_node("SongClock") and not watch.has_node("Wheel"), "Left Watch Mode button launches selected song")
	watch._process(0.0)
	check(watch.get_node("NoPhotos").visible, "Tracks without photos support audio-only playback")
	app.queue_free()
	await process_frame
	await create_timer(1.2).timeout
	print("WATCH MODE: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)

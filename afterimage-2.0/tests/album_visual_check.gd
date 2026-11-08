extends SceneTree

var app: Control
var photos: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/" + name + ".png")

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(960, 720))
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	for index: int in range(2):
		var image: Image = Image.create(640, 360, false, Image.FORMAT_RGB8)
		for y: int in range(360):
			for x: int in range(640):
				var sky: Color = Color(0.86, 0.91, 0.97) if index == 0 else Color(0.04, 0.08, 0.15)
				var hill: float = 185 + sin(float(x) / 120.0) * 35
				var color: Color = sky.lerp(Color(0.22, 0.65, 0.69), float(y) / 720.0)
				if y > hill:
					color = Color(0.13, 0.36, 0.3) if index == 0 else Color(0.08, 0.19, 0.24)
				image.set_pixel(x, y, color)
		var path: String = "res://tests/artifacts/album_%d.jpg" % index
		image.save_jpg(path)
		photos.append(ProjectSettings.globalize_path(path))
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.generation.config_path = "res://tests/artifacts/visual_preferences.cfg"
	app.generation.set_album_background(true)
	app.screen._open_review()
	var review: Node2D = app.screen.review
	review.content.get_node("TitleInput").text = "Coast to nightfall"
	review.photos.assign([
		{"photo": photos[0], "thumbnail": photos[0], "name": "Morning coast.jpg", "digest": "one", "source": photos[0]},
		{"photo": photos[1], "thumbnail": photos[1], "name": "Evening hills.jpg", "digest": "two", "source": photos[1]}])
	review._rebuild()
	for index: int in range(4):
		var extra: Dictionary = review.photos[index % 2].duplicate()
		extra.digest = "visual_extra_%d" % index
		review.photos.append(extra)
	review._rebuild()
	await _shot("album_review_landscape")
	DisplayServer.window_set_size(Vector2i(480, 850))
	await _shot("album_review_portrait")
	DisplayServer.window_set_size(Vector2i(480, 720))
	await _shot("album_review_compact")
	DisplayServer.window_set_size(Vector2i(480, 850))
	review._cancel()
	await process_frame
	var album: AlbumData = AlbumData.new()
	album.photos = photos
	album.cues = [{"photo": 0, "start": 0.0, "end": 8.0}, {"photo": 1, "start": 8.0, "end": 36.0}]
	var chart: ChartData = ChartLoader.new().load_chart("res://levels/first_light.json")
	chart.album = album
	app.start_game(chart)
	await process_frame
	var game: Control = app.screen
	game.clock.freeze(true)
	game.clock.time = 2.25
	game.judge.press(2, 2.0)
	game.scheduler.update(2.25, game.judge.states)
	await _shot("album_bright_portrait")
	game.clock.time = 10.0
	game.scheduler.update(10.0, game.judge.states)
	await _shot("album_dark_portrait")
	game._pause()
	await _shot("album_pause_portrait")
	app.generation.set_album_background(false)
	game.get_node("PauseOverlay").hide()
	await _shot("album_disabled")
	app.generation.set_album_background(true)
	DisplayServer.window_set_size(Vector2i(960, 720))
	game.clock.time = 7.6
	await _shot("album_crossfade_landscape")
	var generated_path: String = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("level-generation/outputs/gundum-dynamic/hard.json")
	if FileAccess.file_exists(generated_path):
		var hard: ChartData = ChartLoader.new().load_chart(generated_path)
		if hard != null:
			hard.album = album
			app.start_game(hard)
			await process_frame
			game = app.screen
			game.clock.freeze(true)
			game.clock.time = 20.0
			game.scheduler.update(20.0, game.judge.states)
			await _shot("album_hard_landscape")
	app.start_watch(chart)
	await process_frame
	app.screen.clock.freeze(true)
	app.screen.clock.time = 7.6
	await _shot("watch_landscape")
	DisplayServer.window_set_size(Vector2i(480, 720))
	await _shot("watch_portrait")
	app.show_home()
	await _shot("watch_button_portrait")
	app.queue_free()
	await process_frame
	quit()

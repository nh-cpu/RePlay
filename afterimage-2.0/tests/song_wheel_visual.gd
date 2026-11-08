extends SceneTree

var app: Control

func _initialize() -> void:
	_run.call_deferred()

func shot(name: String) -> void:
	await process_frame
	await process_frame
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/wheel_" + name + ".png")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	var covers: PackedStringArray = []
	for index: int in range(3):
		var image: Image = Image.create(720, 400, false, Image.FORMAT_RGB8)
		var color: Color = [Color("a0b4bc"), Color("baa287"), Color("4b6a63")][index]
		for y: int in range(400):
			for x: int in range(720):
				var ridge: float = 230 + sin(x / 140.0 + index) * 45
				image.set_pixel(x, y, color.lerp(Color("202730"), 0.7 if y > ridge else y / 800.0))
		var path: String = "res://tests/artifacts/wheel_cover_%d.jpg" % index
		image.save_jpg(path)
		covers.append(ProjectSettings.globalize_path(path))
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	var home: Control = app.screen
	var songs: Array[SongMetadata] = []
	var names: PackedStringArray = ["First light, last summer", "Somewhere between the mountains and the sea — a very long album title", "After the rain", "Midnight / quiet streets", "The way home"]
	var chart: ChartData = ChartLoader.new().load_chart("res://levels/first_light.json")
	for index: int in range(200):
		var song: SongMetadata = SongMetadata.new()
		song.id = "fixture_%d" % index
		song.title = names[index % names.size()]
		song.artist = "YOUR PHOTO ALBUM  /  %02d" % (index + 1)
		song.artwork_candidates.append(covers[index % 3])
		for label: String in ["Easy", "Normal", "Hard"]:
			var variant: SongDifficultyMetadata = SongDifficultyMetadata.new()
			variant.id = song.id + label
			variant.label = label
			variant.best_score = 234500 if label == "Hard" else 0
			song.difficulties.append(variant)
			home._chart_lookup[variant.id] = chart
		home._metadata[song.id] = song
		songs.append(song)
	home.wheel.set_songs(songs)
	home.wheel.select_song("fixture_4", false)
	home.wheel.select_difficulty("fixture_4Hard")
	home.get_node("Header/Count").text = "200 TRACKS / VISUAL FIXTURE"
	await shot("landscape")
	DisplayServer.window_set_size(Vector2i(480, 720))
	await shot("portrait")
	home.wheel.select_song("fixture_1", false)
	await shot("long_title")
	DisplayServer.window_set_size(Vector2i(480, 850))
	await shot("tall")
	DisplayServer.window_set_size(Vector2i(1280, 800))
	await shot("wide")
	app.queue_free()
	await process_frame
	quit()

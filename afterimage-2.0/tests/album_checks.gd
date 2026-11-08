extends SceneTree

var failures: int = 0
var checks: int = 0
var base: String
var service: GenerationService

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func write_json(path: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _run() -> void:
	base = "user://album_checks_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(base)
	var photo: Image = Image.create(200, 100, false, Image.FORMAT_RGB8)
	photo.fill(Color.CORNFLOWER_BLUE)
	photo.save_jpg(base.path_join("source.jpg"))
	service = GenerationService.new()
	service.config_path = base.path_join("preferences.cfg")
	service.jobs_root = base.path_join("jobs")
	service.library_root = base.path_join("levels")
	root.add_child(service)
	service.set_album_background(false)
	var restored: GenerationService = GenerationService.new()
	restored.config_path = service.config_path
	root.add_child(restored)
	check(not restored.album_background, "Album preference survives restart")
	restored.queue_free()
	await _preview_and_review()
	await _background()
	_library()
	_recovery()
	service.queue_free()
	await process_frame
	_remove_test_folder(base)
	print("ALBUM CHECKS: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _preview_and_review() -> void:
	var results: Array[Dictionary] = []
	service.preview_finished.connect(func(_token: String, value: Dictionary) -> void: results.append(value))
	var token: String = service.preview(PackedStringArray([ProjectSettings.globalize_path(base.path_join("source.jpg"))]))
	check(not token.is_empty(), "Local preview subprocess launched")
	var deadline: int = Time.get_ticks_msec() + 20000
	while results.is_empty() and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	check(not results.is_empty(), "Preview subprocess reports completion")
	if results.is_empty() or results[0].get("state") != "complete":
		check(false, "Preview failed")
		return
	check(results[0].photos.size() == 1, "Normalized preview returned")
	var review: Node2D = load("res://ui/photo_review.tscn").instantiate()
	review.service = service
	root.add_child(review)
	review.preview_token = token
	review.preview_folders.append(token)
	review._preview_finished(token, results[0])
	check(review.photos.size() == 1, "Photo review displays selected photo")
	review.preview_token = token
	review._preview_finished(token, results[0])
	check(review.photos.size() == 1, "Duplicate photo rejected")
	var other: Dictionary = results[0].photos[0].duplicate()
	other.digest = "different"
	other.source = "another.jpg"
	other.name = "another.jpg"
	review.photos.append(other)
	review._move(1, -1)
	check(review.photos[0].name == "another.jpg", "Photo ordering")
	review._remove(0)
	check(review.photos.size() == 1, "Photo removal")
	review._remove(0)
	check(review.content.get_node("Buttons/Generate").disabled, "Cannot generate an empty album")
	review._cancel()
	await process_frame
	check(FileAccess.file_exists(base.path_join("source.jpg")), "Cancel and remove preserve original")
	check(not DirAccess.dir_exists_absolute(token), "Cancel removes local preview copies")
	service.busy = true
	check(not service.start_generation("Blocked", "", []), "Concurrent generation rejected")
	service.busy = false
	var saved_python: String = service.python_path
	service.python_path = "missing-interpreter"
	check(service.preview(PackedStringArray(["missing.jpg"])).is_empty(), "Missing interpreter reported")
	service.python_path = saved_python

func _background() -> void:
	for view: Vector2 in [Vector2(960, 720), Vector2(480, 850)]:
		for dimensions: Vector2 in [Vector2(1600, 900), Vector2(900, 1600)]:
			for progress: float in [0.0, 0.25, 0.75, 1.0]:
				var rect: Rect2 = AlbumBackground.image_rect(view, dimensions, progress, 1)
				check(rect.position.x <= 0 and rect.position.y <= 0 and rect.end.x >= view.x - 0.001 and rect.end.y >= view.y - 0.001, "Pan never reveals an empty edge")
	var album: AlbumData = AlbumData.new()
	album.photos = PackedStringArray([base.path_join("source.jpg"), base.path_join("source.jpg"), base.path_join("missing.jpg")])
	album.cues = [{"photo": 0, "start": 0.0, "end": 5.0}, {"photo": 1, "start": 5.0, "end": 10.0}, {"photo": 2, "start": 10.0, "end": 15.0}]
	var background: AlbumBackground = load("res://gameplay/album_background.tscn").instantiate()
	background.album = album
	root.add_child(background)
	check(background.show_time(-2.0), "First photo visible during pre-roll")
	background.show_time(2.0)
	var position: Vector2 = background.first.position
	background.show_time(2.0)
	check(background.first.position == position, "Pause freezes pan")
	background.show_time(3.0)
	check(background.first.position != position, "Pan follows song time")
	background.show_time(4.7)
	check(background.second.modulate.a > 0 and background.second.modulate.a < 1, "Crossfade before next cue")
	background.show_time(12.0)
	check(background.visible, "Missing final photo falls back")
	background.enabled = false
	check(not background.show_time(12.0) and background._textures.is_empty(), "Toggle off frees images")
	background.enabled = true
	check(background.show_time(2.0) and background.first.position == position, "Toggle on restores current-time pan")
	background.queue_free()
	await process_frame

func _library() -> void:
	var folder: String = service.library_root.path_join("fixture")
	DirAccess.make_dir_recursive_absolute(folder)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://assets/first_light.wav"), ProjectSettings.globalize_path(folder.path_join("song.wav")))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(base.path_join("source.jpg")), ProjectSettings.globalize_path(folder.path_join("photo.jpg")))
	var charts: Dictionary = {}
	for difficulty: String in ["easy", "normal", "hard"]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/first_light.json"))
		data.song = "song.wav"
		data.difficulty = difficulty.capitalize()
		write_json(folder.path_join(difficulty + ".json"), data)
		charts[difficulty] = difficulty + ".json"
	write_json(folder.path_join("album.json"), {"format_version": 1, "title": "Fixture", "charts": charts, "photos": ["photo.jpg"], "cues": [{"photo": 0, "start": 0, "end": 36}]})
	var library: LevelLibrary = LevelLibrary.new(base)
	var tracks: Array[Dictionary] = library.list_tracks()
	check(tracks.size() == 2, "Generated song appears once alongside demo")
	check(tracks[1].charts.size() == 3, "Three available difficulties")
	var easy: ChartData = tracks[1].charts[0]
	var hard: ChartData = tracks[1].charts[2]
	library.save_best(easy.source_path, 1000)
	check(library.best(hard.source_path) == 0, "Best scores separated by difficulty")
	check(easy.album != null and easy.album.photos.size() == 1, "Album passed separately from unchanged chart format")

func _recovery() -> void:
	var job: String = service.jobs_root.path_join("recovery")
	DirAccess.make_dir_recursive_absolute(job)
	service.active_job = job
	service.active_pid = OS.get_process_id()
	service.busy = true
	write_json(job.path_join("status.json"), {"state": "running", "stage": "Analyzing"})
	service._poll_generation()
	check(service.busy and service.message == "Analyzing", "Reconnect to live job")
	service.active_pid = 2147483647
	service._poll_generation()
	check(not service.busy and service.message.contains("interrupted"), "Dead worker offers recovery")
	service.busy = true
	write_json(job.path_join("status.json"), {"state": "failed", "stage": "Missing credentials"})
	service._poll_generation()
	check(not service.busy and service.message == "Missing credentials", "Failure visible without publishing")
	service.busy = true
	write_json(job.path_join("status.json"), {"state": "complete"})
	service._poll_generation()
	check(not service.busy and service.active_job.is_empty(), "Completed job clears active state")

func _remove_test_folder(folder: String) -> void:
	# Only recurse within this run's unique fixture directory.
	assert(folder.begins_with(base))
	for name: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(name))
	for name: String in DirAccess.get_directories_at(folder):
		_remove_test_folder(folder.path_join(name))
	DirAccess.remove_absolute(folder)

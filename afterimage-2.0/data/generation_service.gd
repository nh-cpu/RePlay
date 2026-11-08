class_name GenerationService
extends Node

signal changed
signal album_background_changed(enabled: bool)
signal preview_finished(token: String, result: Dictionary)
signal track_ready

var album_background: bool = true
var python_path: String = ""
var worker_path: String = ""
var active_job: String = ""
var active_pid: int = -1
var busy: bool = false
var message: String = ""
var config_path: String = "user://preferences.cfg"
var jobs_root: String = "user://generation_jobs"
var library_root: String = "user://levels"
var _previews: Dictionary = {}
var _discard_previews: Dictionary = {}
var _elapsed: float = 0.0
var _last_status: String = ""

func _ready() -> void:
	var project: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	var generator: String = project.get_base_dir().path_join("level-generation")
	python_path = generator.path_join(".venv/Scripts/python.exe")
	worker_path = generator.path_join("src/afterimage_levelgen/godot_worker.py")
	var config: ConfigFile = ConfigFile.new()
	if config.load(config_path) == OK:
		album_background = bool(config.get_value("display", "album_background", true))
		python_path = str(config.get_value("generator", "python_path", python_path))
		worker_path = str(config.get_value("generator", "worker_path", worker_path))
		active_job = str(config.get_value("job", "path", ""))
		active_pid = int(config.get_value("job", "pid", -1))
	if not active_job.is_empty():
		busy = true
		_poll_generation()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5:
		return
	_elapsed = 0.0
	for token: String in _previews.keys():
		var result: Dictionary = _read_status(token)
		if result.get("state", "") in ["complete", "failed"]:
			_previews.erase(token)
			if _discard_previews.has(token):
				discard_preview(token)
			else:
				preview_finished.emit(token, result)
		elif not OS.is_process_running(int(_previews[token])):
			_previews.erase(token)
			if _discard_previews.has(token):
				discard_preview(token)
			else:
				preview_finished.emit(token, {"state": "failed", "stage": "Photo preview worker stopped. Check the configured Python environment."})
	if busy:
		_poll_generation()

func set_album_background(value: bool) -> void:
	album_background = value
	_save()
	album_background_changed.emit(value)

func preview(paths: PackedStringArray) -> String:
	var folder: String = _new_folder("preview")
	var request: Dictionary = {"format_version": 1, "mode": "preview", "photos": Array(paths)}
	var pid: int = _launch(folder, request)
	if pid < 0:
		return ""
	_previews[folder] = pid
	return folder

func start_generation(title: String, description: String, photos: Array[Dictionary]) -> bool:
	if busy:
		message = "A track is already being generated."
		return false
	if title.strip_edges().is_empty() or title.length() > 120 or description.length() > 4000 or photos.is_empty() or photos.size() > 30:
		message = "Enter a title and select between 1 and 30 photos."
		return false
	var folder: String = _new_folder("album")
	var photo_folder: String = folder.path_join("photos")
	if DirAccess.make_dir_recursive_absolute(photo_folder) != OK:
		message = "Cannot create the album snapshot folder."
		return false
	var paths: Array[String] = []
	for index: int in range(photos.size()):
		var target: String = photo_folder.path_join("%03d.jpg" % index)
		if DirAccess.copy_absolute(str(photos[index].photo), target) != OK:
			message = "Cannot snapshot a selected photo. Please add it again."
			return false
		paths.append(ProjectSettings.globalize_path(target))
	var request: Dictionary = {"format_version": 1, "mode": "generate", "title": title.strip_edges(),
		"description": description, "photos": paths, "library_root": ProjectSettings.globalize_path(library_root)}
	var pid: int = _launch(folder, request)
	if pid < 0:
		return false
	active_job = folder
	active_pid = pid
	busy = true
	message = "Preparing your album..."
	_last_status = ""
	_save()
	changed.emit()
	return true

func discard_preview(token: String) -> void:
	if not token.begins_with(jobs_root.path_join("preview_")):
		return
	if _previews.has(token):
		_discard_previews[token] = true
		return
	_discard_previews.erase(token)
	for file: String in DirAccess.get_files_at(token):
		DirAccess.remove_absolute(token.path_join(file))
	DirAccess.remove_absolute(token)

func retry() -> void:
	if busy or active_job.is_empty():
		return
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(active_job.path_join("request.json")))
	if not request is Dictionary:
		message = "The saved job request is missing or invalid."
		changed.emit()
		return
	active_pid = _launch(active_job, request)
	busy = active_pid >= 0
	_last_status = ""
	_save()
	changed.emit()

func _new_folder(prefix: String) -> String:
	return jobs_root.path_join("%s_%d_%d" % [prefix, Time.get_unix_time_from_system(), Time.get_ticks_usec()])

func _launch(folder: String, request: Dictionary) -> int:
	if not FileAccess.file_exists(python_path) or not FileAccess.file_exists(worker_path):
		message = "Generator unavailable. Configure Python and worker paths in user://preferences.cfg (see README)."
		return -1
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		message = "Cannot create generation workspace."
		return -1
	var path: String = folder.path_join("request.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		message = "Cannot write generation request."
		return -1
	file.store_string(JSON.stringify(request))
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		message = "Cannot save generation request."
		return -1
	DirAccess.remove_absolute(folder.path_join("status.json"))
	var pid: int = OS.create_process(python_path, PackedStringArray([worker_path, "--request", ProjectSettings.globalize_path(path)]), false)
	if pid < 0:
		message = "Cannot start the local Python worker."
	return pid

func _read_status(folder: String) -> Dictionary:
	var path: String = folder.path_join("status.json")
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _poll_generation() -> void:
	var status: Dictionary = _read_status(active_job)
	var state: String = str(status.get("state", "running"))
	var stage: String = str(status.get("stage", "Starting local worker..."))
	if state == "complete":
		busy = false
		message = "Your new track is ready."
		active_job = ""
		active_pid = -1
		_save()
		track_ready.emit()
	elif state == "failed":
		busy = false
		message = stage
	elif active_pid > 0 and not OS.is_process_running(active_pid):
		busy = false
		message = "Generation was interrupted. Retry to recover saved stages."
	else:
		message = stage
	if message != _last_status:
		_last_status = message
		changed.emit()

func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(config_path)
	config.set_value("display", "album_background", album_background)
	config.set_value("generator", "python_path", python_path)
	config.set_value("generator", "worker_path", worker_path)
	config.set_value("job", "path", active_job)
	config.set_value("job", "pid", active_pid)
	config.save(config_path)

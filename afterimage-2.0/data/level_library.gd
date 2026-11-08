class_name LevelLibrary
extends RefCounted

var root_path: String = "user://levels"
var best_path: String = "user://bests.json"
var error: String = ""
var bests: Dictionary = {}

func _init(base_path: String = "user://") -> void:
	root_path = base_path.path_join("levels")
	best_path = base_path.path_join("bests.json")
	if FileAccess.file_exists(best_path):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(best_path))
		if value is Dictionary:
			bests = value

func list_paths() -> PackedStringArray:
	var paths: PackedStringArray = ["res://levels/first_light.json"]
	if DirAccess.dir_exists_absolute(root_path):
		for folder: String in DirAccess.get_directories_at(root_path):
			var path: String = root_path.path_join(folder).path_join("chart.json")
			if FileAccess.file_exists(path):
				paths.append(path)
	return paths

func import_chart(chart: ChartData) -> String:
	error = ""
	var folder: String = root_path.path_join("%d_%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		error = "Cannot create the local level folder."
		return ""
	var audio_name: String = "song." + chart.song_path.get_extension().to_lower()
	var audio_path: String = folder.path_join(audio_name)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(chart.song_path)
	var audio_file: FileAccess = FileAccess.open(audio_path, FileAccess.WRITE)
	if audio_file == null:
		error = "Cannot copy audio into the library."
		DirAccess.remove_absolute(folder)
		return ""
	audio_file.store_buffer(bytes)
	var write_error: Error = audio_file.get_error()
	audio_file.close()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(chart.source_path))
	data.song = audio_name
	var destination: String = folder.path_join("chart.json")
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	if file == null or write_error != OK:
		error = "Cannot save the imported level."
	else:
		file.store_string(JSON.stringify(data, "\t"))
		if file.get_error() != OK:
			error = "Cannot save the imported level."
		file.close()
		var loader: ChartLoader = ChartLoader.new()
		if error.is_empty() and loader.load_chart(destination) == null:
			error = loader.error
	if not error.is_empty():
		if file != null and file.is_open():
			file.close()
		DirAccess.remove_absolute(destination)
		DirAccess.remove_absolute(audio_path)
		DirAccess.remove_absolute(folder)
		return ""
	return destination

func best(path: String) -> int:
	return int(bests.get(path, 0))

func list_tracks() -> Array[Dictionary]:
	var tracks: Array[Dictionary] = []
	for path: String in list_paths():
		var loader: ChartLoader = ChartLoader.new()
		var chart: ChartData = loader.load_chart(path)
		if chart != null:
			tracks.append({"title": chart.title, "charts": [chart]})
	if not DirAccess.dir_exists_absolute(root_path):
		return tracks
	for folder: String in DirAccess.get_directories_at(root_path):
		var base: String = root_path.path_join(folder)
		var manifest_path: String = base.path_join("album.json")
		if not FileAccess.file_exists(manifest_path):
			continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
		if not value is Dictionary or value.get("format_version") != 1 or not value.get("charts") is Dictionary:
			continue
		var album: AlbumData = AlbumData.from_manifest(base, value)
		var variants: Array[ChartData] = []
		for difficulty: String in ["easy", "normal", "hard"]:
			var name: String = str(value.charts.get(difficulty, ""))
			if name.is_empty() or name.get_file() != name:
				continue
			var chart: ChartData = ChartLoader.new().load_chart(base.path_join(name))
			if chart != null:
				chart.album = album
				variants.append(chart)
		if not variants.is_empty():
			tracks.append({"title": str(value.get("title", variants[0].title)), "charts": variants})
	return tracks

func save_best(path: String, score: int) -> void:
	bests[path] = maxi(best(path), score)
	var file: FileAccess = FileAccess.open(best_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(bests))

class_name ChartLoader
extends RefCounted

var error: String = ""
var missing_audio: bool = false

static func load_audio(path: String) -> AudioStream:
	if path.get_extension().to_lower() not in ["wav", "ogg", "mp3"]:
		return null
	if path.begins_with("res://"):
		return ResourceLoader.load(path) as AudioStream
	match path.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null

func load_chart(path: String, audio_override: String = "") -> ChartData:
	error = ""
	missing_audio = false
	if not FileAccess.file_exists(path):
		return _fail("Chart file could not be found.")
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return _fail("Invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	var chart: ChartData = parse_data(parser.data, path)
	if chart == null:
		return null
	if not audio_override.is_empty():
		chart.song_path = audio_override
	if not FileAccess.file_exists(chart.song_path) and not ResourceLoader.exists(chart.song_path):
		missing_audio = true
		return _fail("Audio not found. Select the song file for this chart.")
	chart.audio = load_audio(chart.song_path)
	if chart.audio == null:
		return _fail("Cannot decode audio. Use WAV, OGG Vorbis, or MP3.")
	if chart.last_time() > chart.audio.get_length() + 0.16:
		return _fail("The chart extends beyond the end of the audio.")
	return chart

func parse_data(value: Variant, path: String = "chart.json") -> ChartData:
	error = ""
	if not value is Dictionary:
		return _fail("The chart must be a JSON object.")
	var data: Dictionary = value
	if data.get("format_version") != 1 or data.get("lane_count") != 4:
		return _fail("Expected format_version 1 and lane_count 4.")
	if not _number(data.get("bpm")) or float(data.bpm) <= 0.0:
		return _fail("bpm must be a positive finite number.")
	if not _number(data.get("offset_seconds")):
		return _fail("offset_seconds must be finite.")
	if not data.get("song") is String or str(data.song).is_empty():
		return _fail("song must name an audio file.")
	if not data.get("notes") is Array or data.notes.is_empty():
		return _fail("notes must be a nonempty array.")
	var chart: ChartData = ChartData.new()
	chart.source_path = path
	chart.bpm = float(data.bpm)
	chart.offset = float(data.offset_seconds)
	chart.title = str(data.get("title", path.get_file().get_basename()))
	chart.artist = str(data.get("artist", "Unknown artist"))
	chart.difficulty = str(data.get("difficulty", "Custom"))
	var song: String = data.song
	chart.song_path = song if song.is_absolute_path() else path.get_base_dir().path_join(song)
	for index: int in range(data.notes.size()):
		var entry: Variant = data.notes[index]
		if not entry is Dictionary:
			return _fail("Note %d must be an object." % index)
		if not _number(entry.get("beat")) or float(entry.beat) < 0.0:
			return _fail("Note %d has an invalid beat." % index)
		if not _number(entry.get("lane")) or float(entry.lane) != floorf(float(entry.lane)) or int(entry.lane) < 0 or int(entry.lane) > 3:
			return _fail("Note %d needs an integer lane from 0 to 3." % index)
		if entry.get("type") not in ["tap", "hold"]:
			return _fail("Note %d has an unsupported type." % index)
		var note: NoteData = NoteData.new()
		note.lane = int(entry.lane)
		note.time = chart.offset + float(entry.beat) * 60.0 / chart.bpm
		if entry.type == "hold":
			if not _number(entry.get("duration_beats")) or float(entry.duration_beats) <= 0.0:
				return _fail("Hold %d needs a positive duration_beats." % index)
			note.duration = float(entry.duration_beats) * 60.0 / chart.bpm
		if not is_finite(note.time) or not is_finite(note.end_time()):
			return _fail("Note %d timing is outside the supported range." % index)
		chart.notes.append(note)
	chart.notes.sort_custom(func(a: NoteData, b: NoteData) -> bool: return a.time < b.time)
	var ends: Array[float] = [-INF, -INF, -INF, -INF]
	for note: NoteData in chart.notes:
		if note.time <= ends[note.lane]:
			return _fail("Duplicate or overlapping notes in lane %d." % note.lane)
		ends[note.lane] = note.end_time()
	return chart

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _fail(message: String) -> ChartData:
	error = message
	return null

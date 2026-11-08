extends Control

signal play_requested(chart: ChartData)

const REVIEW: PackedScene = preload("res://ui/photo_review.tscn")
var library: LevelLibrary
var service: GenerationService
var charts: Array[ChartData] = []
var tracks: Array[Dictionary] = []
var review: Node2D
var _chart_lookup: Dictionary = {}
var _metadata: Dictionary = {}
@onready var wheel: SongWheel = $Wheel
@onready var detail: VBoxContainer = $Details
@onready var status: Label = $Footer/Status

func _ready() -> void:
	resized.connect(_layout_menu)
	detail.minimum_size_changed.connect(_layout_menu.call_deferred)
	$Footer/Actions/Play.pressed.connect(_play)
	$Footer/Actions/Create.pressed.connect(_open_review)
	wheel.song_selected.connect(_song_changed)
	wheel.difficulty_selected.connect(_difficulty_changed)
	wheel.play_requested.connect(_launch)
	if service != null:
		$Footer/Options/Album.set_pressed_no_signal(service.album_background)
		$Footer/Options/Album.toggled.connect(service.set_album_background)
		service.album_background_changed.connect(func(value: bool) -> void: $Footer/Options/Album.set_pressed_no_signal(value))
		service.changed.connect(_job_changed)
		service.track_ready.connect(_refresh)
		$Footer/Options/Retry.pressed.connect(service.retry)
	_refresh()
	_job_changed()
	_layout_menu()
	wheel.grab_focus.call_deferred()

func _refresh() -> void:
	tracks = library.list_tracks()
	charts.clear()
	_chart_lookup.clear()
	_metadata.clear()
	var values: Array[SongMetadata] = []
	for track: Dictionary in tracks:
		var first: ChartData = track.charts[0]
		charts.append(first)
		var song: SongMetadata = SongMetadata.new()
		song.id = first.source_path.get_base_dir() if first.album != null else first.source_path
		song.title = str(track.title)
		song.artist = first.artist
		if first.album != null:
			song.artwork_candidates = first.album.photos
		for chart: ChartData in track.charts:
			var variant: SongDifficultyMetadata = SongDifficultyMetadata.new()
			variant.id = chart.source_path
			variant.label = chart.difficulty
			variant.bpm = chart.bpm
			variant.note_count = chart.notes.size()
			variant.duration = chart.audio.get_length() if chart.audio != null else chart.last_time()
			variant.best_score = library.best(chart.source_path)
			song.difficulties.append(variant)
			_chart_lookup[variant.id] = chart
		_metadata[song.id] = song
		values.append(song)
	wheel.set_songs(values)
	$Header/Count.text = "%02d TRACKS  /  YOUR MEMORIES, IN RHYTHM" % values.size()
	$Footer/Actions/Play.disabled = values.is_empty()
	if values.is_empty():
		detail.get_node("Title").text = "Your next memory"
		detail.get_node("Artist").text = "Create a track from photos to begin."
		detail.get_node("Stats").text = ""
		detail.get_node("Best").text = ""
		detail.get_node("Artwork").texture = null
		$Artwork.show_artwork("", null)

func _song_changed(id: String) -> void:
	var song: SongMetadata = _metadata[id]
	detail.get_node("Title").text = song.title
	detail.get_node("Artist").text = song.artist
	var texture: Texture2D = wheel.artwork_for_song(song)
	detail.get_node("Artwork").texture = texture
	$Artwork.show_artwork(song.artwork_path, texture)
	_layout_menu()

func _difficulty_changed(_song_id: String, id: String) -> void:
	if not _chart_lookup.has(id):
		return
	var chart: ChartData = _chart_lookup[id]
	var duration: float = chart.audio.get_length() if chart.audio != null else chart.last_time()
	detail.get_node("Stats").text = "%s  /  %02d:%02d\n%.0f BPM   ·   %d NOTES" % [chart.difficulty.to_upper(), int(duration) / 60, int(duration) % 60, chart.bpm, chart.notes.size()]
	detail.get_node("Best").text = "PERSONAL BEST\n%07d" % library.best(id)

func _play() -> void:
	wheel.request_play()

func _launch(_song_id: String, chart_id: String) -> void:
	if not is_instance_valid(review) and _chart_lookup.has(chart_id):
		play_requested.emit(_chart_lookup[chart_id])

func _open_review() -> void:
	if service == null or service.busy or is_instance_valid(review):
		return
	wheel.set_navigation_enabled(false)
	review = REVIEW.instantiate()
	review.service = service
	review.dismissed.connect(func() -> void:
		wheel.set_navigation_enabled(true)
		wheel.grab_focus.call_deferred())
	add_child(review)

func _job_changed() -> void:
	if service == null:
		return
	status.text = service.message if not service.message.is_empty() else "SCROLL / ↑ ↓ SONGS   ·   ← → DIFFICULTY   ·   ENTER TO PLAY"
	status.tooltip_text = service.message
	$Footer/Actions/Create.disabled = service.busy
	$Footer/Options/Retry.visible = not service.busy and not service.active_job.is_empty()

func _layout_menu() -> void:
	var portrait: bool = size.x < 760
	$Header.position = Vector2(24, 20)
	$Header.size = Vector2(size.x - 48, 62)
	detail.position = Vector2(24, 100)
	detail.size = Vector2(size.x - 48 if portrait else size.x * 0.36, 140 if portrait else size.y - 290)
	detail.get_node("Artwork").visible = not portrait and detail.get_node("Artwork").texture != null
	detail.get_node("Best").visible = not portrait
	detail.get_node("Title").add_theme_font_size_override("font_size", 26 if portrait else 34)
	detail.get_node("Stats").add_theme_font_size_override("font_size", 14 if portrait else 16)
	var wheel_top: float = maxf(244, detail.position.y + detail.get_combined_minimum_size().y + 20) if portrait else 88
	wheel.position = Vector2(14 if portrait else size.x * 0.43, wheel_top)
	wheel.size = Vector2(size.x - wheel.position.x, maxf(160, size.y - wheel.position.y - 170))
	$Footer.position = Vector2(24, size.y - 152)
	$Footer.size = Vector2(size.x - 48, 136)

extends Control

signal play_requested(chart: ChartData)

const REVIEW: PackedScene = preload("res://ui/photo_review.tscn")
var library: LevelLibrary
var service: GenerationService
var charts: Array[ChartData] = []
var tracks: Array[Dictionary] = []
var selected_track: int = 0
var review: Node2D
@onready var list: ItemList = $Margin/Content/LibraryPanel/Levels
@onready var detail: Label = $Margin/Content/Detail
@onready var status: Label = $Margin/Content/Status
@onready var difficulty: OptionButton = $Margin/Content/Options/Difficulty

func _ready() -> void:
	resized.connect(_layout_menu)
	_layout_menu()
	$Margin/Content/Buttons/Play.pressed.connect(_play)
	$Margin/Content/Buttons/Create.pressed.connect(_open_review)
	list.item_selected.connect(_selection_changed)
	list.item_activated.connect(func(_index: int) -> void: _play())
	difficulty.item_selected.connect(func(_index: int) -> void: _update_detail())
	if service != null:
		$Margin/Content/Options/Album.set_pressed_no_signal(service.album_background)
		$Margin/Content/Options/Album.toggled.connect(service.set_album_background)
		service.album_background_changed.connect(func(value: bool) -> void: $Margin/Content/Options/Album.set_pressed_no_signal(value))
		service.changed.connect(_job_changed)
		service.track_ready.connect(_refresh)
		$Margin/Content/Retry.pressed.connect(service.retry)
	_refresh()
	_job_changed()

func _refresh() -> void:
	tracks = library.list_tracks()
	charts.clear()
	list.clear()
	for track: Dictionary in tracks:
		charts.append(track.charts[0])
		list.add_item("%02d   /   %s" % [charts.size(), track.title])
	$Margin/Content/Buttons/Play.disabled = tracks.is_empty()
	if not tracks.is_empty():
		selected_track = mini(selected_track, tracks.size() - 1)
		list.select(selected_track)
		_selection_changed(selected_track)

func _selection_changed(index: int) -> void:
	selected_track = index
	difficulty.clear()
	for chart: ChartData in tracks[index].charts:
		difficulty.add_item(chart.difficulty)
	difficulty.select(0)
	_update_detail()

func _update_detail() -> void:
	if tracks.is_empty():
		return
	var chart: ChartData = tracks[selected_track].charts[difficulty.selected]
	detail.text = "%s  •  %s\n%.0f BPM   /   %d NOTES   /   BEST %07d" % [chart.artist, chart.difficulty, chart.bpm, chart.notes.size(), library.best(chart.source_path)]

func _play() -> void:
	if not tracks.is_empty() and not is_instance_valid(review):
		play_requested.emit(tracks[selected_track].charts[difficulty.selected])

func _open_review() -> void:
	if service == null or service.busy or is_instance_valid(review):
		return
	review = REVIEW.instantiate()
	review.service = service
	add_child(review)

func _job_changed() -> void:
	if service == null:
		return
	status.text = service.message
	$Margin/Content/Buttons/Create.disabled = service.busy
	$Margin/Content/Retry.visible = not service.busy and not service.active_job.is_empty()

func _layout_menu() -> void:
	var inset: int = int(maxf(24.0, (size.x - 820.0) / 2.0))
	$Margin.add_theme_constant_override("margin_left", inset)
	$Margin.add_theme_constant_override("margin_right", inset)

extends Control

signal play_requested(chart: ChartData)

var library: LevelLibrary
var charts: Array[ChartData] = []
var pending_path: String = ""
@onready var list: ItemList = $Margin/Content/Levels
@onready var detail: Label = $Margin/Content/Detail
@onready var status: Label = $Margin/Content/Status

func _ready() -> void:
	$Margin/Content/Buttons/Play.pressed.connect(_play)
	$Margin/Content/Buttons/Import.pressed.connect(func() -> void: $ChartPicker.popup_centered_ratio(0.8))
	$ChartPicker.file_selected.connect(_import_selected)
	$AudioPicker.file_selected.connect(func(path: String) -> void: _import_selected(pending_path, path))
	list.item_selected.connect(_selection_changed)
	list.item_activated.connect(func(_index: int) -> void: _play())
	_refresh()

func _refresh() -> void:
	charts.clear()
	list.clear()
	for path: String in library.list_paths():
		var loader: ChartLoader = ChartLoader.new()
		var chart: ChartData = loader.load_chart(path)
		if chart == null:
			status.text = "Skipped %s: %s" % [path.get_file(), loader.error]
			continue
		charts.append(chart)
		list.add_item("%02d   /   %s" % [charts.size(), chart.title])
	$Margin/Content/Buttons/Play.disabled = charts.is_empty()
	if not charts.is_empty():
		list.select(0)
		_selection_changed(0)

func _selection_changed(index: int) -> void:
	var chart: ChartData = charts[index]
	detail.text = "%s  •  %s\n%.0f BPM   /   %d NOTES   /   BEST %07d" % [chart.artist, chart.difficulty, chart.bpm, chart.notes.size(), library.best(chart.source_path)]

func _play() -> void:
	if not list.get_selected_items().is_empty():
		play_requested.emit(charts[list.get_selected_items()[0]])

func _import_selected(path: String, audio_path: String = "") -> void:
	pending_path = path
	var loader: ChartLoader = ChartLoader.new()
	var chart: ChartData = loader.load_chart(path, audio_path)
	if chart == null:
		status.text = loader.error
		if loader.missing_audio:
			$AudioPicker.popup_centered_ratio(0.8)
		return
	var saved: String = library.import_chart(chart)
	if saved.is_empty():
		status.text = library.error
		return
	status.text = "Imported %s. Ready to play."
	_refresh()
	for index: int in range(charts.size()):
		if charts[index].source_path == saved:
			list.select(index)
			_selection_changed(index)

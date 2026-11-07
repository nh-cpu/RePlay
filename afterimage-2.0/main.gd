extends Control

const HOME: PackedScene = preload("res://ui/home_menu.tscn")
const GAME: PackedScene = preload("res://gameplay/gameplay.tscn")
const RESULTS: PackedScene = preload("res://ui/results.tscn")
var library: LevelLibrary = LevelLibrary.new()
var selected: ChartData
var screen: Control

func _ready() -> void:
	show_home()

func show_home() -> void:
	var menu: Control = HOME.instantiate()
	menu.library = library
	menu.play_requested.connect(start_game)
	_replace(menu)

func start_game(chart: ChartData) -> void:
	selected = chart
	var game: Control = GAME.instantiate()
	game.chart = chart
	game.completed.connect(show_results)
	game.home_requested.connect(show_home)
	_replace(game)

func show_results(result: Dictionary) -> void:
	library.save_best(selected.source_path, int(result.score))
	var results: Control = RESULTS.instantiate()
	results.result = result
	results.title = selected.title
	results.retry_requested.connect(func() -> void: start_game(selected))
	results.home_requested.connect(show_home)
	_replace(results)

func _replace(next: Control) -> void:
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = next
	add_child(screen)

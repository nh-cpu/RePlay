extends SceneTree

var app: Control

func _initialize() -> void:
	_run.call_deferred()

func _shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/artifacts/" + name + ".png")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://tests/artifacts")
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await _shot("home_landscape")
	var chart: ChartData = ChartLoader.new().load_chart("res://levels/first_light.json")
	app.start_game(chart)
	await process_frame
	var game: Control = app.screen
	game.clock.freeze(true)
	game.clock.time = 4.0
	game.judge.press(0, 4.0)
	game.scheduler.update(4.0, game.judge.states)
	await _shot("game_landscape")
	game._pause()
	await _shot("pause")
	app.show_home()
	DisplayServer.window_set_size(Vector2i(480, 850))
	await _shot("home_portrait")
	app.start_game(chart)
	await process_frame
	game = app.screen
	game.clock.freeze(true)
	game.clock.time = 2.25
	game.judge.press(2, 2.0)
	game.scheduler.update(2.25, game.judge.states)
	await _shot("game_portrait")
	var results: Control = load("res://ui/results.tscn").instantiate()
	results.title = chart.title
	results.result = {"score": 61250, "max_combo": 42, "accuracy": 89.5, "counts": [45, 12, 5, 2, 4]}
	app._replace(results)
	await _shot("results_portrait")
	app.queue_free()
	await process_frame
	quit()

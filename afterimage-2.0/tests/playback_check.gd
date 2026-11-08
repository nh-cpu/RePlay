extends SceneTree

var done: bool = false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var chart: ChartData = ChartLoader.new().load_chart("res://levels/first_light.json")
	var game: Control = load("res://gameplay/gameplay.tscn").instantiate()
	game.chart = chart
	game.completed.connect(func(result: Dictionary) -> void:
		done = true
		if result.counts[4] != chart.notes.size():
			push_error("Playback did not account for every note")
			quit(1)
			return
		print("REAL-TIME PLAYBACK PASSED: %d notes, audio finished, result emitted" % chart.notes.size())
		quit(0)
	)
	root.add_child(game)
	await create_timer(45.0).timeout
	if not done:
		push_error("Playback timed out")
		quit(1)

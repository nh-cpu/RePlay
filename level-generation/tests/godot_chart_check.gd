extends SceneTree
## Exercise generated files through the actual loader and judgment controller.

var outcomes: Array[int] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("Pass a generation folder after --")
		quit(1)
		return
	for difficulty: String in ["easy", "normal", "hard"]:
		var loader: ChartLoader = ChartLoader.new()
		var chart: ChartData = loader.load_chart(arguments[0].path_join(difficulty + ".json"))
		if chart == null:
			push_error(loader.error)
			quit(1)
			return
		var judge: JudgmentController = JudgmentController.new()
		judge.setup(chart)
		outcomes.clear()
		judge.judged.connect(func(_index: int, grade: int) -> void: outcomes.append(grade))
		var events: Array[Dictionary] = []
		for note: NoteData in chart.notes:
			events.append({"time": note.time, "lane": note.lane, "press": true})
			events.append({"time": note.end_time() + 0.001, "lane": note.lane, "press": false})
		events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.time) < float(b.time))
		for event: Dictionary in events:
			if bool(event.press):
				judge.press(int(event.lane), float(event.time))
			else:
				judge.release(int(event.lane), float(event.time))
		judge.advance(chart.audio.get_length() + 1.0)
		if outcomes.size() != chart.notes.size() or outcomes.any(func(grade: int) -> bool: return grade != 0):
			push_error("Generated chart failed perfect-input simulation: " + difficulty)
			judge.free()
			quit(1)
			return
		print("GENERATED CHART PASSED: %s, %d notes, all perfect including holds" % [difficulty, outcomes.size()])
		judge.free()
	quit(0)

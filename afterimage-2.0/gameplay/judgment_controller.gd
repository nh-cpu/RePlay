class_name JudgmentController
extends Node

signal judged(index: int, grade: int)
signal hold_started(index: int, grade: int)

var notes: Array[NoteData] = []
var states: Array[int] = []
var grades: Array[int] = []
var held: Array[bool] = [false, false, false, false]

static func grade_for(error: float) -> int:
	var windows: Array[float] = [0.040, 0.080, 0.120, 0.160]
	for index: int in range(windows.size()):
		if absf(error) <= windows[index] + 0.000001:
			return index
	return 4

func setup(chart: ChartData) -> void:
	notes = chart.notes
	states.resize(notes.size())
	states.fill(0)
	grades.resize(notes.size())
	held.fill(false)

func press(lane: int, time: float) -> void:
	held[lane] = true
	advance(time)
	for index: int in range(notes.size()):
		var note: NoteData = notes[index]
		if note.lane != lane or states[index] != 0:
			continue
		var grade: int = grade_for(time - note.time)
		if grade == 4:
			return
		if note.duration > 0.0:
			states[index] = 1
			grades[index] = grade
			hold_started.emit(index, grade)
			advance(time)
		else:
			_finish(index, grade)
		return

func release(lane: int, time: float) -> void:
	advance(time)
	held[lane] = false
	for index: int in range(notes.size()):
		if states[index] == 1 and notes[index].lane == lane:
			_finish(index, 4)

func advance(time: float) -> void:
	for index: int in range(notes.size()):
		if states[index] == 0 and time - notes[index].time > 0.160001:
			_finish(index, 4)
		elif states[index] == 1:
			if not held[notes[index].lane]:
				_finish(index, 4)
			elif time >= notes[index].end_time():
				_finish(index, grades[index])

func _finish(index: int, grade: int) -> void:
	states[index] = 2
	judged.emit(index, grade)

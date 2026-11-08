class_name ChartScheduler
extends Node

const TAP: PackedScene = preload("res://gameplay/tap_note.tscn")
const HOLD: PackedScene = preload("res://gameplay/hold_note.tscn")
var chart: ChartData
var lanes: Array[RhythmLane] = []
var views: Dictionary = {}
var next_note: int = 0

func update(time: float, states: Array[int]) -> void:
	while next_note < chart.notes.size() and chart.notes[next_note].time - time <= 2.0:
		if states[next_note] != 2:
			var data: NoteData = chart.notes[next_note]
			var view: NoteView = (HOLD if data.duration > 0.0 else TAP).instantiate()
			view.data = data
			lanes[data.lane].note_layer.add_child(view)
			views[next_note] = view
		next_note += 1
	for index: int in views.keys():
		var view: NoteView = views[index]
		if states[index] == 2:
			view.queue_free()
			views.erase(index)
			continue
		var lane: RhythmLane = lanes[view.data.lane]
		view.position.x = lane.size.x / 2.0
		view.place(time, lane.hit_y, lane.hit_y / 2.0, lane.size.x * 0.83, states[index] == 1)

class_name NoteData
extends Resource

var lane: int = 0
var time: float = 0.0
var duration: float = 0.0

func end_time() -> float:
	return time + duration

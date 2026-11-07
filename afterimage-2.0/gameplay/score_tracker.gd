class_name ScoreTracker
extends Node

signal changed

const NAMES: Array[String] = ["Perfect", "Excellent", "Good", "OK", "Miss"]
const POINTS: Array[int] = [1000, 750, 500, 250, 0]
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var counts: Array[int] = [0, 0, 0, 0, 0]

func record(grade: int) -> void:
	counts[grade] += 1
	score += POINTS[grade]
	combo = 0 if grade == 4 else combo + 1
	max_combo = maxi(max_combo, combo)
	changed.emit()

func summary(total: int) -> Dictionary:
	return {"score": score, "max_combo": max_combo, "counts": counts.duplicate(), "accuracy": float(score) / maxf(1.0, total * 1000.0) * 100.0}

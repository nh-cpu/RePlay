class_name LaneInput
extends Node

signal pressed(lane: int)
signal released(lane: int)

var enabled: bool = true
var regions: Array[Rect2] = []
var fingers: Dictionary = {}
var keyboard: Array[bool] = [false, false, false, false]
var held: Array[bool] = [false, false, false, false]

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey and not event.echo:
		for lane: int in range(4):
			var action: String = "lane_%d" % (lane + 1)
			if event.is_action(action):
				keyboard[lane] = event.is_action_pressed(action)
				_refresh(lane)
	if event is InputEventScreenTouch:
		if event.pressed:
			for lane: int in range(regions.size()):
				if regions[lane].has_point(event.position):
					fingers[event.index] = lane
					_refresh(lane)
					break
		elif fingers.has(event.index):
			var lane: int = fingers[event.index]
			fingers.erase(event.index)
			_refresh(lane)

func clear() -> void:
	fingers.clear()
	keyboard.fill(false)
	held.fill(false)

func _refresh(lane: int) -> void:
	var down: bool = keyboard[lane] or fingers.values().has(lane)
	if down == held[lane]:
		return
	held[lane] = down
	if down:
		pressed.emit(lane)
	else:
		released.emit(lane)

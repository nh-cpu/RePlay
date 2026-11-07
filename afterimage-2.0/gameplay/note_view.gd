class_name NoteView
extends Node2D

var data: NoteData
@onready var head: Sprite2D = $Head

func place(time: float, hit_y: float, speed: float, width: float, active: bool) -> void:
	var head_y: float = hit_y - (data.time - time) * speed
	if active:
		head_y = hit_y
	position.y = head_y
	head.scale = Vector2.ONE * width / 256.0
	if data.duration > 0.0:
		var length: float = maxf(0.0, (data.end_time() - time) * speed if active else data.duration * speed)
		var body: Sprite2D = $Body
		var tail: Sprite2D = $Tail
		body.position.y = -length / 2.0
		body.scale = Vector2(width * 0.44 / 82.0, maxf(1.0, length) / 310.0)
		tail.position.y = -length
		tail.scale = Vector2(width * 0.44 / 82.0, -width * 0.44 / 82.0)
		modulate = Color(1.2, 1.15, 1.0) if active else Color.WHITE

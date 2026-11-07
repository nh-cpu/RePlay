extends Node2D

class_name Note

@export var note_speed : float = 1
@export var move_to_position : float = 700


func _ready() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "position", Vector2(position.x, move_to_position), note_speed)

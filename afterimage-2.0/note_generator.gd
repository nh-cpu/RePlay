extends Node2D
@export var scene_to_instance : PackedScene

func _ready() -> void:
	add_child(scene_to_instance.instantiate())

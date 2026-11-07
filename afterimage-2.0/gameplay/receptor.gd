class_name Receptor
extends Node2D

@onready var idle: Sprite2D = $Idle
@onready var glow: Sprite2D = $Glow

func set_pressed(value: bool) -> void:
	glow.visible = value

func set_width(width: float) -> void:
	idle.scale = Vector2.ONE * width / 256.0
	glow.scale = Vector2.ONE * width / 256.0
	idle.scale.y *= 0.45
	glow.scale.y *= 0.45

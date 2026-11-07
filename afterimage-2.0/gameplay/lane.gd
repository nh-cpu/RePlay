class_name RhythmLane
extends Control

const EFFECT: PackedScene = preload("res://gameplay/hit_effect.tscn")
var hit_y: float = 0.0
@onready var receptor: Receptor = $Receptor
@onready var key_label: Label = $Key
@onready var note_layer: Node2D = $Notes

func configure(index: int) -> void:
	key_label.text = ["D", "F", "J", "K"][index]
	$Background.color = Color("181e25") if index % 2 == 0 else Color("1c222a")

func layout_lane() -> void:
	hit_y = size.y - 90.0
	receptor.position = Vector2(size.x / 2.0, hit_y)
	receptor.set_width(size.x * 0.83)
	key_label.position = Vector2(0, hit_y + 32)
	key_label.size = Vector2(size.x, 35)

func flash(grade: int) -> void:
	if grade == 4:
		return
	var effect: Node2D = EFFECT.instantiate()
	effect.position = receptor.position
	effect.scale = Vector2.ONE * size.x / 160.0
	add_child(effect)

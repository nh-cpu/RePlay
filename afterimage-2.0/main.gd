extends Node2D

var note1 : bool = false
var note2 : bool = false
var note3 : bool = false
var note4 : bool = false
@onready var area_2d: Area2D = $Detector/Area2D



func _input(event: InputEvent) -> void:
		if event.is_action_pressed(("ui_left")):
			note1 = true
		else:
			note1 = false
		if event.is_action_pressed("ui_up"):
			note2 = true
		else:
			note2 = false
		if event.is_action_pressed("ui_up"):
			note3 = true
		else:
			note3 = false
		if event.is_action_pressed("ui_up"):
			note4 = true
		else:
			note4 = false


func _process(_delta:float ) -> void:
		for x in area_2d. get_overlapping_areas():
			if note1 == true and x.name == "LeftLeft":
					print("leftleft action")

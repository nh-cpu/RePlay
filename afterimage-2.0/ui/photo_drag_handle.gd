extends Control

signal grabbed(pointer: int, point: Vector2)
signal nudged(direction: int)

func _gui_input(event: InputEvent) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		grab_focus()
		grabbed.emit(-1, get_global_transform_with_canvas() * event.position)
	elif event is InputEventScreenTouch and event.pressed:
		accept_event()
		grab_focus()
		grabbed.emit(event.index, get_global_transform_with_canvas() * event.position)
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		accept_event()
		nudged.emit(-1 if event.is_action_pressed("ui_up") else 1)

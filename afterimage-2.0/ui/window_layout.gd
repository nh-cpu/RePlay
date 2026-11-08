extends Node

## Fit a landscape desktop window to the current monitor without covering its taskbar.

func _ready() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("mobile") or OS.has_feature("web"):
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var width: int = maxi(1, mini(int(usable.size.x * 0.9), int(usable.size.y * 0.9 * 16.0 / 9.0)))
	var height: int = maxi(1, int(width * 9.0 / 16.0))
	var window_size: Vector2i = Vector2i(width, height)
	DisplayServer.window_set_size(window_size)
	DisplayServer.window_set_position(usable.position + (usable.size - window_size) / 2)

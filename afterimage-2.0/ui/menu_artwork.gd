extends Control

var _fade: Tween
var _path: String = "<unset>"
@onready var previous: TextureRect = $Previous
@onready var current: TextureRect = $Current

func show_artwork(path: String, texture: Texture2D) -> void:
	if _path == path:
		return
	_path = path
	if _fade != null:
		_fade.kill()
	previous.texture = current.texture
	previous.modulate.a = current.modulate.a
	current.texture = texture
	current.modulate.a = 0
	_fade = create_tween().set_parallel(true)
	if texture != null:
		$Shade.color.a = 0.80
	else:
		_fade.tween_property($Shade, "color:a", 0.0, 0.35)
	_fade.tween_property(previous, "modulate:a", 0.0, 0.35)
	_fade.tween_property(current, "modulate:a", 1.0, 0.35)

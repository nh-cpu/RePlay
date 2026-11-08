class_name PerspectivePlayfield
extends Control

## Project the existing lane scenes onto a receding plane, including their effects.
@export_range(0.2, 0.8) var distant_width: float = 0.38

@onready var surface: SubViewport = $Surface
@onready var output: TextureRect = $Output
@onready var lane_root: Control = $Surface/Lanes

func _ready() -> void:
	output.texture = surface.get_texture()
	resized.connect(resize_surface)
	resize_surface()

func get_lanes() -> Array[RhythmLane]:
	var result: Array[RhythmLane] = []
	for child: Node in lane_root.get_children():
		result.append(child as RhythmLane)
	return result

func resize_surface() -> void:
	surface.size = Vector2i(maxi(2, ceili(size.x)), maxi(2, ceili(size.y)))
	lane_root.size = Vector2(surface.size)
	(output.material as ShaderMaterial).set_shader_parameter("distant_width", distant_width)

func screen_to_surface(point: Vector2) -> Vector2:
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * point
	if size.x <= 0.0 or size.y <= 0.0 or not Rect2(Vector2.ZERO, size).has_point(local):
		return Vector2(-1, -1)
	var uv: Vector2 = local / size
	var width_at_y: float = distant_width + (1.0 - distant_width) * uv.y
	var source: Vector2 = Vector2((uv.x - 0.5) / width_at_y + 0.5, uv.y / width_at_y)
	if source.x < 0.0 or source.x >= 1.0:
		return Vector2(-1, -1)
	return source * Vector2(surface.size)

@tool
extends Control

## Quiet geometric details keep the menu readable around the atlas artwork.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("17171c"))
	var center: Vector2 = Vector2(size.x * 0.84, size.y * 0.22)
	for index: int in range(4):
		var radius: float = 80.0 + index * 65.0
		var points: PackedVector2Array = PackedVector2Array([
			center + Vector2(0, -radius), center + Vector2(radius, 0),
			center + Vector2(0, radius), center + Vector2(-radius, 0),
			center + Vector2(0, -radius),
		])
		draw_polyline(points, Color(0.94, 0.92, 0.87, 0.025), 1.0, true)
	draw_line(Vector2(0, size.y - 12), Vector2(size.x, size.y - 12), Color(0.94, 0.92, 0.87, 0.08))

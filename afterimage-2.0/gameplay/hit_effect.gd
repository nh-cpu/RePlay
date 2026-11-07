extends Node2D

func _ready() -> void:
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property($Ring, "scale", Vector2.ONE * 0.65, 0.4).from(Vector2.ONE * 0.12)
	tween.tween_property($Spark, "rotation", 0.6, 0.35)
	tween.tween_property($Diamonds, "position:y", -50.0, 0.45)
	tween.tween_property(self, "modulate:a", 0.0, 0.45)
	tween.chain().tween_callback(queue_free)

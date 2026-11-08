@tool
extends CheckButton

const ATLAS: Texture2D = preload("res://Monochrome rhythm game menu sprite atlas.png")


func _ready() -> void:
	# Reserve native icon space so labels and keyboard focus retain normal behavior.
	var blank: Image = Image.create(48, 28, false, Image.FORMAT_RGBA8)
	blank.fill(Color.TRANSPARENT)
	var icon_texture: ImageTexture = ImageTexture.create_from_image(blank)
	for icon_name: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		add_theme_icon_override(icon_name, icon_texture)
	toggled.connect(func(_value: bool) -> void: queue_redraw())


func _draw() -> void:
	var source: Rect2 = Rect2(521, 1088, 190, 100) if button_pressed else Rect2(313, 1088, 190, 100)
	draw_texture_rect_region(ATLAS, Rect2(Vector2(size.x - 48, (size.y - 26) / 2), Vector2(48, 26)), source)

class_name SongCard
extends Control

var metadata: SongMetadata
var emphasis: float = 0.0
var chosen: int = 0
var artwork: Texture2D
var header_height: float = 86.0
var row_height: float = 38.0
var _rows: Array[Label] = []
@onready var title_label: Label = $Title
@onready var artist_label: Label = $Artist
@onready var rows: Control = $Rows

func configure(song: SongMetadata, texture: Texture2D) -> void:
	metadata = song
	artwork = texture
	title_label.text = song.title
	artist_label.text = song.artist
	tooltip_text = song.title + "\n" + song.artist
	for child: Node in rows.get_children():
		child.free()
	_rows.clear()
	for variant: SongDifficultyMetadata in song.difficulties:
		var label: Label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 14)
		label.text = "%s   /   BEST %07d" % [variant.label.to_upper(), variant.best_score]
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		rows.add_child(label)
		_rows.append(label)
	queue_redraw()

func present(weight: float, difficulty: int) -> void:
	emphasis = weight
	chosen = difficulty
	title_label.position = Vector2(22, 17)
	title_label.size = Vector2(maxf(0, size.x - 42), 29)
	artist_label.position = Vector2(22, 48)
	artist_label.size = Vector2(maxf(0, size.x - 42), 22)
	rows.position = Vector2(12, header_height + 6)
	rows.size = Vector2(size.x - 20, _rows.size() * row_height * weight)
	rows.visible = weight > 0.01
	for index: int in range(_rows.size()):
		_rows[index].position = Vector2(20, index * row_height + 6)
		_rows[index].size = Vector2(rows.size.x - 28, 26)
		_rows[index].modulate.a = weight
	queue_redraw()

func difficulty_at(local: Vector2) -> int:
	if emphasis < 0.95 or local.y < header_height + 6:
		return -1
	var index: int = int((local.y - header_height - 6) / row_height)
	return index if index >= 0 and index < _rows.size() else -1

func _draw() -> void:
	var header: Rect2 = Rect2(Vector2.ZERO, Vector2(size.x, header_height))
	draw_style_box(get_theme_stylebox("normal", "SongCard"), header)
	if artwork != null:
		var source: Rect2 = _cover(artwork.get_size(), header.size)
		draw_texture_rect_region(artwork, header, source, Color(0.6, 0.6, 0.6, 0.48))
	else:
		for index: int in range(3):
			var x: float = size.x - 120 + index * 40
			draw_polyline(PackedVector2Array([Vector2(x, 3), Vector2(x + 40, 43), Vector2(x, 83), Vector2(x - 40, 43), Vector2(x, 3)]), Color(0.94, 0.92, 0.87, 0.09), 1, true)
	draw_rect(header, Color(0.035, 0.035, 0.045, 0.55))
	draw_rect(Rect2(0, 0, 4, header_height), Color(0.94, 0.92, 0.85, lerpf(0.12, 1.0, emphasis)))
	if emphasis > 0.01:
		draw_rect(header.grow(-1), Color(0.94, 0.92, 0.85, emphasis * 0.8), false, 1.0)
		for index: int in range(_rows.size()):
			var rect: Rect2 = Rect2(12, header_height + 6 + index * row_height, size.x - 20, row_height - 3)
			rect.size.y *= emphasis
			draw_rect(rect, Color(0.25, 0.25, 0.27, emphasis * 0.95) if index == chosen else Color(0.08, 0.08, 0.1, emphasis * 0.95))
			if index == chosen:
				draw_rect(Rect2(rect.position, Vector2(3, rect.size.y)), Color(0.94, 0.92, 0.85, emphasis))

func _cover(image: Vector2, target: Vector2) -> Rect2:
	var factor: float = maxf(target.x / image.x, target.y / image.y)
	var region: Vector2 = target / factor
	return Rect2((image - region) / 2, region)

class_name AlbumBackground
extends Control

var album: AlbumData
var enabled: bool = true
var _textures: Dictionary = {}
var _failed: Dictionary = {}
@onready var first: TextureRect = $First
@onready var second: TextureRect = $Second

static func image_rect(view: Vector2, image_size: Vector2, progress: float, index: int) -> Rect2:
	var phase: float = smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))
	var cover: float = maxf(view.x / image_size.x, view.y / image_size.y)
	var dimensions: Vector2 = image_size * cover * lerpf(1.04, 1.10, phase)
	var overflow: Vector2 = (dimensions - view).max(Vector2.ZERO)
	var travel: Vector2 = Vector2(phase, 0.35 + phase * 0.3)
	if index % 2 == 1:
		travel = Vector2.ONE - travel
	return Rect2(-overflow * travel, dimensions)

func show_time(time: float) -> bool:
	if not enabled or album == null or album.cues.is_empty():
		hide()
		first.texture = null
		second.texture = null
		_textures.clear()
		return false
	var index: int = 0
	for candidate: int in range(album.cues.size()):
		if time >= float(album.cues[candidate].start):
			index = candidate
	var current: Texture2D = _texture(index)
	while current == null and index + 1 < album.cues.size():
		index += 1
		current = _texture(index)
	if current == null:
		# A missing final photo should not blank an otherwise usable album.
		while current == null and index > 0:
			index -= 1
			current = _texture(index)
	if current == null:
		hide()
		return false
	show()
	first.texture = current
	_place(first, index, time)
	var next_index: int = index + 1
	var upcoming: Texture2D
	while next_index < album.cues.size():
		upcoming = _texture(next_index)
		if upcoming != null:
			break
		next_index += 1
	second.texture = upcoming
	second.modulate.a = 0.0
	if upcoming != null:
		var fade: float = _incoming_fade(next_index)
		var transition: float = float(album.cues[next_index].start)
		second.modulate.a = clampf((time - transition + fade) / maxf(0.001, fade), 0.0, 1.0)
		_place(second, next_index, time)
	# Retain at most the two displayed textures.
	var keep: Array[int] = [int(album.cues[index].photo)]
	if upcoming != null:
		keep.append(int(album.cues[next_index].photo))
	for key: int in _textures.keys():
		if key not in keep:
			_textures.erase(key)
	return true

func _texture(index: int) -> Texture2D:
	var photo: int = int(album.cues[index].photo)
	if _failed.has(photo):
		return null
	if _textures.has(photo):
		return _textures[photo]
	var path: String = album.photos[photo]
	if not FileAccess.file_exists(path):
		_failed[photo] = true
		return null
	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		_failed[photo] = true
		return null
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_textures[photo] = texture
	return texture

func _incoming_fade(index: int) -> float:
	if index == 0:
		return 0.0
	var previous: Dictionary = album.cues[index - 1]
	var cue: Dictionary = album.cues[index]
	return minf(0.75, minf(float(previous.end) - float(previous.start), float(cue.end) - float(cue.start)) * 0.25)

func _place(layer: TextureRect, index: int, time: float) -> void:
	var cue: Dictionary = album.cues[index]
	var start: float = float(cue.start) - _incoming_fade(index)
	var progress: float = (time - start) / (float(cue.end) - start)
	var rect: Rect2 = image_rect(size, layer.texture.get_size(), progress, index)
	layer.position = rect.position
	layer.size = rect.size

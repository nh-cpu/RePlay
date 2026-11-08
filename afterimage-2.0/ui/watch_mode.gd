extends Control

signal home_requested

var chart: ChartData
var paused: bool = false
var finished: bool = false
@onready var clock: SongClock = $SongClock
@onready var music: AudioStreamPlayer = $Music
@onready var album: AlbumBackground = $AlbumBackground

func _ready() -> void:
	music.stream = chart.audio
	album.album = chart.album
	album.enabled = true
	album.get_node("Dim").color.a = 0.08
	$Controls/Content/Title.text = chart.title
	$Controls/Content/Buttons/Back.pressed.connect(func() -> void: home_requested.emit())
	$Controls/Content/Buttons/Pause.pressed.connect(toggle_pause)
	music.finished.connect(_ended)
	clock.setup(music, 0.0)
	resized.connect(_layout)
	_layout()
	_update_picture()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not finished and not paused:
		toggle_pause()

func _exit_tree() -> void:
	if is_instance_valid(music):
		music.stop()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		toggle_pause()

func _process(_delta: float) -> void:
	_update_picture()
	var duration: float = maxf(0.001, chart.audio.get_length())
	var time: float = clampf(clock.current_time(), 0, duration)
	$Controls/Content/Progress.value = time / duration * 100
	$Controls/Content/Buttons/Time.text = "%02d:%02d / %02d:%02d" % [int(time) / 60, int(time) % 60, int(duration) / 60, int(duration) % 60]

func toggle_pause() -> void:
	if finished:
		music.stop()
		music.stream_paused = false
		clock.started = false
		clock.ended = false
		clock.time = 0.0
		clock.frozen = false
		finished = false
		paused = false
	else:
		paused = not paused
		clock.freeze(paused)
	$Controls/Content/Buttons/Pause.text = "RESUME" if paused else "PAUSE"

func _ended() -> void:
	finished = true
	clock.freeze(true)
	clock.time = chart.audio.get_length()
	$Controls/Content/Buttons/Pause.text = "REPLAY"

func _update_picture() -> void:
	$NoPhotos.visible = not album.show_time(clampf(clock.current_time(), 0, chart.audio.get_length()))

func _layout() -> void:
	$Controls.position = Vector2(16, size.y - 150)
	$Controls.size = Vector2(size.x - 32, 134)

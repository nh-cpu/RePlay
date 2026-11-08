class_name HoldConfirmButton
extends Button

signal confirmed
signal hold_started
signal confirmation_started

const HOLD_SECONDS: float = 3.0
const HOLD_AUDIO: AudioStream = preload("res://assets/hold-confirm.mp3")
var holding: bool = false
var completing: bool = false
var elapsed: float = 0.0
var _audio: AudioStreamPlayer

func _ready() -> void:
	set_meta("custom_confirmation_audio", true)
	_audio = AudioStreamPlayer.new()
	_audio.stream = HOLD_AUDIO
	_audio.volume_db = -10.0
	add_child(_audio)
	button_down.connect(begin_hold)
	button_up.connect(cancel_hold)
	mouse_exited.connect(cancel_hold)
	focus_exited.connect(cancel_hold)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			cancel_hold())
	tooltip_text = "Hold for 3 seconds. Releasing early cancels."

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_hold()

func _process(delta: float) -> void:
	if not holding:
		return
	if disabled or not is_visible_in_tree():
		cancel_hold()
		return
	elapsed = minf(HOLD_SECONDS, elapsed + delta)
	queue_redraw()
	if elapsed >= HOLD_SECONDS:
		holding = false
		completing = true
		_audio.stop()
		disabled = true
		confirmation_started.emit()
		get_node("/root/UISounds").play_confirmation()
		if is_inside_tree():
			confirmed.emit()

func _draw() -> void:
	if holding or completing:
		draw_rect(Rect2(0, size.y - 4, size.x * elapsed / HOLD_SECONDS, 4), Color(0.25, 0.3, 0.31, 1))

func begin_hold() -> void:
	if disabled or completing or holding:
		return
	elapsed = 0
	holding = true
	_audio.play(0)
	hold_started.emit()
	queue_redraw()

func cancel_hold() -> void:
	if not holding:
		return
	holding = false
	elapsed = 0
	if _audio != null:
		_audio.stop()
	queue_redraw()

func reset_confirmation() -> void:
	cancel_hold()
	completing = false
	elapsed = 0
	disabled = false
	queue_redraw()

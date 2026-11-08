class_name SongClock
extends Node

var time: float = -2.0
var frozen: bool = false
var started: bool = false
var ended: bool = false
var player: AudioStreamPlayer

func setup(audio_player: AudioStreamPlayer, start_time: float) -> void:
	player = audio_player
	time = start_time
	player.finished.connect(func() -> void: ended = true)

func _process(delta: float) -> void:
	if frozen or player == null:
		return
	if not started:
		time += delta
		if time >= 0.0:
			started = true
			time = 0.0
			player.play()
	elif ended:
		time += delta
	else:
		var audio_time: float = player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		time = maxf(time, audio_time)

func freeze(value: bool) -> void:
	if value:
		time = current_time()
	frozen = value
	player.stream_paused = value

func current_time() -> float:
	if not started or frozen or ended:
		return time
	return maxf(time, player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())

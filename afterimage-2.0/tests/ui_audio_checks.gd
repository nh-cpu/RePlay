extends SceneTree

var checks: int = 0
var failures: int = 0
var clicks: int = 0
var sounds: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	sounds = root.get_node("UISounds")
	sounds.menu_played.connect(func() -> void: clicks += 1)
	var normal: Button = Button.new()
	root.add_child(normal)
	normal.pressed.emit()
	check(clicks == 1, "Regular buttons play one menu sound")
	normal.free()
	var hold: HoldConfirmButton = HoldConfirmButton.new()
	root.add_child(hold)
	hold.set_process(false)
	var results: Array[bool] = []
	hold.confirmed.connect(func() -> void: results.append(true))
	hold.pressed.emit()
	check(clicks == 1 and results.is_empty(), "Ordinary click cannot bypass hold or double-play audio")
	hold.begin_hold()
	hold._process(1.5)
	check(hold.holding and hold._audio.playing and results.is_empty(), "Holding plays audio without acting early")
	hold.cancel_hold()
	check(not hold.holding and not hold._audio.playing and hold.elapsed == 0, "Early release stops and resets hold")
	hold.begin_hold()
	hold._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not hold.holding and hold.elapsed == 0, "Focus loss cancels hold")
	hold.disabled = true
	hold.begin_hold()
	check(not hold.holding, "Disabled confirmation cannot start")
	hold.disabled = false
	hold.begin_hold()
	hold._process(3.0)
	check(hold.completing and not hold._audio.playing and is_equal_approx(hold.elapsed, 3.0), "Hold sound stops at three seconds")
	check(clicks == 2 and results.size() == 1, "Confirmation fires immediately when hold completes")
	hold.cancel_hold()
	hold.begin_hold()
	await create_timer(sounds.MENU.get_length() + 0.3).timeout
	check(results.size() == 1, "Menu sound ending does not trigger a second confirmation")
	hold.reset_confirmation()
	check(not hold.completing and not hold.disabled and hold.elapsed == 0, "Failed action can reset for retry")
	hold.queue_free()
	var service: GenerationService = GenerationService.new()
	service.config_path = "res://tests/artifacts/audio_preferences.cfg"
	service.jobs_root = "res://tests/artifacts/audio_jobs"
	root.add_child(service)
	var review: Node2D = load("res://ui/photo_review.tscn").instantiate()
	review.service = service
	root.add_child(review)
	var cancel: HoldConfirmButton = review.content.get_node("Buttons/Cancel")
	var generate: HoldConfirmButton = review.content.get_node("Buttons/Generate")
	check(generate.disabled, "Invalid draft still cannot generate")
	cancel.begin_hold()
	review._lock_confirmation()
	check(review.get_node("Layer/Root/InputBlocker").visible and generate.disabled, "Committed action blocks draft editing")
	review._unlock_confirmation()
	check(not review.get_node("Layer/Root/InputBlocker").visible and generate.disabled, "Unlock restores original validation")
	review._cancel()
	service.queue_free()
	await process_frame
	# Let the audio mixer release stopped MP3 playback before shutting down the test.
	await create_timer(0.1).timeout
	check(ProjectSettings.get_setting("application/boot_splash/image") == "res://assets/Afterimage vintage camera logo.png", "Custom startup splash is configured")
	print("UI AUDIO: %d assertions, %d failures; menu %.2fs, hold %.2fs" % [checks, failures, sounds.MENU.get_length(), HoldConfirmButton.HOLD_AUDIO.get_length()])
	quit(1 if failures else 0)

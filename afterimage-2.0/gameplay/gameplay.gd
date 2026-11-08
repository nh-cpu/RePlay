extends Control

signal completed(result: Dictionary)
signal home_requested

var chart: ChartData
var service: GenerationService
var paused: bool = false
var resuming: bool = false
var resume_left: float = 0.0
var finished: bool = false
var lanes: Array[RhythmLane] = []
@onready var clock: SongClock = $SongClock
@onready var judge: JudgmentController = $JudgmentController
@onready var score: ScoreTracker = $ScoreTracker
@onready var controls: LaneInput = $LaneInput
@onready var scheduler: ChartScheduler = $ChartScheduler
@onready var hud: Control = $HUD

func _ready() -> void:
	lanes = $Playfield.get_lanes()
	controls.position_mapper = $Playfield.screen_to_surface
	$AlbumBackground.album = chart.album
	if service != null:
		$AlbumBackground.enabled = service.album_background
		$PauseOverlay/Center/Panel/Content/Album.set_pressed_no_signal(service.album_background)
		$PauseOverlay/Center/Panel/Content/Album.toggled.connect(service.set_album_background)
		service.album_background_changed.connect(_album_setting_changed)
	for index: int in range(4):
		lanes[index].configure(index)
	$Music.stream = chart.audio
	clock.setup($Music, minf(-2.0, chart.notes[0].time - 2.0))
	judge.setup(chart)
	scheduler.chart = chart
	scheduler.lanes = lanes
	judge.judged.connect(_on_judged)
	judge.hold_started.connect(_on_hold_started)
	controls.pressed.connect(_on_pressed)
	controls.released.connect(_on_released)
	score.changed.connect(func() -> void: hud.set_score(score.score, score.combo))
	$HUD/Title.text = chart.title
	$HUD/Pause.pressed.connect(_pause)
	$PauseOverlay/Center/Panel/Content/Resume.pressed.connect(_resume)
	$PauseOverlay/Center/Panel/Content/Home.pressed.connect(func() -> void: home_requested.emit())
	resized.connect(_layout)
	_layout.call_deferred()
	hud.set_score(0, 0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and not finished:
		_pause()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if paused and not resuming:
			_resume()
		else:
			_pause()

func _process(delta: float) -> void:
	_update_album()
	if finished:
		return
	if resuming:
		resume_left -= delta
		$HUD/Countdown.text = "REJOIN HOLDS\n%d" % maxi(1, ceili(resume_left))
		if resume_left <= 0.0:
			resuming = false
			paused = false
			judge.held.assign(controls.held)
			clock.freeze(false)
	if paused:
		return
	judge.advance(clock.time)
	scheduler.update(clock.time, judge.states)
	$HUD/Progress.value = maxf(0.0, clock.time) / chart.audio.get_length() * 100.0
	$HUD/Countdown.text = str(ceili(-clock.time)) if clock.time < 0.0 else ""
	if clock.time >= maxf(chart.audio.get_length(), chart.last_time() + 0.2) + 0.5:
		finished = true
		controls.enabled = false
		completed.emit(score.summary(chart.notes.size()))

func _layout() -> void:
	$HUD/Title.size.x = maxf(100.0, size.x - 285.0)
	$HUD/Title.clip_text = true
	var width: float = minf(680.0, size.x - 24.0)
	$Playfield.position = Vector2((size.x - width) / 2.0, 100)
	$Playfield.size = Vector2(width, maxf(240.0, size.y - 124.0))
	$Playfield.resize_surface()
	controls.regions.clear()
	for index: int in range(4):
		var lane: RhythmLane = lanes[index]
		lane.position = Vector2(index * width / 4.0, 0)
		lane.size = Vector2(width / 4.0 - 2.0, $Playfield.size.y)
		lane.layout_lane()
		controls.regions.append(Rect2(lane.position, lane.size))

func _pause() -> void:
	if finished:
		return
	paused = true
	resuming = false
	clock.freeze(true)
	controls.enabled = false
	controls.clear()
	for lane: RhythmLane in lanes:
		lane.receptor.set_pressed(false)
	$PauseOverlay.show()
	$HUD/Countdown.text = ""

func _resume() -> void:
	$PauseOverlay.hide()
	controls.enabled = true
	resuming = true
	resume_left = 3.0

func _on_pressed(lane: int) -> void:
	lanes[lane].receptor.set_pressed(true)
	if not paused:
		judge.press(lane, clock.current_time())

func _on_released(lane: int) -> void:
	lanes[lane].receptor.set_pressed(false)
	if not paused:
		judge.release(lane, clock.current_time())

func _on_judged(index: int, grade: int) -> void:
	score.record(grade)
	hud.feedback(grade)
	lanes[chart.notes[index].lane].flash(grade)

func _on_hold_started(index: int, grade: int) -> void:
	hud.feedback(grade)
	lanes[chart.notes[index].lane].flash(grade)

func _album_setting_changed(value: bool) -> void:
	$AlbumBackground.enabled = value
	$PauseOverlay/Center/Panel/Content/Album.set_pressed_no_signal(value)
	_update_album()

func _update_album() -> void:
	var active: bool = $AlbumBackground.show_time(clock.time)
	for lane: RhythmLane in lanes:
		lane.set_album_visible(active)

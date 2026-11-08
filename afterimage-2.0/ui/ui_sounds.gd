extends Node

signal menu_played
const MENU: AudioStream = preload("res://assets/menu-sound.mp3")
var _clicks: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_clicks = AudioStreamPlayer.new()
	_clicks.stream = MENU
	_clicks.volume_db = -10.0
	_clicks.max_polyphony = 4
	add_child(_clicks)
	get_tree().node_added.connect(_watch_button)
	_watch_tree(get_tree().root)

func play_menu() -> void:
	_clicks.play()
	menu_played.emit()

func play_confirmation() -> void:
	# A dedicated voice lets confirmation finish even if another UI sound plays.
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = MENU
	player.volume_db = -10.0
	add_child(player)
	player.finished.connect(player.queue_free, CONNECT_ONE_SHOT)
	player.play()
	menu_played.emit()

func _watch_tree(node: Node) -> void:
	_watch_button(node)
	for child: Node in node.get_children():
		_watch_tree(child)

func _watch_button(node: Node) -> void:
	if node is BaseButton:
		var button: BaseButton = node as BaseButton
		if not button.pressed.is_connected(_button_pressed.bind(button)):
			button.pressed.connect(_button_pressed.bind(button))

func _button_pressed(button: BaseButton) -> void:
	if not button.get_meta("custom_confirmation_audio", false):
		play_menu()

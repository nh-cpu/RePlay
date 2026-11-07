extends Control

signal retry_requested
signal home_requested

var result: Dictionary
var title: String

func _ready() -> void:
	$Center/Content/Title.text = title
	$Center/Content/Score.text = "%07d" % int(result.score)
	$Center/Content/Stats.text = "%.2f%% ACCURACY    /    %d MAX COMBO" % [result.accuracy, result.max_combo]
	var lines: String = ""
	for index: int in range(5):
		lines += "%s    %d\n" % [ScoreTracker.NAMES[index].to_upper(), result.counts[index]]
	$Center/Content/Judgments.text = lines
	$Center/Content/Buttons/Retry.pressed.connect(func() -> void: retry_requested.emit())
	$Center/Content/Buttons/Home.pressed.connect(func() -> void: home_requested.emit())

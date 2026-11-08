extends Control

signal retry_requested
signal home_requested

var result: Dictionary
var title: String

func _ready() -> void:
	$Center/Card/Content/Title.text = title
	$Center/Card/Content/Score.text = "%07d" % int(result.score)
	$Center/Card/Content/Stats.text = "%.2f%% ACCURACY\n%d MAX COMBO" % [result.accuracy, result.max_combo]
	var lines: String = ""
	for index: int in range(5):
		lines += "%s    %d\n" % [ScoreTracker.NAMES[index].to_upper(), result.counts[index]]
	$Center/Card/Content/Judgments.text = lines
	$Center/Card/Content/Buttons/Retry.pressed.connect(func() -> void: retry_requested.emit())
	$Center/Card/Content/Buttons/Home.pressed.connect(func() -> void: home_requested.emit())

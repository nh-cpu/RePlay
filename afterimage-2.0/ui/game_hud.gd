extends Control

var feedback_tween: Tween

func set_score(score: int, combo: int) -> void:
	$Score.text = "%07d" % score
	$Feedback/Combo.text = "%d\nCOMBO" % combo if combo > 0 else ""

func feedback(grade: int) -> void:
	$Feedback/Judgment.text = ScoreTracker.NAMES[grade].to_upper()
	$Feedback/Judgment.modulate = Color("f8dfac") if grade < 2 else Color("cbd8e6")
	if grade == 4:
		$Feedback/Judgment.modulate = Color("ef8795")
	if feedback_tween:
		feedback_tween.kill()
	feedback_tween = create_tween()
	feedback_tween.tween_interval(0.35)
	feedback_tween.tween_property($Feedback/Judgment, "modulate:a", 0.0, 0.25)

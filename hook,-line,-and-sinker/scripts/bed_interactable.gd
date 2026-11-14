class_name BedInteractable
extends Interactable

# Bed: skips to the next period (night -> next morning) via GameManager.rest().
# Free, and usable even after night's actions are spent (spends_time() is false).
# At night it fades to black and back (sleeping until morning).

@export var prompt: InteractPrompt


func _on_body_entered(body: Node2D) -> void:
	super(body)
	if body is Player and prompt != null:
		prompt.pop_in()


func _on_body_exited(body: Node2D) -> void:
	super(body)
	if body is Player and prompt != null:
		prompt.pop_out()


# Sleeping through the night: fade to black, rest at full black, fade back in.
const NIGHT_FADE := 0.8
const NIGHT_HOLD := 0.5

var _sleeping := false


func interact(player: Node2D) -> void:
	if _sleeping or (player is Player and player.busy):
		return
	if not GameManager.is_period(GameManager.Times.NIGHT):
		_rest()
		return
	_sleeping = true
	var fade := ScreenFade.new()
	get_tree().root.add_child(fade)
	await fade.fade_to(1.0, NIGHT_FADE)
	_rest()
	await get_tree().create_timer(NIGHT_HOLD).timeout
	await fade.fade_to(0.0, NIGHT_FADE)
	fade.queue_free()
	_sleeping = false


func _rest() -> void:
	GameManager.rest()
	print("Rested: day %d, %s" % [GameManager.get_day(), GameManager.get_period_name()])

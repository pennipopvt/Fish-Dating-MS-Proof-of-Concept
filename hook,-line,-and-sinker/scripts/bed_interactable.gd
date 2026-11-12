class_name BedInteractable
extends Interactable

# Bed: skips to the next period (night -> next morning) via GameManager.rest().
# Free, and usable even after night's actions are spent (spends_time() is false).

@export var prompt: InteractPrompt


func _on_body_entered(body: Node2D) -> void:
	super(body)
	if body is Player and prompt != null:
		prompt.pop_in()


func _on_body_exited(body: Node2D) -> void:
	super(body)
	if body is Player and prompt != null:
		prompt.pop_out()


func interact(player: Node2D) -> void:
	if player is Player and player.busy:
		return
	GameManager.rest()
	print("Rested: day %d, %s" % [GameManager.get_day(), GameManager.get_period_name()])

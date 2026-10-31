class_name BaitInteractable
extends Interactable

# Object on the ground that opens the bait menu (any node in the "bait_menu" group).

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
	# Don't open while the player is fishing or otherwise busy
	if player is Player and player.busy:
		return
	get_tree().call_group(&"bait_menu", &"open")

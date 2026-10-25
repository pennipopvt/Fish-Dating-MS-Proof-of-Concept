class_name Interactable
extends Area2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player != null:
		player.current_interactable = self

func _on_body_exited(body: Node2D) -> void:
	var player := body as Player
	if player != null:
		if player.current_interactable == self:
			player.current_interactable = null

func interact(_player: Node2D) -> void:
	#should be overwritten with inheritance
	print("ERROR: Interact not overwritten")
	pass

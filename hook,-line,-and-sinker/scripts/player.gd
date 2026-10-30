class_name Player
extends CharacterBody2D

const SPEED = 100.0
const ACC=2000
var held_item: ItemData = null
var current_interactable: Interactable = null
var busy: bool = false;

@onready var fishing_controller: Node = $FishingController


func _physics_process(delta: float) -> void:
	
	if busy:
		velocity.x = 0;
		move_and_slide()
		return
	
	var direction := Input.get_axis("Move Left", "Move Right")
	if direction:
		velocity.x = move_toward(velocity.x,direction * SPEED,ACC*delta)
	else:
		velocity.x = move_toward(velocity.x, 0, ACC*delta)

	move_and_slide()	


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Interact"):
		interact()


func interact() -> void:
	if is_instance_valid(current_interactable):
		current_interactable.interact(self)

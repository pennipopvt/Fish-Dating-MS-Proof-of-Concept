extends CharacterBody2D

const SPEED = 300.0

var held_item: ItemData = null
var current_interactable: Interactable = null


func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("Move Left", "Move Right")

	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("Interact"):
		interact()


func interact() -> void:
	if is_instance_valid(current_interactable):
		current_interactable.interact(self)

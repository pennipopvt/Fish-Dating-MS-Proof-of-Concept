extends CharacterBody2D
const SPEED = 300.0

var held_item : ItemData = null;

func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("Move Left", "Move Right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

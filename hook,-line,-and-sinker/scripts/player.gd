class_name Player
extends CharacterBody2D

const SPEED = 150.0

var held_item: ItemData = null
var current_interactable: Interactable = null
var busy: bool = false;
var last_direction : float;

@onready var fishing_controller: Node = $FishingController
@onready var animator : AnimatedSprite2D = $AnimatedSprite2D


func _physics_process(delta: float) -> void:
	
	if busy or DialogueManager.is_active or ShopManager.is_shop_open:
		velocity.x = 0;
		move_and_slide()
		return
	
	var direction := Input.get_axis("Move Left", "Move Right")

	if direction:
		velocity.x = direction * SPEED
		if sign(velocity.x) < 0:
			animator.play("walk_l")
		else:
			animator.play("walk_r")
		last_direction = direction
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		if sign(last_direction) < 0:
			animator.play("idle_l")
		else:
			animator.play("idle_r")

	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if not DialogueManager.is_active and not ShopManager.is_shop_open and not busy and event.is_action_pressed("Interact"):
		interact()


func interact() -> void:
	if is_instance_valid(current_interactable):
		current_interactable.interact(self)

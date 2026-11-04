class_name Player
extends CharacterBody2D

const SPEED = 100.0
const ACC = 2000.0


signal held_item_changed(item: ItemData)
var held_item: ItemData = null
var held_item_visual: Sprite2D

var current_interactable: Interactable = null
var busy: bool = false;
var last_direction : float;

@onready var fishing_controller: Node = $FishingController
@onready var animator : AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	held_item_visual = Sprite2D.new()
	held_item_visual.position = Vector2(0, -39)
	held_item_visual.z_index = 5
	add_child(held_item_visual)
	_refresh_held_item()

func take_item(item: ItemData) -> bool:
	if held_item != null or item == null:
		return false
	held_item = item
	_refresh_held_item()
	held_item_changed.emit(held_item)
	return true

func remove_held_item() -> ItemData:
	var previous := held_item
	held_item = null
	_refresh_held_item()
	held_item_changed.emit(held_item)
	return previous

func _refresh_held_item() -> void:
	if held_item_visual == null:
		return
	held_item_visual.texture = held_item.sprite if held_item != null else null
	held_item_visual.visible = held_item != null and held_item.sprite != null

func drop_item() -> void:
	if held_item == null:
		return
	var item := remove_held_item()
	var pickup := ItemPickup.new()
	pickup.item = item
	get_parent().add_child(pickup)
	pickup.global_position = global_position + Vector2(24 if last_direction >= 0 else -24, 0)



func _physics_process(delta: float) -> void:

	if busy or GameManager.is_modal_ui_open():
		velocity.x = 0;
		move_and_slide()
		return

	var direction := Input.get_axis("Move Left", "Move Right")

	if direction:
		velocity.x = move_toward(velocity.x, direction * SPEED, ACC * delta)
		if sign(direction) < 0:
			animator.play("walk_l")
		else:
			animator.play("walk_r")
		last_direction = direction
	else:
		velocity.x = move_toward(velocity.x, 0, ACC * delta)
		if sign(last_direction) < 0:
			animator.play("idle_l")
		else:
			animator.play("idle_r")

	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if GameManager.is_modal_ui_open() or busy:
		return
	if event.is_action_pressed("Interact"):
		interact()


func interact() -> void:
	if is_instance_valid(current_interactable):
		current_interactable.interact(self)
	elif held_item != null:
		# Space drops the item when there is nothing nearby to interact with.
		drop_item()

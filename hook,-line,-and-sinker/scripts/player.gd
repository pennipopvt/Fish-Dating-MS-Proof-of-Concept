class_name Player
extends CharacterBody2D

const SPEED = 100.0
const ACC = 2000.0

signal held_item_changed(item: ItemData)
var held_item: ItemData = null
var held_item_visual: Sprite2D

const PICKUP_SHOW_TIME := 1.0

var current_interactable: Interactable = null
var busy: bool = false;
var last_direction : float;

var _pickup_visual: Sprite2D
var _pickup_tween: Tween
var _pickup_time_left := 0.0

@onready var fishing_controller: Node = $FishingController
@onready var animator : AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	held_item_visual = Sprite2D.new()
	held_item_visual.position = Vector2(0, -39)
	held_item_visual.z_index = 5
	add_child(held_item_visual)
	_refresh_held_item()

	_pickup_visual = Sprite2D.new()
	_pickup_visual.z_index = 6
	_pickup_visual.visible = false
	add_child(_pickup_visual)

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
	if _pickup_time_left > 0.0:
		_pickup_time_left -= delta
		if _pickup_time_left <= 0.0:
			_pickup_visual.visible = false

	if busy or GameManager.is_modal_ui_open():
		velocity.x = 0;
		move_and_slide()
		return

	var direction := Input.get_axis("Move Left", "Move Right")

	if direction:
		velocity.x = move_toward(velocity.x, direction * SPEED, ACC * delta)
		if sign(direction) < 0:
			animator.play("walk_carry_l" if _is_carrying() else "walk_l")
		else:
			animator.play("walk_carry_r" if _is_carrying() else "walk_r")
		last_direction = direction
	else:
		velocity.x = move_toward(velocity.x, 0, ACC * delta)
		if sign(last_direction) < 0:
			animator.play("idle_carry_l" if _is_carrying() else "idle_l")
		else:
			animator.play("idle_carry_r" if _is_carrying() else "idle_r")

	move_and_slide()


# Mouse input can be consumed by the SubViewportContainer before
# _unhandled_input runs. Catch mouse interactions at the input stage instead.
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if GameManager.is_modal_ui_open() or busy:
		return
	if event.is_action_pressed("Interact"):
		interact()
		get_viewport().set_input_as_handled()


# Keyboard interaction stays unhandled so focused UI controls take priority.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		return
	if GameManager.is_modal_ui_open() or busy:
		return
	if event.is_action_pressed("Interact"):
		interact()


func interact() -> void:
	# Overlapping interactables (e.g. a delivery dropped on the bobber shelf):
	# use the best one in reach, not just whichever was entered last.
	var best := _best_interactable(null)
	if best != null:
		current_interactable = best
	if is_instance_valid(current_interactable):
		current_interactable.interact(self)
	elif held_item != null:
		# Space drops the item when there is nothing nearby to interact with.
		drop_item()


# Hold a just-picked-up thing overhead for a moment (e.g. an upgrade package,
# already applied). Doesn't use the held-item slot.
func show_pickup(texture: Texture2D) -> void:
	if texture == null:
		return
	# Sit above the held item if hands are full.
	var top := held_item_visual.position.y - (16.0 if held_item != null else 0.0)
	_pickup_visual.texture = texture
	_pickup_visual.position = Vector2(0, top + 6)
	_pickup_visual.visible = true
	_pickup_time_left = PICKUP_SHOW_TIME

	if _pickup_tween != null:
		_pickup_tween.kill()
	_pickup_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pickup_tween.tween_property(_pickup_visual, "position:y", top, 0.2)


# Stop targeting an interactable that's going away, and switch to another one
# the player is still standing on (the closest, e.g. in a pile of deliveries).
func release_interactable(which: Interactable) -> void:
	if current_interactable != which:
		return
	current_interactable = _best_interactable(which)


# Of the interactables the player overlaps: loose pickups first, then the
# closest one.
func _best_interactable(exclude: Interactable) -> Interactable:
	var best: Interactable = null
	var best_score := INF
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var other := node as Interactable
		if other == exclude or other.is_queued_for_deletion() or not other.overlaps_body(self):
			continue
		var score := absf(other.global_position.x - global_position.x)
		if not other is ItemPickup:
			score += 1000.0
		if score < best_score:
			best_score = score
			best = other
	return best


func _is_carrying() -> bool:
	return held_item != null or _pickup_time_left > 0.0

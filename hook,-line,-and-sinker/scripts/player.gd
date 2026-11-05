class_name Player
extends CharacterBody2D

const SPEED = 100.0
const ACC = 2000.0
const SPRITE_FRAME_SIZE = Vector2i(32, 32)

const CARRY_WALK_LEFT = preload("res://sprites/characters/penni/penni_carry_L.png")
const CARRY_WALK_RIGHT = preload("res://sprites/characters/penni/penni_carry_r.png")
const CARRY_IDLE_LEFT = preload("res://sprites/characters/penni/penni_idle_carry_L.png")
const CARRY_IDLE_RIGHT = preload("res://sprites/characters/penni/penni_idle_carry_R.png")


signal held_item_changed(item: ItemData)
var held_item: ItemData = null
var held_item_visual: Sprite2D

var current_interactable: Interactable = null
var busy: bool = false;
var last_direction : float;

@onready var fishing_controller: Node = $FishingController
@onready var animator : AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	_setup_carry_animations()
	held_item_visual = Sprite2D.new()
	held_item_visual.position = Vector2(0, -39)
	held_item_visual.z_index = 5
	add_child(held_item_visual)
	_refresh_held_item()

# Build carrying animations from the existing sprite strips.
func _setup_carry_animations() -> void:
	animator.sprite_frames = animator.sprite_frames.duplicate(true)
	_add_carry_animation(&"walk_carry_l", CARRY_WALK_LEFT, 12.0)
	_add_carry_animation(&"walk_carry_r", CARRY_WALK_RIGHT, 12.0)
	_add_carry_animation(&"idle_carry_l", CARRY_IDLE_LEFT, 3.0)
	_add_carry_animation(&"idle_carry_r", CARRY_IDLE_RIGHT, 3.0)


func _add_carry_animation(animation_name: StringName, sheet: Texture2D, fps: float) -> void:
	var frames := animator.sprite_frames
	if not frames.has_animation(animation_name):
		frames.add_animation(animation_name)
	frames.clear(animation_name)
	frames.set_animation_speed(animation_name, fps)
	frames.set_animation_loop(animation_name, true)
	var frame_count: int = sheet.get_width() / SPRITE_FRAME_SIZE.x
	for i in range(frame_count):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(i * SPRITE_FRAME_SIZE.x, 0, SPRITE_FRAME_SIZE.x, SPRITE_FRAME_SIZE.y)
		frames.add_frame(animation_name, frame)


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
			animator.play("walk_carry_l" if held_item != null else "walk_l")
		else:
			animator.play("walk_carry_r" if held_item != null else "walk_r")
		last_direction = direction
	else:
		velocity.x = move_toward(velocity.x, 0, ACC * delta)
		if sign(last_direction) < 0:
			animator.play("idle_carry_l" if held_item != null else "idle_l")
		else:
			animator.play("idle_carry_r" if held_item != null else "idle_r")

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
	if is_instance_valid(current_interactable):
		current_interactable.interact(self)
	elif held_item != null:
		# Space drops the item when there is nothing nearby to interact with.
		drop_item()

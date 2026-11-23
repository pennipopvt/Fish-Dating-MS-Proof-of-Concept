class_name Player
extends CharacterBody2D

const SPEED = 100.0
const ACC = 2000.0
const SWIM_SPEED: float = 78.0
const SWIM_LEFT_SHEET: Texture2D = preload("res://sprites/characters/penni/penni_swim_L.png")
const SWIM_RIGHT_SHEET: Texture2D = preload("res://sprites/characters/penni/penni_swim_R.png")
const SWIM_IDLE_LEFT_SHEET: Texture2D = preload("res://sprites/characters/penni/penni_swim_idle_L.png")
const SWIM_IDLE_RIGHT_SHEET: Texture2D = preload("res://sprites/characters/penni/penni_swim_idle_R.png")

@export_group("Swimming Animation")
@export var swim_frame_size: Vector2i = Vector2i(32, 32)
@export_range(1.0, 24.0, 0.5) var swim_frames_per_second: float = 8.0
@export_range(1.0, 24.0, 0.5) var swim_idle_frames_per_second: float = 5.0

signal held_item_changed(item: ItemData)
var held_item: ItemData = null
var held_item_visual: Sprite2D

const PICKUP_SHOW_TIME := 1.0

var current_interactable: Interactable = null
var busy: bool = false;
var swimming: bool = false
var swim_bounds: Rect2 = Rect2(Vector2(16, 154), Vector2(888, 460))
var _land_collision_mask: int = 1
# Land walking border (global x) and walking height, read at start from the
# pixels of the sibling Ground tiles, so both follow the map if it changes.
var walk_limits: Vector2 = Vector2(-INF, INF)
const WALK_EDGE_MARGIN: float = 6.0  # half the body width
const FEET_HALF_WIDTH: int = 2
const WALK_HEIGHT_SPEED: float = 160.0  # px/s when stepping up or down
const GROUND_PROFILE_SCRIPT = preload("res://scripts/ground_profile.gd")
var _ground = null  # ground_profile.gd instance (untyped: script has no class_name)
var _feet_offset: float = 0.0
var last_direction : float;

var _pickup_visual: Sprite2D
var _pickup_tween: Tween
var _pickup_time_left := 0.0

@onready var fishing_controller: Node = $FishingController
@onready var animator : AnimatedSprite2D = $AnimatedSprite2D

func _ready() -> void:
	_install_swim_animations()
	_land_collision_mask = collision_mask
	_read_walk_limits.call_deferred()
	held_item_visual = Sprite2D.new()
	held_item_visual.position = Vector2(0, -39)
	held_item_visual.z_index = 5
	add_child(held_item_visual)
	_refresh_held_item()

	_pickup_visual = Sprite2D.new()
	_pickup_visual.z_index = 6
	_pickup_visual.visible = false
	add_child(_pickup_visual)

# Populate the existing AnimatedSprite2D with both swimming and treading-water
# animations, using the same pixel-sheet setup for each. Keep any versions
# already authored in SpriteFrames through the Godot editor.
func _install_swim_animations() -> void:
	if animator.sprite_frames == null:
		return
	var frames: SpriteFrames = animator.sprite_frames.duplicate() as SpriteFrames
	animator.sprite_frames = frames
	var cell := Vector2i(maxi(1, swim_frame_size.x), maxi(1, swim_frame_size.y))
	for animation_name in [&"swim_l", &"swim_r", &"swim_idle_l", &"swim_idle_r"]:
		if frames.has_animation(animation_name):
			continue
		var sheet: Texture2D
		match animation_name:
			&"swim_l":
				sheet = SWIM_LEFT_SHEET
			&"swim_r":
				sheet = SWIM_RIGHT_SHEET
			&"swim_idle_l":
				sheet = SWIM_IDLE_LEFT_SHEET
			&"swim_idle_r":
				sheet = SWIM_IDLE_RIGHT_SHEET
		var columns: int = sheet.get_width() / cell.x
		var rows: int = sheet.get_height() / cell.y
		if columns < 1 or rows < 1:
			push_warning("Swimming sheet has no complete frames: " + String(animation_name))
			continue
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, true)
		frames.set_animation_speed(animation_name,
			swim_idle_frames_per_second if String(animation_name).begins_with("swim_idle") else swim_frames_per_second)
		for row in range(rows):
			for column in range(columns):
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = Rect2(column * cell.x, row * cell.y, cell.x, cell.y)
				frames.add_frame(animation_name, atlas)


# Keep swimming animation selection in one place for entering the sea,
# actively swimming, pausing, and waiting during underwater dialogue.
func _set_swim_animation(moving: bool) -> void:
	var facing_left: bool = last_direction < 0.0
	var animation_name: StringName
	if moving:
		animation_name = &"swim_l" if facing_left else &"swim_r"
	else:
		animation_name = &"swim_idle_l" if facing_left else &"swim_idle_r"
	if animator.animation != animation_name:
		animator.play(animation_name)


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



func set_swimming(enabled: bool, bounds: Rect2 = Rect2()) -> void:
	swimming = enabled
	velocity = Vector2.ZERO
	if enabled:
		_set_swim_animation(false)
		swim_bounds = bounds
		collision_mask = _land_collision_mask | 2
		$FishingController.process_mode = Node.PROCESS_MODE_DISABLED
		$FishingRod.hide()
		held_item_visual.hide()
	else:
		collision_mask = _land_collision_mask
		$FishingController.process_mode = Node.PROCESS_MODE_INHERIT
		# Surfacing restores land controls, not an active rod cast. The
		# FishingRod listens for FishingController state changes and draws
		# itself only when an actual fishing session starts.
		$FishingRod.hide()
		_refresh_held_item()
		animator.position.y = -16.0
		animator.rotation = 0.0
		animator.play(&"idle_l" if last_direction < 0.0 else &"idle_r")


func _swim_physics(delta: float) -> void:
	var vertical: float = 0.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		vertical += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		vertical -= 1.0
	var direction := Vector2(Input.get_axis("Move Left", "Move Right"), vertical)
	if direction.length_squared() > 1.0:
		direction = direction.normalized()
	velocity = velocity.move_toward(direction * SWIM_SPEED, ACC * delta)
	move_and_slide()
	global_position.x = clampf(global_position.x, swim_bounds.position.x + 8.0, swim_bounds.end.x - 8.0)
	global_position.y = clampf(global_position.y, swim_bounds.position.y + 8.0, swim_bounds.end.y - 8.0)
	if absf(direction.x) > 0.03:
		last_direction = direction.x
	# Movement plays the directional swim; without input Penni treads water.
	# Her new idle-swim sheets include the scuba mask, so no extra overlay is needed.
	_set_swim_animation(direction.length_squared() > 0.01)
	animator.rotation = lerpf(animator.rotation, direction.x * 0.13, minf(delta * 6.0, 1.0))
	animator.position.y = -16.0 + sin(Time.get_ticks_msec() * 0.0026) * 0.8


func _physics_process(delta: float) -> void:
	if _pickup_time_left > 0.0:
		_pickup_time_left -= delta
		if _pickup_time_left <= 0.0:
			_pickup_visual.visible = false

	if busy or GameManager.is_modal_ui_open():
		velocity = Vector2.ZERO
		if swimming:
			_set_swim_animation(false)
		move_and_slide()
		return
	if swimming:
		_swim_physics(delta)
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

	var previous_x: float = global_position.x
	move_and_slide()
	_keep_inside_walk_limits(previous_x)
	_follow_ground_height(delta)


# Reads the drawn ground (World/Ground tiles) once at start: the walk border
# is where the ground's pixels start and end (the beach stops where the sand
# meets the water), and the feet follow the surface height.
func _read_walk_limits() -> void:
	var ground := get_parent().get_node_or_null("Ground") as TileMapLayer
	if ground == null:
		return
	_ground = GROUND_PROFILE_SCRIPT.new()
	_ground.build(ground)
	if _ground.is_empty():
		_ground = null
		return
	var left: float = float(_ground.left)
	var right: float = float(_ground.right)
	var water := get_parent().get_node_or_null("Water") as Control
	if water != null:
		var water_top: float = water.global_position.y
		while right > left and _ground.surface_at(right) >= water_top:
			right -= 1.0
	walk_limits = Vector2(left + WALK_EDGE_MARGIN, right - WALK_EDGE_MARGIN)
	var surface: float = _walk_surface_at(global_position.x)
	_feet_offset = 0.0 if is_nan(surface) else global_position.y - surface


# Highest surface point under the feet, so 1px bumps in the sand don't jitter.
func _walk_surface_at(x: float) -> float:
	var best: float = NAN
	for dx in range(-FEET_HALF_WIDTH, FEET_HALF_WIDTH + 1):
		var y: float = _ground.surface_at(x + dx)
		if not is_nan(y) and (is_nan(best) or y < best):
			best = y
	return best


func _follow_ground_height(delta: float) -> void:
	if _ground == null:
		return
	var surface: float = _walk_surface_at(global_position.x)
	if is_nan(surface):
		return  # off the ground (e.g. the ship date venue): leave y alone
	global_position.y = move_toward(global_position.y, surface + _feet_offset, WALK_HEIGHT_SPEED * delta)


# Stops walking past the ends of the ground. Only blocks moving outward, so
# a scripted move past the edge (like the ship date venue) is left alone.
func _keep_inside_walk_limits(previous_x: float) -> void:
	if previous_x >= walk_limits.x and global_position.x < walk_limits.x:
		global_position.x = walk_limits.x
		velocity.x = 0.0
	elif previous_x <= walk_limits.y and global_position.x > walk_limits.y:
		global_position.x = walk_limits.y
		velocity.x = 0.0


# Mouse input can be consumed by the SubViewportContainer before
# _unhandled_input runs. Catch mouse interactions at the input stage instead.
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if GameManager.is_modal_ui_open() or busy or swimming:
		return
	if event.is_action_pressed("Interact"):
		interact()
		get_viewport().set_input_as_handled()


# Keyboard interaction stays unhandled so focused UI controls take priority.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		return
	if GameManager.is_modal_ui_open() or busy or swimming:
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
		if current_interactable.spends_time() and not GameManager.can_act():
			print("Too late for that. Rest until morning.")
			return
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

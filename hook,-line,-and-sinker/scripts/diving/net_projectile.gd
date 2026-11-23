extends Node2D
class_name DivingNetProjectile

# The throw is aimed, not targeted: it always launches from Penni in the
# clicked direction, travels at a visible speed and stops at a hard range.
# A swept collision test keeps small, fast-moving fish catchable.
signal fish_hit(fish: DivingWildFish)
signal missed()

enum State { IDLE, OUTBOUND, RETURNING, LATCHED }

@export_range(24.0, 240.0, 1.0) var max_range: float = 110.0
@export_range(60.0, 600.0, 10.0) var throw_speed: float = 275.0
@export_range(60.0, 800.0, 10.0) var retract_speed: float = 370.0
@export_range(3.0, 20.0, 1.0) var hit_radius: float = 11.0

@export_group("Net Sprite Line Attachment")
# Tweak the one-pixel cord endpoint relative to the handle-side rim.
@export_range(-16.0, 16.0, 1.0, "suffix:px") var cord_attachment_inset: float = 0.0
# Unflipped artwork faces left. Zero keeps left throws horizontal.
@export_range(-180.0, 180.0, 1.0, "suffix:deg") var sprite_angle_offset_degrees: float = 0.0

# The visuals live in Sea/NetProjectile: the Sprite2D divides the authored
# four-frame sheet equally and AnimationPlayer owns contact timing.
@onready var _net_sprite: Sprite2D = get_node_or_null("NetSprite") as Sprite2D
@onready var _net_animation: AnimationPlayer = get_node_or_null("AnimationPlayer") as AnimationPlayer

# Match FishingLine's pale -> amber -> red tension language.
@export var calm_line_color: Color = Color("#d8e6e4")
@export var strained_line_color: Color = Color("#efb65a")
@export var danger_line_color: Color = Color("#ee514d")
@export var stunned_line_color: Color = Color("#ffe55c")
@export_range(0.0, 1.0) var strained_threshold: float = 0.55
var line_tension: float = 0.0
var line_stunned: bool = false

func set_line_state(tension_amount: float, stunned: bool = false) -> void:
	var updated_tension: float = clampf(tension_amount, 0.0, 1.0)
	if not is_equal_approx(updated_tension, line_tension) or stunned != line_stunned:
		line_tension = updated_tension
		line_stunned = stunned
		queue_redraw()


func get_line_color() -> Color:
	if line_stunned:
		return stunned_line_color
	if line_tension <= strained_threshold:
		return calm_line_color.lerp(strained_line_color, line_tension / maxf(strained_threshold, 0.001))
	return strained_line_color.lerp(
		danger_line_color,
		(line_tension - strained_threshold) / maxf(1.0 - strained_threshold, 0.001)
	)


var state: State = State.IDLE
var tip: Vector2 = Vector2.ZERO
var direction: Vector2 = Vector2.RIGHT
var _start: Vector2 = Vector2.ZERO
var _travelled: float = 0.0
var _origin: Node2D
var _latched_fish: DivingWildFish
var _candidates: Array[DivingWildFish] = []
var _age: float = 0.0


func _ready() -> void:
	# Keep both the sprite and its one-pixel cord below the world water
	# reflection/tint pass (Water z=10), not in front of the sea overlay.
	z_index = 7
	visible = false
	set_process(false)


func is_busy() -> bool:
	return state != State.IDLE


func is_latched() -> bool:
	return state == State.LATCHED


# Inspector max_range stays the base value. Apply any equipment bonus on read.
func effective_max_range() -> float:
	return max_range + FishingManager.net_range_bonus_pixels


func cast_net(origin: Node2D, aim_position: Vector2, fish_in_water: Array[DivingWildFish]) -> bool:
	if is_busy() or origin == null:
		return false
	_origin = origin
	_start = _get_anchor()
	var aim: Vector2 = aim_position - _start
	if aim.length_squared() <= 1.0:
		return false
	direction = aim.normalized()
	tip = _start
	_travelled = 0.0
	_age = 0.0
	line_tension = 0.0
	line_stunned = false
	_latched_fish = null
	_candidates.clear()
	_candidates.append_array(fish_in_water)
	state = State.OUTBOUND
	if _net_animation != null:
		_net_animation.stop()
	if _net_sprite != null:
		_net_sprite.frame = 0
		_net_sprite.position = tip.round()
		_orient_net_sprite()
	visible = true
	set_process(true)
	queue_redraw()
	return true


func _process(delta: float) -> void:
	if state == State.IDLE:
		return
	_age += delta
	match state:
		State.OUTBOUND:
			var previous: Vector2 = tip
			_travelled = minf(effective_max_range(), _travelled + throw_speed * delta)
			var next_position: Vector2 = _start + direction * _travelled
			# Physics layer 2 contains only the lagoon's painted solid tiles.
			# Shorten this segment at a wall so a fish behind a cave wall
			# cannot be hooked through it.
			var wall_hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(
				PhysicsRayQueryParameters2D.create(previous, next_position, 2)
			)
			var unobstructed_end: Vector2 = next_position
			if not wall_hit.is_empty():
				unobstructed_end = wall_hit["position"]
			var collided: DivingWildFish = _first_fish_on_segment(previous, unobstructed_end)
			if collided != null:
				_latched_fish = collided
				tip = collided.position
				state = State.LATCHED
				if _net_animation != null:
					_net_animation.play(&"contact")
				fish_hit.emit(collided)
			else:
				tip = unobstructed_end
				if not wall_hit.is_empty() or _travelled >= effective_max_range():
					state = State.RETURNING
		State.RETURNING:
			tip = tip.move_toward(_get_anchor(), retract_speed * delta)
			if tip.distance_squared_to(_get_anchor()) <= 4.0:
				reset_net()
				missed.emit()
				return
		State.LATCHED:
			if is_instance_valid(_latched_fish):
				tip = _latched_fish.position
			else:
				reset_net()
				return
	if _net_sprite != null:
		_net_sprite.position = tip.round()
	queue_redraw()


func _first_fish_on_segment(previous: Vector2, next_position: Vector2) -> DivingWildFish:
	var movement: Vector2 = next_position - previous
	var distance_squared: float = movement.length_squared()
	if distance_squared <= 0.00001:
		return null
	var earliest: float = INF
	var selected: DivingWildFish = null
	for fish in _candidates:
		if not is_instance_valid(fish) or fish.catch_cooldown > 0.0:
			continue
		var t: float = clampf((fish.position - previous).dot(movement) / distance_squared, 0.0, 1.0)
		var nearest: Vector2 = previous + movement * t
		# Encounter-specific larger sprites (e.g. Kuda) have matching
		# hit areas. Normal fish retain at least the net's authored radius.
		var radius: float = maxf(hit_radius, fish.capture_radius)
		if fish.position.distance_squared_to(nearest) > radius * radius:
			continue
		if t < earliest:
			earliest = t
			selected = fish
	return selected


func retract() -> void:
	if state == State.OUTBOUND or state == State.LATCHED:
		_latched_fish = null
		state = State.RETURNING


func reset_net() -> void:
	state = State.IDLE
	line_tension = 0.0
	line_stunned = false
	_latched_fish = null
	_origin = null
	_candidates.clear()
	if _net_animation != null:
		_net_animation.stop()
	if _net_sprite != null:
		_net_sprite.frame = 0
		_net_sprite.flip_h = false
		_net_sprite.rotation = 0.0
	visible = false
	set_process(false)
	queue_redraw()


func _get_anchor() -> Vector2:
	return _origin.position + Vector2(0.0, -7.0) if is_instance_valid(_origin) else _start


# The original net artwork faces left, with its handle on the right.
# Rotate (not mirror) the Sprite2D to align with any casting direction.
# This keeps exactly the same physical handle pixel for every angle.
func _orient_net_sprite() -> void:
	if _net_sprite == null:
		return
	_net_sprite.flip_h = false
	_net_sprite.rotation = wrapf(
		direction.angle() - PI + deg_to_rad(sprite_angle_offset_degrees),
		-PI, PI
	)


# The line endpoint is the original right-hand handle location in the
# unrotated sprite. Transform it with the Sprite2D so the cord follows
# the rotating artwork instead of attaching to its center.
func _cord_endpoint() -> Vector2:
	if _net_sprite == null or _net_sprite.texture == null:
		return tip.round()
	var bounds: Rect2 = _net_sprite.get_rect()
	var handle: Vector2 = Vector2(bounds.end.x - cord_attachment_inset, bounds.get_center().y)
	return (_net_sprite.transform * handle).round()


func _draw() -> void:
	if state == State.IDLE:
		return
	draw_line(_get_anchor(), _cord_endpoint(), get_line_color(), 1.0, false)

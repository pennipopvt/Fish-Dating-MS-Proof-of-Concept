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
	z_index = 9
	visible = false
	set_process(false)


func is_busy() -> bool:
	return state != State.IDLE


func is_latched() -> bool:
	return state == State.LATCHED


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
			_travelled = minf(max_range, _travelled + throw_speed * delta)
			var next_position: Vector2 = _start + direction * _travelled
			var collided: DivingWildFish = _first_fish_on_segment(previous, next_position)
			if collided != null:
				_latched_fish = collided
				tip = collided.position
				state = State.LATCHED
				fish_hit.emit(collided)
			else:
				tip = next_position
				if _travelled >= max_range:
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
		if fish.position.distance_squared_to(nearest) > hit_radius * hit_radius:
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
	visible = false
	set_process(false)
	queue_redraw()


func _get_anchor() -> Vector2:
	return _origin.position + Vector2(0.0, -7.0) if is_instance_valid(_origin) else _start


func _draw() -> void:
	if state == State.IDLE:
		return
	var anchor: Vector2 = _get_anchor()
	var net_center: Vector2 = tip.round()
	# Reusable cord on cast, on retrieval, and when attached to a fish.
	draw_line(anchor, net_center, get_line_color(), 1.6, false)
	if state == State.LATCHED:
		draw_circle(net_center, 9.0, Color(0.61, 0.95, 0.85, 0.14))
	draw_arc(net_center, 7.0, 0.0, TAU, 12, Color(0.86, 0.97, 0.91, 0.98), 1.6, true)
	draw_line(net_center + Vector2(-5, -5), net_center + Vector2(5, 5), Color(0.73, 0.93, 0.88, 0.88), 1.0)
	draw_line(net_center + Vector2(5, -5), net_center + Vector2(-5, 5), Color(0.73, 0.93, 0.88, 0.88), 1.0)
	draw_line(net_center + Vector2(-7, 0), net_center + Vector2(7, 0), Color(0.73, 0.93, 0.88, 0.65), 1.0)
	draw_line(net_center + Vector2(0, -7), net_center + Vector2(0, 7), Color(0.73, 0.93, 0.88, 0.65), 1.0)

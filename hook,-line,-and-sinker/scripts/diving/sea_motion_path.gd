@tool
extends Path2D
class_name SeaMotionPath

## Edit this Path2D's Curve2D handles in the 2D viewport to change WHERE
## the animation travels. Edit Speed Curve below to change HOW FAST it
## moves over time. This is a velocity curve, not a position easing curve:
## the area under it is normalized, so the motion always ends on time.
@export_range(0.1, 4.0, 0.05, "suffix:s") var duration_seconds: float = 0.8
@export var speed_curve: Curve

const INTEGRATION_STEPS: int = 48


func is_valid_motion() -> bool:
	return curve != null and curve.get_point_count() >= 2


func authored_start() -> Vector2:
	return to_global(curve.get_point_position(0)) if is_valid_motion() else global_position


func authored_end() -> Vector2:
	return to_global(curve.get_point_position(curve.get_point_count() - 1)) \
		if is_valid_motion() else global_position


# The graph's X axis is normalized time; Y is the instantaneous speed
# multiplier. Integrate positive speed values into a distance percentage.
# This avoids backwards jumps and preserves the authored duration even if
# the artist changes the height or shape of the speed graph.
func progress_at_time(time_ratio: float) -> float:
	var t: float = clampf(time_ratio, 0.0, 1.0)
	if speed_curve == null or speed_curve.get_point_count() < 2:
		return t
	var total: float = 0.0
	var traveled: float = 0.0
	var step: float = 1.0 / float(INTEGRATION_STEPS)
	for i in range(INTEGRATION_STEPS):
		var start_t: float = float(i) * step
		var end_t: float = float(i + 1) * step
		var first_speed: float = maxf(0.0, speed_curve.sample_baked(start_t))
		var last_speed: float = maxf(0.0, speed_curve.sample_baked(end_t))
		var area: float = (first_speed + last_speed) * 0.5 * step
		total += area
		var covered: float = clampf((t - start_t) / step, 0.0, 1.0)
		if covered > 0.0:
			var covered_speed: float = lerpf(first_speed, last_speed, covered)
			traveled += (first_speed + covered_speed) * 0.5 * step * covered
	if total <= 0.00001:
		return t
	return clampf(traveled / total, 0.0, 1.0)


# Optional actual endpoints are useful for followers returning from wherever
# they were swimming. The offsets smoothly taper across the authored curve,
# preserving its bends while preventing a teleport at either end.
func world_position_at(time_ratio: float,
		from: Vector2 = Vector2.INF, to: Vector2 = Vector2.INF) -> Vector2:
	if not is_valid_motion():
		return global_position
	var distance_ratio: float = progress_at_time(time_ratio)
	var shaped: Vector2 = to_global(curve.sample_baked(
		curve.get_baked_length() * distance_ratio, true))
	if from != Vector2.INF:
		shaped += (from - authored_start()) * (1.0 - distance_ratio)
	if to != Vector2.INF:
		shaped += (to - authored_end()) * distance_ratio
	return shaped


func animate(actor: Node2D, from: Vector2 = Vector2.INF,
		to: Vector2 = Vector2.INF, on_move: Callable = Callable()) -> void:
	if not is_valid_motion():
		push_error("SeaMotionPath needs at least two Curve2D points: " + name)
		return
	if not is_instance_valid(actor):
		return
	actor.global_position = world_position_at(0.0, from, to)
	var tween: Tween = create_tween()
	# A linear time tween is intentional: the editable speed graph alone
	# determines acceleration and deceleration.
	tween.tween_method(_advance.bind(actor, from, to, on_move),
		0.0, 1.0, duration_seconds)
	await tween.finished
	if is_instance_valid(actor):
		_advance(1.0, actor, from, to, on_move)


func _advance(time_ratio: float, actor: Node2D, from: Vector2,
		to: Vector2, on_move: Callable) -> void:
	if not is_instance_valid(actor):
		return
	actor.global_position = world_position_at(time_ratio, from, to)
	if on_move.is_valid():
		on_move.call(time_ratio, progress_at_time(time_ratio))

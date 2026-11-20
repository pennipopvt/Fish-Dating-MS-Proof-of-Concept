extends RefCounted
class_name HookedFishMover

# Where the hooked fish sits during the reel/parry fight. The fight
# (DivingCombat) owns the line length; this only decides the fish's spot on
# the circle of that radius around Penni, so it never ends up above the
# waterline or inside rock/ground:
# - Pulling into a border, the fish slides along it at the same line length.
# - When it can't slide either way (pinned in a corner), it waits a moment
#   and then dashes in a U-turn back past Penni to the opposite side.
# Movement only: the dash never changes line length, tension or escape.

# Fish center positions that are open water. Set by DivingWorld.
var is_open: Callable
# How fast the fish may slide along a border (world px/s).
var slide_speed: float = 220.0
# How long the fish must be pinned before it dashes away.
var stuck_time: float = 0.12
var dash_duration: float = 0.3

var _slide_side: float = 1.0
var _stuck_for: float = 0.0
var _dashing: bool = false
var _dash_elapsed: float = 0.0
var _dash_start: Vector2
var _dash_end_angle: float = 0.0

const SEARCH_STEPS: int = 8
const FULL_SEARCH_STEPS: int = 72


func reset() -> void:
	_slide_side = 1.0
	_stuck_for = 0.0
	_dashing = false


func is_dashing() -> bool:
	return _dashing


func step(delta: float, player: Vector2, fish: Vector2, length: float) -> Vector2:
	length = maxf(length, 0.001)
	if _dashing:
		return _step_dash(delta, player, length)
	var offset: Vector2 = fish - player
	var angle: float = offset.angle() if offset.length_squared() > 0.0001 else 0.0
	var target: Vector2 = player + Vector2.from_angle(angle) * length
	if is_open.call(target):
		_stuck_for = 0.0
		return target
	if not is_open.call(fish):
		# Started (or got pushed) somewhere blocked: jump to the nearest
		# open spot at this length instead of counting it as pinned.
		var nearest: Variant = _nearest_open_angle(player, angle, length, PI, FULL_SEARCH_STEPS)
		_stuck_for = 0.0
		return fish if nearest == null else player + Vector2.from_angle(nearest) * length
	# Slide: look a little to each side, preferring the side we were already
	# sliding toward so the fish doesn't jitter between two directions.
	var max_turn: float = slide_speed * delta / length
	for i in range(1, SEARCH_STEPS + 1):
		for side in [_slide_side, -_slide_side]:
			var a: float = angle + side * max_turn * float(i) / float(SEARCH_STEPS)
			var p: Vector2 = player + Vector2.from_angle(a) * length
			if is_open.call(p):
				_slide_side = side
				_stuck_for = 0.0
				return p
	# Pinned: hold at the farthest open point on the line, then dash.
	_stuck_for += delta
	if _stuck_for >= stuck_time:
		var opposite: Variant = _nearest_open_angle(player, angle + PI, length, PI, FULL_SEARCH_STEPS)
		if opposite != null:
			_dashing = true
			_dash_elapsed = 0.0
			_dash_start = fish
			_dash_end_angle = opposite
			_stuck_for = 0.0
	return _farthest_open_on_line(player, Vector2.from_angle(angle), length, fish)


func _step_dash(delta: float, player: Vector2, length: float) -> Vector2:
	_dash_elapsed += delta
	var t: float = clampf(_dash_elapsed / maxf(dash_duration, 0.001), 0.0, 1.0)
	var end: Vector2 = player + Vector2.from_angle(_dash_end_angle) * length
	if t >= 1.0:
		_dashing = false
	# Ease out: a fast burst that settles on the far side.
	return _dash_start.lerp(end, 1.0 - pow(1.0 - t, 3.0))


# Closest open angle to `center` on the circle, searching up to `span` each way.
func _nearest_open_angle(player: Vector2, center: float, length: float, span: float, steps: int) -> Variant:
	for i in range(0, steps + 1):
		for side in [1.0, -1.0]:
			var a: float = center + side * span * float(i) / float(steps)
			if is_open.call(player + Vector2.from_angle(a) * length):
				return a
			if i == 0:
				break
	return null


func _farthest_open_on_line(player: Vector2, dir: Vector2, length: float, fallback: Vector2) -> Vector2:
	var d: float = length
	while d > 0.0:
		var p: Vector2 = player + dir * d
		if is_open.call(p):
			return p
		d -= 2.0
	return fallback
